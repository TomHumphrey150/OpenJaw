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
