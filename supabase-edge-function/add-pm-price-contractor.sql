-- ============================================================================
-- เมนู "PM" — เพิ่มราคาฝั่งผู้รับเหมา แยกจากราคา CJ
-- วันที่ 18 กันยายน 2026  (เวอร์ชัน 1.0.67)
--
-- ของเดิม  pm_billing_documents.price             = ราคา CJ (ราคาเดียวในตาราง)
-- ของใหม่  pm_billing_documents.price_contractor  = ราคาที่จ่ายผู้รับเหมา
--
-- แนวเดียวกับตารางวางบิล CJ ที่มี unit_price / unit_price_contractor อยู่แล้ว
-- สองช่องแยกขาดจากกัน ไม่มีการเดาแทนกัน:
--   รอบไหนยังไม่ได้ตั้งราคาผู้รับเหมา จะขึ้นขีดกลาง ไม่ใช่ไปหยิบราคา CJ มาแสดงแทน
--   (บั๊กแบบนี้เคยเกิดกับฝั่งบิล CJ มาแล้ว แก้ไปรอบหนึ่ง จึงกันไว้ตั้งแต่ต้น)
--
-- ต้นทางของค่านี้คือ pm_schedules.price_contractor ในระบบ PM
-- ซึ่งส่งมาให้ผ่าน Edge Function "pm-billing-export"
-- ต้องรันไฟล์ _price_contractor_2026-09-18.sql ที่ฐานข้อมูล PM ก่อน
-- แล้ว deploy pm-billing-export ตัวใหม่ ไม่งั้นค่าที่ส่งมาจะเป็น null ทุกแถว
--
-- วิธีใช้: เปิด Supabase Dashboard ของโปรเจกต์ CP9X -> SQL Editor -> New query
-- แล้ววางโค้ดด้านล่างนี้ทั้งหมด กด Run
--
-- ไฟล์นี้รันซ้ำได้ ไม่พัง และไม่แตะข้อมูลเดิมสักแถว
-- ============================================================================

alter table pm_billing_documents
  add column if not exists price_contractor numeric;

comment on column pm_billing_documents.price_contractor is
  'ราคาที่จ่ายผู้รับเหมาสำหรับรอบนี้ — แยกขาดจาก price ซึ่งเป็นราคา CJ · null = ยังไม่ได้ตั้งราคา ห้ามถอยไปใช้ราคา CJ แทน';

comment on column pm_billing_documents.price is
  'ราคาฝั่ง CJ สำหรับรอบนี้ — ดึงมาจากระบบ PM ตอนบันทึกรอบบิล แก้ไขในตารางนี้ได้ภายหลัง';

-- ตรวจสอบผลลัพธ์ (ควรเห็นสองแถว: price และ price_contractor)
select column_name, data_type
from information_schema.columns
where table_name = 'pm_billing_documents'
  and column_name in ('price', 'price_contractor')
order by column_name;

-- นับรายการที่มีราคาแต่ละฝั่ง (ก่อนบันทึกรอบบิลใหม่ ราคาผู้รับเหมาจะยังเป็น 0 แถว เป็นเรื่องปกติ
-- เพราะรอบเก่าบันทึกไว้ตอนที่ระบบยังไม่มีคอลัมน์นี้ — ถ้าต้องการให้รอบเก่ามีด้วย ต้องกรอกเองในตาราง)
select count(*) filter (where price is not null)            as "มีราคา CJ",
       count(*) filter (where price_contractor is not null) as "มีราคาผู้รับเหมา",
       count(*)                                             as "รายการทั้งหมด"
from pm_billing_documents;
