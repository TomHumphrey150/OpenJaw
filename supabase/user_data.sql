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

create or replace function public.backfill_default_graph_if_missing(
  graph_data jsonb,
  last_modified text
)
returns boolean
language plpgsql
security invoker
set search_path = public
as $$
declare
  affected_rows integer := 0;
  trimmed_last_modified text := nullif(trim(last_modified), '');
  payload jsonb := jsonb_build_object(
    'graphData',
    coalesce(graph_data, jsonb_build_object('nodes', jsonb_build_array(), 'edges', jsonb_build_array())),
    'lastModified',
    trimmed_last_modified
  );
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  insert into public.user_data (user_id, data, updated_at)
  values (
    auth.uid(),
    jsonb_build_object('customCausalDiagram', payload),
    timezone('utc'::text, now())
  )
  on conflict (user_id) do update
  set
    data = jsonb_set(
      coalesce(public.user_data.data, '{}'::jsonb),
      '{customCausalDiagram}',
      payload,
      true
    ),
    updated_at = timezone('utc'::text, now())
  where public.user_data.data->'customCausalDiagram' is null;

  get diagnostics affected_rows = row_count;
  return affected_rows > 0;
end;
$$;

create or replace function public.upsert_user_data_patch(
  patch jsonb
)
returns boolean
language plpgsql
security invoker
set search_path = public
as $$
declare
  affected_rows integer := 0;
  safe_patch jsonb := coalesce(patch, '{}'::jsonb);
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if jsonb_typeof(safe_patch) is distinct from 'object' then
    raise exception 'Patch must be a JSON object';
  end if;

  insert into public.user_data (user_id, data, updated_at)
  values (
    auth.uid(),
    safe_patch,
    timezone('utc'::text, now())
  )
  on conflict (user_id) do update
  set
    data = coalesce(public.user_data.data, '{}'::jsonb) || safe_patch,
    updated_at = timezone('utc'::text, now());

  get diagnostics affected_rows = row_count;
  return affected_rows > 0;
end;
$$;
