-- =====================================================================
-- شريك التخرج: تعديل الحسابات من الأدمن + إلزام تغيير معرّف التلغرام
-- شغّله مرة من Supabase > SQL Editor. ما بيحذف أي بيانات، وآمن للتشغيل أكتر من مرة.
-- =====================================================================

-- علامة على الحساب: لازم يغيّر معرّف التلغرام قبل ما يكمّل
alter table public.students
  add column if not exists must_change_telegram boolean not null default false;

-- اسم الدخول (username) بيلحق معرّف التلغرام دايماً، من أي مكان تغيّر
create or replace function private.sync_username()
returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.telegram is not null and new.telegram is distinct from old.telegram then
    if exists (select 1 from public.students where username = lower(new.telegram) and id <> new.id) then
      raise exception 'هالمعرّف مستخدم بحساب تاني';
    end if;
    new.username := lower(new.telegram);
  end if;
  return new;
end $$;

drop trigger if exists students_sync_username on public.students;
create trigger students_sync_username
  before update of telegram on public.students
  for each row execute function private.sync_username();

-- التحقق من التوكن بدون شرط التلغرام (للدوال المسموحة للحساب المعلَّم)
create or replace function private.auth_any(p_token text)
returns public.students
language plpgsql security definer set search_path = public, extensions as $$
declare s public.students;
begin
  if p_token is null or p_token = '' then
    raise exception 'لازم تسجّل دخول أولاً';
  end if;
  select st.* into s
    from public.sessions se join public.students st on st.id = se.student_id
   where se.token_hash = encode(digest(p_token, 'sha256'), 'hex')
     and se.expires_at > now();
  if not found then
    raise exception 'انتهت الجلسة، سجّل دخول من جديد';
  end if;
  return s;
end $$;

-- كل باقي الدوال بتمر من هون: الحساب المعلَّم ما بيقدر يعمل شي لحد ما يغيّر المعرّف
create or replace function private.auth(p_token text)
returns public.students
language plpgsql security definer set search_path = public, extensions as $$
declare s public.students;
begin
  s := private.auth_any(p_token);
  if s.must_change_telegram and not s.is_admin then
    raise exception 'لازم تغيّر معرّف التلغرام قبل ما تكمّل. حدّث الصفحة'
      using hint = 'TG_CHANGE';
  end if;
  return s;
end $$;

create or replace function public.me(p_token text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s public.students; gid bigint;
begin
  s := private.auth_any(p_token);
  select id into gid from public.groups where owner_id = s.id;
  return jsonb_build_object(
    'id', s.id, 'username', s.username, 'full_name', s.full_name, 'telegram', s.telegram,
    'role', s.role, 'fields', to_jsonb(s.fields), 'techs', to_jsonb(s.techs), 'is_admin', s.is_admin,
    'must_change_telegram', s.must_change_telegram and not s.is_admin,
    'group', case when gid is null then null else private.group_json(gid, s.id) end
  );
end $$;

-- الطالب بيغيّر معرّفه (هي اللي بتفك العلامة)
create or replace function public.change_my_telegram(p_token text, p_telegram text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare s public.students; tg text;
begin
  s := private.auth_any(p_token);
  tg := private.norm_telegram(p_telegram);
  if s.must_change_telegram and lower(tg) = lower(coalesce(s.telegram, '')) then
    raise exception 'اكتب معرّف جديد غير الحالي';
  end if;
  update public.students set telegram = tg, must_change_telegram = false where id = s.id;
  update public.groups set owner_telegram = tg where owner_id = s.id;
end $$;

create or replace function public.admin_list_students(p_token text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform private.require_admin(p_token);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'username', username, 'full_name', full_name, 'telegram', telegram,
      'role', role, 'is_admin', is_admin, 'must_change_telegram', must_change_telegram,
      'created_at', created_at) order by id)
    from public.students
  ), '[]'::jsonb);
end $$;

-- الأدمن بيعدّل اسم وتلغرام وكلمة سر أي حساب (كلمة السر الفاضية = بدون تغيير)
create or replace function public.admin_update_student(
  p_token text, p_id bigint, p_full_name text, p_telegram text, p_new_password text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare a public.students; nm text; tg text; pw text := coalesce(p_new_password, '');
begin
  a := private.require_admin(p_token);
  perform 1 from public.students where id = p_id for update;
  if not found then raise exception 'الحساب مو موجود'; end if;
  nm := private.clean_name(p_full_name);
  tg := private.norm_telegram(p_telegram);
  if pw <> '' and (char_length(pw) < 6 or char_length(pw) > 72) then
    raise exception 'كلمة السر لازم تكون 6 محارف على الأقل';
  end if;
  update public.students
     set full_name = nm, telegram = tg,
         password_hash = case when pw <> '' then crypt(pw, gen_salt('bf')) else password_hash end
   where id = p_id;
  update public.groups set owner_name = nm, owner_telegram = tg where owner_id = p_id;
  if pw <> '' and p_id <> a.id then
    delete from public.sessions where student_id = p_id;
  end if;
end $$;

-- الأدمن بيحط أو بيشيل علامة "لازم تغيّر التلغرام"
create or replace function public.admin_require_telegram_change(p_token text, p_id bigint, p_on boolean)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare t public.students;
begin
  perform private.require_admin(p_token);
  select * into t from public.students where id = p_id;
  if not found then raise exception 'الحساب مو موجود'; end if;
  if t.is_admin then raise exception 'هالخاصية ما بتنطبق على حساب الأدمن'; end if;
  update public.students set must_change_telegram = coalesce(p_on, false) where id = p_id;
end $$;

revoke all on all functions in schema private from public, anon, authenticated;
revoke all on function
  public.me(text),
  public.change_my_telegram(text, text),
  public.admin_list_students(text),
  public.admin_update_student(text, bigint, text, text, text),
  public.admin_require_telegram_change(text, bigint, boolean)
from public, anon, authenticated;
grant execute on function
  public.me(text),
  public.change_my_telegram(text, text),
  public.admin_list_students(text),
  public.admin_update_student(text, bigint, text, text, text),
  public.admin_require_telegram_change(text, bigint, boolean)
to anon;

notify pgrst, 'reload schema';
