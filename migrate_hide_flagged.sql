-- =====================================================================
-- شريك التخرج: الطالب المنبَّه لتغيير التلغرام ما بيظهر لباقي الطلاب
-- شغّله بعد migrate_admin_edit.sql. ما بيحذف بيانات، وآمن للتشغيل أكتر من مرة.
-- بيختفي من: المجموعات، طلاب بدون مجموعة، والطلبات (بالاتجاهين). وبيرجع يظهر لحاله أول ما يغيّر المعرّف.
-- الأدمن بيضل يشوفه بلوحة الإدارة.
-- =====================================================================

create or replace function public.list_groups(p_token text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s public.students;
begin
  s := private.auth(p_token);
  return coalesce((
    select jsonb_agg(private.group_json(g.id, s.id) order by
             exists (select 1 from public.group_slots x where x.group_id = g.id and x.filled_by is null) desc,
             g.created_at desc)
      from public.groups g
      join public.students o on o.id = g.owner_id
     where not o.must_change_telegram
  ), '[]'::jsonb);
end $$;

create or replace function public.list_seekers(p_token text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform private.auth(p_token);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'full_name', full_name, 'telegram', telegram,
      'fields', to_jsonb(fields), 'techs', to_jsonb(techs)) order by id desc)
    from public.students
    where role = 'seeker' and not is_admin and not must_change_telegram
      and full_name is not null and telegram is not null
  ), '[]'::jsonb);
end $$;

create or replace function public.incoming_requests(p_token text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s public.students;
begin
  s := private.auth(p_token);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r.id, 'status', r.status, 'message', r.message, 'created_at', r.created_at,
      'student_name', st.full_name, 'student_telegram', st.telegram,
      'student_fields', to_jsonb(st.fields), 'student_techs', to_jsonb(st.techs),
      'slot_pos', sl.pos, 'slot_field', sl.field, 'slot_techs', to_jsonb(sl.techs)
    ) order by (r.status = 'pending') desc, r.created_at desc)
    from public.requests r
    join public.groups g on g.id = r.group_id and g.owner_id = s.id
    join public.students st on st.id = r.student_id and not st.must_change_telegram
    join public.group_slots sl on sl.id = r.slot_id
  ), '[]'::jsonb);
end $$;

create or replace function public.my_requests(p_token text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s public.students;
begin
  s := private.auth(p_token);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r.id, 'status', r.status, 'message', r.message, 'created_at', r.created_at,
      'group_name', g.name, 'owner_name', g.owner_name, 'owner_telegram', g.owner_telegram,
      'slot_field', sl.field, 'slot_techs', to_jsonb(sl.techs)
    ) order by (r.status = 'pending') desc, r.created_at desc)
    from public.requests r
    join public.groups g on g.id = r.group_id
    join public.students o on o.id = g.owner_id and not o.must_change_telegram
    join public.group_slots sl on sl.id = r.slot_id
    where r.student_id = s.id
  ), '[]'::jsonb);
end $$;

-- العدّاد لازم يطابق اللي بينعرض
create or replace function public.pending_count(p_token text)
returns int
language plpgsql security definer set search_path = public, extensions as $$
declare s public.students;
begin
  s := private.auth(p_token);
  return (
    select count(*)::int
      from public.requests r
      join public.groups g on g.id = r.group_id
      join public.students o  on o.id = g.owner_id
      join public.students st on st.id = r.student_id
     where r.status = 'pending'
       and ((r.student_id = s.id and not o.must_change_telegram)
         or (g.owner_id   = s.id and not st.must_change_telegram))
  );
end $$;

revoke all on function
  public.list_groups(text), public.list_seekers(text), public.incoming_requests(text),
  public.my_requests(text), public.pending_count(text)
from public, anon, authenticated;
grant execute on function
  public.list_groups(text), public.list_seekers(text), public.incoming_requests(text),
  public.my_requests(text), public.pending_count(text)
to anon;

notify pgrst, 'reload schema';
