// ============================================================
// PATHFINDER PORTAL — enrolment processes
//
// Three fixed checklists. Shared by tasks.html (which starts a
// process on conversion) and students.html (which works through it).
//
// auto_key names a check the portal runs itself. Those items are
// evaluated LIVE, not stored — "added a trial lesson" only becomes
// true after the process has started.
// ============================================================

const PROCESS_DEFS = {
  trial_confirmation: {
    label: 'Trial confirmation',
    items: [
      { label: 'Trial student added to the Portal',   auto: 'status_trial'  },
      { label: 'Trial lesson added to the Portal',    auto: 'lesson_exists' },
      { label: 'Confirmation email sent to the student', auto: 'email_sent', email: 'trial' },
      { label: 'Xero invoice created for the trial',  auto: null, deferrable: true },
      { label: 'Trial announced to internal staff',   auto: null },
    ],
  },
  ongoing_enrolment: {
    label: 'Ongoing enrolment',
    items: [
      { label: 'Active student added to the Portal',  auto: 'status_active' },
      { label: 'Lesson series added to the Portal',   auto: 'series_exists' },
      { label: 'Confirmation email sent to the student', auto: 'email_sent', email: 'enrolment' },
      { label: 'Repeating invoices created in Xero',  auto: null, deferrable: true },
      { label: 'Recurring payments created in eWay',  auto: null, deferrable: true },
      { label: 'Enrolment announced to internal staff', auto: null },
    ],
  },
  end_enrolment: {
    label: 'End enrolment',
    items: [
      { label: 'Cancellation policies explained',     auto: null },
      { label: 'End date set for lessons',            auto: 'lessons_ended' },
      { label: 'Invoices deleted in Xero',            auto: null, deferrable: true },
      { label: 'End date set for payments in eWay',   auto: null, deferrable: true },
      { label: 'Unenrolment announced to internal staff', auto: null },
    ],
  },
};

// Create a process and its items. Labels are copied in, so changing a
// checklist later leaves completed processes as they were.
async function startProcess(studentId, type, createdBy) {
  const def = PROCESS_DEFS[type];
  if (!def) throw new Error('Unknown process type: ' + type);

  const { data: stu } = await db.from('students')
    .select('status').eq('id', studentId).maybeSingle();
  const wasAlreadyEnrolled = stu?.status === 'active';

  // Booking a trial or enrolling brings a prospective, lapsed or former
  // student back into the fold. An existing active student stays active
  // — a second instrument doesn't demote them to a trial.
  if (type === 'trial_confirmation' && !wasAlreadyEnrolled && stu?.status !== 'trial') {
    await db.from('students').update({ status: 'trial' }).eq('id', studentId);
  }
  if (type === 'ongoing_enrolment' && stu?.status !== 'active') {
    await db.from('students').update({ status: 'active' }).eq('id', studentId);
  }

  const { data: proc, error } = await db.from('student_processes')
    .insert({ student_id: studentId, process_type: type, started_by: createdBy })
    .select('id,started_at').single();
  if (error) throw new Error(error.message);

  // Drop the "student added" step when they are already enrolled —
  // it would never tick and only makes the checklist look stuck.
  const items = def.items.filter(it =>
    !(wasAlreadyEnrolled && type === 'trial_confirmation' && it.auto === 'status_trial'));

  const rows = items.map((it, i) => ({
    process_id: proc.id, item_order: i,
    label: it.label, auto_key: it.auto,
    can_defer: !!it.deferrable,
  }));
  const { error: iErr } = await db.from('process_items').insert(rows);
  if (iErr) throw new Error(iErr.message);

  // Each process brings its own follow-up work, dated from the lessons
  try { await createProcessTasks(studentId, type, createdBy, proc.started_at); }
  catch (err) { console.error('[processes] task creation failed', err); }

  // The farewell goes out as soon as leaving is confirmed
  if (type === 'end_enrolment') {
    try { await sendFarewellEmail(studentId, createdBy); }
    catch (err) { console.error('[processes] farewell failed', err); }
  }

  return proc.id;
}

