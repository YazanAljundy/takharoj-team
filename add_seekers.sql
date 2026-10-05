create function public.list_seekers(p_token text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform private.auth(p_token);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'full_name', full_name, 'telegram', telegram,
      'fields', to_jsonb(fields), 'techs', to_jsonb(techs)) order by id desc)
    from public.students
    where role = 'seeker' and full_name is not null and telegram is not null
  ), '[]'::jsonb);
end $$;

grant execute on function public.list_seekers(text) to anon;
