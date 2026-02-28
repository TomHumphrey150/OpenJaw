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

create table if not exists public.first_party_content (
  content_type text not null,
  content_key text not null,
  data jsonb not null,
  version integer not null default 1,
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  primary key (content_type, content_key),
  constraint first_party_content_type_check check (
    content_type in ('graph', 'inputs', 'outcomes', 'planning', 'citations', 'info')
  )
);

create table if not exists public.user_content (
  user_id uuid not null references auth.users (id) on delete cascade,
  content_type text not null,
  content_key text not null,
  data jsonb not null,
  version integer not null default 1,
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  primary key (user_id, content_type, content_key),
  constraint user_content_type_check check (
    content_type in ('graph', 'inputs', 'outcomes', 'planning', 'citations', 'info')
  )
);

alter table public.first_party_content enable row level security;
alter table public.user_content enable row level security;

grant select on table public.first_party_content to anon, authenticated;
grant select, insert, update, delete on table public.user_content to authenticated;

drop policy if exists "Read first-party content" on public.first_party_content;
create policy "Read first-party content"
  on public.first_party_content
  for select
  using (true);

drop policy if exists "Users can read own content" on public.user_content;
create policy "Users can read own content"
  on public.user_content
  for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own content" on public.user_content;
create policy "Users can insert own content"
  on public.user_content
  for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own content" on public.user_content;
create policy "Users can update own content"
  on public.user_content
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete own content" on public.user_content;
create policy "Users can delete own content"
  on public.user_content
  for delete
  using (auth.uid() = user_id);

create or replace function public.get_first_party_content(
  requested_content_type text,
  requested_content_key text
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  normalized_type text := nullif(trim(requested_content_type), '');
  normalized_key text := nullif(trim(requested_content_key), '');
  result jsonb;
begin
  if normalized_type is null or normalized_key is null then
    return null;
  end if;

  select data
  into result
  from public.first_party_content
  where content_type = normalized_type
    and content_key = normalized_key;

  return result;
end;
$$;

create or replace function public.upsert_user_content(
  requested_content_type text,
  requested_content_key text,
  next_data jsonb,
  next_version integer default 1
)
returns boolean
language plpgsql
security invoker
set search_path = public
as $$
declare
  normalized_type text := nullif(trim(requested_content_type), '');
  normalized_key text := nullif(trim(requested_content_key), '');
  safe_data jsonb := coalesce(next_data, '{}'::jsonb);
  safe_version integer := greatest(1, coalesce(next_version, 1));
  affected_rows integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if normalized_type is null or normalized_key is null then
    raise exception 'content_type and content_key are required';
  end if;

  insert into public.user_content (
    user_id,
    content_type,
    content_key,
    data,
    version,
    created_at,
    updated_at
  )
  values (
    auth.uid(),
    normalized_type,
    normalized_key,
    safe_data,
    safe_version,
    timezone('utc'::text, now()),
    timezone('utc'::text, now())
  )
  on conflict (user_id, content_type, content_key) do update
  set
    data = excluded.data,
    version = excluded.version,
    updated_at = timezone('utc'::text, now());

  get diagnostics affected_rows = row_count;
  return affected_rows > 0;
end;
$$;
