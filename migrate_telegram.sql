drop function if exists public.signup(text, text);

create or replace function private.resolve_tg(p_current text, p_new text)
returns text
language plpgsql immutable set search_path = public, extensions as $$
begin
  if btrim(coalesce(p_new, '')) <> '' then
    return private.norm_telegram(p_new);
  end if;
  if p_current is null then
    raise exception 'ضيف معرّف التلغرام';
  end if;
  return p_current;
end $$;

create function public.signup(p_username text, p_password text, p_telegram text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u text := lower(btrim(coalesce(p_username, ''))); s public.students; tok text; tg text;
begin
  tg := private.norm_telegram(p_telegram);
  if u !~ '^[a-z0-9_.]{3,30}$' then
    raise exception 'اسم المستخدم لازم يكون 3 إلى 30 محرف: أحرف إنجليزية صغيرة وأرقام و _ و .';
  end if;
  if char_length(coalesce(p_password, '')) < 6 or char_length(p_password) > 72 then
    raise exception 'كلمة السر لازم تكون 6 محارف على الأقل';
  end if;
  begin
    insert into public.students (username, password_hash, telegram)
    values (u, crypt(p_password, gen_salt('bf')), tg) returning * into s;
  exception when unique_violation then
    raise exception 'اسم المستخدم محجوز، جرّب غيره';
  end;
  tok := encode(gen_random_bytes(32), 'hex');
  insert into public.sessions (token_hash, student_id, expires_at)
  values (encode(digest(tok, 'sha256'), 'hex'), s.id, now() + interval '7 days');
  return jsonb_build_object('token', tok);
end $$;

create or replace function public.save_seeker_profile(p_token text, p_full_name text, p_telegram text, p_fields text[], p_techs text[])
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare s public.students; nm text; tg text; f text[];
begin
  s := private.auth(p_token);
  nm := private.clean_name(p_full_name);
  tg := private.resolve_tg(s.telegram, p_telegram);
  f  := private.clean_list(p_fields, 5, 40, 'المجالات');
  if coalesce(array_length(f, 1), 0) = 0 then
    raise exception 'اختار مجال واحد على الأقل';
  end if;
  delete from public.groups where owner_id = s.id;
  update public.students
     set full_name = nm, telegram = tg, role = 'seeker', fields = f,
         techs = private.clean_list(p_techs, 15, 30, 'التقنيات')
   where id = s.id;
end $$;

create or replace function public.save_group(
  p_token text, p_name text, p_description text, p_owner_name text, p_owner_telegram text,
  p_members_count int, p_slots jsonb)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  s public.students; g public.groups; nm text; gn text; tg text; ds text;
  n int; i int; el jsonb; fld text; tch text[]; same boolean := true; ex record; gid bigint;
begin
  s := private.auth(p_token);
  gn := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  if char_length(gn) < 2 or char_length(gn) > 60 then
    raise exception 'اسم المجموعة لازم يكون بين 2 و60 محرف';
  end if;
  ds := btrim(coalesce(p_description, ''));
  if char_length(ds) > 300 then
    raise exception 'الوصف أطول من 300 محرف';
  end if;
  nm := private.clean_name(p_owner_name);
  tg := private.resolve_tg(s.telegram, p_owner_telegram);
  if p_members_count is null or p_members_count < 1 or p_members_count > 30 then
    raise exception 'عدد الأعضاء الحاليين لازم يكون بين 1 و30';
  end if;
  if p_slots is null or jsonb_typeof(p_slots) <> 'array' then
    raise exception 'حدد الأشخاص المطلوبين';
  end if;
  n := jsonb_array_length(p_slots);
  if n < 1 or n > 6 then
    raise exception 'عدد الأشخاص المطلوبين لازم يكون من 1 إلى 6';
  end if;

  for i in 0 .. n - 1 loop
    el := p_slots -> i;
    if jsonb_typeof(el) <> 'object' then raise exception 'بيانات الخانة مو صحيحة'; end if;
    fld := btrim(regexp_replace(coalesce(el ->> 'field', ''), '\s+', ' ', 'g'));
    if fld = '' or char_length(fld) > 40 then
      raise exception 'حدد مجال لكل خانة (حتى 40 محرف)';
    end if;
    select coalesce(array_agg(x), '{}') into tch
      from jsonb_array_elements_text(coalesce(el -> 'techs', '[]'::jsonb)) x;
    tch := private.clean_list(tch, 10, 30, 'التقنيات');
    p_slots := jsonb_set(p_slots, array[i::text], jsonb_build_object('field', fld, 'techs', to_jsonb(tch)));
  end loop;

  delete from public.requests where student_id = s.id;

  select * into g from public.groups where owner_id = s.id;
  if not found then
    insert into public.groups (owner_id, name, description, owner_name, owner_telegram, members_count)
    values (s.id, gn, ds, nm, tg, p_members_count) returning id into gid;
    same := false;
  else
    gid := g.id;
    update public.groups
       set name = gn, description = ds, owner_name = nm, owner_telegram = tg, members_count = p_members_count
     where id = gid;
    if (select count(*) from public.group_slots where group_id = gid) <> n then
      same := false;
    else
      for ex in select pos, field, techs from public.group_slots where group_id = gid order by pos loop
        el := p_slots -> (ex.pos - 1);
        if el ->> 'field' <> ex.field
           or (select coalesce(array_agg(x), '{}') from jsonb_array_elements_text(el -> 'techs') x) <> ex.techs then
          same := false; exit;
        end if;
      end loop;
    end if;
  end if;

  if not same then
    delete from public.group_slots where group_id = gid;
    for i in 0 .. n - 1 loop
      el := p_slots -> i;
      insert into public.group_slots (group_id, pos, field, techs)
      values (gid, i + 1, el ->> 'field',
              (select coalesce(array_agg(x), '{}') from jsonb_array_elements_text(el -> 'techs') x));
    end loop;
  end if;

  update public.students
     set role = 'owner', full_name = nm, telegram = tg, fields = '{}', techs = '{}'
   where id = s.id;

  return private.group_json(gid, s.id);
end $$;

grant execute on function public.signup(text, text, text) to anon;
