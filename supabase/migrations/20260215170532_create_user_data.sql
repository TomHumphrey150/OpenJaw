-- Bruxism Dashboard: per-user data sync table
-- Run this once in Supabase SQL Editor for your project.

create table if not exists public.user_data (
  user_id uuid primary key references auth.users (id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default timezone('utc'::text, now())
);

alter table public.user_data enable row level security;

drop policy if exists "Users can read own data" on public.user_data;
create policy "Users can read own data"
  on public.user_data
  for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own data" on public.user_data;
create policy "Users can insert own data"
  on public.user_data
  for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own data" on public.user_data;
create policy "Users can update own data"
  on public.user_data
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete own data" on public.user_data;
create policy "Users can delete own data"
  on public.user_data
  for delete
  using (auth.uid() = user_id);
