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
