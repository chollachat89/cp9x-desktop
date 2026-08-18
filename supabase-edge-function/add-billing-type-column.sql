-- ============================================================================
-- เพิ่มคอลัมน์ "ประเภทการเก็บเงิน" (billing_type) ในตารางวางบิล (billing_documents)
--
-- ค่าที่ใช้ได้ 2 แบบ:
--   'normal' = เก็บเงินปกติ  -> ออกใบวางบิลทั้งฝั่ง CJ และฝั่งผู้รับเหมา (ค่าเริ่มต้น)
--   'claim'  = เคลม          -> เก็บเงินเฉพาะฝั่ง CJ ตามปกติ แต่ไม่เก็บเงินผู้รับเหมา
--                              และต้องไม่แสดงในใบวางบิล/ตารางของฝั่งผู้รับเหมาเลย
--
-- แถวเก่าทั้งหมดจะได้ค่า 'normal' อัตโนมัติ ซึ่งตรงกับพฤติกรรมเดิมของระบบก่อนมีฟีเจอร์นี้
-- (เดิมทุกแถวถูกเก็บเงินทั้งสองฝั่งอยู่แล้ว) จึงไม่กระทบข้อมูลที่วางบิลไปแล้ว
--
-- วิธีใช้: เปิด Supabase Dashboard ของโปรเจกต์ CP9X -> SQL Editor -> New query
-- แล้ววางโค้ดด้านล่างนี้ทั้งหมด กด Run (รันซ้ำได้อย่างปลอดภัย เพราะใช้ if not exists)
-- ============================================================================

alter table billing_documents
    add column if not exists billing_type text not null default 'normal';

-- กันค่าแปลกปลอมหลุดเข้ามาจากการแก้ข้อมูลตรง ๆ ในฐานข้อมูล
-- (ระบบส่งมาแค่ 2 ค่านี้อยู่แล้ว แต่ล็อกไว้อีกชั้นให้ชัดเจน)
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'billing_documents'::regclass and conname = 'billing_documents_billing_type_chk'
  ) then
    alter table billing_documents
      add constraint billing_documents_billing_type_chk
      check (billing_type in ('normal', 'claim'));
  end if;
end $$;

-- ตรวจสอบผลลัพธ์
select billing_type, count(*) as จำนวนแถว
from billing_documents
group by billing_type;
