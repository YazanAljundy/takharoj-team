# شريك التخرج

موقع بسيط لطلاب هندسة البرمجيات ليلاقوا مجموعات لمشاريع التخرج. HTML + CSS + JS عادي، وSupabase (Postgres) كقاعدة بيانات فقط.

## خطوات التشغيل
1. أنشئ مشروع Supabase جديد.
2. افتح **SQL Editor** والصق محتوى `schema.sql` كامل وشغّله. تقدر تعيد تشغيله بأي وقت لتحديث الدوال: بيحذف الدوال القديمة وبيثبّت الجديدة بدون ما يمس البيانات.
3. من **Project Settings → API** انسخ الـ Project URL والـ anon (أو publishable) key وحطهم بأول سطرين بـ `app.js`:
   ```js
   const SUPABASE_URL = 'https://xxxx.supabase.co';
   const SUPABASE_KEY = '...';
   ```
4. افتح `index.html` بالمتصفح (أو ارفع المجلد على أي استضافة ثابتة).
5. أنشئ حساب من الموقع، ثم رقّيه لأدمن من SQL Editor:
   ```sql
   update public.students set is_admin = true where username = 'your_username';
   ```

## ملاحظات
- ما في Supabase Auth: الدخول username + password (bcrypt)، والتوكن (7 أيام) بينحفظ بالقاعدة كـ sha256 فقط.
- كل الجداول عليها RLS بدون policies؛ كل شي بيمر عبر دوال `security definer` بتتحقق من التوكن.
- حدود معروفة: ما في rate limit على محاولات تسجيل الدخول، وما في استرجاع كلمة سر.

## تحديث قاعدة موجودة
- `migrate_admin_edit.sql`: تعديل الحسابات من الأدمن (اسم، تلغرام، كلمة سر) + إلزام طالب بتغيير معرّف التلغرام. شغّله مرة وحدة من SQL Editor؛ ما بيحذف بيانات. (`schema.sql` بيتضمنه للتنصيب من الصفر.)
- `migrate_hide_flagged.sql`: الطالب المنبَّه لتغيير التلغرام ما بيظهر لباقي الطلاب لحد ما يغيّره. شغّله بعد الملف السابق.
- مع كل تعديل على `app.js` أو `style.css` زيد رقم `?v=` بـ `index.html`.
