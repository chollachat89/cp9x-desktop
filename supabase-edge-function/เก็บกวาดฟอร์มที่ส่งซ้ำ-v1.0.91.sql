-- =====================================================================
--  เก็บกวาด "ฟอร์มที่ส่งซ้ำ" ที่ค้างอยู่ก่อน v1.0.91   (ไม่บังคับ)
-- =====================================================================
--
--  v1.0.91 กันการส่งซ้ำ "ตั้งแต่รอบต่อไป" ไว้แล้ว
--  ไฟล์นี้ไว้จัดการแถวที่ซ้ำไปแล้วก่อนหน้านั้นเท่านั้น
--
--  ⚠ บล็อก C ลบข้อมูลจริง — อ่าน A กับ B ให้จบก่อน แล้วค่อยตัดสินใจ
--  ⚠ ไม่ทำอะไรเลยก็ได้ ไม่กระทบการตัดบิลหรือรายงาน
--    (ระบบดู "แถวล่าสุดของแต่ละเลขงาน" กับ "มีใบที่อนุมัติแล้วอย่างน้อย 1 ใบ" อยู่แล้ว)
--    ผลเสียของการปล่อยไว้คือ แอดมินเห็นซ้ำและต้องกดตรวจ 2 ครั้ง กับเปลืองที่เก็บไฟล์
-- =====================================================================


-- =====================================================================
--  A. ดูก่อนว่ามีกี่งานที่ซ้ำ            >>> อ่านอย่างเดียว <<<
-- =====================================================================

select customer_case                      as เลขงาน,
       count(*)                           as จำนวนแถว,
       count(distinct file_name)          as ชื่อไฟล์ไม่ซ้ำกี่แบบ,
       min(submitted_at)                  as ส่งครั้งแรก,
       max(submitted_at)                  as ส่งครั้งล่าสุด,
       string_agg(distinct status, ', ')  as สถานะที่มี
from public.job_form_submissions
group by customer_case
having count(*) > 1
order by count(*) desc, max(submitted_at) desc;


-- =====================================================================
--  B. ดูรายแถวของงานที่สงสัยว่าซ้ำ      >>> อ่านอย่างเดียว <<<
-- =====================================================================
--  "ซ้ำจากการกดส่งซ้ำ" มีหน้าตาแบบนี้ — ชื่อไฟล์เหมือนกัน · สถานะ pending ทั้งคู่ ·
--  เวลาห่างกันไม่กี่นาที  ส่วนแถวที่ห่างกันเป็นวัน หรือมีแถว rejected คั่น
--  = เขาตั้งใจส่งใหม่หลังถูกตีกลับ **ห้ามลบ** เพราะเป็นประวัติจริง
--
--  คอลัมน์ "ควรทำยังไง" คือคำแนะนำ ไม่ได้ลบอะไรให้

with pair as (
  select s.*,
         lag(submitted_at) over (partition by customer_case, file_name order by submitted_at) as แถวก่อนหน้า
  from public.job_form_submissions s
)
select เลขงาน, ไฟล์, สถานะ, ส่งเมื่อ, ห่างจากแถวก่อน,
       case when ห่างจากแถวก่อน is null then 'แถวแรก — เก็บไว้'
            when ห่างจากแถวก่อน < interval '15 minutes' and สถานะ = 'pending'
              then '>>> น่าจะเกิดจากการกดส่งซ้ำ'
            else 'ห่างกันนาน / คนละสถานะ — เก็บไว้ เป็นการส่งใหม่จริง'
       end as ควรทำยังไง
from (
  select customer_case as เลขงาน, file_name as ไฟล์, status as สถานะ,
         submitted_at  as ส่งเมื่อ, submitted_at - แถวก่อนหน้า as ห่างจากแถวก่อน
  from pair
) t
where เลขงาน in (
  select customer_case from public.job_form_submissions
  group by customer_case having count(*) > 1
)
order by เลขงาน, ส่งเมื่อ;


-- =====================================================================
--  C. ลบแถวที่ซ้ำ                        >>> ลบข้อมูลจริง <<<
-- =====================================================================
--  ⚠ รันบล็อก A กับ B ดูก่อน ถ้าไม่มีแถวไหนขึ้นว่า ">>> น่าจะเกิดจากการกดส่งซ้ำ"
--    ก็ไม่ต้องรันบล็อกนี้เลย
--
--  เงื่อนไขเข้มไว้ก่อน — ลบเฉพาะแถวที่ครบทุกข้อ:
--    ก. เลขงานเดียวกัน และ "ชื่อไฟล์เหมือนกันเป๊ะ"
--    ข. สถานะ pending ทั้งคู่ (ยังไม่มีใครตรวจ — ลบแล้วไม่ทำประวัติการตรวจหาย)
--    ค. ส่งห่างจากแถวก่อนหน้าไม่เกิน 15 นาที
--    ง. **เก็บแถวแรกสุดไว้เสมอ** ลบเฉพาะแถวที่มาทีหลัง
--
--  ไฟล์ใน Storage ของแถวที่ถูกลบจะยังอยู่ (ไม่ได้ลบตาม) — ไม่กระทบอะไร แค่กินที่
--  ถ้าจะลบไฟล์ด้วย ให้เอา drive_file_id จากตารางสำรองไปลบใน Storage เอง

-- ---- ขั้นที่ 1: สำรองก่อนเสมอ ----
create table if not exists job_form_submissions_dup_backup as
with ranked as (
  select id, customer_case, file_name, status, submitted_at, drive_file_id,
         lag(submitted_at) over (partition by customer_case, file_name order by submitted_at, id) as prev_at,
         row_number() over (partition by customer_case, file_name order by submitted_at, id)      as rn
  from public.job_form_submissions
)
select s.*
from public.job_form_submissions s
join ranked r on r.id = s.id
where r.rn > 1
  and r.status = 'pending'
  and r.prev_at is not null
  and r.submitted_at - r.prev_at < interval '15 minutes';

-- ดูว่าสำรองไว้กี่แถว = จำนวนที่กำลังจะถูกลบ
select count(*) as กำลังจะลบกี่แถว from job_form_submissions_dup_backup;

-- ---- ขั้นที่ 2: ลบจริง (รันก็ต่อเมื่อตัวเลขข้างบนดูถูกต้องแล้ว) ----
-- delete from public.job_form_submissions
-- where id in (select id from job_form_submissions_dup_backup);

-- ---- ถ้าลบผิด กู้คืนด้วยคำสั่งนี้ ----
-- insert into public.job_form_submissions
-- select * from job_form_submissions_dup_backup
-- on conflict do nothing;
