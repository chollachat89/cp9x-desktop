-- ==========================================================
-- v1.0.61 — สลับลำดับการอนุมัติ + รีเซ็ตสถานะอนุมัติทุกงาน
--
-- ลำดับใหม่:
--   ขั้นที่ 1  ผู้ตรวจสอบ 3 คน (Superbaipo, Admin, Phutphum) กดอนุมัติ/ตีกลับ
--              กดคนเดียวใน 3 คนก็ผ่าน
--   ขั้นที่ 2  TUCK CR กดอนุมัติขั้นสุดท้าย/ตีกลับ — ขั้นนี้เท่านั้นที่ "ตัดบิล" จริง
--              TUCK CR กดขั้นที่ 1 ไม่ได้ ต้องรอ 3 คนกดก่อนเสมอ
--
-- ⚠⚠ ไฟล์นี้มีคำสั่งที่ "ลบสถานะการอนุมัติทั้งหมด" และ "ยกเลิกการตัดบิล"
--     ห้ามวางทั้งไฟล์แล้วกด Run รวดเดียว
--     ให้รันทีละบล็อกตามลำดับ A → B → C → D → E → F และอ่านผลทุกบล็อก
--
-- ⚠ ต้องรันไฟล์นี้ "ก่อน" deploy Edge Function เสมอ
--    เพราะโค้ดใหม่อ่านคอลัมน์ is_final_approver ถ้ายังไม่มีจะเข้าสู่ระบบไม่ได้
--
-- ที่รัน: https://supabase.com/dashboard/project/hefnjozijflnhdunmewl/sql/new
-- ==========================================================


-- ==========================================================
-- บล็อก A — เพิ่มคอลัมน์สิทธิ์ผู้อนุมัติขั้นสุดท้าย  (ปลอดภัย รันซ้ำได้)
-- ==========================================================

alter table contractors add column if not exists is_final_approver boolean not null default false;

comment on column contractors.is_final_approver is
  'true = TUCK CR ผู้อนุมัติขั้นสุดท้าย กดตัดบิล/ตีกลับในขั้นที่ 2 ได้ · ห้ามตั้งคู่กับ is_checker ในบัญชีเดียวกัน';


-- ==========================================================
-- บล็อก B — หา "บัญชี TUCK CR" ให้เจอก่อน  (อ่านอย่างเดียว ไม่แก้อะไร)
--
-- รันบล็อกนี้แล้วดูผลก่อน ว่าบัญชี TUCK CR ในระบบชื่อผู้ใช้ว่าอะไรจริง ๆ
-- แล้วค่อยเอาชื่อนั้นไปใส่ในบล็อก C
-- ==========================================================

-- B1) เดาให้ก่อน: บัญชีที่ชื่อผู้ใช้หรือชื่อที่แสดงมีคำว่า tuck
select id, username as "ชื่อผู้ใช้", display_name as "ชื่อที่แสดง",
       role as "สิทธิ์", is_checker as "ผู้ตรวจสอบ", is_final_approver as "ผู้อนุมัติสุดท้าย"
from contractors
where lower(coalesce(username, '')) like '%tuck%'
   or lower(coalesce(display_name, '')) like '%tuck%'
order by username;

-- B2) ถ้า B1 ไม่เจอ ให้ดูรายชื่อทั้งหมดแล้วหาเอง
select username as "ชื่อผู้ใช้", display_name as "ชื่อที่แสดง",
       role as "สิทธิ์", is_checker as "ผู้ตรวจสอบ", is_final_approver as "ผู้อนุมัติสุดท้าย"
from contractors
order by role, username;


-- ==========================================================
-- บล็อก C — ตั้งสิทธิ์ให้ตรงกับลำดับใหม่
--
-- ⚠ ก่อนรัน: แก้ค่าในบรรทัด "ชื่อผู้ใช้ของ TUCK CR" ด้านล่างให้ตรงกับที่เห็นในบล็อก B
--    ถ้าชื่อในระบบคือ tuckcr ก็ใส่ 'tuckcr' · ถ้าคือ TUCK_CR ก็ใส่ 'tuck_cr'
--    (เทียบแบบไม่สนตัวพิมพ์ใหญ่-เล็กให้แล้ว)
-- ==========================================================

