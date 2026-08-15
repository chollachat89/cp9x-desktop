-- ============================================================================
-- เพิ่มคอลัมน์ "Service Issue" ในตารางเปิดงาน (open_issues)
--
-- ใช้เก็บรหัส/ประเภทอาการเสียที่ได้รับแจ้งมา เช่น "F04_ไม่เย็น/อุณหภูมิไม่ได้มาตรฐาน"
-- เป็นคนละช่องกับ "งานบริการ" (service_work) ที่มีอยู่เดิม
--
-- ค่าเริ่มต้นตั้งเป็น '-' ให้เหมือนช่องอื่น ๆ ในตารางนี้ (ระบบใช้ '-' แทนค่าว่างมาตลอด
-- ไม่ใช้ null เพื่อให้ตอนซิงค์ลง Google Sheet ไม่มีช่องโหว่)
-- แถวเก่าที่มีอยู่แล้วจะได้ค่า '-' ไปด้วย ไม่ต้องไล่แก้เอง
--
-- วิธีใช้: เปิด Supabase Dashboard ของโปรเจกต์ CP9X -> SQL Editor -> New query
-- แล้ววางโค้ดด้านล่างนี้ทั้งหมด กด Run (รันซ้ำได้อย่างปลอดภัย เพราะใช้ if not exists)
-- ============================================================================

alter table open_issues
    add column if not exists service_issue text not null default '-';

-- ตรวจสอบผลลัพธ์ - ต้องเห็นคอลัมน์ service_issue ในรายการ
select column_name, data_type, column_default
from information_schema.columns
where table_name = 'open_issues'
order by ordinal_position;
