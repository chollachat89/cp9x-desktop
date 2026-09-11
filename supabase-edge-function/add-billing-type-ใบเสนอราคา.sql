-- ==========================================================
-- v1.0.58 — เพิ่มประเภทการเก็บเงินแบบที่ 4: 'quotation' (ใบเสนอราคา)
--
-- หลังรันไฟล์นี้ จะมีประเภทให้เลือก 4 แบบ:
--
--   ค่าในฐานข้อมูล    ชื่อที่แสดงในแอป      เก็บ CJ   เก็บผู้รับเหมา
--   ---------------  -------------------  -------  -------------
--   normal           เก็บเงินปกติ            ✅        ✅
--   claim            เคลมประกัน 3 เดือน      ❌        ❌
--   contractor_cr    เคลมอะไหล่             ❌        ✅
--   quotation        ใบเสนอราคา  ← ใหม่     ✅        ❌
--
-- 'quotation' เป็นภาพกลับด้านของ 'contractor_cr' พอดี
--
-- ⚠ ต้องรันไฟล์นี้ "ก่อน" deploy Edge Function เสมอ
--    เพราะ CHECK เดิมล็อกไว้แค่ 3 ค่า ถ้า deploy ก่อนแล้วผู้ใช้เลือก "ใบเสนอราคา"
--    ฐานข้อมูลจะปฏิเสธ แอปจะขึ้น error ตอนกดบันทึกแถว
--
-- ✅ ไม่แตะข้อมูลเดิมเลย แถวเก่าทุกแถวยังเป็นประเภทเดิมเหมือนเดิมทุกแถว
--
-- วิธีใช้: วางทั้งไฟล์ กด Run (รันซ้ำได้ปลอดภัย)
--   https://supabase.com/dashboard/project/hefnjozijflnhdunmewl/sql/new
-- ==========================================================


-- เผื่อกรณียังไม่เคยรันไฟล์ก่อนหน้า จะได้ไม่ error ตอนแก้ constraint
alter table billing_documents
    add column if not exists billing_type text not null default 'normal';

-- ต้องทิ้ง CHECK เดิมก่อน ไม่งั้นค่า 'quotation' จะถูกฐานข้อมูลปฏิเสธ
alter table billing_documents
    drop constraint if exists billing_documents_billing_type_chk;

alter table billing_documents
    add constraint billing_documents_billing_type_chk
    check (billing_type in ('normal', 'claim', 'contractor_cr', 'quotation'));


-- === ตรวจผล ===

-- 1) ข้อมูลที่มีอยู่ตอนนี้ แยกตามประเภท (ต้องไม่มีค่าแปลกปลอม)
select
  billing_type                                        as "ค่าในฐานข้อมูล",
  case billing_type
    when 'normal'        then 'เก็บเงินปกติ'
    when 'claim'         then 'เคลมประกัน 3 เดือน'
    when 'contractor_cr' then 'เคลมอะไหล่'
    when 'quotation'     then 'ใบเสนอราคา'
    else '⚠ ค่าแปลกปลอม'
  end                                                 as "ชื่อที่แสดงในแอป",
  case billing_type
    when 'normal'        then 'เก็บ'
    when 'claim'         then 'ไม่เก็บ'
    when 'contractor_cr' then 'ไม่เก็บ'
    when 'quotation'     then 'เก็บ'
    else '?'
  end                                                 as "ฝั่ง CJ",
  case billing_type
    when 'normal'        then 'เก็บ'
    when 'claim'         then 'ไม่เก็บ'
    when 'contractor_cr' then 'เก็บ'
    when 'quotation'     then 'ไม่เก็บ'
    else '?'
  end                                                 as "ฝั่งผู้รับเหมา",
  count(*)                                            as "จำนวนแถว"
from billing_documents
group by billing_type
order by billing_type;

-- 2) ยืนยันว่า CHECK ใหม่รับค่าครบ 4 แบบแล้ว
select pg_get_constraintdef(oid) as "เงื่อนไขที่ฐานข้อมูลยอมรับตอนนี้"
from pg_constraint
where conname = 'billing_documents_billing_type_chk';


-- ==========================================================
-- ทดสอบเร็ว ๆ ว่าบันทึกค่าใหม่ได้จริง (ไม่บังคับ — เขียนแล้วลบทิ้งในคำสั่งเดียว)
--
--   begin;
--   update billing_documents set billing_type = 'quotation'
--   where id = (select id from billing_documents limit 1);
--   -- ถ้าไม่ error แปลว่าใช้ได้แล้ว
--   rollback;   -- ยกเลิกทั้งหมด ไม่มีอะไรถูกเปลี่ยนจริง
-- ==========================================================
