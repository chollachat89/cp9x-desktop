-- ==========================================================
-- v1.0.57 — แยกสิทธิ์ "ผู้ตรวจสอบ" ออกจากแอดมิน
--
-- ไฟล์นี้ทำ 3 อย่าง:
--   บล็อก A = เพิ่มคอลัมน์ is_checker ในตาราง contractors
--   บล็อก B = เพิ่มคอลัมน์เก็บประวัติการตรวจชั้นที่ 2 ในตาราง job_form_submissions
--   บล็อก C = ตั้งธงผู้ตรวจสอบให้ 3 บัญชี (Superbaipo, Admin, Phutphum)
--
-- ⚠ ต้องรันไฟล์นี้ "ก่อน" deploy Edge Function เสมอ
--    เพราะโค้ดใหม่จะอ่านคอลัมน์ is_checker ถ้ายังไม่มีจะเข้าสู่ระบบไม่ได้
--
-- วิธีใช้: วางทั้งไฟล์ กด Run (รันซ้ำได้ ไม่เกิดข้อมูลซ้ำ)
--   https://supabase.com/dashboard/project/hefnjozijflnhdunmewl/sql/new
-- ==========================================================


-- === บล็อก A: ธงผู้ตรวจสอบ ===
--
-- ทำเป็น "ธงแยก" ไม่ใช่เปลี่ยน role เป็น 'checker'
-- เพราะผู้ตรวจสอบต้องใช้งานทุกเมนูได้เหมือนแอดมินอยู่แล้ว
-- ถ้าไปเปลี่ยน role บัญชีนั้นจะหลุดสิทธิ์แอดมินทั้งหมดทันที (เปิดงาน/ปิดงาน/วางบิล ใช้ไม่ได้เลย)
alter table contractors add column if not exists is_checker boolean not null default false;

comment on column contractors.is_checker is
  'true = เป็นผู้ตรวจสอบ กดสิ้นสุดงาน/ตีกลับในขั้นที่ 2 ได้ · แอดมินทั่วไปกดขั้นนี้ไม่ได้';


-- === บล็อก B: ประวัติการตรวจชั้นที่ 2 ===
alter table job_form_submissions add column if not exists checker_by       text;
alter table job_form_submissions add column if not exists checker_at       timestamptz;
alter table job_form_submissions add column if not exists checker_decision text;
alter table job_form_submissions add column if not exists checker_remark   text;

comment on column job_form_submissions.checker_by       is 'ชื่อผู้ตรวจสอบที่ดำเนินการขั้นที่ 2';
comment on column job_form_submissions.checker_at       is 'เวลาที่ผู้ตรวจสอบดำเนินการ';
comment on column job_form_submissions.checker_decision is 'finished = สิ้นสุดงาน (ตัดบิล) · rejected = ตีกลับ';
comment on column job_form_submissions.checker_remark   is 'เหตุผลที่ผู้ตรวจสอบตีกลับ';


-- === บล็อก C: ตั้งธงผู้ตรวจสอบ 3 บัญชี ===
--
-- ⚠ ชื่อผู้ใช้ต้องตรงตัวพิมพ์ใหญ่-เล็กด้วย จึงเทียบแบบไม่สนตัวพิมพ์ (lower) ไว้กันพลาด
update contractors
set is_checker = true
where lower(username) in ('superbaipo', 'admin', 'phutphum');


-- === ตรวจผล ===

-- 1) ต้องเห็น 3 บัญชี และ is_checker ต้องเป็น true ทั้งหมด
--    ถ้าได้ไม่ครบ 3 แถว แปลว่าชื่อผู้ใช้ในระบบสะกดไม่ตรงกับที่ระบุไว้
select
  username     as "ชื่อผู้ใช้",
  display_name as "ชื่อที่แสดง",
  role         as "สิทธิ์",
  is_checker   as "เป็นผู้ตรวจสอบ"
from contractors
where is_checker = true
order by username;

-- 2) เช็คว่าครบ 3 คนไหม (ถ้าไม่ครบจะบอกว่าขาดใคร)
with ต้องมี(u) as (values ('superbaipo'), ('admin'), ('phutphum'))
select
  w.u                                                   as "ชื่อผู้ใช้ที่ระบุไว้",
  case when c.id is null then '❌ ไม่พบบัญชีนี้ในระบบ'
       when c.is_checker then '✅ ตั้งธงแล้ว'
       else '⚠ พบบัญชีแต่ยังไม่ได้ตั้งธง' end          as "สถานะ",
  c.username                                            as "ชื่อจริงในระบบ"
from ต้องมี w
left join contractors c on lower(c.username) = w.u;

-- 3) รายชื่อบัญชีทั้งหมด เผื่อชื่อสะกดไม่ตรงจะได้เห็นว่าของจริงชื่ออะไร
select username as "ชื่อผู้ใช้", display_name as "ชื่อที่แสดง",
       role as "สิทธิ์", is_checker as "ผู้ตรวจสอบ"
from contractors
order by role, username;


-- ==========================================================
-- ถ้าผลข้อ 2 ขึ้น "ไม่พบบัญชีนี้ในระบบ"
--
-- ให้ดูรายชื่อจริงจากผลข้อ 3 แล้วรันคำสั่งนี้โดยเปลี่ยนชื่อให้ตรง:
--   update contractors set is_checker = true where username = 'ชื่อจริงที่เห็น';
--
-- ถ้าอยากถอดสิทธิ์ผู้ตรวจสอบออกจากใคร:
--   update contractors set is_checker = false where username = 'ชื่อผู้ใช้';
-- ==========================================================
