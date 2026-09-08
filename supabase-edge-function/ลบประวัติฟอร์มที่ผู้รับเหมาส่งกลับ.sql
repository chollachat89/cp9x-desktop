-- ============================================================================
-- ล้างประวัติฟอร์มที่ผู้รับเหมาส่งกลับทั้งหมด (เริ่มนับหนึ่งใหม่ด้วยฟอร์มแบบใหม่)
--
-- ใช้เมื่อ: เปลี่ยนไปใช้ "ฟอร์มแนบรูป" แบบใหม่ใน v1.0.55 แล้วต้องการให้ผู้รับเหมา
--          ดาวน์โหลดฟอร์มใหม่ กรอกใหม่ และส่งกลับมาใหม่ทุกงาน
--
-- ⚠⚠ คำเตือน: บล็อก C และ D "ลบข้อมูลถาวร" กู้คืนไม่ได้
--    ให้รันบล็อก A และ B (อ่านอย่างเดียว) ดูให้ครบก่อนเสมอ
--    ถ้าอยากเก็บสำเนาไว้ก่อน ให้รันบล็อก A แล้วกด Download CSV จากผลลัพธ์เก็บไว้
--
-- วิธีใช้: https://supabase.com/dashboard/project/hefnjozijflnhdunmewl/sql/new
-- ============================================================================


-- ---------------------------------------------------------------- บล็อก A
-- อ่านอย่างเดียว: สรุปว่าตอนนี้มีประวัติอะไรอยู่บ้าง (เก็บ CSV ไว้ก่อนลบได้จากตรงนี้)
select
  status                     as "สถานะ",
  count(*)                   as "จำนวนไฟล์",
  count(distinct customer_case) as "จำนวนเลขงาน",
  count(distinct contractor) as "จำนวนผู้รับเหมา",
  min(submitted_at)          as "ส่งครั้งแรกเมื่อ",
  max(submitted_at)          as "ส่งครั้งล่าสุดเมื่อ"
from job_form_submissions
group by status
order by status;

-- รายการเต็มทุกไฟล์ (กด Download CSV เก็บไว้ก่อนลบได้)
select
  id                as "รหัสรายการ",
  customer_case     as "เลขงาน",
  contractor        as "ผู้รับเหมา",
  branch_name       as "สาขา",
  file_name         as "ชื่อไฟล์",
  file_url          as "ลิงก์ไฟล์",
  drive_file_id     as "ที่เก็บไฟล์ใน Storage",
  status            as "สถานะ",
  submitted_at      as "วันที่ส่ง",
  reviewed_at       as "วันที่ตรวจ",
  reviewed_by       as "ผู้ตรวจ",
  admin_remark      as "หมายเหตุแอดมิน"
from job_form_submissions
order by submitted_at desc;


-- ---------------------------------------------------------------- บล็อก B
-- อ่านอย่างเดียว: เลขงานที่ "ถูกอนุมัติไปแล้ว" จึงถูกตัดบิลปิดไปด้วย
--
-- สำคัญมาก: การลบประวัติอย่างเดียวไม่พอให้ผู้รับเหมาส่งใหม่ได้
-- เพราะตอนแอดมินกดอนุมัติ ระบบจะปิดบิลของเลขงานนั้น (ใส่ค่า completed_at)
-- งานที่ถูกปิดบิลแล้วจะหายจากตาราง "ฟอร์มวางบิล" ฝั่งผู้รับเหมา เขาจึงไม่เห็นงานให้ส่งใหม่
-- ถ้าต้องการให้ส่งใหม่ได้จริง ต้องรันบล็อก D เพื่อเปิดบิลกลับมาด้วย
select
  s.customer_case                                   as "เลขงาน",
  s.contractor                                      as "ผู้รับเหมา",
  s.reviewed_at                                     as "วันที่อนุมัติ",
  count(b.id)                                       as "จำนวนแถวในตารางวางบิล",
  count(b.completed_at)                             as "แถวที่ถูกปิดบิลไปแล้ว",
  string_agg(distinct b.round_no::text, ', ')       as "อยู่ในรอบบิลที่"
