-- ============================================================
-- PATHFINDER PORTAL — Phase 6: Body of Knowledge / grading
-- framework, milestone 1 (schema + artefact library)
--
-- Source: "Pathfinder Music Lessons — Guitar Studio — Grading
-- Framework" (Sep 2026). Four tiers, nine grade levels. Guitar
-- only for now; every table below is instrument-generic so a
-- second instrument's framework can reuse bok_grade_levels and
-- follow the same pattern without a redesign.
--
-- What this migration does NOT do (deliberately, per the agreed
-- README plan): no weighted Repertoire/Technique/Knowledge
-- scoring, no Pass/Merit/Distinction banding, no certificates.
-- A grade milestone here is a fact a teacher/admin records
-- directly — same trust level as today's skill_level edit — not
-- something calculated from sub-scores. That's a later phase.
--
-- Four new tables:
--   bok_grade_levels          — the generic 9-level reference scale
--   bok_artefacts             — the library (chord charts, songs,
--                                backing tracks…), files stay on
--                                Google Drive, this just stores a
--                                link + classification
--   student_grade_milestones  — a student's grade history: one row
--                                per grade reached, so the *current*
--                                grade and *when* they reached every
--                                prior one both fall out of the same
--                                table
--   lesson_occurrence_artefacts — which artefacts a teacher picked
--                                for a given lesson occurrence
--
-- Plus one view, student_current_grades, so every screen that needs
-- "this student's current grade for this instrument" doesn't have
-- to hand-write the latest-row query.
--
-- ⚠ Run ONE STATEMENT AT A TIME and check each result.
-- ============================================================


-- ------------------------------------------------------------
-- 1. bok_grade_levels — generic reference scale, seeded once
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bok_grade_levels (
  id          uuid primary key default gen_random_uuid(),
  sort_order  int  not null unique,
  code        text not null unique,
  tier        text not null check (tier in ('Foundation','Beginner','Intermediate','Advanced')),
  label       text not null
);

INSERT INTO bok_grade_levels (sort_order, code, tier, label) VALUES
  (0, 'pre_grade_1', 'Foundation',   'Pre-Grade 1'),
  (1, 'grade_1',      'Beginner',    'Grade 1'),
  (2, 'grade_2',      'Beginner',    'Grade 2'),
  (3, 'grade_3',      'Beginner',    'Grade 3'),
  (4, 'grade_4',      'Intermediate','Grade 4'),
  (5, 'grade_5',      'Intermediate','Grade 5'),
  (6, 'grade_6',      'Intermediate','Grade 6'),
  (7, 'grade_7',      'Advanced',    'Grade 7'),
  (8, 'grade_8',      'Advanced',    'Grade 8')
ON CONFLICT (code) DO NOTHING;


