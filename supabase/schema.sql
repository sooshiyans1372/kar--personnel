-- =========================================================
-- سامانه کارکرد پرسنل
-- Database Schema - Supabase / PostgreSQL
-- Version: 1.0
-- =========================================================

create extension if not exists pgcrypto;

-- =========================================================
-- 1. Departments
-- =========================================================

create table if not exists public.departments (
    id uuid primary key default gen_random_uuid(),

    name varchar(150) not null,
    code varchar(50),

    is_active boolean not null default true,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint uq_departments_name unique (name),
    constraint uq_departments_code unique (code)
);

create index if not exists idx_departments_active
on public.departments(is_active);


-- =========================================================
-- 2. Positions
-- =========================================================

create table if not exists public.positions (
    id uuid primary key default gen_random_uuid(),

    name varchar(150) not null,
    code varchar(50),

    is_active boolean not null default true,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint uq_positions_name unique (name),
    constraint uq_positions_code unique (code)
);

create index if not exists idx_positions_active
on public.positions(is_active);


-- =========================================================
-- 3. Employees
-- =========================================================

create table if not exists public.employees (
    id uuid primary key default gen_random_uuid(),

    personnel_code varchar(50) not null,
    first_name varchar(100) not null,
    last_name varchar(100) not null,

    national_code varchar(20),

    department_id uuid
        references public.departments(id)
        on delete set null,

    position_id uuid
        references public.positions(id)
        on delete set null,

    phone varchar(30),
    email varchar(150),

    hire_date date,
    termination_date date,

    is_active boolean not null default true,

    -- اطلاعاتی برای شناسایی در دستگاه حضور و غیاب
    device_personnel_code varchar(100),

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint uq_employees_personnel_code
        unique (personnel_code)
);

create unique index if not exists uq_employees_national_code
on public.employees(national_code)
where national_code is not null;

create index if not exists idx_employees_department
on public.employees(department_id);

create index if not exists idx_employees_active
on public.employees(is_active);

create index if not exists idx_employees_name
on public.employees(last_name, first_name);


-- =========================================================
-- 4. Roles
-- =========================================================

create table if not exists public.roles (
    id uuid primary key default gen_random_uuid(),

    name varchar(50) not null,
    title varchar(100) not null,

    created_at timestamptz not null default now(),

    constraint uq_roles_name unique(name)
);

insert into public.roles(name, title)
values
    ('admin', 'مدیر سیستم'),
    ('hr_manager', 'مدیر منابع انسانی'),
    ('supervisor', 'سرپرست'),
    ('user', 'کاربر عادی')
on conflict (name) do nothing;


-- =========================================================
-- 5. Users Profile
-- اتصال به Supabase Auth
-- =========================================================

create table if not exists public.user_profiles (
    id uuid primary key
        references auth.users(id)
        on delete cascade,

    employee_id uuid
        references public.employees(id)
        on delete set null,

    first_name varchar(100),
    last_name varchar(100),

    is_active boolean not null default true,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);


-- =========================================================
-- 6. User Roles
-- =========================================================

create table if not exists public.user_roles (
    user_id uuid not null
        references public.user_profiles(id)
        on delete cascade,

    role_id uuid not null
        references public.roles(id)
        on delete cascade,

    created_at timestamptz not null default now(),

    primary key(user_id, role_id)
);


-- =========================================================
-- 7. Work Calendars
-- =========================================================

create table if not exists public.work_calendars (
    id uuid primary key default gen_random_uuid(),

    name varchar(150) not null,

    work_start time not null default '07:30',
    work_end time not null default '15:00',

    required_minutes integer not null default 450,

    break_minutes integer not null default 0,

    is_active boolean not null default true,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint chk_required_minutes
        check(required_minutes >= 0),

    constraint chk_break_minutes
        check(break_minutes >= 0)
);

insert into public.work_calendars
(
    name,
    work_start,
    work_end,
    required_minutes,
    break_minutes
)
select
    'شیفت اداری',
    '07:30',
    '15:00',
    450,
    0
where not exists (
    select 1
    from public.work_calendars
    where name = 'شیفت اداری'
);


-- =========================================================
-- 8. Employee Calendar Assignment
-- =========================================================

create table if not exists public.employee_calendars (
    id uuid primary key default gen_random_uuid(),

    employee_id uuid not null
        references public.employees(id)
        on delete cascade,

    calendar_id uuid not null
        references public.work_calendars(id)
        on delete restrict,

    start_date date not null,
    end_date date,

    created_at timestamptz not null default now(),

    constraint chk_calendar_dates
        check(end_date is null or end_date >= start_date)
);

