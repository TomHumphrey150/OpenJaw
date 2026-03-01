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
