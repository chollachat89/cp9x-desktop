-- ============================================================================
-- เพิ่มประเภทการเก็บเงินแบบที่ 3: 'contractor_cr' (ผู้รับเหมาเก็บเงินกับ CR)
--
-- ค่าที่ใช้ได้หลังรันไฟล์นี้มี 3 แบบ:
--   'normal'        = เก็บเงินปกติ            -> ออกใบวางบิลทั้งฝั่ง CJ และฝั่งผู้รับเหมา (ค่าเริ่มต้น)
--   'claim'         = เคลม                    -> ไม่เก็บเงินทั้ง 2 ฝั่ง (ไม่ขึ้นทั้งบิล CJ และบิลผู้รับเหมา)
--   'contractor_cr' = ผู้รับเหมาเก็บเงินกับ CR -> ขึ้นเฉพาะใบวางบิลฝั่งผู้รับเหมา ฝั่ง CJ ไม่เก็บ
--
-- หมายเหตุสำคัญ: ไฟล์นี้ไม่แตะข้อมูลเดิมเลย แถวที่เป็น 'claim' อยู่แล้วยังคงเป็น 'claim' เหมือนเดิม
-- สิ่งที่เปลี่ยนคือ "ความหมาย" ของ claim ในโปรแกรม (เดิมเก็บเงิน CJ ด้วย ตอนนี้ไม่เก็บทั้ง 2 ฝั่ง)
-- ถ้ามีแถวเก่าที่ตั้งเป็นเคลมไว้แต่ยัง "ต้องการเก็บเงิน CJ" อยู่ ต้องเข้าไปเปลี่ยนประเภทแถวนั้นเองในแอป
--
-- วิธีใช้: เปิด Supabase Dashboard ของโปรเจกต์ CP9X -> SQL Editor -> New query
-- แล้ววางโค้ดด้านล่างนี้ทั้งหมด กด Run (รันซ้ำได้อย่างปลอดภัย)
--
-- ต้องรันไฟล์ add-billing-type-column.sql ไปก่อนแล้ว (ไฟล์นั้นเป็นตัวสร้างคอลัมน์ billing_type)
-- ถ้ายังไม่เคยรัน ให้รันไฟล์นั้นก่อนแล้วค่อยรันไฟล์นี้
-- ============================================================================

-- เผื่อกรณีที่ยังไม่เคยรันไฟล์ก่อนหน้า จะได้ไม่ error ตอนแก้ constraint
alter table billing_documents
    add column if not exists billing_type text not null default 'normal';

-- CHECK เดิมล็อกไว้แค่ ('normal','claim') ถ้าไม่ทิ้งก่อน การบันทึกค่า 'contractor_cr'
-- จะถูกฐานข้อมูลปฏิเสธและแอปจะขึ้น error ตอนกดบันทึกแถว
alter table billing_documents
    drop constraint if exists billing_documents_billing_type_chk;

alter table billing_documents
    add constraint billing_documents_billing_type_chk
    check (billing_type in ('normal', 'claim', 'contractor_cr'));

-- ตรวจสอบผลลัพธ์ (ควรเห็นเฉพาะค่าที่อยู่ใน 3 แบบข้างต้น)
select billing_type, count(*) as จำนวนแถว
from billing_documents
group by billing_type
order by billing_type;