-- C1) ตั้ง TUCK CR เป็นผู้อนุมัติขั้นสุดท้าย และถอดธงผู้ตรวจสอบออกจากบัญชีนี้
--     (ถอดออกเพราะคนเดียวห้ามกดผ่านทั้ง 2 ขั้น ไม่งั้นการตรวจ 2 ชั้นไม่เหลือความหมาย)
update contractors
set is_final_approver = true,
    is_checker        = false
where lower(username) in ('tuckcr');        -- ⚠ ชื่อผู้ใช้ของ TUCK CR — แก้ตรงนี้ให้ตรงกับผลบล็อก B

-- C2) ผู้ตรวจสอบขั้นที่ 1 ต้องเป็น 3 คนนี้เท่านั้น และต้องไม่มีสิทธิ์ขั้นสุดท้าย
update contractors
set is_checker        = true,
    is_final_approver = false
where lower(username) in ('superbaipo', 'admin', 'phutphum');

-- C3) ตรวจผล — ต้องได้ 3 แถวที่เป็นผู้ตรวจสอบ และ 1 แถวที่เป็นผู้อนุมัติสุดท้าย
--     ถ้า "ผู้อนุมัติสุดท้าย" ไม่มีแถวเลย แปลว่าชื่อผู้ใช้ใน C1 ยังไม่ตรง ให้กลับไปดูบล็อก B
select username     as "ชื่อผู้ใช้",
       display_name as "ชื่อที่แสดง",
       case when is_final_approver then 'ขั้นสุดท้าย (TUCK CR)'
            when is_checker        then 'ขั้นที่ 1 (ผู้ตรวจสอบ)'
            else '-' end                        as "ทำหน้าที่ขั้นไหน"
from contractors
where is_checker or is_final_approver
order by is_final_approver desc, username;

-- C4) กันพลาด — ต้องไม่มีบัญชีไหนถือ 2 ธงพร้อมกัน (ต้องได้ 0 แถว)
select username as "บัญชีที่ถือ 2 ธงพร้อมกัน (ผิด ต้องแก้)"
from contractors
where is_checker and is_final_approver;


-- ==========================================================
-- บล็อก D — สำรองข้อมูลก่อนรีเซ็ต  ⚠ ห้ามข้าม
--
-- บล็อก E ลบสถานะการอนุมัติทั้งหมดและยกเลิกการตัดบิล กู้คืนเองไม่ได้
-- บล็อกนี้จะก๊อปสถานะปัจจุบันเก็บไว้เป็นตารางสำรอง เผื่อต้องย้อนกลับ
-- ==========================================================

-- D1) สำรองสถานะการอนุมัติของทุกไฟล์ที่ผู้รับเหมาส่งกลับ
create table if not exists backup_v1_0_61_submissions as
select id, status, admin_remark, reviewed_at, reviewed_by,
       checker_by, checker_at, checker_decision, checker_remark,
       finished_at, finished_by, now() as backed_up_at
from job_form_submissions;

-- D2) สำรองรายการบิลที่ถูกตัดไปแล้ว (เฉพาะที่จะโดนยกเลิกการตัดในบล็อก E)
create table if not exists backup_v1_0_61_billing_completed as
select id, customer_case, round_no, completed_at, now() as backed_up_at
from billing_documents
where completed_at is not null;

-- D3) ดูก่อนว่าจะกระทบกี่แถว  (อ่านอย่างเดียว — จดตัวเลขไว้เทียบหลังรีเซ็ต)
select
  (select count(*) from job_form_submissions)                                  as "ไฟล์ทั้งหมด",
  (select count(*) from job_form_submissions where status <> 'pending')        as "เคยกดขั้นที่ 1 ไปแล้ว",
  (select count(*) from job_form_submissions where finished_at is not null)    as "เคยอนุมัติขั้นสุดท้ายแล้ว",
  (select count(*) from billing_documents  where completed_at is not null)     as "แถวบิลที่ถูกตัดไปแล้ว",
  (select count(*) from backup_v1_0_61_submissions)                            as "สำรองไฟล์ไว้",
  (select count(*) from backup_v1_0_61_billing_completed)                      as "สำรองบิลที่ตัดไว้";