create index if not exists idx_employee_calendars_employee
on public.employee_calendars(employee_id);


-- =========================================================
-- 9. Raw Attendance
-- اطلاعات خام دستگاه - IMMUTABLE
-- =========================================================

create table if not exists public.raw_attendance (

    id uuid primary key default gen_random_uuid(),

    employee_id uuid
        references public.employees(id)
        on delete set null,

    personnel_code varchar(50),

    attendance_date date not null,

    attendance_time time not null,

    recorded_at timestamptz,

    device_code varchar(100),

    device_name varchar(150),

    transit_type varchar(30),

    source_file varchar(255),

    source_row integer,

    raw_data jsonb,

    imported_at timestamptz not null default now(),

    created_at timestamptz not null default now()
);

create index if not exists idx_raw_attendance_employee_date
on public.raw_attendance(employee_id, attendance_date);

create index if not exists idx_raw_attendance_personnel_date
on public.raw_attendance(personnel_code, attendance_date);

create index if not exists idx_raw_attendance_datetime
on public.raw_attendance(attendance_date, attendance_time);


-- =========================================================
-- 10. Attendance Intervals
-- =========================================================

create table if not exists public.attendance_intervals (

    id uuid primary key default gen_random_uuid(),

    employee_id uuid not null
        references public.employees(id)
        on delete cascade,

    work_date date not null,

    sequence_no integer not null,

    entry_at timestamptz,
    exit_at timestamptz,

    duration_minutes integer not null default 0,

    is_complete boolean not null default false,

    source_raw_entry_id uuid
        references public.raw_attendance(id)
        on delete set null,

    source_raw_exit_id uuid
        references public.raw_attendance(id)
        on delete set null,

    created_at timestamptz not null default now(),

    constraint uq_attendance_interval
        unique(employee_id, work_date, sequence_no),

    constraint chk_interval_duration
        check(duration_minutes >= 0)
);

create index if not exists idx_attendance_intervals_employee_date
on public.attendance_intervals(employee_id, work_date);


-- =========================================================
-- 11. Daily Attendance
-- =========================================================

create table if not exists public.daily_attendance (

    id uuid primary key default gen_random_uuid(),

    employee_id uuid not null
        references public.employees(id)
        on delete cascade,

    work_date date not null,

    calendar_id uuid
        references public.work_calendars(id)
        on delete set null,

    first_entry timestamptz,
    last_exit timestamptz,

    worked_minutes integer not null default 0,

    required_minutes integer not null default 0,

    overtime_minutes integer not null default 0,

    shortage_minutes integer not null default 0,

    work_day numeric(5,2) not null default 0,

    late_minutes integer not null default 0,

    early_leave_minutes integer not null default 0,

    hourly_leave_minutes integer not null default 0,

    absence_days numeric(5,2) not null default 0,

    is_present boolean not null default false,

    is_incomplete boolean not null default false,

    is_holiday boolean not null default false,

    is_locked boolean not null default false,

    calculation_version varchar(30) default '1.0',

    calculated_at timestamptz,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint uq_daily_attendance
        unique(employee_id, work_date),

    constraint chk_daily_worked
        check(worked_minutes >= 0),

    constraint chk_daily_required
        check(required_minutes >= 0),

    constraint chk_daily_overtime
        check(overtime_minutes >= 0),

    constraint chk_daily_shortage
        check(shortage_minutes >= 0)
);

create index if not exists idx_daily_attendance_date
on public.daily_attendance(work_date);

create index if not exists idx_daily_attendance_employee
on public.daily_attendance(employee_id);

create index if not exists idx_daily_attendance_employee_date
on public.daily_attendance(employee_id, work_date);


-- =========================================================
-- 12. Leave Types
-- =========================================================

create table if not exists public.leave_types (

    id uuid primary key default gen_random_uuid(),

    name varchar(100) not null,

    code varchar(50) not null,

    is_hourly boolean not null default false,

    is_paid boolean not null default true,

    created_at timestamptz not null default now(),

    constraint uq_leave_types_code unique(code)
);

insert into public.leave_types
(name, code, is_hourly, is_paid)
values
    ('مرخصی ساعتی', 'HOURLY', true, true),
    ('مرخصی روزانه', 'DAILY', false, true)
on conflict(code) do nothing;


-- =========================================================
-- 13. Leaves
-- =========================================================

