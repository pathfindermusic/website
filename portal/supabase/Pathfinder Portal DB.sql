-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE public.studios (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  address text,
  email text,
  status text NOT NULL DEFAULT 'active'::text CHECK (status = ANY (ARRAY['active'::text, 'inactive'::text])),
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT studios_pkey PRIMARY KEY (id)
);
CREATE TABLE public.profiles (
  id uuid NOT NULL,
  first_name text NOT NULL,
  last_name text NOT NULL,
  phone text,
  role text NOT NULL CHECK (role = ANY (ARRAY['superuser'::text, 'admin'::text, 'teacher'::text, 'student'::text])),
  status text NOT NULL DEFAULT 'active'::text CHECK (status = ANY (ARRAY['active'::text, 'inactive'::text])),
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  must_change_password boolean NOT NULL DEFAULT false,
  CONSTRAINT profiles_pkey PRIMARY KEY (id)
);
CREATE TABLE public.admins (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL,
  studio_ids ARRAY NOT NULL DEFAULT '{}'::uuid[],
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT admins_pkey PRIMARY KEY (id),
  CONSTRAINT admins_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id)
);
CREATE TABLE public.teachers (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL,
  instruments ARRAY NOT NULL DEFAULT '{}'::text[],
  studio_ids ARRAY NOT NULL DEFAULT '{}'::uuid[],
  virtual_room_link text,
  created_at timestamp with time zone DEFAULT now(),
  teaching_room text,
  CONSTRAINT teachers_pkey PRIMARY KEY (id),
  CONSTRAINT teachers_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id)
);
CREATE TABLE public.teacher_availability (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  teacher_id uuid NOT NULL,
  studio_id uuid NOT NULL,
  day_of_week integer NOT NULL CHECK (day_of_week >= 0 AND day_of_week <= 6),
  start_time time without time zone NOT NULL,
  end_time time without time zone NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT teacher_availability_pkey PRIMARY KEY (id),
  CONSTRAINT teacher_availability_teacher_id_fkey FOREIGN KEY (teacher_id) REFERENCES public.teachers(id),
  CONSTRAINT teacher_availability_studio_id_fkey FOREIGN KEY (studio_id) REFERENCES public.studios(id)
);
CREATE TABLE public.students (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL,
  parent_name text,
  parent_phone text,
  parent_email text,
  status text NOT NULL DEFAULT 'active'::text CHECK (status = ANY (ARRAY['prospective'::text, 'trial'::text, 'active'::text, 'inactive'::text, 'lapsed'::text])),
  created_at timestamp with time zone DEFAULT now(),
  studio_id uuid,
  email text,
  enquiry_notes text,
  enquiry_date date,
  enquiry_source text CHECK (enquiry_source IS NULL OR (enquiry_source = ANY (ARRAY['website'::text, 'phone'::text, 'walk_in'::text]))),
  lapsed_reason text,
  CONSTRAINT students_pkey PRIMARY KEY (id),
  CONSTRAINT students_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id),
  CONSTRAINT students_studio_id_fkey FOREIGN KEY (studio_id) REFERENCES public.studios(id)
);
CREATE TABLE public.student_instruments (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  student_id uuid NOT NULL,
  instrument text NOT NULL,
  skill_level integer NOT NULL DEFAULT 0 CHECK (skill_level >= 0 AND skill_level <= 8),
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT student_instruments_pkey PRIMARY KEY (id),
  CONSTRAINT student_instruments_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(id)
);
CREATE TABLE public.student_teachers (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  student_id uuid NOT NULL,
  teacher_id uuid NOT NULL,
  instrument text NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT student_teachers_pkey PRIMARY KEY (id),
  CONSTRAINT student_teachers_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(id),
  CONSTRAINT student_teachers_teacher_id_fkey FOREIGN KEY (teacher_id) REFERENCES public.teachers(id)
);
CREATE TABLE public.lessons (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  student_id uuid,
  teacher_id uuid NOT NULL,
  studio_id uuid NOT NULL,
  instrument text NOT NULL,
  day_of_week integer NOT NULL CHECK (day_of_week >= 0 AND day_of_week <= 6),
  start_time time without time zone NOT NULL,
  duration_mins integer NOT NULL CHECK (duration_mins = ANY (ARRAY[30, 60, 90, 120])),
  recurrence_type text NOT NULL DEFAULT 'indefinite'::text CHECK (recurrence_type = ANY (ARRAY['indefinite'::text, 'occurrences'::text, 'date_range'::text])),
  recurrence_count integer,
  recurrence_start date,
  recurrence_end date,
  status text NOT NULL DEFAULT 'active'::text CHECK (status = ANY (ARRAY['active'::text, 'cancelled'::text])),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  lesson_type text NOT NULL DEFAULT 'private'::text CHECK (lesson_type = ANY (ARRAY['private'::text, 'group'::text])),
  max_students integer NOT NULL DEFAULT 1,
  series_notes text,
  CONSTRAINT lessons_pkey PRIMARY KEY (id),
  CONSTRAINT lessons_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(id),
  CONSTRAINT lessons_teacher_id_fkey FOREIGN KEY (teacher_id) REFERENCES public.teachers(id),
  CONSTRAINT lessons_studio_id_fkey FOREIGN KEY (studio_id) REFERENCES public.studios(id)
);
CREATE TABLE public.lesson_occurrences (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  lesson_id uuid NOT NULL,
  date date NOT NULL,
  status text NOT NULL DEFAULT 'scheduled'::text CHECK (status = ANY (ARRAY['scheduled'::text, 'cancelled'::text, 'completed'::text])),
  is_online boolean NOT NULL DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  occurrence_notes text,
  CONSTRAINT lesson_occurrences_pkey PRIMARY KEY (id),
  CONSTRAINT lesson_occurrences_lesson_id_fkey FOREIGN KEY (lesson_id) REFERENCES public.lessons(id)
);
CREATE TABLE public.attendance (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  lesson_occurrence_id uuid NOT NULL,
  status text CHECK (status = ANY (ARRAY['present'::text, 'absent_no_credit'::text, 'absent_notice'::text, 'teacher_cancelled'::text])),
  marked_by uuid,
  marked_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  student_id uuid NOT NULL,
  CONSTRAINT attendance_pkey PRIMARY KEY (id),
  CONSTRAINT attendance_lesson_occurrence_id_fkey FOREIGN KEY (lesson_occurrence_id) REFERENCES public.lesson_occurrences(id),
  CONSTRAINT attendance_marked_by_fkey FOREIGN KEY (marked_by) REFERENCES public.profiles(id),
  CONSTRAINT attendance_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(id)
);
CREATE TABLE public.lesson_notes (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  lesson_occurrence_id uuid NOT NULL UNIQUE,
  teacher_id uuid NOT NULL,
  note_text text,
  drive_link text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT lesson_notes_pkey PRIMARY KEY (id),
  CONSTRAINT lesson_notes_lesson_occurrence_id_fkey FOREIGN KEY (lesson_occurrence_id) REFERENCES public.lesson_occurrences(id),
  CONSTRAINT lesson_notes_teacher_id_fkey FOREIGN KEY (teacher_id) REFERENCES public.teachers(id)
);
CREATE TABLE public.lesson_students (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  lesson_id uuid NOT NULL,
  student_id uuid NOT NULL,
  joined_at timestamp with time zone DEFAULT now(),
  CONSTRAINT lesson_students_pkey PRIMARY KEY (id),
  CONSTRAINT lesson_students_lesson_id_fkey FOREIGN KEY (lesson_id) REFERENCES public.lessons(id),
  CONSTRAINT lesson_students_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(id)
);
CREATE TABLE public.email_log (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  sent_at timestamp with time zone NOT NULL DEFAULT now(),
  sent_by uuid,
  subject text,
  body text,
  recipient_mode text,
  recipient_count integer,
  recipients jsonb,
  bcc text,
  status text,
  error text,
  CONSTRAINT email_log_pkey PRIMARY KEY (id)
);
CREATE TABLE public.tasks (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  title text NOT NULL,
  subject_type text CHECK (subject_type = ANY (ARRAY['student'::text, 'teacher'::text])),
  subject_id uuid,
  studio_id uuid,
  assigned_to uuid,
  due_date date,
  status text NOT NULL DEFAULT 'open'::text CHECK (status = ANY (ARRAY['open'::text, 'done'::text, 'cancelled'::text])),
  source text NOT NULL DEFAULT 'manual'::text CHECK (source = ANY (ARRAY['manual'::text, 'process'::text, 'system'::text])),
  process_id uuid,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  completed_at timestamp with time zone,
  completed_by uuid,
  kind text NOT NULL DEFAULT 'task'::text CHECK (kind = ANY (ARRAY['task'::text, 'waitlist'::text])),
  awaiting_admin boolean NOT NULL DEFAULT false,
  CONSTRAINT tasks_pkey PRIMARY KEY (id),
  CONSTRAINT tasks_studio_id_fkey FOREIGN KEY (studio_id) REFERENCES public.studios(id)
);
CREATE TABLE public.task_notes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL,
  note_text text NOT NULL,
  contact_method text CHECK (contact_method = ANY (ARRAY['phone'::text, 'email'::text, 'sms'::text, 'in_person'::text])),
  outcome text CHECK (outcome IS NULL OR (outcome = ANY (ARRAY['spoke'::text, 'left_message'::text, 'unreachable'::text, 'sent'::text, 'replied'::text, 'reached'::text]))),
  logged_by uuid,
  logged_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT task_notes_pkey PRIMARY KEY (id),
  CONSTRAINT task_notes_task_id_fkey FOREIGN KEY (task_id) REFERENCES public.tasks(id)
);
CREATE TABLE public.task_handovers (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL,
  from_user uuid,
  to_user uuid,
  to_studio uuid,
  note text,
  moved_by uuid,
  moved_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT task_handovers_pkey PRIMARY KEY (id),
  CONSTRAINT task_handovers_task_id_fkey FOREIGN KEY (task_id) REFERENCES public.tasks(id),
  CONSTRAINT task_handovers_to_studio_fkey FOREIGN KEY (to_studio) REFERENCES public.studios(id)
);
CREATE TABLE public.student_processes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL,
  process_type text NOT NULL CHECK (process_type = ANY (ARRAY['trial_confirmation'::text, 'ongoing_enrolment'::text, 'end_enrolment'::text])),
  status text NOT NULL DEFAULT 'in_progress'::text CHECK (status = ANY (ARRAY['in_progress'::text, 'complete'::text, 'abandoned'::text])),
  started_by uuid,
  started_at timestamp with time zone NOT NULL DEFAULT now(),
  completed_at timestamp with time zone,
  CONSTRAINT student_processes_pkey PRIMARY KEY (id),
  CONSTRAINT student_processes_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(id)
);
CREATE TABLE public.process_items (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  process_id uuid NOT NULL,
  item_order integer NOT NULL,
  label text NOT NULL,
  auto_key text,
  is_done boolean NOT NULL DEFAULT false,
  done_by uuid,
  done_at timestamp with time zone,
  blocked_task_id uuid,
  sent_at timestamp with time zone,
  can_defer boolean NOT NULL DEFAULT false,
  CONSTRAINT process_items_pkey PRIMARY KEY (id),
  CONSTRAINT process_items_process_id_fkey FOREIGN KEY (process_id) REFERENCES public.student_processes(id),
  CONSTRAINT process_items_blocked_task_id_fkey FOREIGN KEY (blocked_task_id) REFERENCES public.tasks(id)
);