// Evaluate the portal-verifiable items for one student.
// Returns { status_trial: bool, status_active: bool, ... }
// `since` is when the process began. Lessons that already existed are
// not evidence that this checklist's step was done — an active student
// trying a second instrument already has lessons.
async function evaluateAutoChecks(studentId, since = null) {
  const [{ data: stu }, { data: ls }] = await Promise.all([
    db.from('students').select('status').eq('id', studentId).maybeSingle(),
    db.from('lesson_students').select('lesson_id').eq('student_id', studentId),
  ]);

  const lessonIds = (ls ?? []).map(r => r.lesson_id);
  let anyActive = false, anySeries = false;
  let anyLesson = false;

  if (lessonIds.length) {
    let q = db.from('lessons').select('id,status,created_at').in('id', lessonIds);
    if (since) q = q.gte('created_at', since);
    const { data: lessons } = await q;

    const active = (lessons ?? []).filter(l => l.status === 'active');
    anyActive = active.length > 0;
    anyLesson = (lessons ?? []).length > 0;

    // A trial is a single occurrence; a series recurs. That is the
    // difference that matters — an ongoing series is usually a
    // different day and time, and often a different teacher.
    for (const l of active) {
      const { count } = await db.from('lesson_occurrences')
        .select('id', { count: 'exact', head: true }).eq('lesson_id', l.id);
      if ((count ?? 0) > 1) { anySeries = true; break; }
    }
  }

  // "Ended" is about every lesson, not just new ones
  let allEnded = false;
  if (lessonIds.length) {
    const { data: allLessons } = await db.from('lessons')
      .select('status').in('id', lessonIds);
    allEnded = (allLessons ?? []).length > 0
      && !(allLessons ?? []).some(l => l.status === 'active');
  }

  return {
    status_trial:  stu?.status === 'trial',
    status_active: stu?.status === 'active',
    lesson_exists: anyLesson,
    series_exists: anySeries,
    lessons_ended: allEnded,
  };
}

// An item counts as done when an admin ticked it, or when the portal
// can verify it. Blocked items are neither.
function itemIsDone(item, checks) {
  // The email item records its own state — it either went or it didn't
  if (item.auto_key === 'email_sent') return !!item.sent_at;
  if (item.auto_key) return !!checks[item.auto_key];
  // An item deferred to a task is done when that task is done
  if (item.blocked_task_id) {
    return item.is_done || !!checks._blockedDone?.[item.blocked_task_id];
  }
  return item.is_done;
}

// Which of the tasks standing in for blocked items have been completed
async function blockedTaskStatuses(items) {
  const ids = items.map(i => i.blocked_task_id).filter(Boolean);
  if (!ids.length) return {};
  const { data } = await db.from('tasks').select('id,status').in('id', ids);
  const out = {};
  (data ?? []).forEach(t => { out[t.id] = t.status === 'done'; });
  return out;
}

function processProgress(items, checks) {
  const done    = items.filter(i => itemIsDone(i, checks)).length;
  const blocked = items.filter(i => i.blocked_task_id && !itemIsDone(i, checks)).length;
  return { done, blocked, total: items.length, complete: done === items.length };
}


// ============================================================
// CONFIRMATION EMAILS
//
// Fixed welcome and policy text, with the lesson details generated
// from what is actually booked. Sent when the lesson is added,
// because that is when the details come into existence — not at
// conversion, when there is nothing to tell them yet.
//
// Idempotent: process_items.sent_at is the guard, so calling this
// twice cannot send twice.
// ============================================================

// ------------------------------------------------------------
// Email content
//
// Taken from the templates Pathfinder already sends, so the wording,
// tone and — importantly — the policies match what students are
// actually told. Earlier drafted text had two of these wrong.
// ------------------------------------------------------------

const PAYMENT_URL = 'https://www.pathfindermusiclessons.com.au/payments';

const SIGNATURE =
  'Talk to you soon!\n' +
  'The Pathfinder Team';

