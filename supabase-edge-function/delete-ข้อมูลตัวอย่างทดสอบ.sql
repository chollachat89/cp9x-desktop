-- ============================================================================
-- ลบข้อมูลตัวอย่างที่ใช้ทดสอบออกจากระบบ
--
-- ลบเฉพาะเลขงานชุดตัวอย่าง CM20260901-9001 ถึง CM20260901-9006 เท่านั้น
-- ข้อมูลงานจริงไม่ถูกแตะต้องเลย เพราะทุกคำสั่งกรองด้วย like 'CM20260901-900%'
--
-- ไฟล์นี้พร้อมรันทันที ไม่ต้องแก้อะไร (ไม่มีบรรทัดไหนถูกคอมเมนต์ทิ้งไว้)
--
-- วิธีใช้: https://supabase.com/dashboard/project/hefnjozijflnhdunmewl/sql/new
--   วางทั้งไฟล์ กด Run ครั้งเดียวจบ
--   (จะรันบล็อก A ดูก่อนว่ามีกี่แถวก็ได้ แต่ไม่จำเป็น)
-- ============================================================================


-- ---------------------------------------------------------------- บล็อก A
-- ดูก่อนว่ามีข้อมูลตัวอย่างค้างอยู่กี่แถว (อ่านอย่างเดียว)
select 'open_issues (เปิดงาน)'          as "ตาราง", count(*) as "แถวตัวอย่างที่จะลบ" from open_issues          where main_id       like 'CM20260901-900%'
union all select 'close_issues (ปิดงาน)',         count(*) from close_issues         where job_id        like 'CM20260901-900%'
union all select 'pause_records (พักงาน)',        count(*) from pause_records        where main_id       like 'CM20260901-900%'
union all select 'billing_documents (ตารางวางบิล)', count(*) from billing_documents    where customer_case like 'CM20260901-900%'
union all select 'job_form_submissions (ฟอร์มส่งกลับ)', count(*) from job_form_submissions where customer_case like 'CM20260901-900%';


-- ---------------------------------------------------------------- บล็อก B
-- ลบจริง — ครอบด้วย transaction ถ้าพังกลางทางจะย้อนกลับทั้งหมด
-- ลบตารางลูกก่อน แล้วค่อยลบตารางเปิดงานที่เป็นต้นทาง
begin;

delete from job_form_submissions where customer_case like 'CM20260901-900%';
delete from billing_documents    where customer_case like 'CM20260901-900%';
delete from pause_records        where main_id       like 'CM20260901-900%';
delete from close_issues         where job_id        like 'CM20260901-900%';
delete from open_issues          where main_id       like 'CM20260901-900%';

commit;


-- ---------------------------------------------------------------- บล็อก C
-- ตรวจหลังลบ: ทุกบรรทัดต้องเป็น 0
select 'open_issues'          as "ตาราง", count(*) as "เหลืออยู่" from open_issues          where main_id       like 'CM20260901-900%'
union all select 'close_issues',           count(*) from close_issues         where job_id        like 'CM20260901-900%'
union all select 'pause_records',          count(*) from pause_records        where main_id       like 'CM20260901-900%'
union all select 'billing_documents',      count(*) from billing_documents    where customer_case like 'CM20260901-900%'
union all select 'job_form_submissions',   count(*) from job_form_submissions where customer_case like 'CM20260901-900%';


-- ============================================================================
-- ถ้าเคยกดซิงค์ไป Google Sheet ตอนทดสอบ
-- ระบบซิงค์ไม่เคยลบแถวออกจากชีตเอง แถวตัวอย่างจะยังค้างอยู่ในชีต
-- ให้เปิดชีตแล้วลบแถวที่ขึ้นต้นด้วย CM20260901-900 ออกเองในทุกแท็บที่เจอ
-- ============================================================================
