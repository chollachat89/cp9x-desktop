-- =====================================================================
--  v1.0.98 — อัปเดตทะเบียนสาขา + ทะเบียนทรัพย์สิน + วันรับประกัน
--  จากไฟล์ ฟอล์มส่งรูปวางบิล2.xlsx (3 ต.ค. 2569)
-- =====================================================================
--
--  ⚠ วิธีนี้เป็น "เติม/อัปเดตทับ" ไม่ใช่ "ล้างแล้วใส่ใหม่" — ตั้งใจให้ต่างจากรอบก่อน
--
--  เหตุผล: ไฟล์ใหม่มีทรัพย์สิน 61,665 ชิ้น ส่วนในระบบมีอยู่ 62,310 ชิ้น = ไฟล์ใหม่ "น้อยกว่า" 645 ชิ้น
--  ถ้าล้างแล้วใส่ใหม่ ของที่หายไปจะหายจริง และในนั้นมี 4 ชิ้นที่ "งานจริงอ้างถึงอยู่" คือ
--      130000018622 · 130000018623  (0083-เฉี่ยวโอชา)
--      130022005072                 (0103-ท้ายหาด)
--      131000021110                 (0285-นราภิรมย์)
--  ถ้าหายไป ฟอร์มแนบรูปวางบิลของงานเหล่านั้นจะไม่มีรายละเอียดทรัพย์สิน และช่องเลือกเลขทรัพย์สิน
--  ตอนปิดงานก็จะหาไม่เจอ ทั้งที่งานยังเดินอยู่ -> จึงเก็บของเดิมที่ไม่มีในไฟล์ใหม่ไว้ทั้งหมด
--
--  สรุปสิ่งที่จะเกิด
--    สาขา        2,006 -> เพิ่มของใหม่ (ไฟล์มี 2,266) + แก้ชื่อที่เปลี่ยน
--    ทรัพย์สิน    62,310 -> เพิ่มของใหม่ + แก้สาขา/รายละเอียดที่เปลี่ยน · ของเดิมไม่หาย
--    วันรับประกัน 54,866 -> เพิ่ม/อัปเดตจากไฟล์ (ไฟล์มี 58,748)
--
--  ✅ สำรองทั้ง 3 ตารางไว้ใน schema cp9x_backup ก่อนแก้ (บล็อก C)
--  ✅ รันซ้ำได้ทุกบล็อก
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

create table public.stg_branches (branch_code text, branch_name text);
create table public.stg_branch_assets (branch_code text, branch_name text, asset_no text, description text);
create table public.stg_asset_warranty (asset_no text, warranty_start text, warranty_expire text, warranty_months text);

alter table public.stg_branches enable row level security;
alter table public.stg_branch_assets enable row level security;
alter table public.stg_asset_warranty enable row level security;
revoke all on public.stg_branches, public.stg_branch_assets, public.stg_asset_warranty from anon, authenticated;

select 'สร้างตารางพักข้อมูลแล้ว — ไปนำเข้าไฟล์ CSV ทั้ง 3 ไฟล์ต่อได้เลย' as "ขั้นต่อไป";


-- =====================================================================
--  บล็อก B — ตรวจไฟล์ที่นำเข้ามา (รันหลังนำเข้า CSV ครบ 3 ไฟล์)
-- =====================================================================
--  ทุกบรรทัดต้องเป็น 0 ยกเว้นจำนวนแถว

select 'สาขา (ต้องได้ 2266)'            as "ตรวจ", count(*)::text as "ค่า" from public.stg_branches
union all select 'ทรัพย์สิน (ต้องได้ 61665)', count(*)::text from public.stg_branch_assets
union all select 'วันรับประกัน (ต้องได้ 58748)', count(*)::text from public.stg_asset_warranty
union all select '❌ รหัสสาขาไม่ใช่ 4 ตัว (ต้อง 0)', count(*)::text from public.stg_branches where length(trim(branch_code)) <> 4
union all select '❌ เลขทรัพย์สินไม่ใช่ 12 หลัก (ต้อง 0)', count(*)::text from public.stg_branch_assets where trim(asset_no) !~ '^[0-9]{12}$'
union all select '❌ เลขทรัพย์สินซ้ำ (ต้อง 0)', count(*)::text from (select asset_no from public.stg_branch_assets group by 1 having count(*) > 1) z
union all select '❌ รายละเอียดทรัพย์สินว่าง (ต้อง 0)', count(*)::text from public.stg_branch_assets where coalesce(trim(description),'') = ''
union all select '❌ วันรับประกันผิดรูปแบบ (ต้อง 0)', count(*)::text from public.stg_asset_warranty
  where (coalesce(trim(warranty_start),'') <> '' and trim(warranty_start) !~ '^\d{4}-\d{2}-\d{2}$')
     or (coalesce(trim(warranty_expire),'') <> '' and trim(warranty_expire) !~ '^\d{4}-\d{2}-\d{2}$');


