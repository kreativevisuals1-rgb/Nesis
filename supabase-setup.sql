-- ============================================================================
-- NESIS — Supabase setup
-- Run this once in Supabase Dashboard → SQL Editor → New query → Run.
-- Safe to re-run: uses "if not exists" / "or replace" everywhere it can.
-- ============================================================================

create extension if not exists pgcrypto;

-- ----------------------------------------------------------------------------
-- 1. Registrations table
-- ----------------------------------------------------------------------------
create table if not exists registrations (
  id              uuid primary key default gen_random_uuid(),
  created_at      timestamptz not null default now(),
  reference       text unique not null,
  parent_name     text not null,
  parent_phone    text not null,
  parent_email    text,
  child_name      text not null,
  child_age       int not null check (child_age between 10 and 17),
  course          text not null check (course in (
                    'ai-explorer','young-speaker','code-create',
                    'digital-creator','young-entrepreneur'
                  )),
  status          text not null default 'pending_payment' check (status in (
                    'pending_payment','pending_verification','verified','rejected','cancelled'
                  )),
  pop_path        text,          -- storage path of the uploaded proof of payment
  verified_at     timestamptz,
  verified_by     text,          -- optional: admin name/email, set manually when verifying
  admin_note      text           -- optional: why a payment was rejected, etc.
);

create index if not exists idx_registrations_course_status on registrations (course, status);
create index if not exists idx_registrations_reference on registrations (reference);

alter table registrations enable row level security;

-- ----------------------------------------------------------------------------
-- 2. Capacity guard — hard server-side limit of 4 active registrations
--    per course, so two parents can never both take the "last seat" at once.
--    Adjust the "4" below if CONFIG.CAPACITY_PER_COURSE ever changes.
-- ----------------------------------------------------------------------------
create or replace function enforce_course_capacity()
returns trigger
language plpgsql
as $$
declare
  taken int;
begin
  select count(*) into taken
  from registrations
  where course = new.course
    and status in ('pending_payment','pending_verification','verified')
    and id <> new.id;

  if taken >= 4 then
    raise exception 'capacity_reached: this programme is full';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_course_capacity on registrations;
create trigger trg_enforce_course_capacity
  before insert on registrations
  for each row execute function enforce_course_capacity();

-- ----------------------------------------------------------------------------
-- 3. Public-safe status view — exposes only what the website needs to show
--    (no parent/child personal details), so it's safe to make readable by
--    anyone with the anon key.
-- ----------------------------------------------------------------------------
create or replace view registration_status as
  select id, reference, course, status
  from registrations;

grant select on registration_status to anon, authenticated;

-- ----------------------------------------------------------------------------
-- 4. RLS policies on the base table
--    - anon can INSERT a new registration (status must start as pending_payment)
--    - anon CANNOT select/update the base table directly (use the view + RPC below)
-- ----------------------------------------------------------------------------
drop policy if exists "public can insert registrations" on registrations;
create policy "public can insert registrations"
  on registrations for insert
  to anon
  with check ( status = 'pending_payment' );

-- (No anon SELECT/UPDATE/DELETE policies are created on purpose — the
--  registration_status view and the RPC function below are the only
--  public-facing read/write paths. You, the admin, verify/reject payments
--  from the Table Editor in the Supabase Dashboard, which uses your
--  service-role access and bypasses RLS.)

