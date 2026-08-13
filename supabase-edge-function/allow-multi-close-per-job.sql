-- ============================================================================
-- อนุญาตให้ "1 หมายเลขเปิดงาน" ปิดงานได้มากกว่า 1 ครั้ง (ต่างกันแค่ "เลขทรัพย์สิน")
-- เดิมระบบกันไว้แน่นเกินไป: ห้ามปิดงานเลขเดิมซ้ำแม้จะเป็นทรัพย์สินคนละชิ้น
-- รอบนี้เปลี่ยนกฎกันซ้ำจาก "ห้ามซ้ำเลขงาน" -> "ห้ามซ้ำ (เลขงาน + เลขทรัพย์สิน) คู่เดียวกัน"
-- แปลว่า: เลขงานเดียวกัน + เลขทรัพย์สินคนละชิ้น = ปิดได้เรื่อย ๆ ไม่จำกัด
--         เลขงานเดียวกัน + เลขทรัพย์สินชิ้นเดิม (หรือไม่กรอกเลขทรัพย์สินทั้งคู่) = ยังกันซ้ำเหมือนเดิม
--
-- v2: เดิมสคริปต์นี้ลบกฎเก่าด้วยชื่อที่เดาไว้ตรง ๆ (close_issues_job_id_uniq) ถ้าชื่อจริงในระบบไม่ตรง
-- (เช่นถูกสร้างเป็น constraint คนละชื่อ) จะลบไม่ออก แล้วเลขงานเดิมจะยังปิดซ้ำไม่ได้เหมือนเดิม
-- รอบนี้แก้ให้ค้นหาและลบกฎห้ามซ้ำที่ผูกกับ "job_id" เดี่ยว ๆ ทุกชื่อทุกรูปแบบให้อัตโนมัติแทน
--
-- วิธีใช้: เปิด Supabase Dashboard ของโปรเจกต์ CP9X -> SQL Editor -> New query
-- แล้ววางโค้ดด้านล่างนี้ทั้งหมด กด Run (รันซ้ำได้อย่างปลอดภัย)
-- ============================================================================

-- ขั้นที่ 0 (ไม่บังคับ แต่แนะนำ): ดูก่อนว่าตอนนี้ตาราง close_issues มีกฎห้ามซ้ำอะไรอยู่บ้าง
select conname as ชื่อกฎ, pg_get_constraintdef(oid) as รายละเอียด
from pg_constraint
where conrelid = 'close_issues'::regclass and contype = 'u';

select indexname as ชื่อ_index, indexdef as รายละเอียด
from pg_indexes
where tablename = 'close_issues';

-- ขั้นที่ 1: ค้นหาและลบกฎห้ามซ้ำเดิมที่ผูกกับ "job_id" เดี่ยว ๆ (ไม่มี asset_id ร่วมด้วย) ทิ้งทั้งหมด
-- ไม่ว่าจะถูกสร้างเป็น UNIQUE CONSTRAINT หรือ UNIQUE INDEX ธรรมดา และไม่ว่าจะตั้งชื่อว่าอะไรก็ตาม
do $$
declare r record;
begin
  for r in
    select conname from pg_constraint
    where conrelid = 'close_issues'::regclass
      and contype = 'u'
      and pg_get_constraintdef(oid) = 'UNIQUE (job_id)'
  loop
    execute format('alter table close_issues drop constraint %I', r.conname);
    raise notice 'ลบ constraint % แล้ว', r.conname;
  end loop;

  for r in
    select indexname from pg_indexes
    where tablename = 'close_issues'
      and indexdef ilike '%unique index%(job_id)%'
      and indexdef not ilike '%asset_id%'
  loop
    execute format('drop index if exists %I', r.indexname);
    raise notice 'ลบ index % แล้ว', r.indexname;
  end loop;
end $$;

-- ขั้นที่ 2: สร้างกฎใหม่ - ห้ามซ้ำเฉพาะ (เลขงาน + เลขทรัพย์สิน) คู่เดียวกัน
-- IF NOT EXISTS แปลว่ารันซ้ำได้อย่างปลอดภัย ไม่พังถ้าเคยรันไปแล้ว
create unique index if not exists close_issues_job_asset_uniq
    on close_issues (job_id, asset_id);

-- ขั้นที่ 3: ตรวจสอบผลลัพธ์สุดท้าย (ควรเห็นแค่ close_issues_job_asset_uniq เท่านั้นที่เป็น unique
-- ไม่ควรมีกฎไหนที่ผูกกับ job_id เดี่ยว ๆ หลงเหลืออยู่แล้ว)
select conname as ชื่อกฎ, pg_get_constraintdef(oid) as รายละเอียด
from pg_constraint
where conrelid = 'close_issues'::regclass and contype = 'u';

select indexname as ชื่อ_index, indexdef as รายละเอียด
from pg_indexes
where tablename = 'close_issues';