create table if not exists public.leaves (

    id uuid primary key default gen_random_uuid(),

    employee_id uuid not null
        references public.employees(id)
        on delete cascade,

    leave_type_id uuid not null
        references public.leave_types(id)
        on delete restrict,

    start_at timestamptz not null,
    end_at timestamptz not null,

    minutes integer not null default 0,

    status varchar(30) not null default 'approved',

    description text,

    created_by uuid
        references auth.users(id)
        on delete set null,

    created_at timestamptz not null default now(),

    constraint chk_leave_dates
        check(end_at >= start_at),

    constraint chk_leave_minutes
        check(minutes >= 0)
);

create index if not exists idx_leaves_employee
on public.leaves(employee_id);

create index if not exists idx_leaves_dates
on public.leaves(start_at, end_at);


-- =========================================================
-- 14. Missions
-- =========================================================

create table if not exists public.missions (

    id uuid primary key default gen_random_uuid(),

    employee_id uuid not null
        references public.employees(id)
        on delete cascade,

    start_at timestamptz not null,
    end_at timestamptz not null,

    description text,

    status varchar(30) not null default 'approved',

    created_by uuid
        references auth.users(id)
        on delete set null,

    created_at timestamptz not null default now(),

    constraint chk_mission_dates
        check(end_at >= start_at)
);


-- =========================================================
-- 15. Overtime
-- =========================================================

create table if not exists public.overtimes (

    id uuid primary key default gen_random_uuid(),

    employee_id uuid not null
        references public.employees(id)
        on delete cascade,

    work_date date not null,

    minutes integer not null default 0,

    reason text,

    status varchar(30) not null default 'approved',

    created_by uuid
        references auth.users(id)
        on delete set null,

    created_at timestamptz not null default now(),

    constraint chk_overtime_minutes
        check(minutes >= 0),

    constraint uq_employee_overtime_date
        unique(employee_id, work_date)
);


-- =========================================================
-- 16. Payroll Periods
-- =========================================================

create table if not exists public.payroll_periods (

    id uuid primary key default gen_random_uuid(),

    title varchar(150) not null,

    start_date date not null,
    end_date date not null,

    status varchar(30) not null default 'open',

    locked_at timestamptz,

    locked_by uuid
        references auth.users(id)
        on delete set null,

    created_at timestamptz not null default now(),

    constraint chk_payroll_dates
        check(end_date >= start_date)
);


-- =========================================================
-- 17. Payroll Adjustments
-- =========================================================

create table if not exists public.payroll_adjustments (

    id uuid primary key default gen_random_uuid(),

    payroll_period_id uuid not null
        references public.payroll_periods(id)
        on delete cascade,

    employee_id uuid not null
        references public.employees(id)
        on delete cascade,

    adjustment_type varchar(50) not null,

    minutes integer not null default 0,

    reason text not null,

    created_by uuid
        references auth.users(id)
        on delete set null,

    created_at timestamptz not null default now(),

    constraint chk_adjustment_minutes
        check(minutes >= 0)
);


-- =========================================================
-- 18. Audit Logs
-- =========================================================

create table if not exists public.audit_logs (

    id uuid primary key default gen_random_uuid(),

    user_id uuid
        references auth.users(id)
        on delete set null,

    action varchar(100) not null,

    table_name varchar(100),

    record_id uuid,

    old_data jsonb,
    new_data jsonb,

    ip_address inet,

    created_at timestamptz not null default now()
);

create index if not exists idx_audit_logs_created
on public.audit_logs(created_at desc);

create index if not exists idx_audit_logs_user
on public.audit_logs(user_id);


-- =========================================================
-- 19. Updated At Function
-- =========================================================

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;


-- =========================================================
-- 20. Updated At Triggers
-- =========================================================

drop trigger if exists trg_departments_updated
on public.departments;

create trigger trg_departments_updated
before update on public.departments
for each row
execute function public.set_updated_at();


drop trigger if exists trg_positions_updated
on public.positions;

create trigger trg_positions_updated
before update on public.positions
for each row
execute function public.set_updated_at();


drop trigger if exists trg_employees_updated
on public.employees;

create trigger trg_employees_updated
before update on public.employees
for each row
execute function public.set_updated_at();


drop trigger if exists trg_profiles_updated
on public.user_profiles;

create trigger trg_profiles_updated
before update on public.user_profiles
for each row
execute function public.set_updated_at();


drop trigger if exists trg_calendars_updated
on public.work_calendars;

create trigger trg_calendars_updated
before update on public.work_calendars
for each row
execute function public.set_updated_at();


drop trigger if exists trg_daily_attendance_updated
on public.daily_attendance;

