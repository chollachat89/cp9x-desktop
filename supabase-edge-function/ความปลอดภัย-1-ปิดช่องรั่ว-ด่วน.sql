-- =====================================================================
--  ความปลอดภัย ขั้นที่ 1 — ปิดช่องรั่วร้ายแรง (ด่วน · รันได้ทันที ไม่ต้องรอวันอัปเดต)
-- =====================================================================
--  ตรวจพบเมื่อ 2 ต.ค. 2569 ในโปรเจกต์จริง (maintenance-system / hefnjozijflnhdunmewl)
--
--  ---------------------------------------------------------------
--  เจออะไร
--  ---------------------------------------------------------------
--  เกือบทุกตารางมี policy ชื่อ "mshadow read" ที่ให้ role anon อ่านได้ทั้งตาราง (เงื่อนไข true)
--  role anon = ใครก็ตามที่ถือ publishable key ซึ่ง "ฝังอยู่ในตัวแอป" ที่ผู้รับเหมาทุกคนมี
--  = เปิดไฟล์แอปเอา key ไปยิงตรงเข้า https://<โปรเจกต์>.supabase.co/rest/v1/<ตาราง>
--    ก็อ่านได้ทั้งตาราง โดยไม่ผ่านเซิร์ฟเวอร์ และไม่ผ่านด่านตรวจสิทธิ์ใด ๆ เลย
--
--  ที่ร้ายแรงที่สุด:
--    contractors   มี session_token ของทุกคน  -> ล็อกอินเป็นใครก็ได้ รวมแอดมิน ไม่ต้องรู้รหัสผ่าน
--    app_secrets   มี google_service_account_private_key -> คุมบัญชี Google ของบริษัทได้
--    photo_submissions  มี policy "allow all" -> anon เพิ่ม/แก้/ลบได้
--    ฟังก์ชัน claim_billing_jobs / next_billing_round_no -> anon เรียกได้
--       = จองเลขงานให้หลุดจากรอบบิล / เดินเลขรอบบิลจริงได้จากภายนอก
--
--  ตรวจ log ย้อนหลัง 2 วันแล้ว: ไม่มีใครเข้ามาอ่าน contractors / app_secrets ตรง ๆ
--  (log ดูย้อนได้จำกัด ก่อนหน้านั้นยืนยันไม่ได้)
--
--  ---------------------------------------------------------------
--  ใครใช้สิทธิ์ anon อยู่บ้าง — ตรวจจาก log จริงแล้ว ไม่มีใครเลย
--  ---------------------------------------------------------------
--  จาก log 2 วัน มีผู้อ่านตารางตรง ๆ แค่ 2 ราย:
--    1) เซิร์ฟเวอร์ของเรา (Edge Function) -> ใช้ key ลับ sb_secret_ = service_role
--    2) Google Apps Script ดึง 5 ตารางทุก ~5 นาที (open/close/billing/pause/quotations)
--       และแก้ข้อมูลด้วย (PATCH) ซึ่ง log บอกว่า "โดนแถวจริง" 1-5 แถวทุกครั้ง
--
--  ข้อ 2 คือหลักฐานว่า Apps Script ใช้ key สิทธิ์เต็ม (service_role แบบเก่า) ไม่ใช่ anon
--  เพราะตารางเหล่านั้นเปิด RLS และมีแค่ policy "อ่าน" — ถ้าเป็น anon คำสั่งแก้จะโดน 0 แถวเสมอ
--  service_role ข้าม RLS ได้ทั้งหมด ไม่ต้องพึ่ง policy ใด ๆ
--
--  = policy "mshadow read" ไม่มีระบบไหนใช้งานเลย ปิดได้ทั้งหมดโดยไม่มีอะไรพัง
--  (ถ้ามีระบบอื่นที่ไม่ได้ทำงานในช่วง 2 วันที่ดู log แล้วหยุดทำงานหลังรัน ให้แจ้ง
--   แก้ได้ด้วยการให้ระบบนั้นใช้ key ลับของตัวเอง ไม่ใช่เปิดสิทธิ์ anon คืน)
--
--  ---------------------------------------------------------------
--  รันแล้วมีอะไรเปลี่ยนบ้าง
--  ---------------------------------------------------------------
--  ✓ แอป CP9X ใช้งานได้ปกติ — แอปคุยผ่านเซิร์ฟเวอร์ (Edge Function) ซึ่งใช้ service_role
--    ไม่ได้ใช้สิทธิ์ anon เลย (ตรวจแล้วทั้งตัวในเครื่องและตัวที่ deploy อยู่บนระบบจริง)
--  ✓ Google Apps Script ทำงานต่อได้ (ใช้ key สิทธิ์เต็ม ไม่ได้พึ่ง policy ที่ปิด)
--  ⚠ ทุกคนต้องล็อกอินใหม่ 1 ครั้ง — ข้อ 6 ล้าง session ทิ้งทั้งหมด
--    เพราะ session_token อาจถูกอ่านไปแล้วในช่วงก่อนที่ log จะย้อนไปถึง
--
--  รันซ้ำได้ ไม่พัง (ทุกคำสั่งเขียนแบบ "ถ้ามีค่อยทำ")
--  รันได้เลยวันนี้ ไม่ต้องรอวันอัปเดตแอป — ใช้ได้ทั้งกับแอป v1.0.67 ตัวปัจจุบันและตัวใหม่
-- =====================================================================


