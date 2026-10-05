
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;

do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig
      from pg_proc p
     where p.pronamespace in ('public'::regnamespace, 'private'::regnamespace)
       and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  loop
    execute 'drop function ' || r.sig || ' cascade';
  end loop;
end $$;

create table if not exists public.students (
  id            bigint generated always as identity primary key,
  username      text not null unique check (username = lower(username) and username ~ '^[a-z0-9_.]{3,30}$'),
  password_hash text not null,
  full_name     text check (char_length(full_name) between 2 and 60),
  telegram      text check (telegram ~ '^[A-Za-z0-9_]{5,32}$'),
  role          text check (role in ('owner', 'seeker')),
  fields        text[] not null default '{}',
  techs         text[] not null default '{}',
  is_admin      boolean not null default false,
  created_at    timestamptz not null default now()
);

alter table public.students drop constraint if exists students_username_check;
alter table public.students add constraint students_username_check check (username = lower(username) and username ~ '^[a-z0-9_.]{3,32}$');

create table if not exists public.sessions (
  token_hash text primary key,
  student_id bigint not null references public.students(id) on delete cascade,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index if not exists sessions_student_id_idx on public.sessions (student_id);

create table if not exists public.groups (
  id             bigint generated always as identity primary key,
  owner_id       bigint not null unique references public.students(id) on delete cascade,
  name           text not null check (char_length(name) between 2 and 60),
  description    text not null default '' check (char_length(description) <= 300),
  owner_name     text not null,
  owner_telegram text not null,
  members_count  int  not null check (members_count between 1 and 30),
  created_at     timestamptz not null default now()
);

create table if not exists public.group_slots (
  id        bigint generated always as identity primary key,
  group_id  bigint not null references public.groups(id) on delete cascade,
  pos       int    not null,
  field     text   not null check (char_length(field) between 1 and 40),
  techs     text[] not null default '{}',
  filled_by bigint references public.students(id) on delete set null,
  unique (group_id, pos)
);

create table if not exists public.requests (
  id         bigint generated always as identity primary key,
  student_id bigint not null references public.students(id) on delete cascade,
  group_id   bigint not null references public.groups(id) on delete cascade,
  slot_id    bigint not null references public.group_slots(id) on delete cascade,
  message    text not null default '' check (char_length(message) <= 300),
  status     text not null default 'pending' check (status in ('pending', 'accepted', 'rejected')),
  created_at timestamptz not null default now(),
  unique (student_id, group_id)
);
create index if not exists requests_group_status_idx on public.requests (group_id, status);
create index if not exists requests_slot_id_idx on public.requests (slot_id);

alter table public.students    enable row level security;
alter table public.sessions    enable row level security;
alter table public.groups      enable row level security;
alter table public.group_slots enable row level security;
alter table public.requests    enable row level security;

revoke all on all tables    in schema public from public, anon, authenticated;
revoke all on all sequences in schema public from public, anon, authenticated;

create function private.auth(p_token text)
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

create function private.require_admin(p_token text)
returns public.students
language plpgsql security definer set search_path = public, extensions as $$
declare s public.students;
begin
  s := private.auth(p_token);
  if not s.is_admin then
    raise exception 'ما عندك صلاحية لهالعملية';
  end if;
  return s;
end $$;

create function private.norm_telegram(p text)
returns text
language plpgsql immutable set search_path = public, extensions as $$
declare t text := btrim(coalesce(p, ''));
begin
  t := regexp_replace(t, '^(https?://)?(www\.)?(t\.me|telegram\.me)/', '', 'i');
  t := regexp_replace(t, '[/?#].*$', '');
  t := regexp_replace(t, '^@', '');
  if t !~ '^[A-Za-z0-9_]{5,32}$' then
    raise exception 'معرّف التلغرام مو مظبوط (5 إلى 32 حرف: أحرف إنجليزية وأرقام و _)';
  end if;
  return t;
end $$;

create function private.resolve_tg(p_current text, p_new text)
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

create function private.clean_list(p text[], p_max int, p_len int, p_what text)
returns text[]
language plpgsql immutable set search_path = public, extensions as $$
declare r text[] := '{}'; x text; v text;
begin
  foreach x in array coalesce(p, '{}') loop
    v := btrim(regexp_replace(coalesce(x, ''), '\s+', ' ', 'g'));
    if v = '' then continue; end if;
    if char_length(v) > p_len then
      raise exception 'أحد عناصر % أطول من % محرف: %', p_what, p_len, left(v, 20);
    end if;
    if not exists (select 1 from unnest(r) u where lower(u) = lower(v)) then
      r := r || v;
    end if;
  end loop;
  if coalesce(array_length(r, 1), 0) > p_max then
    raise exception 'عدد % أكتر من المسموح (الحد الأقصى %)', p_what, p_max;
  end if;
  return r;
end $$;

create function private.clean_name(p text)
returns text
language plpgsql immutable set search_path = public, extensions as $$
declare v text := btrim(regexp_replace(coalesce(p, ''), '\s+', ' ', 'g'));
begin
  if char_length(v) < 2 or char_length(v) > 60 then
    raise exception 'الاسم الكامل لازم يكون بين 2 و60 محرف (كتبت % محرف)', char_length(v);
  end if;
  return v;
end $$;

create function private.group_json(p_group_id bigint, p_viewer bigint)
returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object(
    'id', g.id,
    'name', g.name,
    'description', g.description,
    'members_count', g.members_count,
    'owner_name', g.owner_name,
    'owner_telegram', g.owner_telegram,
    'is_mine', g.owner_id = p_viewer,
    'created_at', g.created_at,
    'complete', not exists (select 1 from public.group_slots x where x.group_id = g.id and x.filled_by is null),
    'my_request_status', (select r.status from public.requests r where r.group_id = g.id and r.student_id = p_viewer),
    'slots', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', gs.id, 'pos', gs.pos, 'field', gs.field, 'techs', to_jsonb(gs.techs),
        'filled', gs.filled_by is not null
      ) order by gs.pos)
      from public.group_slots gs where gs.group_id = g.id
    ), '[]'::jsonb)
  )
  from public.groups g where g.id = p_group_id;
