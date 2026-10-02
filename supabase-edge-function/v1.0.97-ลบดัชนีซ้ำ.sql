-- =====================================================================
--  v1.0.97 — ลบดัชนี (index) ที่ซ้ำกัน 7 คู่
-- =====================================================================
--
--  ตัวตรวจประสิทธิภาพของ Supabase (Performance Advisor) แจ้งว่ามีดัชนี "เหมือนกันทุกอย่าง" ซ้ำกัน 7 คู่
--  ดัชนีซ้ำไม่ได้ทำให้ค้นเร็วขึ้นเลย แต่ทุกครั้งที่บันทึก/แก้ข้อมูล ฐานข้อมูลต้องอัปเดตทั้ง 2 ตัว
--  = เขียนช้าลงเปล่า ๆ และกินพื้นที่สองเท่า
--
--  เก็บชื่อแบบ *_idx ไว้ (เป็นชื่อที่ไฟล์ เพิ่มดัชนี-รองรับ3ปี.sql ของโปรเจกต์นี้สร้าง)
--  ลบชื่อแบบ idx_* ทิ้ง (ไม่มีไฟล์ไหนในโปรเจกต์สร้าง — ถ้าลบฝั่งนี้ รันไฟล์ดัชนีซ้ำวันหลังก็ไม่กลับมาซ้ำอีก)
--
--  ✅ ปลอดภัย: ไม่แตะข้อมูลเลยแม้แต่แถวเดียว และไม่มีดัชนีตัวไหนเป็นตัวคุม unique / primary key
--  ✅ รันซ้ำได้ (if exists)
--  ✅ ย้อนกลับได้: create index idx_xxx on ... (คำสั่งเดิมอยู่ท้ายไฟล์)
-- =====================================================================

drop index if exists public.idx_billing_documents_contractor;
drop index if exists public.idx_billing_documents_customer_case;
drop index if exists public.idx_billing_documents_round_no;
drop index if exists public.idx_branches_branch_code;
drop index if exists public.idx_close_issues_job_id;
drop index if exists public.idx_open_issues_main_id;
drop index if exists public.idx_pause_records_main_id;

-- ---- ตรวจผล: ทุกคอลัมน์ต้องเหลือดัชนี 1 ตัวพอดี (ตัว *_idx) ----
select t.relname as "ตาราง", a.attname as "คอลัมน์", count(*) as "จำนวนดัชนี (ต้อง = 1)"
from pg_index i
join pg_class t on t.oid = i.indrelid
join pg_attribute a on a.attrelid = t.oid and a.attnum = i.indkey[0]
where t.relnamespace = 'public'::regnamespace and i.indnatts = 1
  and (t.relname, a.attname) in (('billing_documents','contractor'), ('billing_documents','customer_case'),
       ('billing_documents','round_no'), ('branches','branch_code'), ('close_issues','job_id'),
       ('open_issues','main_id'), ('pause_records','main_id'))
group by 1, 2 order by 1, 2;

-- ---- ถ้าต้องการย้อนกลับ (ไม่จำเป็น) ----
-- create index idx_billing_documents_contractor    on public.billing_documents (contractor);
-- create index idx_billing_documents_customer_case on public.billing_documents (customer_case);
-- create index idx_billing_documents_round_no      on public.billing_documents (round_no);
-- create index idx_branches_branch_code            on public.branches (branch_code);
-- create index idx_close_issues_job_id             on public.close_issues (job_id);
-- create index idx_open_issues_main_id             on public.open_issues (main_id);
-- create index idx_pause_records_main_id           on public.pause_records (main_id);