-- =====================================================================
--  0. ดูก่อนว่าตอนนี้เปิดอะไรไว้บ้าง (อ่านอย่างเดียว)
-- =====================================================================
select c.relname as "ตาราง",
       case when c.relrowsecurity then 'เปิด' else 'ปิด' end as "RLS",
       coalesce((select string_agg(p.polname, ', ') from pg_policy p where p.polrelid = c.oid), '-') as "policy",
       has_table_privilege('anon', c.oid, 'select') as "anon อ่านได้ (grant)"
from pg_class c
where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
order by c.relname;


-- =====================================================================
--  1. ฟังก์ชันในฐานข้อมูล — ให้เรียกได้เฉพาะเซิร์ฟเวอร์ (service_role)
-- =====================================================================
--  เดิม anon เรียกได้ทั้ง 4 ตัว ทั้งหมดเป็น security definer (รันด้วยสิทธิ์เจ้าของ)
--  เซิร์ฟเวอร์ของเราเรียกผ่าน service_role จึงให้สิทธิ์ service_role ซ้ำไว้ชัด ๆ กันพลาด

do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f'
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
    execute format('grant execute on function %s to service_role', f.sig);
    raise notice 'ปิดสิทธิ์ anon: %', f.sig;
  end loop;
end $$;


-- =====================================================================
--  2. ลบ policy ที่เปิดให้ anon อ่านทั้งตาราง — ทุกตาราง
-- =====================================================================
--  ตัวสำคัญ: contractors (session_token) · app_secrets (Google key) · billing_documents
--  (ราคา CJ ของทุกผู้รับเหมา) · parts (ราคา CJ) · open/close/pause (งานของทุกผู้รับเหมา)

do $$
declare r record;
begin
  for r in
    select p.polname, c.relname
    from pg_policy p join pg_class c on c.oid = p.polrelid
    where c.relnamespace = 'public'::regnamespace
      and p.polname = 'mshadow read'
  loop
    execute format('drop policy %I on public.%I', r.polname, r.relname);
    raise notice 'ลบ policy "%" ของตาราง %', r.polname, r.relname;
  end loop;
end $$;

-- policy ที่ให้ anon "ทำได้ทุกอย่าง" (เพิ่ม/แก้/ลบ) กับ photo_submissions
drop policy if exists "allow all photo_submissions" on public.photo_submissions;

-- ข้อมูลประกันทรัพย์สิน — เปิดให้ทุกคนอ่าน แต่ไม่มีระบบไหนอ่านทางนี้ (ตรวจจาก log แล้ว)
drop policy if exists "asset_warranty_read" on public.asset_warranty;


-- =====================================================================
--  3. เปิด RLS ทุกตารางที่ยังปิดอยู่
-- =====================================================================
--  รวมตารางสำรอง close_issues_fixdate_backup_20260930 ที่สร้างเมื่อ 30 ก.ย.
--  ซึ่งถูกสร้างโดยไม่ได้เปิด RLS -> ข้อมูล 9 แถวในนั้นอ่านได้จากภายนอก
--  (เปิด RLS แล้ว anon อ่านไม่ได้ เซิร์ฟเวอร์ยังอ่านได้ตามปกติ)

do $$
declare r record;
begin
  for r in
    select c.relname from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and not c.relrowsecurity
  loop
    execute format('alter table public.%I enable row level security', r.relname);
    raise notice 'เปิด RLS: %', r.relname;
  end loop;
end $$;