const POLICIES =
  '---\n\n' +
  'PATHFINDER MUSIC POLICIES\n\n' +

  '**How do payments work?**\n' +
  'After you have paid for your first lesson, we\'ll set up the recurring payment ' +
  'to process the day before your lesson each week. If ever you need to pause or ' +
  'stop lessons for a while, just give us 4 weeks notice and we\'ll stop payments ' +
  'and lessons after those 4 weeks.\n\n' +

  '**What do I do if I can\'t attend a lesson?**\n' +
  'Let us know via the Student Portal, email or phone 24 hours in advance. By ' +
  'default your teacher will record and send through a video lesson instead so you ' +
  'can practise at home. If you\'d prefer a makeup lesson, let us know and we\'ll try ' +
  'to accommodate if a suitable time is available within a week. Note that we can\'t ' +
  'pause payments week to week.\n\n' +

  '**What if I want to change times, days, teachers or instruments?**\n' +
  'No problem, just let us know and we\'ll do our best to accommodate you — so long ' +
  'as it\'s not too often, as routine and structure are important for learning music.\n\n' +

  '**What about school holidays or public holidays?**\n' +
  'We still run lessons through school holidays, but not on public holidays. If you ' +
  'can\'t attend over any school holidays, please give us 2 weeks notice. For public ' +
  'holidays, we\'ll organise makeup lessons when they come up on your lesson day.\n\n' +

  '**Will I (or my child) be filmed or photographed?**\n' +
  'We try to film and take photos at all performance days to share with friends and ' +
  'family, and sometimes in lessons too — typically with just first names if we want ' +
  'to praise a student on social media or in newsletters. If you\'d rather we didn\'t ' +
  '(or would like us to film more), just let us know.\n\n' +

  '**Anything else I should know?**\n' +
  'We\'re a small team of musicians who love passing on our love of music to others, ' +
  'and you\'re now part of that community. We\'ll probably make mistakes, but we\'re a ' +
  'friendly, honest and open bunch — so feel free to tell us when we\'re doing well, ' +
  'when we\'re not, any questions you have, whatever.';

async function buildLessonSummary(studentId, wantSeries = false, since = null) {
  const { data: ls } = await db.from('lesson_students')
    .select('lesson_id').eq('student_id', studentId);
  const ids = (ls ?? []).map(r => r.lesson_id);
  if (!ids.length) return null;

  let lq = db.from('lessons')
    .select('id,instrument,lesson_type,day_of_week,start_time,duration_mins,teacher_id,studio_id,status,created_at')
    .in('id', ids).eq('status','active');
  // Only lessons booked for this process — otherwise a student's
  // existing lesson would be described as their new one
  if (since) lq = lq.gte('created_at', since);
  const { data: lessons } = await lq;
  if (!lessons?.length) return null;

  // For an enrolment, pick the recurring series. The trial lesson is
  // still on file and would otherwise be described as their enrolment.
  let l = lessons[0];
  if (wantSeries) {
    let picked = null;
    for (const cand of lessons) {
      const { count } = await db.from('lesson_occurrences')
        .select('id', { count: 'exact', head: true }).eq('lesson_id', cand.id);
      if ((count ?? 0) > 1) { picked = cand; break; }
    }
    if (!picked) return null;          // no series yet — nothing to confirm
    l = picked;
  }

  const [{ data: t }, { data: st }, { data: occ }] = await Promise.all([
    db.from('teachers').select('user_id').eq('id', l.teacher_id).maybeSingle(),
    db.from('studios').select('name,email').eq('id', l.studio_id).maybeSingle(),
    db.from('lesson_occurrences').select('date')
      .eq('lesson_id', l.id).eq('status','scheduled')
      .order('date').limit(1),
  ]);

  let teacherName = '';
  if (t?.user_id) {
    const { data: p } = await db.from('profiles')
      .select('first_name,last_name').eq('id', t.user_id).maybeSingle();
    teacherName = `${p?.first_name ?? ''} ${p?.last_name ?? ''}`.trim();
  }

  const DAYS = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
  const first = occ?.[0]?.date;

  return {
    instrument: l.instrument,
    type:       l.lesson_type === 'group' ? 'Group' : 'Private',
    teacher:    teacherName,
    studio:     st?.name  ?? '',
    studioEmail:st?.email ?? null,
    day:        DAYS[l.day_of_week],
    time:       formatTime(l.start_time),
    duration:   `${l.duration_mins} minutes`,
    firstDate:  first ? formatLongDate(parseLocalDate(first)) : null,
  };
}

