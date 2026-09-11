-- ==========================================================
-- เช็คว่าทำไม CM20260820-0042 ถูกส่งมา 2 ครั้ง
--
-- อ่านอย่างเดียวทั้งไฟล์ ไม่แก้ ไม่ลบอะไรเลย
-- รันบล็อก 1 ก่อน แล้วดูคอลัมน์ "สรุปว่าเกิดจากอะไร" ตอบได้เลย
--
-- วิธีใช้: https://supabase.com/dashboard/project/hefnjozijflnhdunmewl/sql/new
-- ==========================================================


-- === บล็อก 1: คำตอบอยู่ตรงนี้ ===
-- แสดงทุกครั้งที่ส่ง เรียงตามเวลา พร้อมบอกว่าห่างจากครั้งก่อนกี่วินาที
-- และสรุปให้เลยว่าน่าจะเกิดจากอะไร
select
  row_number() over (order by submitted_at)                     as "ครั้งที่",
  to_char(submitted_at at time zone 'Asia/Bangkok',
          'DD/MM/YYYY HH24:MI:SS')                              as "เวลาที่ส่ง (เวลาไทย)",
  contractor                                                    as "ผู้ส่ง",
  case status when 'pending'  then 'รอตรวจสอบ'
              when 'approved' then 'อนุมัติแล้ว'
              when 'rejected' then 'ตีกลับ'
              else status end                                   as "สถานะ",
  reviewed_by                                                   as "ผู้อนุมัติ/ตีกลับ",
  admin_remark                                                  as "หมายเหตุแอดมิน",
  file_name                                                     as "ชื่อไฟล์",
  round(extract(epoch from (
    submitted_at - lag(submitted_at) over (order by submitted_at)
  )))                                                           as "ห่างกัน (วินาที)",

  -- สรุปสาเหตุอัตโนมัติ
  case
    when lag(submitted_at) over (order by submitted_at) is null
      then '— ครั้งแรก ปกติ —'

    -- ครั้งก่อนถูกตีกลับ = ผู้รับเหมาส่งใหม่ตามที่ควรทำ ไม่ใช่บั๊ก
    when lag(status) over (order by submitted_at) = 'rejected'
      then '✅ ปกติ — ครั้งก่อนถูกตีกลับ ผู้รับเหมาจึงส่งใหม่ตามหน้าที่'

    -- ห่างกันไม่ถึง 5 นาที และครั้งก่อนไม่ได้ถูกตีกลับ = ส่งซ้ำโดยไม่ตั้งใจ
    when extract(epoch from (submitted_at - lag(submitted_at) over (order by submitted_at))) < 300
      then '⚠ ส่งซ้ำโดยไม่ตั้งใจ — น่าจะเกิดจากครั้งแรกขึ้นว่า "เชื่อมต่อล้มเหลว" เพราะหมดเวลารอ แต่จริง ๆ เซิร์ฟเวอร์บันทึกไปแล้ว ผู้รับเหมาเลยกดส่งอีกรอบ'

    -- ห่างกันนาน แต่ครั้งก่อนยังค้างอยู่ = ผู้รับเหมาส่งเองซ้ำ
    when lag(status) over (order by submitted_at) = 'pending'
      then '⚠ ส่งซ้ำเอง — ครั้งก่อนยังรอตรวจสอบอยู่ (ยังไม่ถูกตีกลับ) ผู้รับเหมาอาจไม่เห็นว่าส่งสำเร็จแล้ว'

    when lag(status) over (order by submitted_at) = 'approved'
      then '⚠ ส่งซ้ำทั้งที่อนุมัติไปแล้ว — ระบบไม่ได้ห้ามไว้'

    else '⚠ ส่งซ้ำ — ดูสถานะครั้งก่อนประกอบ'
  end                                                           as "สรุปว่าเกิดจากอะไร"
from job_form_submissions
where customer_case = 'CM20260820-0042'
order by submitted_at;


-- === บล็อก 2: ข้อมูลงานนี้ในตารางวางบิล ===
-- ดูว่าเลขงานนี้มีกี่แถว กี่รอบบิล และตัดบิลไปหรือยัง
select
  round_no        as "รอบบิล",
  contractor      as "ผู้รับเหมา",
  asset_id        as "เลขทรัพย์สิน",
  part_code       as "รหัสอะไหล่",
  sent_to_contractor as "ส่งบิลแล้ว",
  case when completed_at is null then 'ยังไม่ตัดบิล'
       else to_char(completed_at at time zone 'Asia/Bangkok', 'DD/MM/YYYY HH24:MI') end as "ตัดบิลเมื่อ"
from billing_documents
where customer_case = 'CM20260820-0042'
order by round_no, seq, asset_id;


-- === บล็อก 3: เช็คว่าเป็นปัญหาเฉพาะงานนี้ หรือเป็นทั้งระบบ ===
-- ถ้ามีเลขงานอื่นอีกเยอะที่ส่งซ้ำภายใน 5 นาที = ปัญหาเชิงระบบ ไม่ใช่ผู้รับเหมาคนเดียวพลาด
with เรียงตามเวลา as (
  select
    customer_case, contractor, status, submitted_at,
    lag(submitted_at) over (partition by customer_case order by submitted_at) as ครั้งก่อน,
    lag(status)       over (partition by customer_case order by submitted_at) as สถานะครั้งก่อน
  from job_form_submissions
)
select
  customer_case                                                  as "เลขงาน",
  contractor                                                     as "ผู้รับเหมา",
  to_char(ครั้งก่อน at time zone 'Asia/Bangkok', 'DD/MM/YYYY HH24:MI:SS')   as "ส่งครั้งก่อน",
  to_char(submitted_at at time zone 'Asia/Bangkok', 'DD/MM/YYYY HH24:MI:SS') as "ส่งซ้ำเมื่อ",
  round(extract(epoch from (submitted_at - ครั้งก่อน)))          as "ห่างกัน (วินาที)"
from เรียงตามเวลา
where ครั้งก่อน is not null
  and สถานะครั้งก่อน <> 'rejected'          -- ตัดกรณีที่ถูกตีกลับแล้วส่งใหม่ออก เพราะอันนั้นปกติ
  and extract(epoch from (submitted_at - ครั้งก่อน)) < 300
order by submitted_at desc;

-- นับรวมทั้งระบบ
with เรียงตามเวลา as (
  select
    customer_case, status, submitted_at,
    lag(submitted_at) over (partition by customer_case order by submitted_at) as ครั้งก่อน,
    lag(status)       over (partition by customer_case order by submitted_at) as สถานะครั้งก่อน
  from job_form_submissions
)
select
  count(*)                                                       as "ส่งซ้ำไม่ตั้งใจ (ครั้ง)",
  count(distinct customer_case)                                  as "เลขงานที่เจอ"
from เรียงตามเวลา
where ครั้งก่อน is not null
  and สถานะครั้งก่อน <> 'rejected'
  and extract(epoch from (submitted_at - ครั้งก่อน)) < 300;


-- ==========================================================
-- ถ้าผลออกมาว่าเป็น "ส่งซ้ำโดยไม่ตั้งใจ" และต้องการลบแถวซ้ำทิ้ง
-- ให้ดูเลข id จากบล็อก 1 ก่อน แล้วค่อยลบทีละแถวแบบเจาะจง เช่น
--
--   delete from job_form_submissions where id = 123;
--
-- ⚠ ตัวไฟล์ PDF ใน Storage จะยังค้างอยู่ ต้องไปลบเองที่
--   https://supabase.com/dashboard/project/hefnjozijflnhdunmewl/storage/buckets/job-form-submissions
-- ==========================================================
