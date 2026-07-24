-- ============================================================
-- PATHFINDER MUSIC LESSONS — STUDENT PORTAL
-- Supabase PostgreSQL Schema v1.0
-- Run this in the Supabase SQL Editor (in order)
-- ============================================================

-- Enable UUID generation
create extension if not exists "uuid-ossp";

-- ============================================================
-- 1. STUDIOS
-- ============================================================
create table studios (
  id          uuid primary key default uuid_generate_v4(),
  name        text not null,
  address     text,
  email       text,
  status      text not null default 'active' check (status in ('active','inactive')),
  created_at  timestamptz default now()
);

-- Seed studios
insert into studios (name, address, email) values
  ('Kilsyth',  '20 Collins Place, Kilsyth VIC 3137',          'kilsyth@pathfindermusiclessons.com.au'),
  ('Ringwood', 'G3 / 93a Heatherdale Road, Ringwood VIC 3134', 'ringwood@pathfindermusiclessons.com.au');

-- ============================================================
-- 2. PROFILES (extends Supabase auth.users)
-- ============================================================
create table profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  first_name    text not null,
  last_name     text not null,
  phone         text,
  role          text not null check (role in ('superuser','admin','teacher','student')),
  status        text not null default 'active' check (status in ('active','inactive')),
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);

-- ============================================================
-- 3. ADMINS
-- ============================================================
create table admins (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null references profiles(id) on delete cascade,
  studio_ids  uuid[] not null default '{}',  -- array of studio IDs they can access
  created_at  timestamptz default now()
);

-- ============================================================
-- 4. TEACHERS
-- ============================================================
create table teachers (
  id                uuid primary key default uuid_generate_v4(),
  user_id           uuid not null references profiles(id) on delete cascade,
  instruments       text[] not null default '{}',
  studio_ids        uuid[] not null default '{}',
  virtual_room_link text,
  created_at        timestamptz default now()
);

-- ============================================================
-- 5. TEACHER AVAILABILITY
-- ============================================================
create table teacher_availability (
  id           uuid primary key default uuid_generate_v4(),
  teacher_id   uuid not null references teachers(id) on delete cascade,
  studio_id    uuid not null references studios(id) on delete cascade,
  day_of_week  int  not null check (day_of_week between 0 and 6), -- 0=Sun, 1=Mon ... 6=Sat
  start_time   time not null,
  end_time     time not null,
  created_at   timestamptz default now()
);

-- ============================================================
-- 6. STUDENTS
-- ============================================================
create table students (
  id              uuid primary key default uuid_generate_v4(),
  user_id         uuid not null references profiles(id) on delete cascade,
  parent_name     text,
  parent_phone    text,
  parent_email    text,
  status          text not null default 'active' check (status in ('trial','active','inactive')),
  created_at      timestamptz default now()
);

-- ============================================================
-- 7. STUDENT INSTRUMENTS (up to 5 per student)
-- ============================================================
create table student_instruments (
  id          uuid primary key default uuid_generate_v4(),
  student_id  uuid not null references students(id) on delete cascade,
  instrument  text not null,
  skill_level int  not null default 0 check (skill_level between 0 and 8),
  created_at  timestamptz default now(),
  unique (student_id, instrument)
);

-- ============================================================
-- 8. STUDENT–TEACHER ASSIGNMENTS (one per instrument)
-- ============================================================
create table student_teachers (
  id          uuid primary key default uuid_generate_v4(),
  student_id  uuid not null references students(id) on delete cascade,
  teacher_id  uuid not null references teachers(id) on delete cascade,
  instrument  text not null,
  created_at  timestamptz default now(),
  unique (student_id, instrument)
);

-- ============================================================
-- 9. LESSONS (recurring template)
-- ============================================================
create table lessons (
  id               uuid primary key default uuid_generate_v4(),
  student_id       uuid not null references students(id) on delete cascade,
  teacher_id       uuid not null references teachers(id) on delete cascade,
  studio_id        uuid not null references studios(id) on delete cascade,
  instrument       text not null,
  day_of_week      int  not null check (day_of_week between 0 and 6),
  start_time       time not null,
  duration_mins    int  not null check (duration_mins in (30,60,90,120)),
  -- Recurrence
  recurrence_type  text not null default 'indefinite' check (recurrence_type in ('indefinite','occurrences','date_range')),
  recurrence_count int,           -- used when recurrence_type = 'occurrences'
  recurrence_start date,          -- first occurrence date
  recurrence_end   date,          -- used when recurrence_type = 'date_range'
  status           text not null default 'active' check (status in ('active','cancelled')),
  created_at       timestamptz default now(),
  updated_at       timestamptz default now()
);