create trigger trg_daily_attendance_updated
before update on public.daily_attendance
for each row
execute function public.set_updated_at();


-- =========================================================
-- 21. Automatically create user profile
-- =========================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin

    insert into public.user_profiles
    (
        id,
        first_name,
        last_name
    )
    values
    (
        new.id,
        coalesce(new.raw_user_meta_data->>'first_name', ''),
        coalesce(new.raw_user_meta_data->>'last_name', '')
    )
    on conflict(id) do nothing;

    return new;

end;
$$;


drop trigger if exists on_auth_user_created
on auth.users;

create trigger on_auth_user_created
after insert on auth.users
for each row
execute function public.handle_new_user();


-- =========================================================
-- 22. Security Helper
-- =========================================================

create or replace function public.has_role(
    requested_role varchar
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from public.user_roles ur
        join public.roles r
            on r.id = ur.role_id
        where ur.user_id = auth.uid()
        and r.name = requested_role
    );
$$;


-- =========================================================
-- 23. Enable RLS
-- =========================================================

alter table public.departments enable row level security;
alter table public.positions enable row level security;
alter table public.employees enable row level security;
alter table public.roles enable row level security;
alter table public.user_profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.work_calendars enable row level security;
alter table public.employee_calendars enable row level security;
alter table public.raw_attendance enable row level security;
alter table public.attendance_intervals enable row level security;
alter table public.daily_attendance enable row level security;
alter table public.leave_types enable row level security;
alter table public.leaves enable row level security;
alter table public.missions enable row level security;
alter table public.overtimes enable row level security;
alter table public.payroll_periods enable row level security;
alter table public.payroll_adjustments enable row level security;
alter table public.audit_logs enable row level security;


-- =========================================================
-- 24. Basic Policies
-- =========================================================

create policy "authenticated_departments_select"
on public.departments
for select
to authenticated
using (true);

create policy "authenticated_positions_select"
on public.positions
for select
to authenticated
using (true);

create policy "authenticated_employees_select"
on public.employees
for select
to authenticated
using (true);

create policy "authenticated_calendars_select"
on public.work_calendars
for select
to authenticated
using (true);

create policy "authenticated_daily_attendance_select"
on public.daily_attendance
for select
to authenticated
using (true);

create policy "authenticated_raw_attendance_select"
on public.raw_attendance
for select
to authenticated
using (true);

create policy "authenticated_leave_types_select"
on public.leave_types
for select
to authenticated
using (true);

create policy "authenticated_leaves_select"
on public.leaves
for select
to authenticated
using (true);

create policy "authenticated_overtimes_select"
on public.overtimes
for select
to authenticated
using (true);

create policy "authenticated_payroll_select"
on public.payroll_periods
for select
to authenticated
using (true);


-- =========================================================
-- 25. Admin Policies
-- =========================================================

create policy "admin_employees_insert"
on public.employees
for insert
to authenticated
with check (
    public.has_role('admin')
    or public.has_role('hr_manager')
);

create policy "admin_employees_update"
on public.employees
for update
to authenticated
using (
    public.has_role('admin')
    or public.has_role('hr_manager')
)
with check (
    public.has_role('admin')
    or public.has_role('hr_manager')
);


create policy "admin_employees_delete"
on public.employees
for delete
to authenticated
using (
    public.has_role('admin')
);


-- =========================================================
-- 26. Raw Attendance Insert
-- =========================================================

create policy "attendance_import_insert"
on public.raw_attendance
for insert
to authenticated
with check (
    public.has_role('admin')
    or public.has_role('hr_manager')
);


-- =========================================================
-- 27. Audit Insert
-- =========================================================

create policy "authenticated_audit_insert"
on public.audit_logs
for insert
to authenticated
with check (
    user_id = auth.uid()
);


-- =========================================================
-- 28. Grants
-- =========================================================

grant usage on schema public
to anon, authenticated;

grant select on
    public.departments,
    public.positions,
    public.employees,
    public.roles,
    public.user_profiles,
    public.user_roles,
    public.work_calendars,
    public.employee_calendars,
    public.raw_attendance,
    public.attendance_intervals,
    public.daily_attendance,
    public.leave_types,
    public.leaves,
    public.missions,
    public.overtimes,
    public.payroll_periods,
    public.payroll_adjustments,
    public.audit_logs
to authenticated;

grant insert, update on public.employees
to authenticated;

grant insert on public.raw_attendance
to authenticated;

grant insert on public.audit_logs
to authenticated;


-- =========================================================
-- پایان Schema
-- =========================================================