-- ==========================================================
-- บล็อก E — ⚠⚠ รีเซ็ตสถานะอนุมัติ "ทุกงาน" ให้เริ่มกดใหม่ทั้งหมด ⚠⚠
--
-- สิ่งที่จะเกิดขึ้นจริง หลังรันบล็อกนี้:
--   1. ไฟล์ที่ผู้รับเหมาส่งกลับ "ทุกไฟล์" กลับไปเป็น "รอผู้ตรวจสอบ (ขั้นที่ 1)"
--      ชื่อคนที่เคยกดอนุมัติ/สิ้นสุดงาน และหมายเหตุเดิม จะถูกล้างทิ้งทั้งหมด
--   2. บิลที่ "เคยถูกตัด" จากการกดสิ้นสุดงาน จะถูกยกเลิกการตัด
--      งานพวกนั้นจะออกจากเมนู "งานที่เสร็จสิ้น" กลับเข้าตารางวางบิลของผู้รับเหมาอีกครั้ง
--      และจะกลับไปเป็น "ตัดบิลแล้ว" ก็ต่อเมื่อมีคนกดครบ 2 ขั้นใหม่
--   3. ไฟล์ที่ผู้รับเหมาส่งมา ไม่ถูกลบ ยังอยู่ครบทุกไฟล์
--
-- ต้องรันบล็อก D ให้ผ่านก่อนเสมอ ไม่งั้นย้อนกลับไม่ได้
-- ==========================================================

-- E1) ยกเลิกการตัดบิล เฉพาะเลขงานที่เคยผ่านขั้นสิ้นสุดงานของระบบเดิม
--     (ไม่แตะบิลที่ completed_at มาจากทางอื่น ถ้าจะมี)
update billing_documents b
set completed_at = null
where b.completed_at is not null
  and exists (
    select 1 from job_form_submissions s
    where s.customer_case = b.customer_case
      and s.finished_at is not null
  );

-- E2) รีเซ็ตสถานะการอนุมัติของทุกไฟล์ กลับไปเป็น "รอผู้ตรวจสอบ"
update job_form_submissions
set status           = 'pending',
    admin_remark     = null,
    reviewed_at      = null,
    reviewed_by      = null,
    checker_by       = null,
    checker_at       = null,
    checker_decision = null,
    checker_remark   = null,
    finished_at      = null,
    finished_by      = null,
    is_read          = false;


-- ==========================================================
-- บล็อก F — ตรวจผลหลังรีเซ็ต  (อ่านอย่างเดียว)
-- ==========================================================

-- F1) ทุกตัวเลขในแถว "ต้องเป็น 0" ต้องได้ 0 ทั้งหมด
select
  (select count(*) from job_form_submissions)                               as "ไฟล์ทั้งหมด (ต้องเท่าเดิม)",
  (select count(*) from job_form_submissions where status <> 'pending')     as "ยังค้างสถานะเก่า (ต้องเป็น 0)",
  (select count(*) from job_form_submissions where reviewed_by is not null) as "ยังค้างชื่อขั้นที่ 1 (ต้องเป็น 0)",
  (select count(*) from job_form_submissions where finished_at is not null) as "ยังค้างขั้นสุดท้าย (ต้องเป็น 0)";

-- F2) เทียบจำนวนบิลที่ยกเลิกการตัดไป กับที่สำรองไว้
select
  (select count(*) from backup_v1_0_61_billing_completed)                 as "บิลที่เคยถูกตัด (ก่อนรีเซ็ต)",
  (select count(*) from billing_documents where completed_at is not null) as "บิลที่ยังถูกตัดอยู่ (หลังรีเซ็ต)";


-- ==========================================================
-- ถ้าต้องย้อนกลับ (ใช้เฉพาะตอนจำเป็นจริง ๆ)
--
-- คืนสถานะการอนุมัติ:
--   update job_form_submissions s
--   set status = b.status, admin_remark = b.admin_remark,
--       reviewed_at = b.reviewed_at, reviewed_by = b.reviewed_by,
--       checker_by = b.checker_by, checker_at = b.checker_at,
--       checker_decision = b.checker_decision, checker_remark = b.checker_remark,
--       finished_at = b.finished_at, finished_by = b.finished_by
--   from backup_v1_0_61_submissions b
--   where b.id = s.id;
--
-- คืนการตัดบิล:
--   update billing_documents d
--   set completed_at = b.completed_at
--   from backup_v1_0_61_billing_completed b
--   where b.id = d.id;
--
-- ตารางสำรองทั้ง 2 ตัวเก็บไว้ได้ ไม่กระทบการทำงานของระบบ
-- จะลบทิ้งเมื่อมั่นใจแล้วก็ได้:
--   drop table backup_v1_0_61_submissions;
--   drop table backup_v1_0_61_billing_completed;
-- ==========================================================