-- =====================================================================
--  4. ถอนสิทธิ์ (grant) ของ anon ออกทุกตาราง — กันอีกชั้น
-- =====================================================================
--  RLS + ไม่มี policy ก็กันได้แล้ว แต่ถ้าวันหน้ามีใครเผลอเพิ่ม policy เปิดให้ anon อีก
--  ชั้นนี้จะยังกันไว้ให้ (service_role ไม่โดน — มีสิทธิ์ของตัวเองแยกต่างหาก)

do $$
declare r record;
begin
  for r in
    select c.relname from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm')
  loop
    execute format('revoke all on public.%I from anon, authenticated', r.relname);
  end loop;
end $$;

revoke all on all sequences in schema public from anon, authenticated;

-- ตาราง/ฟังก์ชันที่จะสร้างใหม่ในอนาคต (เช่น ตารางของ v1.0.69 / v1.0.75 / v1.0.93)
-- ไม่ให้ anon ได้สิทธิ์อัตโนมัติอีก
alter default privileges for role postgres in schema public revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public revoke execute on functions from public, anon, authenticated;


-- =====================================================================
--  5. ตรวจซ้ำ: ตารางลับต้องอ่านไม่ได้แล้ว
-- =====================================================================
select 'contractors'  as "ตาราง", has_table_privilege('anon', 'public.contractors', 'select') as "anon อ่านได้ (ต้องเป็น false)"
union all select 'billing_documents (ราคา CJ)', has_table_privilege('anon', 'public.billing_documents', 'select')
union all select 'open_issues',       has_table_privilege('anon', 'public.open_issues', 'select')
union all select 'app_secrets',       has_table_privilege('anon', 'public.app_secrets', 'select')
union all select 'parts',             has_table_privilege('anon', 'public.parts', 'select')
union all select 'photo_submissions', has_table_privilege('anon', 'public.photo_submissions', 'select')
union all select 'ฟังก์ชัน claim_billing_jobs',
  has_function_privilege('anon', 'public.claim_billing_jobs(text[], integer)', 'execute')
union all select 'ฟังก์ชัน next_billing_round_no',
  has_function_privilege('anon', 'public.next_billing_round_no()', 'execute')
union all select '(ต้องเป็น true) เซิร์ฟเวอร์ยังเรียก claim_billing_jobs ได้',
  has_function_privilege('service_role', 'public.claim_billing_jobs(text[], integer)', 'execute');


-- =====================================================================
--  6. ล้าง session ทุกคน — ทุกคนต้องล็อกอินใหม่ 1 ครั้ง
-- =====================================================================
--  session_token ของทุกคนเคยอ่านได้จากภายนอก (ข้อ 2 ปิดแล้ว)
--  log ย้อนหลังที่ดูได้ไม่พบว่ามีใครอ่านไป แต่ก่อนช่วงนั้นยืนยันไม่ได้
--  ล้างทิ้งทั้งหมด = token เก่าที่อาจหลุดไปแล้วใช้ไม่ได้อีก
--
--  ⚠ แจ้งทีมก่อนรันข้อนี้: ทุกคนจะเด้งออกจากแอป ต้องล็อกอินใหม่ (รหัสผ่านเดิม)

update public.contractors set session_token = null, session_created_at = null;


-- =====================================================================
--  สิ่งที่ต้องทำต่อ (นอก SQL)
-- =====================================================================
--  ก. เปลี่ยน Google service account key (แนะนำ)
--     google_service_account_private_key ใน app_secrets เคยอ่านได้จากภายนอก
--     Google Cloud Console -> IAM -> Service Accounts -> บัญชีที่ใช้ซิงค์ -> Keys
--     -> สร้าง key ใหม่ -> อัปเดตค่าใน app_secrets -> ลบ key เก่าทิ้ง
--
--  ข. ตรวจว่า Google Apps Script ยังทำงานหลังรัน (ควรทำงานปกติ)
--     มันถือ key สิทธิ์เต็มของระบบไว้ = ใครแก้ Apps Script ตัวนั้นได้ ก็เข้าถึงฐานข้อมูลได้ทั้งหมด
--     ดูแลสิทธิ์แก้ไขของ Apps Script ให้เหมือนรหัสผ่านแอดมิน
--     และถ้าวันหน้าปิด key แบบเก่า (legacy) ใน Supabase -> Apps Script จะหยุดทำงาน ต้องเปลี่ยน key ก่อน
-- =====================================================================
