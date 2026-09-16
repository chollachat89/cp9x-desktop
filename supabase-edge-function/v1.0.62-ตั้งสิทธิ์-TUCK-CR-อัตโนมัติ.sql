-- ==========================================================
-- v1.0.62 — ตั้งสิทธิ์ TUCK CR ให้อัตโนมัติ (ไม่ต้องแก้ชื่อผู้ใช้เอง)
--
-- ใช้ไฟล์นี้เมื่อ TUCK CR กด "อนุมัติขั้นสุดท้าย" ไม่ได้
-- ไฟล์นี้ปลอดภัย — ไม่ลบ ไม่แก้ข้อมูลงาน แตะแค่ตารางผู้ใช้ (contractors) เท่านั้น
-- รันซ้ำได้ไม่เสียหาย · วางทั้งไฟล์แล้วกด Run ได้เลย
--
-- ที่รัน: https://supabase.com/dashboard/project/hefnjozijflnhdunmewl/sql/new
-- ==========================================================


-- === 1) มีคอลัมน์สิทธิ์ครบทั้ง 2 ตัวแน่ ๆ ===
alter table contractors add column if not exists is_checker        boolean not null default false;
alter table contractors add column if not exists is_final_approver boolean not null default false;


-- === 1b) คอลัมน์เก็บประวัติการตรวจ ต้องมีครบด้วย ===
--
-- ถ้าคอลัมน์พวกนี้ขาด ปุ่ม "ตีกลับ" ของขั้นสุดท้ายจะบันทึกไม่ผ่านทั้งคำสั่ง = ตีกลับไม่ได้เลย
-- (เดิมอยู่ในไฟล์ของ v1.0.57 ซึ่งอาจยังไม่ได้รัน จึงใส่ซ้ำไว้ตรงนี้ให้ครบในไฟล์เดียว)
-- คำสั่งเป็นแบบ if not exists ทั้งหมด รันซ้ำไม่มีผลเสีย
alter table job_form_submissions add column if not exists checker_by       text;
alter table job_form_submissions add column if not exists checker_at       timestamptz;
alter table job_form_submissions add column if not exists checker_decision text;
alter table job_form_submissions add column if not exists checker_remark   text;
alter table job_form_submissions add column if not exists finished_at      timestamptz;
alter table job_form_submissions add column if not exists finished_by      text;


-- === 2) ตั้ง TUCK CR ให้อัตโนมัติ ===
--
-- หาจากชื่อผู้ใช้หรือชื่อที่แสดง โดยตัดช่องว่าง/ขีด/จุด ออกก่อนเทียบ
-- จึงเจอทุกแบบ: "TUCK CR" · "tuck cr" · "TUCK_CR" · "tuck-cr" · "tuckcr" · "TUCK"
--
-- และถอดธงผู้ตรวจสอบออกจากบัญชีนี้ด้วย เพราะคนเดียวห้ามกดผ่านทั้ง 2 ขั้น
update contractors
set is_final_approver = true,
    is_checker        = false
where translate(lower(coalesce(username, '')),     ' ._-', '') like '%tuckcr%'
   or translate(lower(coalesce(display_name, '')), ' ._-', '') like '%tuckcr%'
   or translate(lower(coalesce(username, '')),     ' ._-', '') = 'tuck'
   or translate(lower(coalesce(display_name, '')), ' ._-', '') = 'tuck';


-- === 3) ผู้ตรวจสอบขั้นที่ 1 ต้องเป็น 3 คนนี้ และต้องไม่มีสิทธิ์ขั้นสุดท้าย ===
update contractors
set is_checker        = true,
    is_final_approver = false
where lower(username) in ('superbaipo', 'admin', 'phutphum');


-- ==========================================================
-- ตรวจผล
-- ==========================================================

-- A) ต้องเห็น 3 แถวเป็น "ขั้นที่ 1" และ 1 แถวเป็น "ขั้นสุดท้าย"
select username     as "ชื่อผู้ใช้",
       display_name as "ชื่อที่แสดง",
       role         as "สิทธิ์",
       case when is_final_approver then 'ขั้นสุดท้าย (TUCK CR)'
            when is_checker        then 'ขั้นที่ 1 (ผู้ตรวจสอบ)'
            else '-' end            as "ทำหน้าที่ขั้นไหน"
from contractors
where is_checker or is_final_approver
order by is_final_approver desc, username;

-- B) ถ้า A ไม่มีแถว "ขั้นสุดท้าย" เลย แปลว่าชื่อบัญชีไม่มีคำว่า tuck อยู่จริง
--    ให้ดูรายชื่อทั้งหมดจากตรงนี้ หาบัญชีที่ใช่ แล้วตั้งเองด้วยคำสั่งใต้ตาราง
select username as "ชื่อผู้ใช้", display_name as "ชื่อที่แสดง",
       role as "สิทธิ์", is_checker as "ขั้นที่ 1", is_final_approver as "ขั้นสุดท้าย"
from contractors
order by role, username;

--   ตั้งเอง (เปลี่ยน 'ชื่อผู้ใช้จริง' ให้ตรงกับที่เห็นในตาราง B):
--     update contractors
--     set is_final_approver = true, is_checker = false
--     where username = 'ชื่อผู้ใช้จริง';

-- C) กันพลาด — ต้องไม่มีบัญชีไหนถือ 2 ธงพร้อมกัน (ต้องได้ 0 แถว)
select username as "บัญชีที่ถือ 2 ธงพร้อมกัน (ผิด ต้องแก้)"
from contractors
where is_checker and is_final_approver;

-- D) ดูว่าตอนนี้งานค้างอยู่ขั้นไหนบ้าง
--    ถ้า "รอ TUCK CR" เป็น 0 แสดงว่า TUCK CR ไม่เห็นปุ่มเพราะยังไม่มีงานถึงคิว
--    ไม่ใช่เพราะสิทธิ์ผิด — ต้องให้ผู้ตรวจสอบกดอนุมัติขั้นที่ 1 ก่อน
select
  count(*) filter (where status = 'pending')                          as "รอขั้นที่ 1 (ผู้ตรวจสอบ)",
  count(*) filter (where status = 'approved' and finished_at is null) as "รอ TUCK CR (ขั้นสุดท้าย)",
  count(*) filter (where finished_at is not null)                     as "อนุมัติสุดท้ายแล้ว",
  count(*) filter (where status = 'rejected')                         as "ตีกลับ",
  count(*)                                                            as "ไฟล์ทั้งหมด"
from job_form_submissions;
