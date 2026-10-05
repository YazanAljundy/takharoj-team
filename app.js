const SUPABASE_URL = 'https://vrfcvuougtotxgmjpsoy.supabase.co';
const SUPABASE_KEY = 'sb_publishable_Ns-tCz-FI2hKzG0bwFPWiQ_lf2u5rwf';

const CATALOG = {
  'Frontend': ['HTML/CSS', 'JavaScript', 'TypeScript', 'React', 'Next.js', 'Vue', 'Angular', 'Tailwind CSS'],
  'Backend': ['Node.js', 'Express', 'NestJS', 'Laravel', 'Django', 'ASP.NET Core', 'Spring Boot', 'PostgreSQL', 'MySQL', 'MongoDB'],
  'Mobile': ['Flutter', 'React Native', 'Kotlin', 'Swift', 'Dart', 'Jetpack Compose', 'Firebase'],
  'AI / ML': ['Python', 'TensorFlow', 'PyTorch', 'scikit-learn', 'OpenCV', 'NLP', 'LLMs', 'Pandas'],
  'Data': ['SQL', 'Python', 'Pandas', 'Power BI', 'Tableau', 'Spark', 'Airflow', 'Excel'],
  'DevOps / Cloud': ['Docker', 'Kubernetes', 'Linux', 'AWS', 'Azure', 'GCP', 'CI/CD', 'Terraform', 'GitHub Actions'],
  'UI / UX': ['Figma', 'Adobe XD', 'Wireframing', 'Prototyping', 'User Research', 'Design Systems'],
  'Cybersecurity': ['Penetration Testing', 'Network Security', 'Cryptography', 'OWASP', 'Kali Linux', 'Wireshark', 'Malware Analysis'],
  'Game Dev': ['Unity', 'Unreal Engine', 'C#', 'C++', 'Godot', 'Blender'],
  'QA / Testing': ['Selenium', 'Cypress', 'Playwright', 'Jest', 'JUnit', 'Postman', 'Manual Testing'],
  'Embedded / IoT': ['Arduino', 'Raspberry Pi', 'ESP32', 'C', 'C++', 'MQTT', 'RTOS', 'Sensors'],
};
const OTHER = '__other';
const ALL_TECHS = [...new Set(Object.values(CATALOG).flat())].sort((a, b) => a.localeCompare(b));

const $ = (s) => document.querySelector(s);
const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const store = {
  get: (k) => { try { return localStorage.getItem(k) || ''; } catch { return ''; } },
  set: (k, v) => { try { localStorage.setItem(k, v); } catch {} },
  del: (k) => { try { localStorage.removeItem(k); } catch {} },
};
const tgLink = (u) => `<a href="https://t.me/${esc(u)}" target="_blank" rel="noopener noreferrer" dir="ltr">@${esc(u)}</a>`;

const S = {
  token: store.get('sh_token'),
  me: null,
  view: 'auth',
  authMode: 'login',
  tab: 'groups',
  groups: [], seekers: [], sq: '', sfield: '', incoming: [], mine: [], count: 0,
  admin: { students: [], groups: [], requests: [] },
  f: { q: '', field: '', tech: '', open: false },
  draft: null,
  busy: false,
};

function toast(msg, ok) {
  const el = document.createElement('div');
  el.className = 'toast' + (ok ? ' ok' : '');
  el.textContent = msg;
  $('#toasts').appendChild(el);
  setTimeout(() => el.remove(), 4500);
}

function errorText(status, data) {
  const msg = (data && data.message) || '';
  if (/[؀-ۿ]/.test(msg)) return msg;
  const code = (data && data.code) || '';
  if (code === 'PGRST202' || status === 404) return 'هالعملية مو موجودة بقاعدة البيانات. تأكد إنك شغّلت آخر نسخة من ملفات SQL على Supabase';
  if (status === 401 || status === 403 || /api key|jwt/i.test(msg)) return 'مفتاح Supabase أو رابط المشروع غلط. تأكد من SUPABASE_URL و SUPABASE_KEY بأول app.js';
  if (status === 429) return 'طلبات كتير بوقت قصير، استنى شوي وجرّب';
  if (status >= 500) return 'في مشكلة بالسيرفر، جرّب كمان شوي';
  if (status === 400) return 'البيانات اللي دخلتها مو مظبوطة، راجعها وجرّب';
  return 'صار خطأ غير متوقع، جرّب كمان مرة';
}

