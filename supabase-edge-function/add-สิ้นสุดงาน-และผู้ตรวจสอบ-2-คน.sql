-- ============================================================================
-- v1.0.56 — เพิ่มขั้น "สิ้นสุดงาน" + ผู้ตรวจสอบ 2 คนใหม่
--
-- ไฟล์นี้ทำ 2 อย่าง:
--   บล็อก A = เพิ่มคอลัมน์ finished_at / finished_by ในตาราง job_form_submissions
--   บล็อก B = เพิ่มผู้ใช้ 2 คน (Phutphum, Superbaipo) สิทธิ์แอดมินเต็ม
--
-- ⚠ ต้องรันไฟล์นี้ "ก่อน" deploy Edge Function
--    เพราะโค้ดใหม่จะอ่าน/เขียนคอลัมน์ finished_at ถ้ายังไม่มีคอลัมน์จะพัง
--
-- วิธีใช้: https://supabase.com/dashboard/project/hefnjozijflnhdunmewl/sql/new
--          วางทั้งไฟล์ กด Run (รันซ้ำได้ปลอดภัย ไม่เกิดข้อมูลซ้ำ)
-- ============================================================================


-- ---------------------------------------------------------------- บล็อก A
-- เพิ่มคอลัมน์เก็บ "ใครกดสิ้นสุดงาน และกดเมื่อไหร่"
--
-- ทำไมต้องแยกจาก reviewed_by/reviewed_at: ตอนนี้มีการตรวจ 2 ชั้น
--   ชั้นที่ 1 อนุมัติเอกสาร  -> เก็บที่ reviewed_by / reviewed_at
--   ชั้นที่ 2 กดสิ้นสุดงาน   -> เก็บที่ finished_by / finished_at  (ขั้นนี้คือขั้นที่ตัดบิลจริง)
-- แยกช่องกันไว้จึงตรวจย้อนหลังได้ว่าใครทำขั้นไหน ไม่ทับกัน
alter table job_form_submissions add column if not exists finished_at  timestamptz;
alter table job_form_submissions add column if not exists finished_by  text;

comment on column job_form_submissions.finished_at is 'เวลาที่กดปุ่มสิ้นสุดงาน (ขั้นที่ตัดบิลจริง) ว่าง = ยังไม่สิ้นสุด';
comment on column job_form_submissions.finished_by is 'ชื่อผู้ที่กดปุ่มสิ้นสุดงาน';

-- ดัชนีสำหรับกรอง "อนุมัติแล้วแต่ยังไม่สิ้นสุด" ซึ่งเป็นกองงานหลักของผู้ตรวจสอบ
create index if not exists job_form_submissions_finished_idx
  on job_form_submissions (finished_at);


-- ---------------------------------------------------------------- บล็อก B
-- เพิ่มผู้ใช้ 2 คน สิทธิ์แอดมินเต็ม (เห็นทุกเมนูเหมือนแอดมินเดิมทุกอย่าง)
--
--   1. username: Phutphum    รหัสผ่าน 1234
--   2. username: Superbaipo  รหัสผ่าน 1234
--
-- รหัสผ่านไม่ได้เก็บเป็นข้อความตรง ๆ ระบบเก็บเป็นค่า hash แบบ SHA-256 ของ (SALT + รหัสผ่าน)
-- ซึ่งเป็นสูตรเดียวกับฟังก์ชัน hashPassword() ใน index.ts เป๊ะ ๆ
-- ค่า hash ของรหัสผ่าน "1234" คือ:
--   a0c664768c7aadf3b6c8c19633694ee181aa5a125fafbc5d91d7695c502ff2a6
-- (ค่าเดียวกับที่ใช้ตอนเพิ่มผู้ใช้ contractor11 ซึ่งล็อกอินได้จริงแล้ว)
--
-- ⚠ รหัสผ่าน "1234" เดาง่ายมาก และคนที่ใช้รหัสนี้มีสิทธิ์แอดมินเต็ม ตัดบิลได้ ลบข้อมูลได้
--    แนะนำให้เปลี่ยนเป็นรหัสที่ยาวและเดายากหลังจากทั้งสองคนล็อกอินครั้งแรกเรียบร้อยแล้ว
--
-- ชื่อที่แสดง (display_name) จะถูกบันทึกลงช่อง "ผู้อนุมัติ" และ "ผู้สิ้นสุดงาน" ในตาราง
-- จึงตั้งเป็นชื่อที่อ่านแล้วรู้ว่าใคร ไม่ใช่ username ดิบ