// Send if the lesson exists and it hasn't gone already.
// Returns 'sent' | 'already' | 'no-lesson' | 'no-studio-email' | 'failed'
async function maybeSendConfirmation(studentId, sentBy) {
  const { data: procs } = await db.from('student_processes')
    .select('id,process_type,started_at').eq('student_id', studentId)
    .in('process_type', ['trial_confirmation','ongoing_enrolment'])
    .eq('status','in_progress');
  if (!procs?.length) return 'no-process';

  for (const proc of procs) {
    const { data: items } = await db.from('process_items')
      .select('id,sent_at').eq('process_id', proc.id).eq('auto_key','email_sent');
    const item = items?.[0];
    if (!item || item.sent_at) continue;             // already gone

    const isTrial = proc.process_type === 'trial_confirmation';

    // An enrolment email needs the series, not the trial lesson
    const lesson = await buildLessonSummary(studentId, !isTrial, proc.started_at);
    if (!lesson) return 'no-lesson';                 // nothing to tell them yet
    if (!lesson.studioEmail) return 'no-studio-email';

    // The enrolment email previously carried no lesson details at all —
    // Zoho held the enrolment and MyMusicStaff held the lessons, so they
    // went as two separate emails. Both live here now.
    const details = isTrial
      ? (lesson.firstDate ? `Date: ${lesson.firstDate}\n` : '') +
        `Time: ${lesson.time}\n` +
        `Teacher: ${lesson.teacher}\n` +
        `Studio: ${lesson.studio}\n` +
        `Instrument: ${lesson.instrument}`
      : `Instrument: ${lesson.instrument}\n` +
        `Lesson type: ${lesson.type}\n` +
        `Teacher: ${lesson.teacher}\n` +
        `Studio: ${lesson.studio}\n` +
        `Day and time: ${lesson.day}s, ${lesson.time}\n` +
        `Duration: ${lesson.duration}` +
        (lesson.firstDate ? `\nFirst lesson: ${lesson.firstDate}` : '');

    const body = isTrial
      ? `{{first_name}}, your trial lesson is booked!\n\n` +
        `Welcome to Pathfinder Music Lessons! We're so happy to help you on your ` +
        `musical journey :)\n\n` +
        `TRIAL DETAILS\n\n` +
        `**${details}**\n\n` +
        `See you then!\n\n` +
        `Pay for your lesson: ${PAYMENT_URL}\n\n` +
        `${POLICIES}\n\n` +
        `${SIGNATURE}`
      : `Congratulations {{first_name}}, you're enrolled!\n\n` +
        `Welcome to Pathfinder Music Lessons! We're so happy to help you on your ` +
        `musical journey :)\n\n` +
        `YOUR LESSONS\n\n` +
        `**${details}**\n\n` +
        `NEXT STEPS\n\n` +
        `See your upcoming lessons: you'll receive a link to log in to the Student ` +
        `Portal shortly — there are lots of music resources in there too.\n\n` +
        `Pay for your first lesson: ${PAYMENT_URL}\n` +
        `We'll then set it up ongoing using the same card for you.\n\n` +
        `Read the policies below: any questions, let us know. If after reading them ` +
        `you'd rather not proceed, no problem — just tell us at least 24 hours before ` +
        `your first lesson and we'll cancel your lessons.\n\n` +
        `${POLICIES}\n\n` +
        `${SIGNATURE}`;

    try {
      const res = await fetch('/.netlify/functions/send-email', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          action: 'send', mode: 'students', studentIds: [studentId],
          from: lesson.studioEmail,
          fromName: `Pathfinder Music Lessons (${lesson.studio})`,
          subject: isTrial
            ? 'Your trial is booked, {{first_name}}!'
            : "You're enrolled, {{first_name}}!",
          bodyText: body,
          sentBy: sentBy ?? null,
        }),
      });
      const data = await res.json();
      if (!res.ok || !data.sent) {
        console.error('[processes] confirmation email failed', data);
        return 'failed';
      }
    } catch (err) {
      console.error('[processes] confirmation email failed', err);
      return 'failed';
    }

    await db.from('process_items')
      .update({ sent_at: new Date().toISOString() }).eq('id', item.id);
    return 'sent';
  }
  return 'already';
}


