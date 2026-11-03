-- =====================================================================
--  v1.3.10 — ประเภทสัญญาผูกกับสาขา + อัปเดตทะเบียนสาขา/ทรัพย์สิน
--  จากไฟล์ ฟอล์มส่งรูปวางบิล (1).xlsx (3 พ.ย. 2569)
-- =====================================================================
--
--  สิ่งที่ไฟล์นี้ทำ
--    1. เพิ่มคอลัมน์ branches.contract_type  — ประเภทสัญญาประจำสาขา (ว่าง = ให้กรอกมือในแอป)
--    2. เพิ่มคอลัมน์ branch_assets.cap_date  — วันขึ้นทะเบียนทรัพย์สิน (ช่อง Cap.date ในฟอร์มแนบรูปแบบใหม่)
--    3. อัปเดตทะเบียนสาขา 2,334 สาขา · ทะเบียนทรัพย์สิน 61,665 ชิ้น · วันรับประกัน 58,748 ชิ้น
--    4. เปลี่ยนชื่อประเภทสัญญาของงานเก่าให้ตรงกับชื่อในไฟล์ (ดูตารางแปลงในบล็อก C ข้อ 5)
--
--  ⚠ เป็น "เติม/อัปเดตทับ" ไม่ใช่ "ล้างแล้วใส่ใหม่" — เหมือนรอบ v1.0.98
--    ของเดิมที่ไม่มีในไฟล์ใหม่จะไม่ถูกลบ เพราะมีงานจริงอ้างถึงอยู่
--
--  สิ่งที่จะเปลี่ยนจริง (เทียบไฟล์รอบ 3 ต.ค. ที่นำเข้าไปแล้ว)
--    · สาขาใหม่ 68 สาขา (ไฟล์มี 2,334 · รอบก่อน 2,266) ไม่มีสาขาไหนหายไป
--    · ชื่อสาขาเปลี่ยน 1,279 สาขา — ส่วนใหญ่คือตัดคำว่า "-ปิดถาวร" ท้ายชื่อออก
--    · ⚠ แก้ชื่อสาขาที่ตัวอักษรไทยเสียจากการนำเข้ารอบก่อน: 6 สาขาในตารางสาขา
--      และ 94 แถวในตารางทรัพย์สิน (เช่น "นนทบุร�� 42" -> "นนทบุรี 42")
--    · วันรับประกันเหมือนรอบก่อนทุกไบต์ (นำเข้าซ้ำได้ ไม่มีอะไรเปลี่ยน)
--    · ประเภทสัญญา: Contract Service 1,450 · Turnkey Warranty 593 · Turnkey Service 164
--      และ 127 สาขาที่ไฟล์ไม่ได้ระบุ (ในไฟล์เป็น "0" หรือเว้นว่าง) = เว้นเป็น NULL ให้กรอกมือ
--
--  ✅ สำรองทุกตารางที่แก้ไว้ใน schema cp9x_backup ก่อนแก้ (บล็อก C)
--  ✅ รันซ้ำได้ทุกบล็อก
--
--  ลำดับการรัน:  บล็อก A  ->  นำเข้า CSV 3 ไฟล์  ->  บล็อก B  ->  บล็อก C  ->  บล็อก D
--  ไฟล์ CSV อยู่ในโฟลเดอร์  นำเข้าทะเบียน-3พฤศจิกายน2569
-- =====================================================================


-- =====================================================================
--  ⚠ ด่านกันรันผิดโปรเจกต์ — ต้องเป็น maintenance-system (CP9X) เท่านั้น
-- =====================================================================
do $$
begin
  if to_regclass('public.branch_assets') is null or to_regclass('public.branches') is null then
    raise exception E'หยุด: นี่ไม่ใช่ฐานข้อมูลของ CP9X\n'
      'คุณกำลังเปิด SQL Editor ของโปรเจกต์อื่นอยู่ (เช่น Inventory)\n'
      'มุมบนซ้ายกดสลับโปรเจกต์เป็น "maintenance-system" (hefnjozijflnhdunmewl) แล้วรันใหม่';
  end if;
end $$;


-- =====================================================================
--  บล็อก A — สร้างตารางพักข้อมูล (รันก่อนนำเข้า CSV)
-- =====================================================================
--  ทุกคอลัมน์เป็น text โดยตั้งใจ เพื่อไม่ให้ตัวนำเข้าเดาชนิดข้อมูลเอง
--  ถ้าปล่อยให้เดา รหัสสาขา "0083" จะกลายเป็นเลข 83 และเลขทรัพย์สินจะกลายเป็น 1.3E+11

