-- ============================================================================
-- PROBE 3 — ตัวอย่างข้อมูลจริงใน cm_work_orders (โปรเจกต์ vzyhueinaeulsxfpilrv)
--
-- ไฟล์นี้ "อ่านอย่างเดียว" ไม่แก้ ไม่ลบ ไม่เพิ่มข้อมูลใด ๆ ทั้งสิ้น รันซ้ำได้ปลอดภัย
--
-- ทำไมต้องรัน: ตาราง cm_work_orders มี 4 คอลัมน์ที่หน้าตาเหมือน "เลขงาน" อยู่ด้วยกัน
-- (work_order_no, request_no, ticket_no, order_no) ต้องดูข้อมูลจริงก่อนถึงจะรู้ว่า
-- เลขงานของเรา (เช่น CM20260817-0177) ควรไปลงคอลัมน์ไหน และคอลัมน์ไหนใช้กันซ้ำได้จริง
--
-- วิธีใช้:
--   1. เปิด https://supabase.com/dashboard/project/vzyhueinaeulsxfpilrv/sql/new
--   2. วางทีละบล็อก (A, B, C, D) แล้วกด Run
--   3. คัดลอกผลลัพธ์กลับมาวางในแชท
-- ============================================================================


-- ---------------------------------------------------------------- บล็อก A
-- ตัวอย่างข้อมูลจริง 20 แถวล่าสุด ดูรูปแบบเลขงาน/สาขา/เลขทรัพย์สินที่ใช้จริง
select
  id, store_code, store_name, work_order_no, request_no, ticket_no, order_no,
  status, work_type, service_type, asset_no, asset_name, source,
  created_at at time zone 'Asia/Bangkok' as created_at_th,
  requested_at at time zone 'Asia/Bangkok' as requested_at_th,
  work_date at time zone 'Asia/Bangkok' as work_date_th
from cm_work_orders
order by created_at desc
limit 20;


-- ---------------------------------------------------------------- บล็อก B
-- แต่ละคอลัมน์ที่อาจเป็น "เลขงาน" กรอกครบกี่แถว จาก 1012 แถวทั้งหมด และมีรูปแบบหน้าตายังไง
-- (ตัวไหนกรอกครบเกือบทุกแถวและหน้าตาคล้ายเลขงานเรา คือตัวที่ควรใช้)
select
  'work_order_no' as "คอลัมน์",
  count(*) filter (where work_order_no is not null and trim(work_order_no) <> '') as "กรอกแล้ว",
  count(distinct work_order_no) as "ค่าไม่ซ้ำ",
  (array_agg(work_order_no) filter (where work_order_no is not null and trim(work_order_no) <> ''))[1:3] as "ตัวอย่าง"
from cm_work_orders
union all
select 'request_no',
  count(*) filter (where request_no is not null and trim(request_no) <> ''),
  count(distinct request_no),
  (array_agg(request_no) filter (where request_no is not null and trim(request_no) <> ''))[1:3]
from cm_work_orders
union all
select 'ticket_no',
  count(*) filter (where ticket_no is not null and trim(ticket_no) <> ''),
  count(distinct ticket_no),
  (array_agg(ticket_no) filter (where ticket_no is not null and trim(ticket_no) <> ''))[1:3]
from cm_work_orders
union all
select 'order_no',
  count(*) filter (where order_no is not null and trim(order_no) <> ''),
  count(distinct order_no),
  (array_agg(order_no) filter (where order_no is not null and trim(order_no) <> ''))[1:3]
from cm_work_orders;


-- ---------------------------------------------------------------- บล็อก C
-- เช็คว่าคอลัมน์เลขงานที่จะใช้กันซ้ำ มีค่าซ้ำกันอยู่แล้วในข้อมูลเดิมไหม
-- (ถ้ามีแถวที่ "จำนวน" > 1 แปลว่าคอลัมน์นั้นใส่ unique constraint ตรง ๆ ไม่ได้ ต้องจัดการข้อมูลซ้ำก่อน)
select work_order_no, count(*) as "จำนวน"
from cm_work_orders
where work_order_no is not null and trim(work_order_no) <> ''
group by work_order_no
having count(*) > 1
order by count(*) desc
limit 20;


-- ---------------------------------------------------------------- บล็อก D
-- รูปแบบข้อมูลสาขา (store_code / store_name) ที่ใช้จริงใน cm_work_orders
-- เทียบกับ store_directory/store_master เพื่อดูว่าจะจับคู่สาขาของเรา (เช่น "0064-โป่งดุสิต") เข้ากับฝั่งเขายังไง
select store_code, store_name, count(*) as "จำนวนงาน"
from cm_work_orders
group by store_code, store_name
order by "จำนวนงาน" desc
limit 20;