// ============================================================
// THE OTHER FOUR EMAILS
//
// Enquiry acknowledgement, check-in, finance follow-up and
// farewell. Same wording as the templates Pathfinder already
// sends, so nothing changes for the student.
// ============================================================

// Studio address to send from, plus its name
async function studioFor(studentId) {
  const { data: s } = await db.from('students')
    .select('studio_id').eq('id', studentId).maybeSingle();
  if (!s?.studio_id) return null;
  const { data: st } = await db.from('studios')
    .select('name,email').eq('id', s.studio_id).maybeSingle();
  return st?.email ? { id: s.studio_id, name: st.name, email: st.email } : null;
}

async function sendStudentEmail(studentId, subject, bodyText, sentBy) {
  const studio = await studioFor(studentId);
  if (!studio) return 'no-studio-email';
  try {
    const res = await fetch('/.netlify/functions/send-email', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        action: 'send', mode: 'students', studentIds: [studentId],
        from: studio.email,
        fromName: `Pathfinder Music Lessons (${studio.name})`,
        subject, bodyText, sentBy: sentBy ?? null,
      }),
    });
    const data = await res.json();
    if (res.ok && data.sent) return 'sent';
    console.error('[processes] email not sent', { status: res.status, data });
    if (data?.unreachable)  return 'no-address';
    if (data?.count === 0)  return 'no-recipients';
    return 'failed';
  } catch (err) {
    console.error('[processes] email failed', err);
    return 'failed';
  }
}

// 1 — Acknowledgement, on a new enquiry
async function sendEnquiryAcknowledgement(studentId, sentBy) {
  return sendStudentEmail(studentId,
    'Thanks for getting in touch about music lessons, {{first_name}}!',
    `Welcome, {{first_name}}!\n\n` +
    `Thanks for getting in touch about music lessons, and congratulations on taking ` +
    `the first step on your (or your child's) musical journey with us!\n\n` +
    `We'll be in touch shortly to talk about the fun stuff — like the type of music ` +
    `you're into and your musical goals — and the practical stuff, like how lessons ` +
    `run, the times available and all the options.\n\n` +
    `If you're super keen and just can't wait (we totally understand and approve), ` +
    `feel free to reply to this email answering some of the questions below.\n\n` +
    `****What are your goals for music lessons?**\n` +
    `Could be learning particular songs, performing, writing, or even just having fun ` +
    `making music.\n\n` +
    `**What lesson days and times are you available?**\n` +
    `We're open after school and work until late most days, and Saturdays.\n\n` +
    `**Would you like your lessons focused and challenging, fun and relaxed, or ` +
    `somewhere in the middle?**\n` +
    `There's no right or wrong answer — we'll tailor lessons to help you find your path.\n\n` +
    `**When would you like to start?**\n` +
    `We run lessons all year round and can usually get you started within a week, so ` +
    `we're ready when you are!**\n\n` +
    SIGNATURE, sentBy);
}

// 2 — Check-in, a fortnight in
async function sendCheckInEmail(studentId, sentBy) {
  return sendStudentEmail(studentId,
    '{{first_name}}, we\'re just checking in!',
    `Hi {{first_name}},\n\n` +
    `We hope you have been enjoying your music lessons at Pathfinder Music!\n\n` +
    `We would love to hear any feedback you might have about your experience. ` +
    `And if there's anything specific you'd like to learn or focus on in your ` +
    `lessons, please let us know and we'll be happy to help.\n\n` +
    `Remember to have fun and practise regularly at home!\n\n` +
    `Cheers,\nThe Pathfinder Team`, sentBy);
}

