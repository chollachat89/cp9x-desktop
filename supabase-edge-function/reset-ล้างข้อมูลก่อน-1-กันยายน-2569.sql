-- ============================================================================
-- ⚠⚠ ล้างข้อมูลงานทั้งหมดที่เกิดก่อนวันที่ 1 กันยายน 2569 (= 1 ก.ย. 2026) ⚠⚠
--
--            คำสั่งนี้ลบข้อมูลถาวร กู้คืนไม่ได้ ไม่มีถังขยะ ไม่มี undo
--
-- ตารางที่จะถูกลบ 5 ตาราง:
--   open_issues          (เปิดงาน)
--   close_issues         (ปิดงาน)
--   pause_records        (พักงาน)
--   billing_documents    (ตารางวางบิล)
--   job_form_submissions (ไฟล์ฟอร์มที่ผู้รับเหมาส่งกลับ)
--
-- จากข้อมูลที่ตรวจไว้: เปิดงาน 195 แถว / ปิดงาน 70 แถว ทั้งหมดอยู่ในเดือนสิงหาคม 2026
-- แปลว่ารอบนี้จะไม่เหลือข้อมูลเก่าเลย เท่ากับรีเซ็ตระบบเริ่มนับใหม่ตั้งแต่ 1 ก.ย.
--
-- ใช้ "วันที่ตัด" แทนการล้างทั้งตาราง (ไม่ใช้ truncate/delete ทั้งหมด) เพื่อความปลอดภัย:
-- ถ้าวันนี้มีคนบันทึกงานของวันที่ 1 ก.ย. เข้ามาแล้ว งานนั้นจะไม่ถูกลบไปด้วย
--
-- วิธีใช้: https://supabase.com/dashboard/project/hefnjozijflnhdunmewl/sql/new
--   รันบล็อก A ก่อนเสมอ -> ดูตัวเลขให้แน่ใจ -> (แนะนำ) รันบล็อก B สำรองข้อมูล -> แล้วค่อยรันบล็อก C
-- ============================================================================


-- ---------------------------------------------------------------- บล็อก A
-- อ่านอย่างเดียว: นับดูก่อนว่าจะลบกี่แถว และจะเหลือกี่แถว
-- ตัวเลขในคอลัมน์ "จะถูกลบ" คือจำนวนที่จะหายถาวร ดูให้แน่ใจก่อนไปบล็อกต่อไป
select 'open_issues (เปิดงาน)' as "ตาราง",
       count(*) filter (where created_at <  timestamptz '2026-09-01 00:00:00+07') as "จะถูกลบ",
       count(*) filter (where created_at >= timestamptz '2026-09-01 00:00:00+07') as "จะเหลือไว้"
from open_issues
union all
select 'close_issues (ปิดงาน)',
       count(*) filter (where created_at <  timestamptz '2026-09-01 00:00:00+07'),
       count(*) filter (where created_at >= timestamptz '2026-09-01 00:00:00+07')
from close_issues
union all
select 'pause_records (พักงาน)',
       count(*) filter (where paused_at <  timestamptz '2026-09-01 00:00:00+07'),
       count(*) filter (where paused_at >= timestamptz '2026-09-01 00:00:00+07')
from pause_records
union all
select 'billing_documents (ตารางวางบิล)',
       count(*) filter (where created_at <  timestamptz '2026-09-01 00:00:00+07'),
       count(*) filter (where created_at >= timestamptz '2026-09-01 00:00:00+07')
from billing_documents
union all
select 'job_form_submissions (ฟอร์มที่ส่งกลับ)',
       count(*) filter (where submitted_at <  timestamptz '2026-09-01 00:00:00+07'),
       count(*) filter (where submitted_at >= timestamptz '2026-09-01 00:00:00+07')
from job_form_submissions;


-- ---------------------------------------------------------------- บล็อก B
-- (แนะนำอย่างยิ่ง แต่ข้ามได้) สำรองข้อมูลเป็นตารางสำเนาไว้ก่อนลบ
-- ใช้เวลาไม่กี่วินาที และเป็นทางเดียวที่จะกู้ข้อมูลกลับได้ถ้าลบผิด
-- ตารางสำเนาจะชื่อลงท้ายด้วย _backup_20260901 อยู่ในฐานข้อมูลเดียวกัน ไม่กระทบการใช้งานแอป
-- (ถ้าไม่ต้องการสำรอง ให้ข้ามบล็อกนี้ไปเลย)
create table if not exists open_issues_backup_20260901          as select * from open_issues;
create table if not exists close_issues_backup_20260901         as select * from close_issues;
create table if not exists pause_records_backup_20260901        as select * from pause_records;
create table if not exists billing_documents_backup_20260901    as select * from billing_documents;
create table if not exists job_form_submissions_backup_20260901 as select * from job_form_submissions;