drop table if exists public.stg_branches;
drop table if exists public.stg_branch_assets;
drop table if exists public.stg_asset_warranty;

create table public.stg_branches (branch_code text, branch_name text, contract_type text);
create table public.stg_branch_assets (branch_code text, branch_name text, asset_no text, description text, cap_date text);
create table public.stg_asset_warranty (asset_no text, warranty_start text, warranty_expire text, warranty_months text);

alter table public.stg_branches enable row level security;
alter table public.stg_branch_assets enable row level security;
alter table public.stg_asset_warranty enable row level security;
revoke all on public.stg_branches, public.stg_branch_assets, public.stg_asset_warranty from anon, authenticated;

select 'สร้างตารางพักข้อมูลแล้ว — ไปนำเข้าไฟล์ CSV ทั้ง 3 ไฟล์ต่อได้เลย' as "ขั้นต่อไป";


-- =====================================================================
--  บล็อก B — ตรวจไฟล์ที่นำเข้ามา (รันหลังนำเข้า CSV ครบ 3 ไฟล์)
-- =====================================================================
--  ทุกบรรทัดที่ขึ้นต้นด้วย ❌ ต้องได้ 0

select 'สาขา (ต้องได้ 2334)'                  as "ตรวจ", count(*)::text as "ค่า" from public.stg_branches
union all select 'ทรัพย์สิน (ต้องได้ 61665)', count(*)::text from public.stg_branch_assets
union all select 'วันรับประกัน (ต้องได้ 58748)', count(*)::text from public.stg_asset_warranty
union all select 'สาขาที่ไม่ได้ระบุประเภทสัญญา (ควรได้ 127)', count(*)::text from public.stg_branches
  where coalesce(trim(contract_type), '') = ''
union all select '❌ รหัสสาขาไม่ใช่ 4 ตัว (ต้อง 0)', count(*)::text from public.stg_branches where length(trim(branch_code)) <> 4
union all select '❌ ชื่อสาขาว่าง (ต้อง 0)', count(*)::text from public.stg_branches where coalesce(trim(branch_name),'') = ''
union all select '❌ รหัสสาขาซ้ำ (ต้อง 0)', count(*)::text from (select branch_code from public.stg_branches group by 1 having count(*) > 1) z
union all select '❌ ประเภทสัญญาที่ไม่รู้จัก (ต้อง 0)', count(*)::text from public.stg_branches
  where coalesce(trim(contract_type), '') <> ''
    and trim(contract_type) not in ('Contract Service', 'Turnkey Warranty', 'Turnkey Service')
union all select '❌ ตัวอักษรไทยเสียในชื่อสาขา (ต้อง 0)', count(*)::text from public.stg_branches
  where branch_name like '%' || chr(65533) || '%'
union all select '❌ เลขทรัพย์สินไม่ใช่ 12 หลัก (ต้อง 0)', count(*)::text from public.stg_branch_assets where trim(asset_no) !~ '^[0-9]{12}$'
union all select '❌ เลขทรัพย์สินซ้ำ (ต้อง 0)', count(*)::text from (select asset_no from public.stg_branch_assets group by 1 having count(*) > 1) z
union all select '❌ รายละเอียดทรัพย์สินว่าง (ต้อง 0)', count(*)::text from public.stg_branch_assets where coalesce(trim(description),'') = ''
union all select '❌ ตัวอักษรไทยเสียในทะเบียนทรัพย์สิน (ต้อง 0)', count(*)::text from public.stg_branch_assets
  where branch_name like '%' || chr(65533) || '%' or description like '%' || chr(65533) || '%'
union all select '❌ Cap.date ผิดรูปแบบ (ต้อง 0)', count(*)::text from public.stg_branch_assets
  where coalesce(trim(cap_date),'') <> '' and trim(cap_date) !~ '^\d{4}-\d{2}-\d{2}$'
union all select '❌ วันรับประกันผิดรูปแบบ (ต้อง 0)', count(*)::text from public.stg_asset_warranty
  where (coalesce(trim(warranty_start),'') <> '' and trim(warranty_start) !~ '^\d{4}-\d{2}-\d{2}$')
     or (coalesce(trim(warranty_expire),'') <> '' and trim(warranty_expire) !~ '^\d{4}-\d{2}-\d{2}$');


-- =====================================================================
--  บล็อก C — สำรอง แล้วอัปเดตเข้าตารางจริง
-- =====================================================================
--  ⚠ บล็อก B ต้องผ่านหมดก่อน ถ้าแถวไม่ครบแปลว่านำเข้าไม่สมบูรณ์ อย่ารันบล็อกนี้

