-- StreetWalk in-App feedback from Settings > Help and Feedback.
-- Deploy once after 001_init.sql through an authorized migration process; before deployment, sending fails and the local draft remains.
--
-- Authenticated anonymous users may insert their own feedback only; no App user can select, update or delete it under these policies.
-- Developers can inspect feedback through authorized Supabase Table Editor or SQL Editor access.
--   select created_at, lang, app_version, device, os, demo, body from public.feedback order by created_at desc;
-- No location is stored; user_id is an anonymous account without phone/email. Deleting that auth account cascades to feedback.

create table public.feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  lang text check (lang in ('yue', 'cmn')),
  app_version text check (char_length(app_version) <= 40),
  device text check (char_length(device) <= 60),
  os text check (char_length(os) <= 40),
  demo boolean not null default false,
  created_at timestamptz not null default now()
);
create index feedback_created on public.feedback (created_at desc);

alter table public.feedback enable row level security;
revoke all on public.feedback from anon;

-- As in 001, RLS allows only this insert policy and denies reads/updates/deletes without policies.
create policy "insert own feedback" on public.feedback for insert to authenticated
  with check (user_id = auth.uid());
