-- ============================================================================
-- เพิ่มคอลัมน์ "ประเภทการเก็บเงิน" (billing_type) ในตารางวางบิล (billing_documents)
--
-- ค่าที่ใช้ได้ 2 แบบ:
--   'normal' = เก็บเงินปกติ  -> ออกใบวางบิลทั้งฝั่ง CJ และฝั่งผู้รับเหมา (ค่าเริ่มต้น)
--   'claim'  = เคลม          -> ไม่เก็บเงินผู้รับเหมา
--
-- *** ไฟล์นี้เป็นของเวอร์ชัน 1.0.36 ตอนนี้มีไฟล์ที่ใหม่กว่าแล้ว ***
-- ตั้งแต่เวอร์ชัน 1.0.37 เป็นต้นไป ให้รัน add-billing-type-contractor-cr.sql ต่อจากไฟล์นี้ด้วย
-- ไฟล์นั้นจะเพิ่มประเภทที่ 3 ('contractor_cr' = ผู้รับเหมาเก็บเงินกับ CR) และเปลี่ยนความหมายของ 'claim'
-- ให้เป็น "ไม่เก็บเงินทั้ง CJ และผู้รับเหมา"
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