-- ============================================================
-- 10. LESSON OCCURRENCES (each individual instance)
-- ============================================================
create table lesson_occurrences (
  id           uuid primary key default uuid_generate_v4(),
  lesson_id    uuid not null references lessons(id) on delete cascade,
  date         date not null,
  status       text not null default 'scheduled' check (status in ('scheduled','cancelled','completed')),
  is_online    boolean not null default false,
  created_at   timestamptz default now(),
  unique (lesson_id, date)
);

-- ============================================================
-- 11. ATTENDANCE
-- ============================================================
create table attendance (
  id                   uuid primary key default uuid_generate_v4(),
  lesson_occurrence_id uuid not null references lesson_occurrences(id) on delete cascade unique,
  status               text check (status in ('present','absent_no_credit','absent_notice','teacher_cancelled')),
  marked_by            uuid references profiles(id),
  marked_at            timestamptz,
  created_at           timestamptz default now()
);

-- ============================================================
-- 12. LESSON NOTES
-- ============================================================
create table lesson_notes (
  id                   uuid primary key default uuid_generate_v4(),
  lesson_occurrence_id uuid not null references lesson_occurrences(id) on delete cascade unique,
  teacher_id           uuid not null references teachers(id),
  note_text            text,
  drive_link           text,
  created_at           timestamptz default now(),
  updated_at           timestamptz default now()
);

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

-- Enable RLS on all tables
alter table studios             enable row level security;
alter table profiles            enable row level security;
alter table admins              enable row level security;
alter table teachers            enable row level security;
alter table teacher_availability enable row level security;
alter table students            enable row level security;
alter table student_instruments enable row level security;
alter table student_teachers    enable row level security;
alter table lessons             enable row level security;
alter table lesson_occurrences  enable row level security;
alter table attendance          enable row level security;
alter table lesson_notes        enable row level security;

-- Helper function: get the role of the current user
create or replace function get_my_role()
returns text as $$
  select role from profiles where id = auth.uid();
$$ language sql security definer stable;

-- Helper function: get the teacher id of the current user
create or replace function get_my_teacher_id()
returns uuid as $$
  select id from teachers where user_id = auth.uid();
$$ language sql security definer stable;

-- Helper function: get the student id of the current user
create or replace function get_my_student_id()
returns uuid as $$
  select id from students where user_id = auth.uid();
$$ language sql security definer stable;

-- ---- STUDIOS ----
create policy "Superuser and admin can view studios"
  on studios for select
  using (get_my_role() in ('superuser','admin','teacher','student'));

create policy "Only superuser can insert/update/delete studios"
  on studios for all
  using (get_my_role() = 'superuser');

-- ---- PROFILES ----
create policy "Users can view their own profile"
  on profiles for select
  using (id = auth.uid());

create policy "Superuser and admin can view all profiles"
  on profiles for select
  using (get_my_role() in ('superuser','admin'));

create policy "Users can update their own profile"
  on profiles for update
  using (id = auth.uid());

create policy "Superuser and admin can manage all profiles"
  on profiles for all
  using (get_my_role() in ('superuser','admin'));

-- ---- TEACHERS ----
create policy "Teachers can view their own record"
  on teachers for select
  using (user_id = auth.uid());

create policy "Admins and superuser can view and manage all teachers"
  on teachers for all
  using (get_my_role() in ('superuser','admin'));

create policy "Students can view teachers (name only via join)"
  on teachers for select
  using (get_my_role() = 'student');

-- ---- TEACHER AVAILABILITY ----
create policy "Admins and superuser manage availability"
  on teacher_availability for all
  using (get_my_role() in ('superuser','admin'));

create policy "Teachers view own availability"
  on teacher_availability for select
  using (teacher_id = get_my_teacher_id());

-- ---- STUDENTS ----
create policy "Students view own record"
  on students for select
  using (user_id = auth.uid());

create policy "Admins and superuser manage all students"
  on students for all
  using (get_my_role() in ('superuser','admin'));

create policy "Teachers view their assigned students only"
  on students for select
  using (
    get_my_role() = 'teacher'
    and id in (
      select student_id from student_teachers where teacher_id = get_my_teacher_id()
    )
  );

-- ---- STUDENT INSTRUMENTS ----
create policy "Student views own instruments"
  on student_instruments for select
  using (student_id = get_my_student_id());

create policy "Teacher views instruments of their students"
  on student_instruments for select
  using (
    get_my_role() = 'teacher'
    and student_id in (
      select student_id from student_teachers where teacher_id = get_my_teacher_id()
    )
  );