create schema if not exists cp9x_backup;
drop table if exists cp9x_backup.branches_20261103;
drop table if exists cp9x_backup.branch_assets_20261103;
drop table if exists cp9x_backup.asset_warranty_20261103;
drop table if exists cp9x_backup.open_contract_type_20261103;
create table cp9x_backup.branches_20261103       as select * from public.branches;
create table cp9x_backup.branch_assets_20261103  as select * from public.branch_assets;
create table cp9x_backup.asset_warranty_20261103 as select * from public.asset_warranty;
-- สำรองประเภทสัญญาเดิมของทุกงาน เผื่อตารางแปลงชื่อผิดคู่ แล้วต้องย้อนกลับ
create table cp9x_backup.open_contract_type_20261103 as
  select 'CM'::text as job_kind, main_id, contract_type from public.open_issues
  union all
  select 'RE'::text, main_id, contract_type from public.re_open_issues;

-- ---- 0. คอลัมน์ใหม่ 2 ตัว ----
alter table public.branches     add column if not exists contract_type text;
alter table public.branch_assets add column if not exists cap_date date;

comment on column public.branches.contract_type is
  'ประเภทสัญญาประจำสาขา (Contract Service / Turnkey Warranty / Turnkey Service) · NULL = ไม่ได้ระบุ ให้กรอกมือตอนเปิดงาน';
comment on column public.branch_assets.cap_date is
  'วันขึ้นทะเบียนทรัพย์สิน (Cap.date) ใช้เติมหัวฟอร์มแนบรูป';

-- ---- 1. สาขา: แก้ชื่อ + ประเภทสัญญาที่เปลี่ยน แล้วเพิ่มสาขาใหม่ ----
update public.branches b
set branch_name   = trim(s.branch_name),
    contract_type = nullif(trim(s.contract_type), ''),
    updated_at    = now()
from public.stg_branches s
where b.branch_code = trim(s.branch_code)
  and (b.branch_name   is distinct from trim(s.branch_name)
    or b.contract_type is distinct from nullif(trim(s.contract_type), ''));

insert into public.branches (branch_code, branch_name, contract_type)
select trim(s.branch_code), trim(s.branch_name), nullif(trim(s.contract_type), '')
from public.stg_branches s
where not exists (select 1 from public.branches b where b.branch_code = trim(s.branch_code));

-- ---- 2. ทรัพย์สิน: แก้ของเดิมที่เปลี่ยน แล้วเพิ่มของใหม่ (ของเดิมที่ไม่มีในไฟล์ไม่ถูกลบ) ----
update public.branch_assets a
set branch_code = trim(s.branch_code),
    branch_name = trim(s.branch_name),
    description = trim(s.description),
    cap_date    = nullif(trim(s.cap_date), '')::date
from public.stg_branch_assets s
where a.asset_no = trim(s.asset_no)
  and (a.branch_code is distinct from trim(s.branch_code)
    or a.branch_name is distinct from trim(s.branch_name)
    or a.description is distinct from trim(s.description)
    or a.cap_date    is distinct from nullif(trim(s.cap_date), '')::date);

insert into public.branch_assets (branch_code, branch_name, asset_no, description, cap_date)
select trim(s.branch_code), trim(s.branch_name), trim(s.asset_no), trim(s.description),
       nullif(trim(s.cap_date), '')::date
from public.stg_branch_assets s
where not exists (select 1 from public.branch_assets a where a.asset_no = trim(s.asset_no));

-- ---- 3. วันรับประกัน: มีอยู่แล้วอัปเดตทับ ไม่มีก็เพิ่ม (asset_no เป็น primary key) ----
insert into public.asset_warranty (asset_no, warranty_start, warranty_expire, warranty_months)
select trim(s.asset_no),
       nullif(trim(s.warranty_start), '')::date,
       nullif(trim(s.warranty_expire), '')::date,
       nullif(trim(s.warranty_months), '')::integer
from public.stg_asset_warranty s
on conflict (asset_no) do update
set warranty_start  = excluded.warranty_start,
    warranty_expire = excluded.warranty_expire,
    warranty_months = excluded.warranty_months;

-- ---- 4. ดัชนีค้นสาขาด้วยรหัส (ใช้ตอนเติมประเภทสัญญาอัตโนมัติ) ----
create index if not exists branches_branch_code_idx on public.branches (branch_code);