$$;

create function public.signup(p_username text, p_password text, p_full_name text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare tg text; nm text; s public.students; tok text;
begin
  tg := private.norm_telegram(p_username);
  nm := private.clean_name(p_full_name);
  if char_length(coalesce(p_password, '')) < 6 or char_length(p_password) > 72 then
    raise exception 'كلمة السر لازم تكون 6 محارف على الأقل';
  end if;
  begin
    insert into public.students (username, password_hash, telegram, full_name)
    values (lower(tg), crypt(p_password, gen_salt('bf')), tg, nm) returning * into s;
  exception when unique_violation then
    raise exception 'هالمعرّف مسجّل من قبل، سجّل دخول أو تأكد من المعرّف';
  end;
  tok := encode(gen_random_bytes(32), 'hex');
  insert into public.sessions (token_hash, student_id, expires_at)
  values (encode(digest(tok, 'sha256'), 'hex'), s.id, now() + interval '7 days');
  return jsonb_build_object('token', tok);
end $$;

create function public.login(p_username text, p_password text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s public.students; tok text;
begin
  select * into s from public.students where username = lower(regexp_replace(btrim(coalesce(p_username, '')), '^@', ''));
  if not found or s.password_hash <> crypt(coalesce(p_password, ''), s.password_hash) then
    raise exception 'اسم المستخدم أو كلمة السر غلط';
  end if;
  delete from public.sessions where expires_at < now();
  tok := encode(gen_random_bytes(32), 'hex');
  insert into public.sessions (token_hash, student_id, expires_at)
  values (encode(digest(tok, 'sha256'), 'hex'), s.id, now() + interval '7 days');
  return jsonb_build_object('token', tok);
end $$;

create function public.logout(p_token text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  delete from public.sessions where token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex');
end $$;

create function public.me(p_token text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s public.students; gid bigint;
begin
  s := private.auth(p_token);
  select id into gid from public.groups where owner_id = s.id;
  return jsonb_build_object(
    'id', s.id, 'username', s.username, 'full_name', s.full_name, 'telegram', s.telegram,
    'role', s.role, 'fields', to_jsonb(s.fields), 'techs', to_jsonb(s.techs), 'is_admin', s.is_admin,
    'group', case when gid is null then null else private.group_json(gid, s.id) end
  );
end $$;

create function public.save_seeker_profile(p_token text, p_full_name text, p_telegram text, p_fields text[], p_techs text[])
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

create function public.save_group(
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
    raise exception 'اسم المجموعة لازم يكون بين 2 و60 محرف (كتبت % محرف)', char_length(gn);
  end if;
  ds := btrim(coalesce(p_description, ''));
  if char_length(ds) > 300 then
    raise exception 'الوصف أطول من 300 محرف (كتبت % محرف)', char_length(ds);
  end if;
  nm := private.clean_name(p_owner_name);
  tg := private.resolve_tg(s.telegram, p_owner_telegram);
  if p_members_count is null or p_members_count < 1 or p_members_count > 30 then
    raise exception 'عدد الأعضاء الحاليين لازم يكون بين 1 و30';
  end if;
  if p_slots is null or jsonb_typeof(p_slots) <> 'array' then
    raise exception 'حدد الأشخاص اللي بدك ياهن (من 1 إلى 6)';
  end if;
  n := jsonb_array_length(p_slots);
  if n < 1 or n > 6 then
    raise exception 'عدد الأشخاص المطلوبين لازم يكون من 1 إلى 6';
  end if;

  for i in 0 .. n - 1 loop
    el := p_slots -> i;
    if jsonb_typeof(el) <> 'object' then raise exception 'بيانات الخانة مو صحيحة'; end if;
    fld := btrim(regexp_replace(coalesce(el ->> 'field', ''), '\s+', ' ', 'g'));
    if fld = '' then
      raise exception 'حدد مجال للشخص رقم %', i + 1;
    end if;
    if char_length(fld) > 40 then
      raise exception 'مجال الشخص رقم % أطول من 40 محرف', i + 1;
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

create function public.delete_my_group(p_token text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare s public.students;
begin
  s := private.auth(p_token);
  delete from public.groups where owner_id = s.id;
  if not found then raise exception 'ما عندك مجموعة'; end if;
end $$;

create function public.list_groups(p_token text)
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
  ), '[]'::jsonb);
end $$;

create function public.send_request(p_token text, p_slot_id bigint, p_message text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare s public.students; sl public.group_slots; g public.groups; m text := btrim(coalesce(p_message, ''));
begin
  s := private.auth(p_token);
  if s.role is distinct from 'seeker' then
    raise exception 'طلب الانضمام للطلاب اللي عم يدوّروا على مجموعة بس. غيّر ملفك من "تعديل ملفي" لتقدر تقدّم';
  end if;
  if char_length(m) > 300 then raise exception 'الرسالة أطول من 300 محرف'; end if;
  select * into sl from public.group_slots where id = p_slot_id;
  if not found then raise exception 'هالخانة مو موجودة'; end if;
  select * into g from public.groups where id = sl.group_id;
  if g.owner_id = s.id then raise exception 'ما فيك تطلب الانضمام لمجموعتك'; end if;
  if sl.filled_by is not null then raise exception 'هالخانة انحجزت'; end if;
  begin
    insert into public.requests (student_id, group_id, slot_id, message)
    values (s.id, g.id, sl.id, m);
  exception when unique_violation then
    raise exception 'سبق وقدّمت طلب لهالمجموعة';
  end;
end $$;

create function public.cancel_request(p_token text, p_request_id bigint)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare s public.students; r public.requests;
begin
  s := private.auth(p_token);
  select * into r from public.requests where id = p_request_id for update;
  if not found or r.student_id <> s.id then raise exception 'الطلب مو موجود'; end if;
  if r.status <> 'pending' then raise exception 'ما فيك تلغي طلب مو معلّق'; end if;
  delete from public.requests where id = r.id;
end $$;

create function public.respond_request(p_token text, p_request_id bigint, p_accept boolean)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare s public.students; r public.requests; sl public.group_slots;
begin
  s := private.auth(p_token);
  select * into r from public.requests where id = p_request_id for update;
  if not found or not exists (select 1 from public.groups where id = r.group_id and owner_id = s.id) then
    raise exception 'الطلب مو موجود';
  end if;
  if r.status <> 'pending' then raise exception 'هالطلب انرد عليه من قبل'; end if;
  if p_accept is null then raise exception 'حدد قبول أو رفض'; end if;

  if not p_accept then
    update public.requests set status = 'rejected' where id = r.id;
    return;
  end if;

  select * into sl from public.group_slots where id = r.slot_id for update;
  if sl.filled_by is not null then raise exception 'هالخانة انحجزت'; end if;
  update public.group_slots set filled_by = r.student_id where id = sl.id;
  update public.requests set status = 'accepted' where id = r.id;
  update public.requests set status = 'rejected'
   where slot_id = sl.id and status = 'pending' and id <> r.id;
end $$;

create function public.incoming_requests(p_token text)
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
    join public.students st on st.id = r.student_id
    join public.group_slots sl on sl.id = r.slot_id
  ), '[]'::jsonb);
end $$;

create function public.my_requests(p_token text)
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
    join public.group_slots sl on sl.id = r.slot_id
    where r.student_id = s.id
  ), '[]'::jsonb);
end $$;

create function public.pending_count(p_token text)
returns int
language plpgsql security definer set search_path = public, extensions as $$
declare s public.students;
begin
  s := private.auth(p_token);
  return (
    select count(*)::int from public.requests r
     where r.status = 'pending'
       and (r.student_id = s.id
            or r.group_id in (select id from public.groups where owner_id = s.id))
  );
end $$;

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
    where role = 'seeker' and not is_admin and full_name is not null and telegram is not null
  ), '[]'::jsonb);