async function rpc(name, args = {}, auth = true) {
  if (SUPABASE_URL.includes('YOUR-PROJECT')) throw new Error('حط SUPABASE_URL و SUPABASE_KEY بأول app.js');
  const body = auth ? { p_token: S.token, ...args } : args;
  const headers = { 'Content-Type': 'application/json', apikey: SUPABASE_KEY };
  if (SUPABASE_KEY.startsWith('eyJ')) headers.Authorization = 'Bearer ' + SUPABASE_KEY;
  let res;
  try {
    res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, { method: 'POST', headers, body: JSON.stringify(body) });
  } catch {
    throw new Error('ما في اتصال بالسيرفر، جرّب كمان مرة');
  }
  const text = await res.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch {}
  if (!res.ok) {
    const msg = errorText(res.status, data);
    if (auth && /انتهت الجلسة|لازم تسجّل دخول/.test(msg)) { dropSession(); render(); }
    throw new Error(msg);
  }
  return data;
}

async function run(fn) {
  if (S.busy) return;
  S.busy = true;
  try { await fn(); } catch (e) { toast(e.message || 'صار خطأ'); } finally { S.busy = false; }
}

function dropSession() {
  S.token = ''; S.me = null; S.view = 'auth'; S.draft = null;
  store.del('sh_token');
}

function getPath(o, path) { return path.split('.').reduce((a, k) => (a == null ? a : a[k]), o); }
function setPath(o, path, v) {
  const ks = path.split('.'); const last = ks.pop();
  (ks.length ? getPath(o, ks.join('.')) : o)[last] = v;
}

async function boot() {
  if (!S.token) { S.view = 'auth'; return render(); }
  try { await loadMe(); } catch (e) { toast(e.message); dropSession(); }
  render();
}

async function loadMe() {
  S.me = await rpc('me');
  S.view = S.me.role ? 'main' : 'role';
  if (S.view === 'main') { S.tab = 'groups'; await loadTab(); }
}

async function loadCount() {
  try { S.count = await rpc('pending_count'); } catch {}
}

async function loadTab() {
  if (S.tab === 'groups') S.groups = await rpc('list_groups');
  else if (S.tab === 'seekers') S.seekers = await rpc('list_seekers');
  else if (S.tab === 'requests') {
    if (S.me.role === 'owner') S.incoming = await rpc('incoming_requests');
    else S.mine = await rpc('my_requests');
  } else if (S.tab === 'admin') {
    const [students, groups, requests] = await Promise.all([rpc('admin_list_students'), rpc('admin_list_groups'), rpc('admin_list_requests')]);
    S.admin = { students, groups, requests };
  }
  await loadCount();
}

function render() {
  const app = $('#app');
  if (S.view === 'auth') app.innerHTML = viewAuth();
  else {
    let body = '';
    if (S.view === 'role') body = viewRole();
    else if (S.view === 'form') body = S.draft.kind === 'group' ? viewGroupForm() : viewSeekerForm();
    else body = viewMain();
    app.innerHTML = header() + body;
  }
}

function header() {
  const name = S.me ? esc(S.me.full_name || S.me.username) : '';
  const edit = S.me && S.me.role && S.view === 'main' ? '<button class="btn-sm" data-act="edit-profile">تعديل ملفي</button>' : '';
  return `<div class="top"><div class="brand">🎓 شريك التخرج</div>
    <div class="actions"><span class="muted">${name}</span>${edit}<button class="btn-sm" data-act="logout">خروج</button></div></div>`;
}