-- ---- 5. เปลี่ยนชื่อประเภทสัญญาของงานเก่าให้ตรงกับชื่อในไฟล์ ----
--  ตารางแปลง (ยืนยันกับผู้ใช้แล้ว 3 พ.ย. 2569):
--      Service Contract  ->  Contract Service
--      Service Turnkey   ->  Turnkey Service
--      In Warranty       ->  Turnkey Warranty
--  ค่าอื่นที่ไม่อยู่ในตารางนี้ไม่ถูกแตะ (เช่นค่าที่เคยพิมพ์มือไว้)
--  ถ้าคู่ไหนแปลงผิด ย้อนกลับได้จาก cp9x_backup.open_contract_type_20261103
update public.open_issues set contract_type = case trim(contract_type)
    when 'Service Contract' then 'Contract Service'
    when 'Service Turnkey'  then 'Turnkey Service'
    when 'In Warranty'      then 'Turnkey Warranty'
    else contract_type end
where trim(coalesce(contract_type, '')) in ('Service Contract', 'Service Turnkey', 'In Warranty');

update public.re_open_issues set contract_type = case trim(contract_type)
    when 'Service Contract' then 'Contract Service'
    when 'Service Turnkey'  then 'Turnkey Service'
    when 'In Warranty'      then 'Turnkey Warranty'
    else contract_type end
where trim(coalesce(contract_type, '')) in ('Service Contract', 'Service Turnkey', 'In Warranty');

-- ---- 6. ให้ซิงค์ Google Sheet เขียนแท็บ "เปิดงาน" ใหม่ทั้งแท็บ ----
--  คอลัมน์ "ประเภทสัญญา" ในชีตยังเป็นชื่อเดิมอยู่ ถ้าไม่สั่งซิงค์ใหม่จะไม่ตรงกับในแอป
update public.open_issues    set synced_to_sheet = false where synced_to_sheet is true;
update public.re_open_issues set synced_to_sheet = false where synced_to_sheet is true;

select 'อัปเดตข้อมูลเสร็จแล้ว — ไปรันบล็อก D เพื่อตรวจผล' as "ขั้นต่อไป";


-- =====================================================================
--  บล็อก D — ตรวจผลหลังอัปเดต (อ่านอย่างเดียว)
-- =====================================================================

select 'สาขาทั้งหมด' as "รายการ", count(*)::text as "จำนวน" from public.branches
union all select '  มีประเภทสัญญาแล้ว', count(*)::text from public.branches where contract_type is not null
union all select '  ยังไม่มี (กรอกมือตอนเปิดงาน)', count(*)::text from public.branches where contract_type is null
union all select 'ทรัพย์สินทั้งหมด', count(*)::text from public.branch_assets
union all select '  มี Cap.date แล้ว', count(*)::text from public.branch_assets where cap_date is not null
union all select 'วันรับประกันทั้งหมด', count(*)::text from public.asset_warranty
union all select '❌ ชื่อสาขาที่ตัวอักษรยังเสีย (ต้อง 0)', count(*)::text from public.branches
  where branch_name like '%' || chr(65533) || '%'
union all select '❌ ทะเบียนทรัพย์สินที่ตัวอักษรยังเสีย (ต้อง 0)', count(*)::text from public.branch_assets
  where branch_name like '%' || chr(65533) || '%' or description like '%' || chr(65533) || '%'
union all select '❌ งานที่ยังใช้ชื่อประเภทสัญญาแบบเก่า (ต้อง 0)', count(*)::text from (
  select 1 from public.open_issues where trim(coalesce(contract_type,'')) in ('Service Contract','Service Turnkey','In Warranty')
  union all
  select 1 from public.re_open_issues where trim(coalesce(contract_type,'')) in ('Service Contract','Service Turnkey','In Warranty')
) z;

-- ประเภทสัญญาที่งานในระบบใช้อยู่ (ควรเหลือแต่ 3 ชื่อใหม่ + NULL)
select coalesce(contract_type, '(ไม่ได้ระบุ)') as "ประเภทสัญญาในงาน", count(*)::text as "จำนวนงาน"
from (
  select contract_type from public.open_issues
  union all select contract_type from public.re_open_issues
) z group by 1 order by 2 desc;


-- =====================================================================
--  บล็อก E — เก็บกวาด (รันได้เมื่อบล็อก D ผ่านหมดแล้ว)
-- =====================================================================
--  ตารางพักข้อมูลไม่ได้ใช้อีก ลบทิ้งให้ฐานข้อมูลสะอาด
--  (ตารางสำรองใน cp9x_backup ให้เก็บไว้ อย่าลบ)

-- drop table if exists public.stg_branches;
-- drop table if exists public.stg_branch_assets;
-- drop table if exists public.stg_asset_warranty;