end $$;

create function public.admin_list_students(p_token text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform private.require_admin(p_token);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'username', username, 'full_name', full_name, 'telegram', telegram,
      'role', role, 'is_admin', is_admin, 'created_at', created_at) order by id)
    from public.students
  ), '[]'::jsonb);
end $$;

create function public.admin_list_groups(p_token text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform private.require_admin(p_token);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', g.id, 'name', g.name, 'owner_name', g.owner_name, 'owner_telegram', g.owner_telegram,
      'members_count', g.members_count,
      'slots_total', (select count(*) from public.group_slots x where x.group_id = g.id),
      'slots_filled', (select count(*) from public.group_slots x where x.group_id = g.id and x.filled_by is not null)
    ) order by g.id)
    from public.groups g
  ), '[]'::jsonb);
end $$;

create function public.admin_list_requests(p_token text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform private.require_admin(p_token);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r.id, 'status', r.status, 'message', r.message,
      'student_username', st.username, 'student_name', st.full_name,
      'group_name', g.name, 'slot_field', sl.field) order by r.id)
    from public.requests r
    join public.students st on st.id = r.student_id
    join public.groups g on g.id = r.group_id
    join public.group_slots sl on sl.id = r.slot_id
  ), '[]'::jsonb);
end $$;

create function public.admin_delete_student(p_token text, p_id bigint)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare a public.students;
begin
  a := private.require_admin(p_token);
  if a.id = p_id then raise exception 'ما فيك تحذف حسابك'; end if;
  delete from public.students where id = p_id;
  if not found then raise exception 'الحساب مو موجود'; end if;