function viewAuth() {
  const login = S.authMode === 'login';
  return `<div class="card narrow"><h1>🎓 شريك التخرج</h1>
    <p class="muted">لاقي مجموعة لمشروع التخرج، أو لاقي أعضاء لمجموعتك.</p>
    <div class="tabs">
      <button class="tab ${login ? 'on' : ''}" data-act="auth-mode" data-v="login">تسجيل الدخول</button>
      <button class="tab ${login ? '' : 'on'}" data-act="auth-mode" data-v="signup">حساب جديد</button>
    </div>
    <form data-form="auth" autocomplete="on">
      <label for="u">اسم المستخدم</label>
      <input id="u" name="u" type="text" dir="ltr" autocomplete="username" required minlength="3" maxlength="30" autocapitalize="none">
      <label for="p">كلمة السر</label>
      <input id="p" name="p" type="password" autocomplete="${login ? 'current-password' : 'new-password'}" required minlength="6" maxlength="72">
      ${login ? '' : '<label for="t">معرّف التلغرام</label><input id="t" name="t" type="text" dir="ltr" maxlength="80" required autocapitalize="none" placeholder="username أو @username أو t.me/username">'}
      ${login ? '' : '<p class="hint">اسم المستخدم: أحرف إنجليزية صغيرة وأرقام و _ و . (3 إلى 30). كلمة السر 6 محارف على الأقل.</p>'}
      <button class="btn-primary btn-block" type="submit">${login ? 'دخول' : 'إنشاء الحساب'}</button>
    </form></div>`;
}

function viewRole() {
  const r = S.me.role;
  return `<div class="card"><h2>شو وضعك؟</h2><p class="muted">بتقدر تغيّر اختيارك لاحقاً من "تعديل ملفي".</p>
    <div class="choices">
      <button class="choice ${r === 'owner' ? 'on' : ''}" data-act="pick-role" data-v="owner"><strong>عندي مجموعة وبدي أعضاء</strong><span class="muted">سجّل مجموعتك وحدد مين بدك.</span></button>
      <button class="choice ${r === 'seeker' ? 'on' : ''}" data-act="pick-role" data-v="seeker"><strong>بدوّر على مجموعة</strong><span class="muted">عبّي ملفك القصير وقدّم على الخانات.</span></button>
    </div>
    ${r ? '<button class="btn-block" data-act="back-main">رجوع</button>' : ''}</div>`;
}

function chipsHtml(opts, selected, ns) {
  const all = [...new Set([...opts, ...selected])];
  return `<div class="chips">${all.map((o) =>
    `<button type="button" class="chip ${selected.includes(o) ? 'on' : ''}" data-act="chip" data-ns="${esc(ns)}" data-v="${esc(o)}">${esc(o)}</button>`).join('')}</div>
    <div class="add-row"><input type="text" maxlength="30" placeholder="أضف يدوياً" data-addinput="${esc(ns)}"><button type="button" class="btn-sm" data-act="add-chip" data-ns="${esc(ns)}">إضافة</button></div>`;
}

function tgField(bind, val) {
  if (S.me.telegram) return '';
  return `<label>معرّف التلغرام</label><input type="text" dir="ltr" maxlength="80" data-bind="${bind}" value="${esc(val)}" placeholder="username أو @username أو t.me/username" required>`;
}

function viewSeekerForm() {
  const d = S.draft;
  const techOpts = [...new Set(d.fields.flatMap((f) => CATALOG[f] || []))];
  return `<div class="card"><h2>ملفي (بدوّر على مجموعة)</h2>
    <form data-form="seeker">
      ${S.me.role === 'owner' ? '<p class="hint" style="color:var(--bad)">تنبيه: حفظ هالملف بيحذف مجموعتك وطلباتها.</p>' : ''}
      <label>الاسم الكامل</label><input type="text" maxlength="60" data-bind="full_name" value="${esc(d.full_name)}" required>
      ${tgField('telegram', d.telegram)}
      <label>مجالي (واحد أو أكتر)</label>${chipsHtml(Object.keys(CATALOG), d.fields, 'fields')}
      <label>تقنياتي</label>${techOpts.length ? '' : '<p class="hint">اختار مجال لتظهرلك تقنيات مقترحة، أو أضفها يدوياً.</p>'}${chipsHtml(techOpts, d.techs, 'techs')}
      <button class="btn-primary btn-block" type="submit">حفظ</button>
      <button class="btn-block" type="button" data-act="${S.me.role ? 'edit-profile' : 'back-role'}">رجوع</button>
    </form></div>`;
}

