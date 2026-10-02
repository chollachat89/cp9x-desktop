-- =====================================================================
--  ตรวจว่ามีเลขงานไหน "ดึงเข้ารอบบิลไม่ได้" บ้าง
-- =====================================================================
--
--  รันในโปรเจกต์จริงได้เลย — **อ่านอย่างเดียวล้วน ๆ** ไม่สร้าง ไม่แก้ ไม่ลบอะไร
--  รันซ้ำได้ตลอด ปลอดภัย 100%
--
--  ---------------------------------------------------------------
--  ทำไมถึงต้องมีไฟล์นี้
--  ---------------------------------------------------------------
--  ตอนกด "ดูตัวอย่างก่อนบันทึกรอบบิล" ระบบจะไล่ดู close_issues ทุกแถว
--  แล้วแปลงคอลัมน์ fix_date (วันที่เข้าแก้ไข) เป็นวันที่จริงเพื่อเทียบกับช่วงรอบบิล
--
--  ถ้าแปลงไม่สำเร็จ ระบบจะ **ข้ามแถวนั้นไปเงียบ ๆ ไม่มี error ไม่มีคำเตือน**
--  งานนั้นจะไม่โผล่ในรอบบิลไหนเลย ไม่ว่าจะเลือกช่วงวันที่อย่างไร
--  และไม่มีทางรู้ได้เลยว่าหายไปกี่งาน นี่คือสาเหตุที่หายากที่สุด
--
--  กติกาการแปลงวันที่ (ลอกมาจากฟังก์ชัน parseFixDateString ใน index.ts เป๊ะ ๆ):
--    - ตัดด้วย - หรือ /  ต้องได้ 3 ท่อนพอดี
--    - ทั้ง 3 ท่อนต้องเป็นตัวเลข และต้องไม่เป็นศูนย์
--    - ปีน้อยกว่า 100 จะบวก 2000 ให้ (เช่น 69 -> 2069)
--    - **ไม่มีการแปลง พ.ศ. เป็น ค.ศ.**  <-- จุดที่พลาดง่ายที่สุด
--
--  ลำดับท่อนคือ วัน/เดือน/ปี (dd/mm/yyyy)
-- =====================================================================


-- =====================================================================
--  1. สรุปภาพรวมก่อน
-- =====================================================================

with base as (
  select c.job_id, c.asset_id, c.fix_date,
         regexp_split_to_array(btrim(coalesce(c.fix_date, '')), '[-/]') as p
  from public.close_issues c
),
flag as (
  select b.*,
         (b.fix_date is null or btrim(b.fix_date) = '')                as ว่าง,
         (array_length(b.p, 1) is distinct from 3)                     as ไม่ครบ3ท่อน,
         (array_length(b.p, 1) = 3
           and (b.p[1] !~ '^[0-9]+$' or b.p[2] !~ '^[0-9]+$' or b.p[3] !~ '^[0-9]+$')) as ไม่ใช่ตัวเลข
  from base b
),
num as (
  select f.*,
         case when not f.ว่าง and not f.ไม่ครบ3ท่อน and not f.ไม่ใช่ตัวเลข
              then f.p[1]::int end as d,
         case when not f.ว่าง and not f.ไม่ครบ3ท่อน and not f.ไม่ใช่ตัวเลข
              then f.p[2]::int end as m,
         case when not f.ว่าง and not f.ไม่ครบ3ท่อน and not f.ไม่ใช่ตัวเลข
              then (case when f.p[3]::int < 100 then f.p[3]::int + 2000 else f.p[3]::int end) end as y
  from flag f
)
select
  case
    when ว่าง            then '1. fix_date ว่าง — ระบบข้ามแถวนี้เสมอ'
    when ไม่ครบ3ท่อน      then '2. รูปแบบวันที่ไม่ถูก (ต้องเป็น วัน/เดือน/ปี) — ระบบข้ามแถวนี้เสมอ'
    when ไม่ใช่ตัวเลข     then '3. มีท่อนที่ไม่ใช่ตัวเลข — ระบบข้ามแถวนี้เสมอ'
    when d = 0 or m = 0 or y = 0 then '4. มีค่าเป็นศูนย์ — ระบบข้ามแถวนี้เสมอ'
    when y > 2400        then '5. ⚠ ปีเป็น พ.ศ. — กลายเป็นปีอนาคตไกล ไม่มีวันเข้ารอบบิลไหนเลย'
    when m > 12          then '6. เดือนเกิน 12 — วันที่เพี้ยน'
    when make_date(y, least(greatest(m,1),12), 1) > current_date
                         then '7. วันที่อยู่ในอนาคต — ต้องรอถึงรอบนั้นก่อน'
    else '✓ ปกติ ดึงเข้ารอบบิลได้'
  end                                                       as อาการ,
  count(*)                                                  as จำนวนแถวปิดงาน,
  count(distinct job_id)                                    as จำนวนเลขงาน
from num
group by 1
order by 1;


-- =====================================================================
--  2. รายชื่อเลขงานที่ "ดึงไม่ได้ถาวร" (ต้องแก้ fix_date ถึงจะดึงได้)
-- =====================================================================
--  พวกนี้คือของจริงที่ต้องลงมือแก้ ไม่ใช่แค่ยังไม่ถึงคิว