insert into contractors (username, password_hash, display_name, role)
select 'Phutphum',
       'a0c664768c7aadf3b6c8c19633694ee181aa5a125fafbc5d91d7695c502ff2a6',
       'Phutphum',
       'admin'
where not exists (select 1 from contractors where username = 'Phutphum');

insert into contractors (username, password_hash, display_name, role)
select 'Superbaipo',
       'a0c664768c7aadf3b6c8c19633694ee181aa5a125fafbc5d91d7695c502ff2a6',
       'Superbaipo',
       'admin'
where not exists (select 1 from contractors where username = 'Superbaipo');


-- ---------------------------------------------------------------- บล็อก C
-- ตรวจหลังรัน

-- 1) คอลัมน์ใหม่ต้องมีครบ 2 ช่อง
select column_name as "คอลัมน์", data_type as "ชนิดข้อมูล"
from information_schema.columns
where table_name = 'job_form_submissions'
  and column_name in ('finished_at', 'finished_by')
order by column_name;

-- 2) ผู้ใช้ใหม่ต้องมี 2 คน และ role ต้องเป็น admin
select id       as "รหัส",
       username as "ชื่อผู้ใช้",
       display_name as "ชื่อที่แสดง",
       role     as "สิทธิ์"
from contractors
where username in ('Phutphum', 'Superbaipo')
order by username;

-- 3) ดูกองงานที่รอ "สิ้นสุดงาน" ตอนนี้ (อนุมัติแล้วแต่ยังไม่มีใครกดสิ้นสุด)
select customer_case as "เลขงาน",
       contractor    as "ผู้รับเหมา",
       reviewed_by   as "ผู้อนุมัติ",
       reviewed_at   as "อนุมัติเมื่อ"
from job_form_submissions
where status = 'approved' and finished_at is null
order by reviewed_at;


-- ============================================================================
-- หมายเหตุสำคัญเรื่องงานเก่าที่อนุมัติไปแล้ว
--
-- งานที่ "อนุมัติไปแล้วก่อนอัปเดตนี้" จะถูกตัดบิลไปเรียบร้อยตั้งแต่ตอนอนุมัติ (พฤติกรรมเดิม)
-- แต่ในตารางจะขึ้นว่ายังไม่สิ้นสุดงาน เพราะตอนนั้นยังไม่มีปุ่มนี้
--
-- ถ้าอยากทำเครื่องหมายงานเก่าเหล่านั้นว่าสิ้นสุดไปแล้ว (จะได้ไม่ปนกับกองงานใหม่ที่ต้องกดจริง)
-- ให้รันคำสั่งข้างล่างนี้ — จะไม่ไปแตะบิลใด ๆ ทั้งสิ้น แค่เติมชื่อกับเวลาเท่านั้น
--
--   update job_form_submissions
--   set finished_at = reviewed_at,
--       finished_by = coalesce(reviewed_by, 'ระบบ (อนุมัติก่อน v1.0.56)')
--   where status = 'approved' and finished_at is null;
--
-- ถ้าไม่รัน งานเก่าจะยังโชว์ปุ่ม "สิ้นสุดงาน" อยู่ — กดได้ ไม่มีอันตราย
-- เพราะบิลถูกตัดไปแล้ว ระบบจะขึ้นว่า "ไม่มีแถวที่ต้องตัดบิล" แล้วบันทึกชื่อผู้กดให้เฉย ๆ
-- ============================================================================
