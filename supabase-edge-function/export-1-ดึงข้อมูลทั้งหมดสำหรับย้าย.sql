-- ============================================================================
-- EXPORT 1 — ดึงข้อมูลทั้งหมดจาก CP9X (โปรเจกต์ hefnjozijflnhdunmewl) เพื่อเตรียมย้าย
-- ไปลง Dashboard CM (vzyhueinaeulsxfpilrv)
--
-- ไฟล์นี้ "อ่านอย่างเดียว" ไม่แก้ไม่ลบข้อมูลฝั่ง CP9X เลย ปลอดภัย รันซ้ำได้
--
-- สำคัญ: ต้อง Export ผลลัพธ์ "ทั้งหมด" (ไม่ใช่แค่ตัวอย่างบางแถว) เพราะขั้นถัดไป
-- ผมจะเอาไปสร้างคำสั่ง INSERT จริงสำหรับทุกแถว
--
-- วิธีใช้:
--   1. เปิด https://supabase.com/dashboard/project/hefnjozijflnhdunmewl/sql/new
--   2. วางคำสั่งทั้งหมดด้านล่าง กด Run
--   3. กด Export -> Download CSV (หรือ JSON) แล้วอัปโหลดไฟล์นั้นกลับมาในแชท
-- ============================================================================

-- หนึ่งแถว = หนึ่งเลขงาน + หนึ่งเลขทรัพย์สินที่ปิดไปแล้ว (ถ้าเลขงานเดียวปิดหลายทรัพย์สิน จะได้หลายแถว)
-- เลขงานที่ยังไม่เคยปิดเลย จะได้ 1 แถว โดยเลขทรัพย์สิน/วันที่ปิด เป็นค่าว่าง
select
  o.main_id                                                          as job_no,
  o.branch                                                           as branch,
  o.service_work                                                     as service_work,
  o.service_issue                                                    as service_issue,
  o.details                                                          as details,
  o.req_date                                                         as req_date_text,
  c.asset_id                                                         as asset_id,
  c.fix_date                                                         as fix_date_text,
  (c.job_id is not null)                                             as is_closed,
  exists(
    select 1 from pause_records p
    where p.main_id = o.main_id and p.status = 'paused'
  )                                                                   as is_paused
from open_issues o
left join close_issues c on c.job_id = o.main_id
order by o.created_at desc;