end $$;

create function public.admin_delete_group(p_token text, p_id bigint)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform private.require_admin(p_token);
  delete from public.groups where id = p_id;
  if not found then raise exception 'المجموعة مو موجودة'; end if;
end $$;

create function public.admin_delete_request(p_token text, p_id bigint)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform private.require_admin(p_token);
  delete from public.requests where id = p_id;
  if not found then raise exception 'الطلب مو موجود'; end if;
end $$;

revoke all on all tables    in schema public from public, anon, authenticated;
revoke all on all sequences in schema public from public, anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
revoke all on schema private from public, anon, authenticated;
revoke all on all functions in schema private from public, anon, authenticated;

grant usage on schema public to anon;
grant execute on function
  public.signup(text, text, text),
  public.login(text, text),
  public.logout(text),
  public.me(text),
  public.save_seeker_profile(text, text, text, text[], text[]),
  public.save_group(text, text, text, text, text, int, jsonb),
  public.delete_my_group(text),
  public.list_groups(text),
  public.list_seekers(text),
  public.send_request(text, bigint, text),
  public.cancel_request(text, bigint),
  public.respond_request(text, bigint, boolean),
  public.incoming_requests(text),
  public.my_requests(text),
  public.pending_count(text),
  public.admin_list_students(text),
  public.admin_list_groups(text),
  public.admin_list_requests(text),
  public.admin_delete_student(text, bigint),
  public.admin_delete_group(text, bigint),
  public.admin_delete_request(text, bigint)
to anon;