-- ------------------------------------------------------------
-- 2. bok_artefacts — the library. Files live on Google Drive;
--    this is the classification + a link, never the file itself.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bok_artefacts (
  id             uuid primary key default gen_random_uuid(),
  instrument     text not null,
  grade_level_id uuid not null references bok_grade_levels(id),
  component      text not null check (component in ('repertoire','technique','knowledge')),
  title          text not null,
  description    text,
  drive_url      text,
  tags           text[] not null default '{}',
  is_active      boolean not null default true,
  created_by     uuid,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

CREATE INDEX IF NOT EXISTS bok_artefacts_lookup_idx
  ON bok_artefacts (instrument, grade_level_id, component);


-- ------------------------------------------------------------
-- 3. student_grade_milestones — history, not a single field.
--    "Current grade" = the row with the latest achieved_on for
--    that student/instrument (see the view below).
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS student_grade_milestones (
  id             uuid primary key default gen_random_uuid(),
  student_id     uuid not null references students(id) on delete cascade,
  instrument     text not null,
  grade_level_id uuid not null references bok_grade_levels(id),
  achieved_on    date not null default current_date,
  notes          text,
  recorded_by    uuid,
  created_at     timestamptz not null default now()
);

CREATE INDEX IF NOT EXISTS student_grade_milestones_student_idx
  ON student_grade_milestones (student_id, instrument, achieved_on desc);


-- ------------------------------------------------------------
-- 4. lesson_occurrence_artefacts — what a teacher picked for one
--    lesson occurrence. One row per occurrence, not per student
--    (matches lesson_notes: one shared note per occurrence, even
--    for a group lesson).
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS lesson_occurrence_artefacts (
  id            uuid primary key default gen_random_uuid(),
  occurrence_id uuid not null references lesson_occurrences(id) on delete cascade,
  artefact_id   uuid not null references bok_artefacts(id) on delete cascade,
  added_by      uuid,
  created_at    timestamptz not null default now(),
  unique (occurrence_id, artefact_id)
);

CREATE INDEX IF NOT EXISTS lesson_occurrence_artefacts_occurrence_idx
  ON lesson_occurrence_artefacts (occurrence_id);
CREATE INDEX IF NOT EXISTS lesson_occurrence_artefacts_artefact_idx
  ON lesson_occurrence_artefacts (artefact_id);


-- ------------------------------------------------------------
-- 5. student_current_grades — latest milestone per student per
--    instrument, joined to its label/tier. Every screen showing
--    a grade badge reads this instead of re-deriving it.
-- ------------------------------------------------------------
DROP VIEW IF EXISTS student_current_grades;

CREATE VIEW student_current_grades AS
SELECT DISTINCT ON (m.student_id, m.instrument)
  m.student_id,
  m.instrument,
  m.grade_level_id,
  m.achieved_on,
  m.notes,
  gl.code,
  gl.label,
  gl.tier,
  gl.sort_order
FROM student_grade_milestones m
JOIN bok_grade_levels gl ON gl.id = m.grade_level_id
ORDER BY m.student_id, m.instrument, m.achieved_on DESC, m.created_at DESC;

ALTER VIEW student_current_grades SET (security_invoker = on);


-- ------------------------------------------------------------
-- 6. Row Level Security
-- ------------------------------------------------------------
ALTER TABLE bok_grade_levels           ENABLE ROW LEVEL SECURITY;
ALTER TABLE bok_artefacts              ENABLE ROW LEVEL SECURITY;
ALTER TABLE student_grade_milestones   ENABLE ROW LEVEL SECURITY;
ALTER TABLE lesson_occurrence_artefacts ENABLE ROW LEVEL SECURITY;

-- 6a. Grade levels — fixed reference data, readable by anyone
--     signed in, writable only by admins (in practice: never,
--     outside this migration's seed).
DROP POLICY IF EXISTS "Anyone signed in reads grade levels" ON bok_grade_levels;
CREATE POLICY "Anyone signed in reads grade levels"
  ON bok_grade_levels FOR SELECT
  USING (get_my_role() IS NOT NULL);

DROP POLICY IF EXISTS "Admins manage grade levels" ON bok_grade_levels;
CREATE POLICY "Admins manage grade levels"
  ON bok_grade_levels FOR ALL
  USING (get_my_role() IN ('superuser','admin'))
  WITH CHECK (get_my_role() IN ('superuser','admin'));

-- 6b. Artefacts — admins run the library; everyone signed in can
--     read the active items (teachers picking for a lesson,
--     students seeing what was covered). Retired (is_active=false)
--     items stay visible to admins only, so old links a student is
--     already looking at in their history don't 404 the row, just
--     stop being offered for new lessons.
DROP POLICY IF EXISTS "Anyone signed in reads active artefacts" ON bok_artefacts;
CREATE POLICY "Anyone signed in reads active artefacts"
  ON bok_artefacts FOR SELECT
  USING (is_active OR get_my_role() IN ('superuser','admin'));

DROP POLICY IF EXISTS "Admins manage artefacts" ON bok_artefacts;
CREATE POLICY "Admins manage artefacts"
  ON bok_artefacts FOR ALL
  USING (get_my_role() IN ('superuser','admin'))
  WITH CHECK (get_my_role() IN ('superuser','admin'));

-- 6c. Grade milestones — admins manage all; a teacher may
--     read/record/amend milestones for their own students only
--     (same shape as teacher-rls-fix.sql's skill_level policies);
--     a student reads their own.
DROP POLICY IF EXISTS "Admins manage grade milestones" ON student_grade_milestones;
CREATE POLICY "Admins manage grade milestones"
  ON student_grade_milestones FOR ALL
  USING (get_my_role() IN ('superuser','admin'))
  WITH CHECK (get_my_role() IN ('superuser','admin'));

DROP POLICY IF EXISTS "Teacher reads own student grade milestones" ON student_grade_milestones;
CREATE POLICY "Teacher reads own student grade milestones"
  ON student_grade_milestones FOR SELECT
  USING (
    student_id IN (
      SELECT ls.student_id
        FROM lesson_students ls
        JOIN lessons l ON l.id = ls.lesson_id
       WHERE l.teacher_id = get_my_teacher_id()
    )
  );

DROP POLICY IF EXISTS "Teacher records own student grade milestones" ON student_grade_milestones;
CREATE POLICY "Teacher records own student grade milestones"
  ON student_grade_milestones FOR INSERT
  WITH CHECK (
    student_id IN (
      SELECT ls.student_id
        FROM lesson_students ls
        JOIN lessons l ON l.id = ls.lesson_id
       WHERE l.teacher_id = get_my_teacher_id()
    )
  );

DROP POLICY IF EXISTS "Student reads own grade milestones" ON student_grade_milestones;
CREATE POLICY "Student reads own grade milestones"
  ON student_grade_milestones FOR SELECT
  USING (student_id = get_my_student_id());

-- 6d. Lesson-occurrence artefact picks — admins manage all; a
--     teacher manages picks on their own occurrences; a student
--     reads picks on their own occurrences (my_lesson_ids(), from
--     phase5-view-rls.sql, already exists).
DROP POLICY IF EXISTS "Admins manage occurrence artefacts" ON lesson_occurrence_artefacts;
CREATE POLICY "Admins manage occurrence artefacts"
  ON lesson_occurrence_artefacts FOR ALL
  USING (get_my_role() IN ('superuser','admin'))
  WITH CHECK (get_my_role() IN ('superuser','admin'));

DROP POLICY IF EXISTS "Teacher reads own occurrence artefacts" ON lesson_occurrence_artefacts;
CREATE POLICY "Teacher reads own occurrence artefacts"
  ON lesson_occurrence_artefacts FOR SELECT
  USING (
    occurrence_id IN (
      SELECT lo.id FROM lesson_occurrences lo
        JOIN lessons l ON l.id = lo.lesson_id
       WHERE l.teacher_id = get_my_teacher_id()
    )
  );

DROP POLICY IF EXISTS "Teacher picks own occurrence artefacts" ON lesson_occurrence_artefacts;
CREATE POLICY "Teacher picks own occurrence artefacts"
  ON lesson_occurrence_artefacts FOR INSERT
  WITH CHECK (
    occurrence_id IN (
      SELECT lo.id FROM lesson_occurrences lo
        JOIN lessons l ON l.id = lo.lesson_id
       WHERE l.teacher_id = get_my_teacher_id()
    )
  );

DROP POLICY IF EXISTS "Teacher removes own occurrence artefacts" ON lesson_occurrence_artefacts;
CREATE POLICY "Teacher removes own occurrence artefacts"
  ON lesson_occurrence_artefacts FOR DELETE
  USING (
    occurrence_id IN (
      SELECT lo.id FROM lesson_occurrences lo
        JOIN lessons l ON l.id = lo.lesson_id
       WHERE l.teacher_id = get_my_teacher_id()
    )
  );

DROP POLICY IF EXISTS "Student reads own occurrence artefacts" ON lesson_occurrence_artefacts;
CREATE POLICY "Student reads own occurrence artefacts"
  ON lesson_occurrence_artefacts FOR SELECT
  USING (
    occurrence_id IN (
      SELECT id FROM lesson_occurrences WHERE lesson_id = ANY(my_lesson_ids())
    )
  );


-- ------------------------------------------------------------
-- 7. PostgREST caches the schema
-- ------------------------------------------------------------
NOTIFY pgrst, 'reload schema';


-- ============================================================
-- VERIFY — run each separately
-- ============================================================

-- a. All four tables + the view exist
SELECT table_name FROM information_schema.tables
 WHERE table_name IN ('bok_grade_levels','bok_artefacts',
                       'student_grade_milestones','lesson_occurrence_artefacts')
 ORDER BY table_name;

-- b. Nine grade levels, in order
SELECT sort_order, code, tier, label FROM bok_grade_levels ORDER BY sort_order;

-- c. Every policy just created
SELECT tablename, policyname, cmd
  FROM pg_policies
 WHERE tablename IN ('bok_grade_levels','bok_artefacts',
                      'student_grade_milestones','lesson_occurrence_artefacts')
 ORDER BY tablename, cmd;

-- d. The view runs with the caller's own permissions
SELECT c.relname,
       COALESCE((SELECT option_value FROM pg_options_to_table(c.reloptions)
                  WHERE option_name = 'security_invoker'), 'off') AS security_invoker
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relname = 'student_current_grades';

-- e. Should be 0 until the portal starts using it
SELECT COUNT(*) FROM bok_artefacts;
