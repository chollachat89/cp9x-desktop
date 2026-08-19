-- ============================================================================
-- PROBE 2 — ตรวจ "ระบบเวลา 2 ระบบ" ฝั่ง CP9X (โปรเจกต์ hefnjozijflnhdunmewl)
--
-- ไฟล์นี้ "อ่านอย่างเดียว" ไม่แก้ ไม่ลบ ไม่เพิ่มข้อมูลใด ๆ ทั้งสิ้น รันซ้ำได้ปลอดภัย
--
-- ทำไมต้องรัน: ตอนนี้ในฐานข้อมูลมีเวลา 2 ชุดที่ไม่ตรงกัน
--
--   ชุดที่ 1 "เวลาที่กรอก"  = open_issues.req_date และ close_issues.fix_date
--                             เป็นคอลัมน์ข้อความ (text) ผู้ใช้พิมพ์/ดูดข้อความมาเอง รูปแบบไม่ถูกบังคับ
--   ชุดที่ 2 "เวลาที่จับ"   = open_issues.created_at และ close_issues.created_at
--                             เป็น timestamp จริง แต่ค่าที่อยู่ในนั้นมี 2 แบบปนกัน
--                               - แถวที่บันทึกตั้งแต่ v1.0.30 ขึ้นไป = วันเวลาที่ผู้ใช้เลือกในฟอร์ม (ถูกต้อง)
--                               - แถวเก่ากว่านั้น / แถวที่ตอนบันทึกไม่ได้เลือกวันเวลา = เวลาที่กดบันทึก (ไม่ตรงงานจริง)
--
-- status_report_view ตอนนี้ใช้ created_at เป็น "วันที่เปิดงาน"/"วันที่ปิดงาน"
-- จึงได้เวลาปนกัน 2 แบบ ซึ่งคือปัญหาที่ต้องแก้ก่อนส่งข้อมูลเข้า Dashboard CM
--
-- ผมต้องเห็น "รูปแบบข้อความจริง" ที่อยู่ในคอลัมน์ req_date / fix_date ก่อน
-- ถึงจะเขียนตัวแปลงวันที่ใน SQL ได้ถูก โดยไม่เดาเอาเอง (เดาผิด = วันที่เพี้ยนทั้งระบบ)
--
-- วิธีใช้:
--   1. เปิด https://supabase.com/dashboard/project/hefnjozijflnhdunmewl/sql/new
--   2. วางทีละบล็อก (A, B, C, D) แล้วกด Run
--   3. คัดลอกผลลัพธ์กลับมาวางในแชท
-- ============================================================================


-- ---------------------------------------------------------------- บล็อก A
-- รูปแบบข้อความจริงของ req_date (แปลงตัวเลขทุกตัวเป็น 9 เพื่อดูแค่ "หน้าตา" ของรูปแบบ)
-- ต้องการรู้ว่ามีแบบไหนบ้าง เช่น 99/99/9999 หรือ 99-99-99 หรือ 9 ม.ค. 9999 และแบบไหนเยอะสุด
select
  regexp_replace(coalesce(req_date, '(null)'), '[0-9]', '9', 'g') as "รูปแบบ",
  count(*)                                                        as "จำนวนแถว",
  min(req_date)                                                   as "ตัวอย่างที่ 1",
  max(req_date)                                                   as "ตัวอย่างที่ 2"
from open_issues
group by 1
order by "จำนวนแถว" desc;


-- ---------------------------------------------------------------- บล็อก B
-- รูปแบบข้อความจริงของ fix_date (เหตุผลเดียวกับบล็อก A)
select
  regexp_replace(coalesce(fix_date, '(null)'), '[0-9]', '9', 'g')  as "รูปแบบ",
  count(*)                                                         as "จำนวนแถว",
  min(fix_date)                                                    as "ตัวอย่างที่ 1",
  max(fix_date)                                                    as "ตัวอย่างที่ 2"
from close_issues
group by 1
order by "จำนวนแถว" desc;


-- ---------------------------------------------------------------- บล็อก C
-- เวลา 2 ชุดตรงกันแค่ไหน — ดูจากปีที่อยู่ใน created_at เทียบกับปีที่อยู่ในข้อความ
-- ถ้าเจอ "ปีในข้อความเป็น พ.ศ." เยอะ ผมต้องใส่ตัวลบ 543 ในตัวแปลงด้วย
select
  'open_issues'                                                    as "ตาราง",
  count(*)                                                         as "จำนวนแถวทั้งหมด",
  count(*) filter (where req_date ~ '(19|20)[0-9]{2}')             as "ข้อความมีปี ค.ศ.",
  count(*) filter (where req_date ~ '25[0-9]{2}')                  as "ข้อความมีปี พ.ศ.",
  count(*) filter (where req_date is null or trim(req_date) in ('', '-')) as "ข้อความว่าง/ขีด",
  min(created_at)                                                  as "created_at เก่าสุด",
  max(created_at)                                                  as "created_at ใหม่สุด"
from open_issues
union all
select
  'close_issues',
  count(*),
  count(*) filter (where fix_date ~ '(19|20)[0-9]{2}'),
  count(*) filter (where fix_date ~ '25[0-9]{2}'),
  count(*) filter (where fix_date is null or trim(fix_date) in ('', '-')),
  min(created_at),
  max(created_at)
from close_issues;


-- ---------------------------------------------------------------- บล็อก D
-- ตัวอย่างของจริง 15 แถวล่าสุด วางคู่กันให้เห็นชัดว่า 2 ชุดต่างกันแค่ไหน
-- (คอลัมน์ "ต่างกันกี่วัน" คือตัวชี้ว่าแถวไหนใช้เวลาที่จับตอนกดบันทึกอยู่)
select
  o.main_id                                                        as "เลขงาน",
  o.req_date                                                       as "วันที่ร้องขอ (ข้อความที่กรอก)",
  o.created_at at time zone 'Asia/Bangkok'                         as "created_at (เวลาไทย)",
  c.fix_date                                                       as "วันที่เข้าแก้ไข (ข้อความที่กรอก)",
  c.created_at at time zone 'Asia/Bangkok'                         as "close created_at (เวลาไทย)"
from open_issues o
left join close_issues c on c.job_id = o.main_id
order by o.created_at desc
limit 15;
