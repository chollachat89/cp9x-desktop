-- ============================================================================
-- เมนู "PM" ใหม่ใน CP9X — ตารางเก็บรอบบิลงาน PM (ดึงข้อมูลมาจากอีกโปรเจกต์ Supabase
-- ของระบบ PM โดยตรง ผ่าน Edge Function "pm-billing-export" — แยกจากระบบวางบิล CJ เดิม
-- ทั้งหมด ไม่ปนกัน ไม่กระทบตาราง billing_documents เดิมแม้แต่น้อย)
--
-- วิธีใช้: เปิด Supabase Dashboard ของโปรเจกต์ CP9X -> SQL Editor -> New query
-- แล้ววางโค้ดด้านล่างนี้ทั้งหมด กด Run
-- ============================================================================

-- ตารางเก็บรายการที่บันทึกรอบบิล PM แล้ว (สร้างจากการกด "ยืนยันบันทึกรอบบิล PM" ในแอป)
create table if not exists pm_billing_documents (
  id bigint generated always as identity primary key,
  pm_visit_id bigint not null,              -- เลขอ้างอิงจากระบบ PM (pm_visits.id) — กันบันทึกซ้ำด้วย unique index ด้านล่าง
  round_no integer not null,
  round_period text,
  seq integer,
  job_code text,
  branch_code text,
  branch_name text,
  contractor text,
  technician text,
  cycle_year integer,
  quarter smallint,
  visit_date date,
  price numeric,                             -- ดึงมาจากระบบ PM ก่อน แต่แก้ไขได้ในตารางนี้ภายหลัง (ข้อมูลราคาต้นทางยังกรอกไม่ครบ)
  due_date date,
  work_done text,
  remark text,
  sent_to_contractor boolean not null default false,
  sent_at timestamptz,
  completed_at timestamptz,
  synced_to_sheet boolean not null default false,
  created_at timestamptz not null default now()
);

-- กันบันทึกงาน PM ตัวเดียวกันซ้ำสองรอบบิล (ด่านสุดท้ายกันซ้ำระดับฐานข้อมูล เหมือนที่ทำกับ open_issues/close_issues)
create unique index if not exists pm_billing_documents_pm_visit_id_uniq
  on pm_billing_documents (pm_visit_id);

create index if not exists pm_billing_documents_round_no_idx
  on pm_billing_documents (round_no);

-- เลขรอบบิล PM แยกชุดจากเลขรอบบิล CJ (คนละ sequence กันคนละสถานะกันสับสน)
create sequence if not exists pm_billing_round_no_seq start 1;

create or replace function next_pm_billing_round_no()
returns integer
language sql
as $$
  select nextval('pm_billing_round_no_seq')::integer;
$$;

-- ตรวจสอบผลลัพธ์ (ควรเห็นตาราง + index + function ครบ)
select tablename from pg_tables where tablename = 'pm_billing_documents';
select indexname from pg_indexes where indexname in ('pm_billing_documents_pm_visit_id_uniq', 'pm_billing_documents_round_no_idx');
select proname from pg_proc where proname = 'next_pm_billing_round_no';