-- ----------------------------------------------------------------------------
-- 5. RPC: submit proof of payment
--    Called by the site after the file is uploaded to Storage. Only allowed
--    to move a row from pending_payment -> pending_verification, and only
--    allowed to set pop_path — parents can never set status to "verified"
--    themselves.
-- ----------------------------------------------------------------------------
create or replace function submit_proof_of_payment(reg_id uuid, path text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update registrations
  set pop_path = path,
      status = 'pending_verification'
  where id = reg_id
    and status = 'pending_payment';
end;
$$;

grant execute on function submit_proof_of_payment(uuid, text) to anon;

-- ----------------------------------------------------------------------------
-- 6. Storage bucket for proof-of-payment uploads
--    Private bucket: parents can upload, but nobody can list/download
--    without your service-role access (Dashboard → Storage).
-- ----------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('proof-of-payment', 'proof-of-payment', false)
on conflict (id) do nothing;

drop policy if exists "anon can upload proof of payment" on storage.objects;
create policy "anon can upload proof of payment"
  on storage.objects for insert
  to anon
  with check ( bucket_id = 'proof-of-payment' );

-- ============================================================================
-- HOW TO VERIFY A PAYMENT (manual, day-to-day admin task)
-- ============================================================================
-- The Admin panel (admin.html) now does steps 1 and 2 below for you with a
-- button click. This section is kept as a fallback / explanation of what
-- those buttons actually do.
-- ----------------------------------------------------------------------------
-- 1. Storage → proof-of-payment → open the file for a given reference code
--    and eyeball it against your bank statement.
-- 2. Table Editor → registrations → find the row (search by "reference") →
--    edit the "status" cell:
--       verified  → payment confirmed, parent's button becomes "Join Class"
--       rejected  → proof didn't match/was unreadable, parent is asked to
--                   re-upload (also set "admin_note" so you remember why)
--    Optionally set "verified_at" = now() and "verified_by" = your name.
-- That's it — the website polls this table via the anon-safe view above,
-- so the parent's next visit (or "Check my status" lookup) picks it up
-- automatically. No code changes needed.
-- ============================================================================


-- ============================================================================
-- 7. ADMIN PANEL SUPPORT
--    Everything below powers admin.html: logging in, approving/rejecting
--    registrations from a UI instead of the Table Editor, managing course
--    materials, and editing WhatsApp/bank settings without touching code.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 7a. Let signed-in (authenticated) admins fully manage registrations.
--     Anyone who can sign in was invited by you (see "creating an admin
--     user" below) — there's no separate "admin" role/flag in this MVP,
--     every authenticated user has full admin rights.
-- ----------------------------------------------------------------------------
grant select, update on registrations to authenticated;

drop policy if exists "admin can view registrations" on registrations;
create policy "admin can view registrations"
  on registrations for select
  to authenticated
  using ( true );

drop policy if exists "admin can update registrations" on registrations;
create policy "admin can update registrations"
  on registrations for update
  to authenticated
  using ( true )
  with check ( true );

-- Let admins generate a signed URL to view an uploaded proof of payment.
drop policy if exists "admin can view proof of payment" on storage.objects;
create policy "admin can view proof of payment"
  on storage.objects for select
  to authenticated
  using ( bucket_id = 'proof-of-payment' );

-- ----------------------------------------------------------------------------
-- 7b. courses — per-course WhatsApp group links, editable from
--     Admin → Settings. The site (index.html) reads this table and falls
--     back to config.js if a row/column is empty.
-- ----------------------------------------------------------------------------
create table if not exists courses (
  slug           text primary key,
  name           text not null,
  whatsapp_group text
);

insert into courses (slug, name) values
  ('ai-explorer',        'AI Explorer'),
  ('young-speaker',      'Young Speaker'),
  ('code-create',        'Code & Create'),
  ('digital-creator',    'Digital Creator'),
  ('young-entrepreneur', 'Young Entrepreneur')
on conflict (slug) do nothing;

alter table courses enable row level security;
grant select on courses to anon, authenticated;
grant update on courses to authenticated;

drop policy if exists "public can read courses" on courses;
create policy "public can read courses" on courses for select to anon, authenticated using ( true );

drop policy if exists "admin can update courses" on courses;
create policy "admin can update courses" on courses for update to authenticated using ( true ) with check ( true );

-- ----------------------------------------------------------------------------
-- 7c. app_settings — simple key/value store for global settings
--     (WhatsApp business number, bank details), editable from
--     Admin → Settings.
-- ----------------------------------------------------------------------------
create table if not exists app_settings (
  key   text primary key,
  value text
);

insert into app_settings (key, value) values
  ('whatsapp_number',     '2340000000000'),
  ('bank_account_name',   'Nesis'),
  ('bank_account_number', '0000000000'),
  ('bank_name',           'Your Bank Name Here')
on conflict (key) do nothing;

alter table app_settings enable row level security;
grant select on app_settings to anon, authenticated;
grant insert, update on app_settings to authenticated;

drop policy if exists "public can read settings" on app_settings;
create policy "public can read settings" on app_settings for select to anon, authenticated using ( true );

drop policy if exists "admin can write settings" on app_settings;
create policy "admin can write settings" on app_settings for all to authenticated using ( true ) with check ( true );

-- ----------------------------------------------------------------------------
-- 7d. course_materials — downloadable PDFs/images/videos/links per course,
--     managed from Admin → Materials, shown to verified parents on the
--     public site (status check / "materials" link on a verified card).
-- ----------------------------------------------------------------------------
create table if not exists course_materials (
  id         uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  course     text not null check (course in (
               'ai-explorer','young-speaker','code-create',
               'digital-creator','young-entrepreneur'
             )),
  title      text not null,
  type       text not null check (type in ('pdf','image','video','link')),
  url        text not null
);

alter table course_materials enable row level security;
grant select on course_materials to anon, authenticated;
grant insert, delete on course_materials to authenticated;

drop policy if exists "public can read materials" on course_materials;
create policy "public can read materials" on course_materials for select to anon, authenticated using ( true );

drop policy if exists "admin can add materials" on course_materials;
create policy "admin can add materials" on course_materials for insert to authenticated with check ( true );

drop policy if exists "admin can delete materials" on course_materials;
create policy "admin can delete materials" on course_materials for delete to authenticated using ( true );

-- Storage bucket for course materials — public read (these aren't
-- sensitive), admin-only write.
insert into storage.buckets (id, name, public)
values ('course-materials', 'course-materials', true)
on conflict (id) do nothing;

drop policy if exists "public can read course materials files" on storage.objects;
create policy "public can read course materials files"
  on storage.objects for select
  to anon, authenticated
  using ( bucket_id = 'course-materials' );

drop policy if exists "admin can upload course materials" on storage.objects;
create policy "admin can upload course materials"
  on storage.objects for insert
  to authenticated
  with check ( bucket_id = 'course-materials' );

drop policy if exists "admin can delete course materials" on storage.objects;
create policy "admin can delete course materials"
  on storage.objects for delete
  to authenticated
  using ( bucket_id = 'course-materials' );

-- ============================================================================
-- CREATING AN ADMIN USER (do this once, per admin)
-- ============================================================================
-- Supabase Dashboard → Authentication → Users → "Add user" → enter an email
-- and password directly (skip the invite-email flow, or use it if you'd
-- rather they set their own password). That's the login for admin.html —
-- there's no separate signup form on the admin panel by design, so only
-- people you've explicitly added can ever get in.
-- ============================================================================

