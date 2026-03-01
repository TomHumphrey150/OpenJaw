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
  sanitized_patch jsonb := safe_patch
    - 'dailyCheckIns'
    - 'morningStates'
    - 'foundationCheckIns'
    - 'progressQuestionSetState'
    - 'morningQuestionnaire';
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
    sanitized_patch,
    timezone('utc'::text, now())
  )
  on conflict (user_id) do update
  set
    data = (
      (coalesce(public.user_data.data, '{}'::jsonb) || sanitized_patch)
      - 'dailyCheckIns'
      - 'morningStates'
      - 'foundationCheckIns'
      - 'progressQuestionSetState'
      - 'morningQuestionnaire'
    ),
    updated_at = timezone('utc'::text, now());

  get diagnostics affected_rows = row_count;
  return affected_rows > 0;
end;
$$;

update public.user_data
set
  data = (
    coalesce(public.user_data.data, '{}'::jsonb)
    - 'dailyCheckIns'
    - 'morningStates'
    - 'foundationCheckIns'
    - 'progressQuestionSetState'
    - 'morningQuestionnaire'
  ),
  updated_at = timezone('utc'::text, now())
where coalesce(public.user_data.data, '{}'::jsonb) ?| array[
  'dailyCheckIns',
  'morningStates',
  'foundationCheckIns',
  'progressQuestionSetState',
  'morningQuestionnaire'
];

alter table public.user_data
drop constraint if exists user_data_only_pillar_checkins;

alter table public.user_data
add constraint user_data_only_pillar_checkins
check (
  not (
    coalesce(public.user_data.data, '{}'::jsonb) ?| array[
      'dailyCheckIns',
      'morningStates',
      'foundationCheckIns',
      'progressQuestionSetState',
      'morningQuestionnaire'
    ]
  )
);
