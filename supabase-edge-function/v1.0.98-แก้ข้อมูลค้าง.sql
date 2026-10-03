-- =====================================================================
--  v1.0.98 — แก้ข้อมูลที่ค้างผิดอยู่ในระบบจริง (ตรวจ 3 ต.ค. 2569)
-- =====================================================================
--
--  1. วันที่เข้าแก้ไขพิมพ์ปีผิดเป็น 2029 — 10 แถว
--     งานพวกนี้ "ดึงเข้ารอบบิลไม่ได้จนถึงปี 2029" เพราะระบบดูวันที่เข้าแก้ไขว่าอยู่ในรอบไหน
--     ทุกแถวบันทึกเมื่อ ก.ย.-ต.ค. 2026 จึงแก้เป็น 2026
--     (โค้ดตั้งแต่ v1.0.93 กันการพิมพ์ปีอนาคตไว้แล้ว — แถวพวกนี้บันทึกก่อนหน้านั้น)
--
--  2. แถวบิล CM20260908-0140 รหัสสาขาเป็น 1736 แต่ชื่อสาขา/เปิดงาน/ปิดงาน เป็น 1420-ชยางกูร 42
--     แก้รหัสสาขาให้ตรงเป็น 1420
--
--  3. คีย์จองรอบบิลที่ไม่มีงานแล้ว 4 คีย์ (เลขงานถูกลบไปตอนล้างข้อมูล 1 ก.ย.) — ลบทิ้ง ไม่กระทบงานไหน
--
--  ✅ สำรองทุกแถวที่จะแก้ไว้ใน schema cp9x_backup ก่อน (ย้อนกลับได้)
--  ✅ รันซ้ำได้ (รอบสองจะไม่เจอแถวให้แก้แล้ว)
-- =====================================================================

create schema if not exists cp9x_backup;

-- ---- สำรอง ----
create table if not exists cp9x_backup.close_issues_fixdate_2029_v1098 as
  select * from public.close_issues where fix_date ~ '[-/]2029$' and created_at < '2027-01-01';
create table if not exists cp9x_backup.billing_branch_fix_v1098 as
  select * from public.billing_documents where customer_case = 'CM20260908-0140' and branch_code = '1736';
create table if not exists cp9x_backup.registry_orphans_v1098 as
  select r.* from public.billing_job_registry r
  where not exists (select 1 from public.open_issues o where o.main_id = split_part(r.customer_case, '__asset__', 1))
    and not exists (select 1 from public.billing_documents b where b.customer_case = split_part(r.customer_case, '__asset__', 1));

-- ---- 1. ปี 2029 -> 2026 ----
update public.close_issues
set fix_date = regexp_replace(fix_date, '2029$', '2026')
where fix_date ~ '[-/]2029$' and created_at < '2027-01-01';

-- ---- 2. รหัสสาขาของแถวบิล ----
update public.billing_documents
set branch_code = '1420'
where customer_case = 'CM20260908-0140' and branch_code = '1736' and branch_name like '1420-%';

-- ---- 3. คีย์จองที่ไม่มีงานแล้ว ----
delete from public.billing_job_registry r
where not exists (select 1 from public.open_issues o where o.main_id = split_part(r.customer_case, '__asset__', 1))
  and not exists (select 1 from public.billing_documents b where b.customer_case = split_part(r.customer_case, '__asset__', 1));

-- ---- ตรวจผล: ทุกบรรทัดต้องเป็น 0 ----
select 'วันที่เข้าแก้ไขปี 2029 ที่ยังเหลือ' as "ตรวจ", count(*) as "ต้อง = 0" from public.close_issues where fix_date ~ '[-/]2029$'
union all
select 'แถวบิลรหัสสาขาไม่ตรงกับเปิดงาน', count(*) from public.billing_documents b join public.open_issues o on o.main_id = b.customer_case
  where b.branch_code is not null and split_part(o.branch, '-', 1) <> b.branch_code
union all
select 'คีย์จองที่ไม่มีงาน', count(*) from public.billing_job_registry r
  where not exists (select 1 from public.open_issues o where o.main_id = split_part(r.customer_case, '__asset__', 1))
    and not exists (select 1 from public.billing_documents b where b.customer_case = split_part(r.customer_case, '__asset__', 1));