create policy "Teacher updates skill level for their students"
  on student_instruments for update
  using (
    get_my_role() = 'teacher'
    and student_id in (
      select student_id from student_teachers where teacher_id = get_my_teacher_id()
    )
  );

create policy "Admin and superuser manage all student instruments"
  on student_instruments for all
  using (get_my_role() in ('superuser','admin'));

-- ---- STUDENT TEACHERS ----
create policy "Admin and superuser manage assignments"
  on student_teachers for all
  using (get_my_role() in ('superuser','admin'));

create policy "Teacher views own assignments"
  on student_teachers for select
  using (teacher_id = get_my_teacher_id());

create policy "Student views own assignments"
  on student_teachers for select
  using (student_id = get_my_student_id());

-- ---- LESSONS ----
create policy "Admin and superuser manage all lessons"
  on lessons for all
  using (get_my_role() in ('superuser','admin'));

create policy "Teacher views own lessons"
  on lessons for select
  using (teacher_id = get_my_teacher_id());

create policy "Student views own lessons"
  on lessons for select
  using (student_id = get_my_student_id());

-- ---- LESSON OCCURRENCES ----
create policy "Admin and superuser manage all occurrences"
  on lesson_occurrences for all
  using (get_my_role() in ('superuser','admin'));

create policy "Teacher views and updates own lesson occurrences"
  on lesson_occurrences for select
  using (
    lesson_id in (select id from lessons where teacher_id = get_my_teacher_id())
  );

create policy "Student views own lesson occurrences"
  on lesson_occurrences for select
  using (
    lesson_id in (select id from lessons where student_id = get_my_student_id())
  );

-- ---- ATTENDANCE ----
create policy "Admin and superuser manage all attendance"
  on attendance for all
  using (get_my_role() in ('superuser','admin'));

create policy "Teacher marks attendance for own lessons"
  on attendance for all
  using (
    lesson_occurrence_id in (
      select lo.id from lesson_occurrences lo
      join lessons l on l.id = lo.lesson_id
      where l.teacher_id = get_my_teacher_id()
    )
  );

create policy "Student views own attendance"
  on attendance for select
  using (
    lesson_occurrence_id in (
      select lo.id from lesson_occurrences lo
      join lessons l on l.id = lo.lesson_id
      where l.student_id = get_my_student_id()
    )
  );

-- ---- LESSON NOTES ----
create policy "Admin and superuser read all notes"
  on lesson_notes for select
  using (get_my_role() in ('superuser','admin'));

create policy "Teacher manages own notes"
  on lesson_notes for all
  using (teacher_id = get_my_teacher_id());

create policy "Student reads own lesson notes"
  on lesson_notes for select
  using (
    lesson_occurrence_id in (
      select lo.id from lesson_occurrences lo
      join lessons l on l.id = lo.lesson_id
      where l.student_id = get_my_student_id()
    )
  );

-- ============================================================
-- TRIGGER: auto-create profile on new auth user sign-up
-- (used when admin creates accounts via Supabase dashboard)
-- ============================================================
create or replace function handle_new_user()
returns trigger as $$
begin
  -- Profile is inserted separately by admin after creating auth user
  return new;
end;
$$ language plpgsql security definer;

-- ============================================================
-- USEFUL VIEWS
-- ============================================================

-- Schedule view: joins all the info needed for a lesson card
create or replace view schedule_view as
select
  lo.id               as occurrence_id,
  lo.date,
  lo.status           as occurrence_status,
  lo.is_online,
  l.start_time,
  l.duration_mins,
  l.instrument,
  s.id                as studio_id,
  s.name              as studio_name,
  sp.first_name || ' ' || sp.last_name as student_name,
  st.id               as student_id,
  tp.first_name || ' ' || tp.last_name as teacher_name,
  t.id                as teacher_id,
  t.virtual_room_link,
  a.status            as attendance_status,
  a.marked_at         as attendance_marked_at,
  ln.note_text,
  ln.drive_link
from lesson_occurrences lo
join lessons         l   on l.id  = lo.lesson_id
join studios         s   on s.id  = l.studio_id
join students        st  on st.id = l.student_id
join profiles        sp  on sp.id = st.user_id
join teachers        t   on t.id  = l.teacher_id
join profiles        tp  on tp.id = t.user_id
left join attendance a   on a.lesson_occurrence_id = lo.id
left join lesson_notes ln on ln.lesson_occurrence_id = lo.id;

-- ============================================================
-- END OF SCHEMA
-- ============================================================