function slotForm(s, i) {
  const sel = s.other ? OTHER : s.field;
  const opts = CATALOG[s.other ? '' : s.field] || [];
  return `<div class="slot-form"><strong>الشخص ${i + 1}</strong>
    <label>المجال</label>
    <select data-slot-field="${i}">
      <option value="" ${sel ? '' : 'selected'} disabled>اختار المجال</option>
      ${Object.keys(CATALOG).map((f) => `<option ${sel === f ? 'selected' : ''} value="${esc(f)}">${esc(f)}</option>`).join('')}
      <option value="${OTHER}" ${s.other ? 'selected' : ''}>غير ذلك</option>
    </select>
    ${s.other ? `<input type="text" maxlength="40" style="margin-top:6px" placeholder="اكتب المجال" data-bind="slots.${i}.otherText" value="${esc(s.otherText)}">` : ''}
    <label>التقنيات المطلوبة (اختياري)</label>${chipsHtml(opts, s.techs, `slots.${i}.techs`)}</div>`;
}

function viewGroupForm() {
  const d = S.draft;
  return `<div class="card"><h2>${S.me.group ? 'تعديل مجموعتي' : 'تسجيل مجموعة'}</h2>
    <form data-form="group">
      ${S.me.role === 'seeker' ? '<p class="hint">تنبيه: تسجيل مجموعة بيلغي طلباتك المرسلة.</p>' : ''}
      <label>اسم المجموعة</label><input type="text" maxlength="60" data-bind="name" value="${esc(d.name)}" required>
      <label>فكرة المشروع / وصف قصير (اختياري)</label><textarea maxlength="300" data-bind="description">${esc(d.description)}</textarea>
      <div class="grid2">
        <div><label>الاسم الكامل لصاحب المجموعة</label><input type="text" maxlength="60" data-bind="owner_name" value="${esc(d.owner_name)}" required></div>
        ${S.me.telegram ? '' : `<div>${tgField('owner_telegram', d.owner_telegram)}</div>`}
        <div><label>عدد الأعضاء الحاليين</label><input type="number" min="1" max="30" data-bind="members" value="${esc(d.members)}" required></div>
        <div><label>كم شخص تحتاج؟ (1 إلى 6)</label><input type="number" min="1" max="6" data-count value="${d.slots.length}" required></div>
      </div>
      ${d.slots.map(slotForm).join('')}
      ${S.me.group ? '<p class="hint">تنبيه: إذا غيّرت الخانات المطلوبة، الطلبات المرتبطة بالخانات القديمة بتنحذف.</p>' : ''}
      <button class="btn-primary btn-block" type="submit">حفظ المجموعة</button>
      <button class="btn-block" type="button" data-act="${S.me.role ? 'edit-profile' : 'back-role'}">رجوع</button>
    </form></div>`;
}

function viewMain() {
  const tabs = [['groups', 'المجموعات'], ['seekers', 'طلاب بدون مجموعة'], ['requests', 'الطلبات']];
  if (S.me.is_admin) tabs.push(['admin', 'الإدارة']);
  const t = tabs.map(([k, l]) =>
    `<button class="tab ${S.tab === k ? 'on' : ''}" data-act="tab" data-v="${k}">${l}${k === 'requests' && S.count ? `<span class="badge-count">${S.count}</span>` : ''}</button>`).join('');
  let body = '';
  if (S.tab === 'groups') body = viewGroups();
  else if (S.tab === 'seekers') body = viewSeekers();
  else if (S.tab === 'requests') body = S.me.role === 'owner' ? viewIncoming() : viewMine();
  else body = viewAdmin();
  return `<div class="tabs">${t}</div>${body}`;
}

function viewGroups() {
  const techs = [...new Set([...ALL_TECHS, ...S.groups.flatMap((g) => g.slots.flatMap((s) => s.techs))])].sort((a, b) => a.localeCompare(b));
  const fields = [...new Set([...Object.keys(CATALOG), ...S.groups.flatMap((g) => g.slots.map((s) => s.field))])];
  return `<div class="filters">
    <input type="text" id="f-q" placeholder="ابحث باسم المجموعة أو الوصف أو المجال..." value="${esc(S.f.q)}">
    <select id="f-field"><option value="">كل المجالات</option>${fields.map((f) => `<option ${S.f.field === f ? 'selected' : ''} value="${esc(f)}">${esc(f)}</option>`).join('')}</select>
    <select id="f-tech"><option value="">كل التقنيات</option>${techs.map((f) => `<option ${S.f.tech === f ? 'selected' : ''} value="${esc(f)}">${esc(f)}</option>`).join('')}</select>
    <label class="check"><input type="checkbox" id="f-open" ${S.f.open ? 'checked' : ''}> فقط الأماكن الشاغرة</label>
  </div><div id="glist">${groupsList()}</div>`;
}

