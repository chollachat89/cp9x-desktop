-- ============================================================================
-- เพิ่มคอลัมน์ "แก้ไขรายละเอียดในใบเสนอราคา" ต่อแถวงาน PM ที่บันทึกรอบบิลไปแล้ว
-- (ใช้กับปุ่มดาวน์โหลดใบเสนอราคา PDF — ถ้าไม่แก้ไข จะใช้ค่าเริ่มต้น "รหัสสาขา + ชื่อสาขา" เหมือนเดิม)
--
-- วิธีใช้: เปิด Supabase Dashboard ของโปรเจกต์ CP9X -> SQL Editor -> New query
-- แล้ววางโค้ดด้านล่างนี้ทั้งหมด กด Run
-- ============================================================================

alter table pm_billing_documents
  add column if not exists desc_override text;

comment on column pm_billing_documents.desc_override is
  'ข้อความ Description ที่แก้ไขเองสำหรับแถวนี้ในใบเสนอราคา PDF (ถ้าเว้นว่าง จะใช้ "รหัสสาขา + ชื่อสาขา" อัตโนมัติ)';

-- ตรวจสอบผลลัพธ์ (ควรเห็นคอลัมน์ desc_override อยู่ในรายการ)
select column_name, data_type from information_schema.columns
where table_name = 'pm_billing_documents' and column_name = 'desc_override';