from job_form_submissions s
left join billing_documents b on b.customer_case = s.customer_case
where s.status = 'approved'
group by s.customer_case, s.contractor, s.reviewed_at
order by s.reviewed_at desc;


-- ---------------------------------------------------------------- บล็อก C
-- ★ ลบจริง ★ ล้างประวัติฟอร์มที่ผู้รับเหมาส่งกลับ "ทั้งหมด"
-- รันเมื่อดูบล็อก A และ B แล้วโอเค (และเก็บ CSV ไว้แล้วถ้าต้องการ)
begin;

-- นับก่อนลบ เพื่อให้เห็นตัวเลขในผลลัพธ์
select count(*) as "กำลังจะลบทั้งหมด (แถว)" from job_form_submissions;

delete from job_form_submissions;

-- ต้องได้ 0
select count(*) as "เหลืออยู่หลังลบ (ต้องเป็น 0)" from job_form_submissions;

commit;


-- ---------------------------------------------------------------- บล็อก D
-- ★ ลบจริง (ทางเลือก แต่แนะนำให้รัน) ★
-- เปิดบิลที่ถูกปิดจากการอนุมัติกลับมา เพื่อให้ผู้รับเหมาเห็นงานและส่งฟอร์มใหม่ได้
--
-- ผลที่ได้: งานเหล่านั้นกลับไปอยู่ในตาราง "ฟอร์มวางบิล" ฝั่งผู้รับเหมาเหมือนยังไม่เคยส่ง
-- ข้อมูลอะไหล่/ราคา/รอบบิล ไม่ถูกแตะเลย แก้แค่ช่อง completed_at ให้ว่าง
--
-- ⚠ ถ้าไม่ต้องการให้งานเก่าที่ปิดบิลไปแล้วกลับมา ให้ข้ามบล็อกนี้
--   (แต่ผู้รับเหมาจะส่งฟอร์มใหม่ของงานเหล่านั้นไม่ได้)
begin;

-- ดูก่อนว่าจะเปิดกลับมากี่แถว
select count(*) as "แถวที่จะเปิดบิลกลับมา"
from billing_documents
where completed_at is not null
  and sent_to_contractor = true;

update billing_documents
set completed_at = null
where completed_at is not null
  and sent_to_contractor = true;

commit;


-- ---------------------------------------------------------------- บล็อก E
-- ตรวจหลังรัน: ต้องไม่เหลือประวัติเลย และไม่มีบิลที่ถูกปิดค้างอยู่
select
  (select count(*) from job_form_submissions)                                   as "ประวัติที่เหลือ (ต้อง 0)",
  (select count(*) from billing_documents where completed_at is not null
     and sent_to_contractor = true)                                             as "บิลที่ยังปิดอยู่ (ต้อง 0 ถ้ารันบล็อก D)",
  (select count(distinct customer_case) from billing_documents
     where sent_to_contractor = true and completed_at is null)                   as "เลขงานที่ผู้รับเหมาจะเห็นให้ส่งฟอร์ม";


-- ============================================================================
-- ยังเหลืออีก 1 อย่างที่ SQL ลบให้ไม่ได้: ไฟล์ PDF ที่ค้างอยู่ใน Storage
--
-- คำสั่งข้างบนลบแค่ "รายการ" ในฐานข้อมูล ตัวไฟล์ PDF จริงยังอยู่ในถัง Storage
-- ไม่มีอะไรเสียหาย (ไม่มีลิงก์ชี้ไปหาแล้ว) แต่ถ้าอยากล้างให้สะอาดจริง:
--
--   1. เข้า https://supabase.com/dashboard/project/hefnjozijflnhdunmewl/storage/buckets/job-form-submissions
--   2. เลือกโฟลเดอร์ทั้งหมด (แต่ละโฟลเดอร์คือ 1 เลขงาน)
--   3. กด Delete
--
-- หลังทำเสร็จทั้งหมด ให้แจ้งผู้รับเหมาว่า:
--   "เข้าแท็บฟอร์มวางบิล กดโหลด/รีเฟรช แล้วดาวน์โหลดฟอร์มใหม่ กรอกและส่งกลับอีกครั้ง"
-- ============================================================================