-- ตรวจว่าสำเนาครบ (ตัวเลขต้องตรงกับตารางจริงก่อนลบ)
select 'open_issues'          as "ตาราง", count(*) as "จำนวนที่สำรองไว้" from open_issues_backup_20260901
union all select 'close_issues',         count(*) from close_issues_backup_20260901
union all select 'pause_records',        count(*) from pause_records_backup_20260901
union all select 'billing_documents',    count(*) from billing_documents_backup_20260901
union all select 'job_form_submissions', count(*) from job_form_submissions_backup_20260901;


-- ---------------------------------------------------------------- บล็อก C
-- ★ ลบจริง ★ — รันบล็อกนี้เมื่อดูตัวเลขในบล็อก A แล้วและยอมรับได้เท่านั้น
--
-- ครอบด้วย transaction: ถ้าคำสั่งใดคำสั่งหนึ่งพัง ทุกอย่างจะย้อนกลับหมด
-- ไม่มีสภาพลบไปครึ่ง ๆ กลาง ๆ ที่ทำให้ข้อมูลไม่สอดคล้องกัน
--
-- ลำดับการลบ: ลบตารางลูกที่อ้างถึงเลขงานก่อน แล้วค่อยลบตารางเปิดงานที่เป็นต้นทาง
begin;

delete from job_form_submissions where submitted_at < timestamptz '2026-09-01 00:00:00+07';
delete from billing_documents    where created_at   < timestamptz '2026-09-01 00:00:00+07';
delete from pause_records        where paused_at    < timestamptz '2026-09-01 00:00:00+07';
delete from close_issues         where created_at   < timestamptz '2026-09-01 00:00:00+07';
delete from open_issues          where created_at   < timestamptz '2026-09-01 00:00:00+07';

commit;


-- ---------------------------------------------------------------- บล็อก D
-- ตรวจหลังลบ: คอลัมน์ "เหลืออยู่" ควรเป็น 0 ทั้งหมด (หรือเท่ากับจำนวนงานของวันที่ 1 ก.ย. ที่บันทึกไปแล้ว)
select 'open_issues'          as "ตาราง", count(*) as "เหลืออยู่" from open_issues
union all select 'close_issues',         count(*) from close_issues
union all select 'pause_records',        count(*) from pause_records
union all select 'billing_documents',    count(*) from billing_documents
union all select 'job_form_submissions', count(*) from job_form_submissions;


-- ============================================================================
-- ต้องทำต่ออีก 2 อย่างหลังรันเสร็จ (SQL ทำให้ไม่ได้ ต้องทำเองในหน้าเว็บ)
--
-- 1) ล้างข้อมูลเก่าใน Google Sheet ปลายทาง
--    ระบบซิงค์จะ "เพิ่มแถวใหม่และแก้แถวเดิม" เท่านั้น ไม่เคยลบแถวออกจากชีตเอง
--    ถ้าไม่ล้าง แถวเก่า 195/70 แถวจะค้างอยู่ในชีตตลอดไป ทั้งที่ในฐานข้อมูลไม่มีแล้ว
--    ให้เปิดชีตแล้วลบข้อมูลทุกแท็บ (เปิดงาน / ปิดงาน / พักงาน / ตารางวางบิล / รายงานสถานะ)
--    โดย "เว้นแถวหัวตารางแถวที่ 1 ไว้" แล้วค่อยกดซิงค์ใหม่จากในแอป
--
-- 2) ลบไฟล์เก่าใน Supabase Storage
--    ไฟล์ฟอร์มที่ผู้รับเหมาเคยอัปโหลดอยู่ในถัง (bucket) ชื่อ job-form-submissions
--    การลบแถวในตารางไม่ได้ลบตัวไฟล์ ไฟล์จะค้างกินพื้นที่อยู่
--    ลบได้ที่ Dashboard -> Storage -> job-form-submissions -> เลือกโฟลเดอร์เก่าแล้วลบ
--
-- สิ่งที่ไม่ได้แตะในไฟล์นี้ (ตั้งใจ):
--   - parts        (ข้อมูลอะไหล่และราคา) ยังอยู่ครบ
--   - contractors  (ผู้ใช้/รหัสผ่าน) ยังอยู่ครบ ล็อกอินได้เหมือนเดิม
--   - pm_billing_documents (งาน PM) เป็นคนละระบบ ไม่เกี่ยวกับงาน CM รอบนี้
--
-- เลขรอบบิลจะเริ่มนับ 1 ใหม่เองอัตโนมัติ เพราะระบบคำนวณจากรอบสูงสุดที่มีอยู่ในตาราง
-- ซึ่งตอนนี้ว่างแล้ว ไม่ต้องรีเซ็ตอะไรเพิ่ม
-- ============================================================================
