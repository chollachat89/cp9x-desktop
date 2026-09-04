-- ============================================================================
-- สืบข้อมูลเลขงานเดียว — ใช้ตรวจว่าใครเกี่ยวข้อง สาขาถูกไหม และมีร่องรอยการกรอกมือหรือไม่
--
-- ไฟล์นี้ "อ่านอย่างเดียว" ไม่แก้ ไม่ลบ ไม่เพิ่มอะไรทั้งสิ้น รันซ้ำได้ปลอดภัย
--
-- ⚠ ข้อจำกัดที่ต้องรู้ก่อนอ่านผล:
--   ตาราง open_issues และ close_issues "ไม่มีคอลัมน์ผู้สร้าง" เลย
--   ระบบไม่เคยบันทึกว่าบัญชีไหนเป็นคนกดบันทึกงานเปิด/ปิด
--   จึงตอบจากฐานข้อมูลตรง ๆ ไม่ได้ว่า "ใครกรอก" — ได้แค่ร่องรอยแวดล้อมเท่านั้น
--
--   ช่องที่พอบอกตัวบุคคลได้:
--     pause_records.paused_by   = ผู้ใช้ "พิมพ์เอง" ในฟอร์มพักงาน (ไม่ได้ดึงจากบัญชีที่ล็อกอิน)
--     pause_records.resumed_by  = ดึงจากบัญชีที่ล็อกอินจริงตอนกดกลับมาทำงาน (เชื่อถือได้)
--     open_issues.contractor    = ทีมที่ถูกมอบหมาย ไม่ใช่คนกรอก
--
-- วิธีใช้: https://supabase.com/dashboard/project/hefnjozijflnhdunmewl/sql/new
--   แก้เลขงานในบรรทัด set_config ด้านล่างให้ตรงกับที่ต้องการตรวจ แล้ววางทั้งไฟล์ กด Run
-- ============================================================================

-- ตั้งเลขงานที่จะตรวจตรงนี้ที่เดียว (บล็อกอื่นอ่านค่าจากตรงนี้ทั้งหมด)
select set_config('cp9x.job', 'CM20260902-0137', false);


-- ---------------------------------------------------------------- บล็อก A
-- ข้อมูลเปิดงาน + สาขาที่กรอกไว้
select
  o.main_id                            as "เลขงาน",
  o.branch                             as "สาขาที่กรอกไว้",
  o.contractor                         as "ทีมที่ถูกมอบหมาย",
  o.service_type                        as "Service Type",
  o.service_work                        as "งานบริการ",
  o.service_issue                       as "Service Issue",
  o.contract_type                       as "ประเภทสัญญา",
  o.req_date                            as "วันที่ร้องขอ (ข้อความที่กรอก)",
  o.created_at at time zone 'Asia/Bangkok' as "วันเวลาที่บันทึกเปิดงาน",
  o.details                             as "รายละเอียดปัญหา",
  o.synced_to_sheet                     as "ซิงค์ Sheet แล้ว"
from open_issues o
where o.main_id = current_setting('cp9x.job');


-- ---------------------------------------------------------------- บล็อก B
-- เช็คสาขา: รหัสสาขาที่กรอกไว้ ตรงกับทะเบียนสาขาจริงหรือไม่
-- ถ้า "สถานะ" ขึ้นว่าไม่พบรหัสนี้ หรือชื่อไม่ตรง = มีการพิมพ์สาขาเองโดยไม่ได้เลือกจากระบบ
with j as (
  select branch from open_issues where main_id = current_setting('cp9x.job')
),
x as (
  select
    branch,
    nullif((regexp_match(branch, '^\s*(\d+)'))[1], '') as code_in_job,
    trim(regexp_replace(branch, '^\s*\d+\s*-\s*', ''))  as name_in_job
  from j
)
select
  x.branch                        as "สาขาที่กรอกในงาน",
  x.code_in_job                   as "รหัสที่แยกได้",
  b.branch_name                   as "ชื่อสาขาในทะเบียน",
  x.name_in_job                   as "ชื่อสาขาที่กรอกในงาน",
  case
    when x.code_in_job is null       then 'กรอกไม่เป็นรูปแบบ รหัส-ชื่อสาขา (น่าจะพิมพ์เอง)'
    when b.branch_code is null       then 'ไม่พบรหัสนี้ในทะเบียนสาขา (พิมพ์เองหรือรหัสผิด)'
    when b.branch_name is distinct from x.name_in_job
                                     then 'รหัสมีจริง แต่ชื่อสาขาไม่ตรงทะเบียน (ถูกแก้ข้อความเอง)'
    else 'ตรงกับทะเบียนสาขา'
  end                             as "สถานะสาขา"