function matches(g) {
  const { q, field, tech, open } = S.f;
  const free = g.slots.filter((s) => !s.filled);
  if (open && !free.length) return false;
  if (field || tech) {
    if (!free.some((s) => (!field || s.field === field) && (!tech || s.techs.includes(tech)))) return false;
  }
  if (q.trim()) {
    const hay = [g.name, g.description, g.owner_name, ...g.slots.flatMap((s) => [s.field, ...s.techs])].join(' ').toLowerCase();
    if (!hay.includes(q.trim().toLowerCase())) return false;
  }
  return true;
}

function groupsList() {
  const list = S.groups.filter(matches);
  if (!list.length) return '<div class="empty">ما في مجموعات مطابقة.</div>';
  return `<div class="cards">${list.map(groupCard).join('')}</div>`;
}

const REQ_LABEL = { pending: 'معلّق', accepted: 'مقبول', rejected: 'مرفوض' };
const REQ_CLASS = { pending: 'st-warn', accepted: 'st-ok', rejected: 'st-bad' };

function groupCard(g) {
  const canAsk = S.me.role === 'seeker' && !g.is_mine && !g.my_request_status;
  const slots = g.slots.map((s) => `<div class="slot ${s.filled ? 'filled' : ''}">
      <div><strong>${esc(s.field)}</strong>${s.techs.length ? `<div class="tags">${s.techs.map((t) => `<span class="tag">${esc(t)}</span>`).join('')}</div>` : ''}</div>
      ${s.filled ? '<span class="status st-ok">تم</span>' : canAsk ? `<button class="btn-sm btn-primary" data-act="join" data-slot="${s.id}" data-group="${g.id}">طلب انضمام</button>` : ''}
    </div>`).join('');
  return `<div class="card gcard ${g.complete ? 'done' : ''}">
    <div class="head"><h3>${esc(g.name)}</h3>${g.complete ? '<span class="status st-ok">مكتملة</span>' : ''}${g.is_mine ? '<span class="status st-warn">مجموعتي</span>' : ''}</div>
    ${g.description ? `<p class="desc">${esc(g.description)}</p>` : ''}
    <div class="muted">الأعضاء الحاليين: ${esc(g.members_count)}</div>
    ${g.my_request_status ? `<div>طلبك: <span class="status ${REQ_CLASS[g.my_request_status]}">${REQ_LABEL[g.my_request_status]}</span></div>` : ''}
    ${slots}
    <div class="owner-line">صاحب المجموعة: ${esc(g.owner_name)} · ${tgLink(g.owner_telegram)}</div>
  </div>`;
}

function techTags(a) { return (a || []).map((t) => `<span class="tag">${esc(t)}</span>`).join(' '); }

function seekersList() {
  const q = S.sq.trim().toLowerCase();
  const list = S.seekers.filter((u) => (!S.sfield || u.fields.includes(S.sfield)) &&
    (!q || [u.full_name, ...u.fields, ...u.techs].join(' ').toLowerCase().includes(q)));
  if (!list.length) return '<div class="empty">ما في طلاب مطابقين.</div>';
  return `<div class="cards">${list.map((u) => `<div class="card gcard">
    <h3>${esc(u.full_name)}</h3>
    <div>المجال: ${techTags(u.fields) || '—'}</div>
    <div>التقنيات: ${techTags(u.techs) || '—'}</div>
    <div class="owner-line">تواصل: ${tgLink(u.telegram)}</div></div>`).join('')}</div>`;
}

