drop function if exists public.append_stress_check_ins(jsonb, integer);

update public.user_data
set data = data - 'stressCheckIns'
where data ? 'stressCheckIns';