// 3 — Failed payment. Creates its own task, due immediately.
async function sendFinanceFollowUp(studentId, sentBy) {
  const result = await sendStudentEmail(studentId,
    '{{first_name}}, something\'s gone wrong with your lesson payments!',
    `Hi {{first_name}},\n\n` +
    `Looks like we've had a payment fail for your music lessons.\n\n` +
    `Can you please check if you have enough funds in your account and let us know ` +
    `a good time to re-try?\n\n` +
    `If we don't hear from you we'll try again in the next few days, but we won't be ` +
    `able to run any lessons until it's resolved.\n\n` +
    `If you're under any financial pressures, just let us know and we'll help out!\n\n` +
    `Thanks,\nThe Pathfinder Team`, sentBy);

  if (result !== 'sent') return result;

  const studio = await studioFor(studentId);
  const { data: stu } = await db.from('students')
    .select('user_id').eq('id', studentId).maybeSingle();
  const { data: p } = stu?.user_id
    ? await db.from('profiles').select('first_name,last_name').eq('id', stu.user_id).maybeSingle()
    : { data: null };
  const name = `${p?.first_name ?? ''} ${p?.last_name ?? ''}`.trim();

  await db.from('tasks').insert({
    title:        `Finance follow-up — ${name}`,
    subject_type: 'student', subject_id: studentId,
    studio_id:    studio?.id ?? null,
    assigned_to:  sentBy ?? null,
    due_date:     toISODate(new Date()),   // chase straight away
    created_by:   sentBy ?? null,
    source:       'system',
  });

  return 'sent';
}

// 4 — Farewell, when the End enrolment process starts
async function sendFarewellEmail(studentId, sentBy) {
  return sendStudentEmail(studentId,
    'Farewell for now, {{first_name}}!',
    `Until next time, {{first_name}}!\n\n` +
    `Sorry to hear that you're finishing up lessons with us soon! Hopefully it's not ` +
    `for too long :)\n\n` +
    `Congratulations on your progress, and try to keep up the practice at least every ` +
    `few days, even if it's just to play easy, fun stuff!\n\n` +
    `You'll be able to see when your last lessons are booked for in the Student ` +
    `Portal, but if you're unsure, just ask us.\n\n` +
    `Finally, if there's feedback you want to pass on to us or your teacher, please ` +
    `reply to this email — we really appreciate it!\n\n` +
    SIGNATURE, sentBy);
}


// ============================================================
// AUTOMATIC TASKS
//
// Due dates are calculated from the lessons, not typed. An admin
// can still move them.
// ============================================================

async function studentName(studentId) {
  const { data: s } = await db.from('students')
    .select('user_id').eq('id', studentId).maybeSingle();
  if (!s?.user_id) return '';
  const { data: p } = await db.from('profiles')
    .select('first_name,last_name').eq('id', s.user_id).maybeSingle();
  return `${p?.first_name ?? ''} ${p?.last_name ?? ''}`.trim();
}

// The student's active lessons, split by whether they recur.
// A trial is a single occurrence; a series recurs. Dating an
// enrolment task from the trial lesson would be wrong.
async function lessonsFor(studentId, since = null) {
  const { data: ls } = await db.from('lesson_students')
    .select('lesson_id').eq('student_id', studentId);
  const ids = (ls ?? []).map(r => r.lesson_id);
  if (!ids.length) return { all: [], series: [] };

  // A returning student has lessons from last time. Only what was
  // booked for this process should date its tasks.
  let q = db.from('lessons').select('id,status,created_at').in('id', ids);
  if (since) q = q.gte('created_at', since);
  const { data: lessons } = await q;
  const active = (lessons ?? []).filter(l => l.status === 'active');

  const series = [];
  for (const l of active) {
    const { count } = await db.from('lesson_occurrences')
      .select('id', { count: 'exact', head: true }).eq('lesson_id', l.id);
    if ((count ?? 0) > 1) series.push(l.id);
  }
  return { all: active.map(l => l.id), series };
}

// First upcoming occurrence. `seriesOnly` restricts it to a recurring
// lesson, which is what an enrolment's dates should be based on.
async function firstOccurrenceDate(studentId, seriesOnly = false, since = null) {
  const { all, series } = await lessonsFor(studentId, since);
  const ids = seriesOnly ? series : all;
  if (!ids.length) return null;

  // Occurrences from a previous enrolment may still sit as 'scheduled'
  // if nobody marked them off. A first lesson that has already happened
  // is not the first lesson of a new arrangement.
  const { data: occ } = await db.from('lesson_occurrences')
    .select('date').in('lesson_id', ids)
    .eq('status','scheduled')
    .gte('date', toISODate(new Date()))
    .order('date').limit(1);
  return occ?.[0]?.date ?? null;
}