function viewSeekers() {
  const fields = [...new Set([...Object.keys(CATALOG), ...S.seekers.flatMap((u) => u.fields)])];
  return `<div class="filters" style="grid-template-columns:2fr 1fr">
    <input type="text" id="s-q" placeholder="ابحث بالاسم أو المجال أو التقنية..." value="${esc(S.sq)}">
    <select id="s-field"><option value="">كل المجالات</option>${fields.map((f) => `<option ${S.sfield === f ? 'selected' : ''} value="${esc(f)}">${esc(f)}</option>`).join('')}</select>
  </div><div id="slist">${seekersList()}</div>`;
}

function viewIncoming() {
  if (!S.me.group) return '<div class="empty">ما عندك مجموعة.</div>';
  if (!S.incoming.length) return '<div class="empty">ما وصلك أي طلب لسا.</div>';
  return S.incoming.map((r) => `<div class="card item"><div class="body">
      <h3>${esc(r.student_name)} <span class="status ${REQ_CLASS[r.status]}">${REQ_LABEL[r.status]}</span></h3>
      <div>مجاله: ${techTags(r.student_fields) || '—'}</div>
      <div>تقنياته: ${techTags(r.student_techs) || '—'}</div>
      <div>الخانة المطلوبة: <strong>${esc(r.slot_field)}</strong> (شخص ${esc(r.slot_pos)})</div>
      ${r.message ? `<p class="muted">"${esc(r.message)}"</p>` : ''}
      <div>تلغرام: ${tgLink(r.student_telegram)}</div></div>
      ${r.status === 'pending' ? `<div class="btns"><button class="btn-ok btn-sm" data-act="respond" data-id="${r.id}" data-v="1">قبول</button><button class="btn-danger btn-sm" data-act="respond" data-id="${r.id}" data-v="0">رفض</button></div>` : ''}
    </div>`).join('');
}

function viewMine() {
  if (!S.mine.length) return '<div class="empty">ما أرسلت أي طلب لسا. روح عتبويب المجموعات وقدّم.</div>';
  return S.mine.map((r) => `<div class="card item"><div class="body">
      <h3>${esc(r.group_name)} <span class="status ${REQ_CLASS[r.status]}">${REQ_LABEL[r.status]}</span></h3>
      <div>الخانة: <strong>${esc(r.slot_field)}</strong> ${techTags(r.slot_techs)}</div>
      ${r.message ? `<p class="muted">رسالتك: "${esc(r.message)}"</p>` : ''}
      <div>صاحب المجموعة: ${esc(r.owner_name)} · ${tgLink(r.owner_telegram)}</div></div>
      ${r.status === 'pending' ? `<div class="btns"><button class="btn-danger btn-sm" data-act="cancel" data-id="${r.id}">إلغاء الطلب</button></div>` : ''}
    </div>`).join('');
}

function viewAdmin() {
  const a = S.admin;
  const del = (kind, id, extra = '') => `<button class="btn-danger btn-sm" data-act="admin-del" data-kind="${kind}" data-id="${id}" ${extra}>حذف</button>`;
  return `<h2 class="section-title">الحسابات (${a.students.length})</h2>` +
    a.students.map((s) => `<div class="card item"><div class="body"><strong>${esc(s.username)}</strong> ${s.is_admin ? '<span class="status st-warn">أدمن</span>' : ''}
      <div class="muted">${esc(s.full_name || '—')} · ${s.telegram ? tgLink(s.telegram) : '—'} · ${s.role === 'owner' ? 'صاحب مجموعة' : s.role === 'seeker' ? 'فردي' : 'بدون اختيار'}</div></div>
      ${s.id === S.me.id ? '' : `<div class="btns">${del('student', s.id)}</div>`}</div>`).join('') +
    `<h2 class="section-title">المجموعات (${a.groups.length})</h2>` +
    (a.groups.map((g) => `<div class="card item"><div class="body"><strong>${esc(g.name)}</strong>
      <div class="muted">${esc(g.owner_name)} · ${tgLink(g.owner_telegram)} · الخانات: ${esc(g.slots_filled)}/${esc(g.slots_total)}</div></div>
      <div class="btns">${del('group', g.id)}</div></div>`).join('') || '<div class="empty">ما في مجموعات.</div>') +
    `<h2 class="section-title">الطلبات (${a.requests.length})</h2>` +
    (a.requests.map((r) => `<div class="card item"><div class="body"><strong>${esc(r.student_name || r.student_username)}</strong> ← ${esc(r.group_name)} (${esc(r.slot_field)})
      <span class="status ${REQ_CLASS[r.status]}">${REQ_LABEL[r.status]}</span></div>
      <div class="btns">${del('request', r.id)}</div></div>`).join('') || '<div class="empty">ما في طلبات.</div>');
}

