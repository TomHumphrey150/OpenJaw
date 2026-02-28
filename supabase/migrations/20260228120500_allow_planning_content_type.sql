alter table public.first_party_content
  drop constraint if exists first_party_content_type_check;

alter table public.first_party_content
  add constraint first_party_content_type_check check (
    content_type in ('graph', 'inputs', 'outcomes', 'planning', 'citations', 'info')
  );

alter table public.user_content
  drop constraint if exists user_content_type_check;

alter table public.user_content
  add constraint user_content_type_check check (
    content_type in ('graph', 'inputs', 'outcomes', 'planning', 'citations', 'info')
  );
