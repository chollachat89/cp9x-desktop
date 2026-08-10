-- ============================================================================
-- รองรับการ "เพิ่มรายการเอง" ในรอบบิล PM (เช่น ค่าใช้จ่ายอื่นๆ ที่ไม่ได้มาจากระบบ PM โดยตรง)
-- pm_visit_id เดิมเป็น bigint not null + unique (อ้างอิงเลขงานจริงจากระบบ PM) เพื่อไม่แก้ constraint เดิม
-- จึงใช้เลขติดลบจาก sequence แยกต่างหากแทนสำหรับรายการที่เพิ่มเอง (การันตีไม่ชนกับเลข pm_visit_id จริงซึ่งเป็นบวกเสมอ)
--
-- วิธีใช้: เปิด Supabase Dashboard ของโปรเจกต์ CP9X -> SQL Editor -> New query
-- แล้ววางโค้ดด้านล่างนี้ทั้งหมด กด Run
-- ============================================================================

alter table pm_billing_documents
  add column if not exists is_manual boolean not null default false;

comment on column pm_billing_documents.is_manual is
  'true = แถวที่แอดมินเพิ่มเองในหน้าแอป (ไม่ได้มาจากระบบ PM) — ใช้ pm_visit_id ปลอมเป็นเลขติดลบจาก pm_billing_manual_id_seq';

create sequence if not exists pm_billing_manual_id_seq
  start with -1 increment by -1 minvalue -9223372036854775000 no cycle;

create or replace function next_pm_manual_visit_id()
returns bigint
language sql
as $$
  select nextval('pm_billing_manual_id_seq');
$$;

-- ตรวจสอบผลลัพธ์ (ควรเห็นคอลัมน์ is_manual + function next_pm_manual_visit_id ครบ)
select column_name, data_type from information_schema.columns
where table_name = 'pm_billing_documents' and column_name = 'is_manual';
select proname from pg_proc where proname = 'next_pm_manual_visit_id';