function openModal(html) {
  const m = $('#modal');
  m.innerHTML = `<div class="box">${html}</div>`;
  m.hidden = false;
}
function closeModal() { const m = $('#modal'); m.hidden = true; m.innerHTML = ''; }

function groupDraft() {
  const g = S.me.group;
  if (!g) return { kind: 'group', name: '', description: '', owner_name: S.me.full_name || '', owner_telegram: '', members: 1, slots: [newSlot()] };
  return {
    kind: 'group', name: g.name, description: g.description, owner_name: g.owner_name, owner_telegram: '', members: g.members_count,
    slots: g.slots.map((s) => (CATALOG[s.field]
      ? { field: s.field, other: false, otherText: '', techs: [...s.techs] }
      : { field: '', other: true, otherText: s.field, techs: [...s.techs] })),
  };
}
const newSlot = () => ({ field: '', other: false, otherText: '', techs: [] });
function seekerDraft() {
  return { kind: 'seeker', full_name: S.me.full_name || '', telegram: '', fields: [...(S.me.fields || [])], techs: [...(S.me.techs || [])] };
}

document.addEventListener('input', (e) => {
  const t = e.target;
  if (t.dataset.bind && S.draft) setPath(S.draft, t.dataset.bind, t.value);
  else if (t.id === 's-q') { S.sq = t.value; $('#slist').innerHTML = seekersList(); }
  else if (t.id === 'f-q') { S.f.q = t.value; $('#glist').innerHTML = groupsList(); }
});

document.addEventListener('change', (e) => {
  const t = e.target;
  if (t.dataset.slotField !== undefined && S.draft) {
    const s = S.draft.slots[+t.dataset.slotField];
    const was = s.other ? OTHER : s.field;
    if (t.value === OTHER) { s.other = true; s.field = ''; } else { s.other = false; s.field = t.value; }
    if (was !== t.value) s.techs = [];
    render();
  } else if (t.dataset.count !== undefined && S.draft) {
    const n = Math.max(1, Math.min(6, parseInt(t.value, 10) || 1));
    while (S.draft.slots.length < n) S.draft.slots.push(newSlot());
    S.draft.slots.length = n;
    render();
  } else if (t.id === 's-field') { S.sfield = t.value; $('#slist').innerHTML = seekersList(); }
  else if (t.id === 'f-field') { S.f.field = t.value; $('#glist').innerHTML = groupsList(); }
  else if (t.id === 'f-tech') { S.f.tech = t.value; $('#glist').innerHTML = groupsList(); }
  else if (t.id === 'f-open') { S.f.open = t.checked; $('#glist').innerHTML = groupsList(); }
});

document.addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && e.target.dataset.addinput) { e.preventDefault(); addChip(e.target.dataset.addinput); }
  if (e.key === 'Escape') closeModal();
});

function addChip(ns) {
  const inp = document.querySelector(`[data-addinput="${CSS.escape(ns)}"]`);
  const v = inp.value.replace(/\s+/g, ' ').trim();
  if (!v) return;
  const arr = getPath(S.draft, ns);
  if (!arr.some((x) => x.toLowerCase() === v.toLowerCase())) arr.push(v);
  render();
}

document.addEventListener('submit', (e) => {
  const f = e.target.dataset.form;
  if (!f) return;
  e.preventDefault();
  if (f === 'auth') {
    const fd = new FormData(e.target);
    run(async () => {
      const r = await rpc(S.authMode, { p_username: fd.get('u'), p_password: fd.get('p'), ...(S.authMode === 'signup' ? { p_telegram: fd.get('t') } : {}) }, false);
      S.token = r.token; store.set('sh_token', r.token);
      await loadMe(); render();
    });
  } else if (f === 'seeker') run(saveSeeker);
  else if (f === 'group') run(saveGroup);
  else if (f === 'join') {
    const msg = new FormData(e.target).get('m');
    const slot = +e.target.dataset.slot;
    run(async () => {
      await rpc('send_request', { p_slot_id: slot, p_message: msg });
      closeModal(); toast('انرسل طلبك', true);
      await loadTab(); render();
    });
  }
});