with base as (
  select c.job_id, c.asset_id, c.fix_date, c.created_at,
         regexp_split_to_array(btrim(coalesce(c.fix_date, '')), '[-/]') as p
  from public.close_issues c
),
flag as (
  select b.*,
         (b.fix_date is null or btrim(b.fix_date) = '')                as ว่าง,
         (array_length(b.p, 1) is distinct from 3)                     as ไม่ครบ3ท่อน,
         (array_length(b.p, 1) = 3
           and (b.p[1] !~ '^[0-9]+$' or b.p[2] !~ '^[0-9]+$' or b.p[3] !~ '^[0-9]+$')) as ไม่ใช่ตัวเลข
  from base b
),
num as (
  select f.*,
         case when not f.ว่าง and not f.ไม่ครบ3ท่อน and not f.ไม่ใช่ตัวเลข then f.p[1]::int end as d,
         case when not f.ว่าง and not f.ไม่ครบ3ท่อน and not f.ไม่ใช่ตัวเลข then f.p[2]::int end as m,
         case when not f.ว่าง and not f.ไม่ครบ3ท่อน and not f.ไม่ใช่ตัวเลข
              then (case when f.p[3]::int < 100 then f.p[3]::int + 2000 else f.p[3]::int end) end as y
  from flag f
)
select n.job_id                              as เลขงาน,
       n.asset_id                            as เลขทรัพย์สิน,
       n.fix_date                            as ค่าที่เก็บอยู่ตอนนี้,
       case
         when n.ว่าง          then 'fix_date ว่าง'
         when n.ไม่ครบ3ท่อน    then 'รูปแบบไม่ถูก'
         when n.ไม่ใช่ตัวเลข   then 'มีท่อนที่ไม่ใช่ตัวเลข'
         when n.d = 0 or n.m = 0 or n.y = 0 then 'มีค่าเป็นศูนย์'
         when n.y > 2400     then 'ปีเป็น พ.ศ. (ควรเป็น ' || (n.y - 543) || ')'
         when n.m > 12       then 'เดือนเกิน 12'
       end                                   as อาการ,
       case
         when n.y > 2400 and n.m between 1 and 12
           then 'แก้เป็น ' || lpad(n.d::text,2,'0') || '/' || lpad(n.m::text,2,'0') || '/' || (n.y - 543)
         else 'แก้ fix_date ให้เป็นรูปแบบ วัน/เดือน/ปี ค.ศ. เช่น 25/09/2026'
       end                                   as ต้องแก้เป็น,
       n.created_at                          as ปิดงานเมื่อ
from num n
where n.ว่าง or n.ไม่ครบ3ท่อน or n.ไม่ใช่ตัวเลข
   or n.d = 0 or n.m = 0 or n.y = 0 or n.y > 2400 or n.m > 12
order by n.created_at desc;


-- =====================================================================
--  3. งานที่ปิดแล้ว วันที่ปกติ แต่ยังไม่เคยถูกดึงเข้ารอบบิลเลย
-- =====================================================================
--  ไม่ใช่บั๊ก ถ้ายังไม่ถึงคิว — แต่ถ้าเก่ามากแล้วยังค้างอยู่ แปลว่าตกหล่น
--  ใช้ดูว่ามีงานตกค้างสะสมอยู่เท่าไหร่ก่อนอัปเดต

select c.job_id                                   as เลขงาน,
       c.asset_id                                 as เลขทรัพย์สิน,
       c.fix_date                                 as วันที่เข้าแก้ไข,
       c.created_at                               as ปิดงานเมื่อ,
       (current_date - c.created_at::date)        as ปิดมาแล้วกี่วัน,
       o.contractor                               as ผู้รับเหมา
from public.close_issues c
left join public.open_issues o on o.main_id = c.job_id
where not exists (
        select 1 from public.billing_documents b
        where b.customer_case = c.job_id
      )
  and btrim(coalesce(c.fix_date, '')) <> ''
order by c.created_at asc;


-- =====================================================================
--  4. ⚠ งานที่ "ถูกจองไว้แล้ว แต่ไม่มีบิลจริง" — ดึงซ้ำไม่ได้ตลอดกาล
-- =====================================================================
--  ตอนกดยืนยันสร้างรอบบิล ระบบจะ "จองคิว" เลขงานไว้ในตาราง billing_job_registry ก่อน
--  แล้วค่อยสร้างแถวใน billing_documents
--
--  ถ้าขั้นตอนพังกลางทาง (เน็ตหลุด / Edge Function หมดเวลา) จะเหลือการจองค้างไว้
--  โดยไม่มีบิลจริง ผลคือ **งานนั้นจะถูกข้ามตลอดไป** เพราะระบบเห็นว่าจองแล้ว
--  แต่ในตารางวางบิลกลับไม่มีอะไรเลย — เป็นอาการ "ดึงไม่ได้" ที่หาสาเหตุยากที่สุด
--
--  คีย์จองมี 2 แบบ: เลขงานตรง ๆ หรือ เลขงาน__asset__เลขทรัพย์สิน จึงต้องตัดด้วย split_part

select r.customer_case                                          as คีย์จอง,
       split_part(r.customer_case, '__asset__', 1)              as เลขงาน,
       nullif(split_part(r.customer_case, '__asset__', 2), '')  as เลขทรัพย์สิน
from public.billing_job_registry r
where not exists (
  select 1 from public.billing_documents b
  where b.customer_case = split_part(r.customer_case, '__asset__', 1)
)
order by 2;

--  ถ้าข้อ 4 มีแถวโผล่มา และยืนยันแล้วว่างานนั้นควรวางบิลได้
--  ให้ลบเฉพาะการจองที่ค้าง (ไม่ได้ลบข้อมูลงาน) แล้วดึงเข้ารอบบิลใหม่ได้ตามปกติ
--  ⚠ สำรองก่อนเสมอ และรันเฉพาะเมื่อตรวจรายการข้างบนแล้วว่าถูกต้อง
--
--   create table billing_job_registry_backup as select * from billing_job_registry;
--
--   delete from public.billing_job_registry r
--   where not exists (
--     select 1 from public.billing_documents b
--     where b.customer_case = split_part(r.customer_case, '__asset__', 1)
--   );
