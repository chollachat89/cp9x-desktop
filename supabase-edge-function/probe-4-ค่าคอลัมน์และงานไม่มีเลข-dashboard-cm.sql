-- ============================================================================
-- PROBE 4 — ค่าที่ใช้จริงในคอลัมน์สถานะ + ดูแถวที่ไม่มี work_order_no
-- (โปรเจกต์ vzyhueinaeulsxfpilrv) — อ่านอย่างเดียว ไม่แก้ไม่ลบ รันซ้ำได้ปลอดภัย
--
-- วิธีใช้: วางทีละบล็อก (A, B, C) ใน SQL Editor แล้วส่งผลกลับมา
-- ============================================================================


-- ---------------------------------------------------------------- บล็อก A
-- ค่าที่ใช้จริงในคอลัมน์สถานะ/หมวดหมู่ทั้งหมด + เช็คว่ามี CHECK constraint บังคับค่าไหม
select
  'status' as "คอลัมน์", status as "ค่า", count(*) as "จำนวน" from cm_work_orders group by status
union all
select 'work_type', work_type, count(*) from cm_work_orders group by work_type
union all
select 'team', team, count(*) from cm_work_orders group by team
union all
select 'wf_status', wf_status, count(*) from cm_work_orders group by wf_status
union all
select 'source', source, count(*) from cm_work_orders group by source
union all
select 'problem_type', problem_type, count(*) from cm_work_orders group by problem_type
union all
select 'action_type', action_type, count(*) from cm_work_orders group by action_type
union all
select 'result_status', result_status, count(*) from cm_work_orders group by result_status
order by 1, 3 desc;


-- ---------------------------------------------------------------- บล็อก B
-- มี CHECK constraint บังคับค่า status (หรือคอลัมน์อื่น) อยู่ไหม
select
  con.conname as "ชื่อ constraint",
  pg_get_constraintdef(con.oid) as "นิยาม"
from pg_constraint con
join pg_namespace n on n.oid = con.connamespace
where n.nspname = 'public'
  and con.conrelid = 'cm_work_orders'::regclass
  and con.contype = 'c';


-- ---------------------------------------------------------------- บล็อก C
-- 282 แถวที่ work_order_no ว่าง มาจากไหน หน้าตาเป็นยังไง (กันสับสนกับข้อมูลเรา)
select id, store_code, store_name, status, work_type, source,
       request_no, ticket_no, asset_no,
       created_at at time zone 'Asia/Bangkok' as created_at_th
from cm_work_orders
where work_order_no is null or trim(work_order_no) = ''
order by created_at desc
limit 15;