from x
left join branches b on b.branch_code = x.code_in_job;


-- ---------------------------------------------------------------- บล็อก C
-- ร่องรอยว่ากรอกมือเองหรือใช้ปุ่มดูดข้อความ
-- ปุ่มดูดข้อความให้รูปแบบตายตัวเสมอ: วันที่ร้องขอ = "DD/MM/YYYY, HH:MM"
-- ถ้ารูปแบบเพี้ยนไปจากนี้ = พิมพ์เองแน่นอน
select
  o.req_date                                                as "วันที่ร้องขอที่กรอก",
  regexp_replace(o.req_date, '[0-9]', '9', 'g')             as "รูปแบบที่กรอก",
  case when o.req_date ~ '^\d{2}/\d{2}/\d{4}, \d{1,2}:\d{2}$'
       then 'รูปแบบตรงกับปุ่มดูดข้อความ'
       else 'รูปแบบไม่ตรง = พิมพ์เอง' end                     as "สรุปฝั่งเปิดงาน",
  c.fix_date                                                as "วันที่เข้าแก้ไขที่กรอก",
  case when c.fix_date is null then 'ยังไม่ปิดงาน'
       when c.fix_date ~ '^\d{1,2}-\d{1,2}-\d{4}$' then 'รูปแบบปกติ'
       else 'รูปแบบเพี้ยน = พิมพ์เอง' end                     as "สรุปฝั่งปิดงาน",
  case when o.details is null or trim(o.details) in ('','-') then 'เว้นว่าง' else 'มีข้อความ' end
                                                            as "รายละเอียดปัญหา",
  case when o.service_issue is null or trim(o.service_issue) in ('','-') then 'เว้นว่าง (ไม่ได้ดูดมา)' else 'มีค่า' end
                                                            as "Service Issue"
from open_issues o
left join close_issues c on c.job_id = o.main_id
where o.main_id = current_setting('cp9x.job');


-- ---------------------------------------------------------------- บล็อก D
-- ข้อมูลปิดงาน (อาจมีหลายแถวถ้าปิดหลายเลขทรัพย์สิน)
select
  c.job_id                              as "เลขงาน",
  c.asset_id                            as "เลขทรัพย์สิน",
  length(coalesce(c.asset_id,''))       as "จำนวนหลักเลขทรัพย์สิน",
  c.branch                              as "สาขาตอนปิดงาน",
  c.fix_date                            as "วันที่เข้าแก้ไข",
  c.parts                               as "รายการอะไหล่ที่เปลี่ยน",
  c.action_taken                        as "ดำเนินการแก้ไข",
  c.created_at at time zone 'Asia/Bangkok' as "วันเวลาที่บันทึกปิดงาน",
  c.photo_form_link                     as "ลิงก์แนบรูป"
from close_issues c
where c.job_id = current_setting('cp9x.job')
order by c.created_at;


-- ---------------------------------------------------------------- บล็อก E
-- ประวัติพักงาน — ช่องเดียวในระบบที่พอระบุตัวบุคคลได้
select
  p.main_id                                  as "เลขงาน",
  p.paused_by                                as "ผู้พักงาน (พิมพ์เอง เชื่อถือได้ต่ำ)",
  p.resumed_by                               as "ผู้กดกลับมาทำงาน (จากบัญชีที่ล็อกอิน เชื่อถือได้)",
  p.status                                   as "สถานะ",
  p.reason                                   as "เหตุผลที่พัก",
  p.cause                                    as "สาเหตุที่ตรวจพบ",
  p.requested_item                           as "รายการที่ขออนุมัติ",
  p.note                                     as "หมายเหตุ",
  p.paused_at  at time zone 'Asia/Bangkok'   as "เวลาที่พัก",
  p.resumed_at at time zone 'Asia/Bangkok'   as "เวลาที่กลับมาทำ"
from pause_records p
where p.main_id = current_setting('cp9x.job')
order by p.paused_at;