-- =====================================================================
--  บล็อก C — สำรอง แล้วอัปเดตเข้าตารางจริง
-- =====================================================================
--  ⚠ บล็อก B ต้องผ่านหมดก่อน ถ้าแถวไม่ครบแปลว่านำเข้าไม่สมบูรณ์ อย่ารันบล็อกนี้

create schema if not exists cp9x_backup;
drop table if exists cp9x_backup.branches_20261003;
drop table if exists cp9x_backup.branch_assets_20261003;
drop table if exists cp9x_backup.asset_warranty_20261003;
create table cp9x_backup.branches_20261003      as select * from public.branches;
create table cp9x_backup.branch_assets_20261003 as select * from public.branch_assets;
create table cp9x_backup.asset_warranty_20261003 as select * from public.asset_warranty;

-- ---- 1. สาขา: แก้ชื่อที่เปลี่ยน แล้วเพิ่มสาขาใหม่ ----
update public.branches b
set branch_name = trim(s.branch_name), updated_at = now()
from public.stg_branches s
where b.branch_code = trim(s.branch_code)
  and b.branch_name is distinct from trim(s.branch_name);

insert into public.branches (branch_code, branch_name)
select trim(s.branch_code), trim(s.branch_name)
from public.stg_branches s
where not exists (select 1 from public.branches b where b.branch_code = trim(s.branch_code));

-- ---- 2. ทรัพย์สิน: แก้ของเดิมที่เปลี่ยน แล้วเพิ่มของใหม่ (ของเดิมที่ไม่มีในไฟล์ไม่ถูกลบ) ----
update public.branch_assets a
set branch_code = trim(s.branch_code), branch_name = trim(s.branch_name), description = trim(s.description)
from public.stg_branch_assets s
where a.asset_no = trim(s.asset_no)
  and (a.branch_code  is distinct from trim(s.branch_code)
    or a.branch_name  is distinct from trim(s.branch_name)
    or a.description  is distinct from trim(s.description));

insert into public.branch_assets (branch_code, branch_name, asset_no, description)
select trim(s.branch_code), trim(s.branch_name), trim(s.asset_no), trim(s.description)
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
set warranty_start   = excluded.warranty_start,
    warranty_expire  = excluded.warranty_expire,
    warranty_months  = excluded.warranty_months;


-- =====================================================================
--  บล็อก D — ตรวจผลหลังอัปเดต
-- =====================================================================

select 'สาขา' as "ตาราง", (select count(*) from cp9x_backup.branches_20261003)::text as "ก่อน", count(*)::text as "หลัง" from public.branches
union all select 'ทรัพย์สิน', (select count(*) from cp9x_backup.branch_assets_20261003)::text, count(*)::text from public.branch_assets
union all select 'วันรับประกัน', (select count(*) from cp9x_backup.asset_warranty_20261003)::text, count(*)::text from public.asset_warranty;

-- เลขทรัพย์สินที่งานจริงอ้างถึง ต้องหาเจอครบทุกชิ้น (ยกเว้นเลขทดสอบ 000.../111.../1234...)
select count(*) as "เลขทรัพย์สินของงานจริงที่หาไม่เจอ (ต้อง = 0)"
from (
  select trim(asset_id) a from public.close_issues where coalesce(trim(asset_id),'') ~ '^[0-9]{12}$'
  union select trim(asset_id) from public.billing_documents where coalesce(trim(asset_id),'') ~ '^[0-9]{12}$'
) x
where a !~ '^(0{12}|1{12}|12345678901[0-9])$'
  and not exists (select 1 from public.branch_assets ba where ba.asset_no = x.a);

-- เลขทรัพย์สินซ้ำในตารางจริง (ต้อง = 0)
select count(*) as "เลขทรัพย์สินซ้ำ (ต้อง = 0)" from (
  select asset_no from public.branch_assets group by 1 having count(*) > 1
) z;


-- =====================================================================
--  บล็อก E — ลบตารางพักข้อมูลทิ้ง (รันเมื่อบล็อก D ผ่านแล้ว)
-- =====================================================================

drop table if exists public.stg_branches;
drop table if exists public.stg_branch_assets;
drop table if exists public.stg_asset_warranty;

select 'เสร็จเรียบร้อย — สำรองของเดิมอยู่ใน schema cp9x_backup (ลงท้าย _20261003)' as "ผล";