function plusDays(dateStr, days) {
  const d = parseLocalDate(dateStr);
  d.setDate(d.getDate() + days);
  return toISODate(d);
}

async function createProcessTasks(studentId, processType, createdBy, since = null) {
  const studio = await studioFor(studentId);
  const name   = await studentName(studentId);
  const today  = toISODate(new Date());
  const rows   = [];

  const add = (title, due) => rows.push({
    title:        `${title} — ${name}`,
    subject_type: 'student', subject_id: studentId,
    studio_id:    studio?.id ?? null,
    assigned_to:  createdBy ?? null,
    due_date:     due ?? today,
    created_by:   createdBy ?? null,
    source:       'process',
  });

  if (processType === 'trial_confirmation') {
    // People leave payment to the last minute, so the check falls on
    // the day of the lesson itself.
    const trialDate = await firstOccurrenceDate(studentId, false, since);
    add('Check payment for trial lesson', trialDate);
    add('Trial follow-up',                trialDate);

  } else if (processType === 'ongoing_enrolment') {
    const first = await firstOccurrenceDate(studentId, true, since);
    add('Check payment for first lesson', first);
    // A fortnight after the first lesson — long enough to have settled in
    add('Check-in with student', first ? plusDays(first, 14) : null);

  } else if (processType === 'end_enrolment') {
    // The last lesson across everything they are enrolled in — not
    // scoped to this process, since ending covers all of it.
    const { all } = await lessonsFor(studentId);
    let last = null;
    if (all.length) {
      const { data: occ } = await db.from('lesson_occurrences')
        .select('date').in('lesson_id', all)
        .neq('status','cancelled')
        .order('date', { ascending: false }).limit(1);
      last = occ?.[0]?.date ?? null;
    }
    let due = today;
    if (last) { const d = parseLocalDate(last); d.setDate(d.getDate() + 7); due = toISODate(d); }
    add('Mark student inactive', due);
  }

  if (rows.length) {
    const { error } = await db.from('tasks').insert(rows);
    if (error) console.error('[processes] could not create tasks', error);
  }
  return rows.length;
}


// ------------------------------------------------------------
// A process starts at conversion, before the lesson exists, so its
// task due dates fall back to today. Once the lesson is booked the
// real dates are known — move them across.
//
// Only touches tasks still sitting on their fallback date, so an
// admin who has deliberately rescheduled one is left alone.
// ------------------------------------------------------------
async function realignProcessTasks(studentId) {
  const { data: procs } = await db.from('student_processes')
    .select('id,process_type,started_at').eq('student_id', studentId)
    .eq('status','in_progress').order('started_at', { ascending: false });
  if (!procs?.length) return;

  // Dates come from lessons booked since the current process began
  const since = procs[0].started_at;
  const anyFirst    = await firstOccurrenceDate(studentId, false, since);
  const seriesFirst = await firstOccurrenceDate(studentId, true,  since);
  if (!anyFirst && !seriesFirst) return;

  const WANTED = {
    'check payment for trial lesson': anyFirst,
    'trial follow-up':                anyFirst,
    'check payment for first lesson': seriesFirst,
    'check-in with student':          seriesFirst ? plusDays(seriesFirst, 14) : null,
  };

  const { data: open } = await db.from('tasks')
    .select('id,title,due_date,created_at')
    .eq('subject_type','student').eq('subject_id', studentId)
    .eq('status','open').eq('source','process');

  for (const t of (open ?? [])) {
    const key = String(t.title ?? '').split(' — ')[0].toLowerCase();
    const want = WANTED[key];
    if (!want || t.due_date === want) continue;


    // Leave anything an admin has already moved
    const createdOn = String(t.created_at ?? '').slice(0, 10);
    if (t.due_date && t.due_date !== createdOn) continue;

    await db.from('tasks').update({ due_date: want }).eq('id', t.id);
  }
}