-- ---------------------------------------------------------------- บล็อก F
-- แถวในตารางวางบิล + ดูว่ามีอะไหล่ที่กรอกเองหรือไม่
-- อะไหล่รหัสขึ้นต้นด้วย NP = แอดมินพิมพ์รายละเอียดและราคาเองทั้งหมด (ไม่ได้มาจากตาราง parts)
-- อะไหล่รหัสอื่นที่หาไม่เจอในตาราง parts = พิมพ์รหัสเองแบบไม่มีในระบบ
select
  b.customer_case                       as "เลขงาน",
  b.asset_id                            as "เลขทรัพย์สิน",
  b.part_code                           as "รหัสอะไหล่",
  b.part_detail                         as "รายละเอียดอะไหล่",
  b.qty                                 as "จำนวน",
  b.unit                                as "หน่วย",
  b.unit_price                          as "ราคา CJ",
  b.unit_price_contractor               as "ราคาผู้รับเหมา",
  b.billing_type                        as "ประเภทเก็บเงิน",
  b.responsible                         as "ผู้รับผิดชอบ (ช่องข้อความ)",
  b.contractor                          as "ผู้รับเหมา",
  b.round_no                            as "รอบบิลที่",
  b.sent_to_contractor                  as "ส่งบิลแล้ว",
  case
    when b.part_code is null or trim(b.part_code) = '' then 'ยังไม่กรอกรหัสอะไหล่'
    when b.part_code ~* '^NP'                          then 'อะไหล่นอกระบบ — กรอกรายละเอียด/ราคาเองทั้งหมด'
    when pa.code_cj is null                            then 'รหัสนี้ไม่มีในตารางอะไหล่ — พิมพ์เอง'
    when pa.unit_price is distinct from b.unit_price   then 'ราคา CJ ถูกแก้เอง (ไม่ตรงราคาตั้งต้น ' || pa.unit_price || ')'
    else 'ตรงกับตารางอะไหล่'
  end                                   as "ร่องรอยการกรอกมือ",
  b.created_at at time zone 'Asia/Bangkok' as "วันเวลาที่สร้างแถวบิล"
from billing_documents b
left join parts pa on pa.code_cj = b.part_code
where b.customer_case = current_setting('cp9x.job')
order by b.created_at;


-- ---------------------------------------------------------------- บล็อก G
-- ไฟล์ฟอร์มที่ผู้รับเหมาส่งกลับ (ถ้ามี) — บอกได้ว่าบัญชีผู้รับเหมาไหนเป็นคนส่ง
select
  s.customer_case                            as "เลขงาน",
  s.contractor                               as "ผู้รับเหมาที่ส่งไฟล์",
  s.file_name                                as "ชื่อไฟล์",
  s.status                                   as "สถานะ",
  s.reviewed_by                              as "ผู้ตรวจ",
  s.admin_remark                             as "หมายเหตุแอดมิน",
  s.submitted_at at time zone 'Asia/Bangkok' as "เวลาที่ส่ง",
  s.reviewed_at  at time zone 'Asia/Bangkok' as "เวลาที่ตรวจ"
from job_form_submissions s
where s.customer_case = current_setting('cp9x.job')
order by s.submitted_at;


-- ---------------------------------------------------------------- บล็อก H
-- เทียบกับงานอื่นที่บันทึกในช่วงเวลาไล่เลี่ยกัน (ก่อน/หลัง 30 นาที)
-- ถ้าเห็นงานอื่นถูกบันทึกติด ๆ กันด้วยผู้รับเหมาคนเดียวกัน มักเป็นการนั่งกรอกรวดเดียวโดยคนเดียวกัน
select
  o.main_id                                as "เลขงาน",
  o.branch                                 as "สาขา",
  o.contractor                             as "ทีมที่มอบหมาย",
  o.created_at at time zone 'Asia/Bangkok' as "เวลาที่บันทึก",
  case when o.main_id = current_setting('cp9x.job') then '<<< งานที่กำลังตรวจ' else '' end as "หมายเหตุ"
from open_issues o
where o.created_at between
      (select created_at - interval '30 minutes' from open_issues where main_id = current_setting('cp9x.job'))
  and (select created_at + interval '30 minutes' from open_issues where main_id = current_setting('cp9x.job'))
order by o.created_at;