async function saveSeeker() {
  const d = S.draft;
  await rpc('save_seeker_profile', { p_full_name: d.full_name, p_telegram: d.telegram, p_fields: d.fields, p_techs: d.techs });
  toast('انحفظ ملفك', true);
  await loadMe(); render();
}

async function saveGroup() {
  const d = S.draft;
  const slots = d.slots.map((s) => ({ field: s.other ? s.otherText : s.field, techs: s.techs }));
  await rpc('save_group', {
    p_name: d.name, p_description: d.description, p_owner_name: d.owner_name, p_owner_telegram: d.owner_telegram,
    p_members_count: parseInt(d.members, 10), p_slots: slots,
  });
  toast('انحفظت المجموعة', true);
  await loadMe(); render();
}

document.addEventListener('click', (e) => {
  if (e.target.id === 'modal') return closeModal();
  const el = e.target.closest('[data-act]');
  if (!el) return;
  const act = el.dataset.act, v = el.dataset.v;

  if (act === 'close') return closeModal();
  if (act === 'auth-mode') { S.authMode = v; return render(); }
  if (act === 'chip') {
    const arr = getPath(S.draft, el.dataset.ns);
    const i = arr.indexOf(v);
    if (i >= 0) arr.splice(i, 1); else arr.push(v);
    return render();
  }
  if (act === 'add-chip') return addChip(el.dataset.ns);
  if (act === 'edit-profile') { S.view = 'role'; return render(); }
  if (act === 'back-main') { S.view = 'main'; return render(); }
  if (act === 'back-role') { S.view = 'role'; return render(); }
  if (act === 'pick-role') {
    if (v === 'seeker' && S.me.group && !confirm('مجموعتك وطلباتها رح تنحذف إذا حفظت الملف الفردي. بدك تكمّل؟')) return;
    S.draft = v === 'owner' ? groupDraft() : seekerDraft();
    S.view = 'form';
    return render();
  }
  if (act === 'logout') {
    return run(async () => { try { await rpc('logout'); } catch {} dropSession(); render(); });
  }
  if (act === 'tab') {
    S.tab = v;
    return run(async () => { await loadTab(); render(); });
  }
  if (act === 'join') {
    const g = S.groups.find((x) => x.id === +el.dataset.group);
    const s = g.slots.find((x) => x.id === +el.dataset.slot);
    return openModal(`<h3>طلب انضمام: ${esc(g.name)}</h3><p class="muted">الخانة: ${esc(s.field)}</p>
      <form data-form="join" data-slot="${s.id}"><label>رسالة (اختياري)</label>
      <textarea name="m" maxlength="300" placeholder="عرّف بنفسك بسطر أو اتنين"></textarea>
      <div class="row" style="margin-top:12px"><button class="btn-primary" type="submit">إرسال الطلب</button><button type="button" data-act="close">إلغاء</button></div></form>`);
  }
  if (act === 'respond') {
    return run(async () => {
      await rpc('respond_request', { p_request_id: +el.dataset.id, p_accept: v === '1' });
      toast(v === '1' ? 'تم القبول' : 'تم الرفض', true);
      await loadTab(); render();
    });
  }
  if (act === 'cancel') {
    if (!confirm('بدك تلغي الطلب؟')) return;
    return run(async () => { await rpc('cancel_request', { p_request_id: +el.dataset.id }); await loadTab(); render(); });
  }
  if (act === 'admin-del') {
    const kind = el.dataset.kind;
    const label = { student: 'الحساب (وكل بياناته)', group: 'المجموعة (وطلباتها)', request: 'الطلب' }[kind];
    if (!confirm(`متأكد بدك تحذف ${label}؟ ما في رجعة.`)) return;
    return run(async () => {
      await rpc('admin_delete_' + kind, { p_id: +el.dataset.id });
      toast('انحذف', true);
      await loadTab(); render();
    });
  }
});

boot();
