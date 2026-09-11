-- ==========================================================
-- ลบรายการที่ผู้รับเหมา "ส่งซ้ำโดยไม่ตั้งใจ" ออก
--
-- นิยามของส่งซ้ำโดยไม่ตั้งใจ (ตรงกับที่ใช้ตอนตรวจ):
--   เลขงานเดียวกัน · ส่งห่างจากครั้งก่อนไม่ถึง 5 นาที · และครั้งก่อน "ไม่ได้ถูกตีกลับ"
--   (ถ้าถูกตีกลับแล้วส่งใหม่ = ปกติ ไม่ใช่ของซ้ำ จะไม่ถูกแตะเลย)
--
-- กฎว่าจะเก็บแถวไหนไว้:
--   1. ถ้ามีแถวที่แอดมินตรวจแล้ว (อนุมัติ/ตีกลับ) -> เก็บแถวนั้นไว้ เพราะมีประวัติการตรวจติดอยู่
--   2. ถ้ายังไม่มีใครตรวจเลย -> เก็บแถวที่ส่งล่าสุดไว้ (แถวที่ผู้รับเหมาเชื่อว่าส่งสำเร็จ)
--   แถวที่เหลือในกลุ่มคือแถวที่จะถูกลบ
--
-- ⚠ บล็อก B ลบข้อมูลถาวร กู้คืนไม่ได้
--    ให้รันบล็อก A (อ่านอย่างเดียว) ดูให้ชัดก่อนเสมอว่าจะลบแถวไหน
--
-- วิธีใช้: https://supabase.com/dashboard/project/hefnjozijflnhdunmewl/sql/new
-- ==========================================================


-- === บล็อก A: ดูก่อนว่าจะลบแถวไหน (อ่านอย่างเดียว) ===
with จัดกลุ่ม as (
  select
    s.*,
    lag(s.submitted_at) over (partition by s.customer_case order by s.submitted_at) as ครั้งก่อน,
    lag(s.status)       over (partition by s.customer_case order by s.submitted_at) as สถานะครั้งก่อน
  from job_form_submissions s
),
-- หาเลขงานที่เข้าข่ายส่งซ้ำโดยไม่ตั้งใจ
เลขงานที่ซ้ำ as (
  select distinct customer_case
  from จัดกลุ่ม
  where ครั้งก่อน is not null
    and สถานะครั้งก่อน <> 'rejected'
    and extract(epoch from (submitted_at - ครั้งก่อน)) < 300
),
-- ในแต่ละเลขงาน จัดอันดับว่าแถวไหนควรเก็บไว้ (อันดับ 1 = เก็บ)
จัดอันดับ as (
  select
    s.*,
    row_number() over (
      partition by s.customer_case
      order by
        (s.status <> 'pending') desc,   -- แถวที่ตรวจแล้วมาก่อน
        s.submitted_at desc             -- ถ้าเสมอกัน เอาแถวล่าสุด
    ) as อันดับ
  from job_form_submissions s
  where s.customer_case in (select customer_case from เลขงานที่ซ้ำ)
)
select
  case when อันดับ = 1 then '✅ เก็บไว้' else '🗑 จะถูกลบ' end   as "จะทำอะไร",
  id                                                            as "id (ใช้ลบเจาะจง)",
  customer_case                                                 as "เลขงาน",
  contractor                                                    as "ผู้รับเหมา",
  to_char(submitted_at at time zone 'Asia/Bangkok',
          'DD/MM/YYYY HH24:MI:SS')                              as "เวลาที่ส่ง",
  case status when 'pending'  then 'รอตรวจสอบ'
              when 'approved' then 'อนุมัติแล้ว'
              when 'rejected' then 'ตีกลับ'
              else status end                                   as "สถานะ",
  reviewed_by                                                   as "ผู้ตรวจ",
  file_name                                                     as "ชื่อไฟล์",
  drive_file_id                                                 as "ไฟล์ใน Storage (ไว้ตามลบเอง)"
from จัดอันดับ
order by customer_case, อันดับ;


-- === บล็อก B: ลบจริง ===
-- รันเมื่อดูบล็อก A แล้วโอเคกับแถวที่ขึ้นว่า "🗑 จะถูกลบ"
--
-- มีตัวกันพลาดในตัว: ถ้าจำนวนแถวที่จะลบมากกว่า 5 แถว จะยกเลิกทั้งหมดทันที
-- (ป้องกันกรณีเงื่อนไขผิดพลาดแล้วกวาดลบข้อมูลดี ๆ ไปด้วย)
do $$
declare
  จำนวนที่จะลบ int;
  รายการที่ลบ  text;
begin
  create temp table _ลบทิ้ง on commit drop as
  with จัดกลุ่ม as (
    select
      s.*,
      lag(s.submitted_at) over (partition by s.customer_case order by s.submitted_at) as ครั้งก่อน,
      lag(s.status)       over (partition by s.customer_case order by s.submitted_at) as สถานะครั้งก่อน
    from job_form_submissions s
  ),
  เลขงานที่ซ้ำ as (
    select distinct customer_case
    from จัดกลุ่ม
    where ครั้งก่อน is not null
      and สถานะครั้งก่อน <> 'rejected'
      and extract(epoch from (submitted_at - ครั้งก่อน)) < 300
  ),
  จัดอันดับ as (
    select
      s.id, s.customer_case, s.submitted_at, s.status, s.drive_file_id, s.file_name,
      row_number() over (
        partition by s.customer_case
        order by (s.status <> 'pending') desc, s.submitted_at desc
      ) as อันดับ
    from job_form_submissions s
    where s.customer_case in (select customer_case from เลขงานที่ซ้ำ)
  )
  select * from จัดอันดับ where อันดับ > 1;

  select count(*) into จำนวนที่จะลบ from _ลบทิ้ง;

  if จำนวนที่จะลบ = 0 then
    raise notice 'ไม่มีแถวที่เข้าข่ายส่งซ้ำโดยไม่ตั้งใจ — ไม่ได้ลบอะไรเลย';
    return;
  end if;

  if จำนวนที่จะลบ > 5 then
    raise exception 'ยกเลิก: จะลบ % แถว ซึ่งมากผิดปกติ (เกิน 5) ไม่ลบให้เพื่อความปลอดภัย กรุณาดูบล็อก A อีกครั้ง', จำนวนที่จะลบ;
  end if;

  select string_agg(customer_case || ' (id=' || id || ', ' ||
                    to_char(submitted_at at time zone 'Asia/Bangkok', 'DD/MM/YYYY HH24:MI:SS') || ')', E'\n  ')
    into รายการที่ลบ from _ลบทิ้ง;

  delete from job_form_submissions where id in (select id from _ลบทิ้ง);

  raise notice 'ลบเรียบร้อย % แถว:%  %', จำนวนที่จะลบ, E'\n  ', รายการที่ลบ;
end $$;


-- === บล็อก C: ตรวจหลังลบ ===
-- ต้องไม่เหลือรายการส่งซ้ำโดยไม่ตั้งใจแล้ว (ผลควรเป็น 0)
with จัดกลุ่ม as (
  select customer_case, status, submitted_at,
    lag(submitted_at) over (partition by customer_case order by submitted_at) as ครั้งก่อน,
    lag(status)       over (partition by customer_case order by submitted_at) as สถานะครั้งก่อน
  from job_form_submissions
)
select count(*) as "ส่งซ้ำไม่ตั้งใจที่เหลือ (ต้องเป็น 0)"
from จัดกลุ่ม
where ครั้งก่อน is not null
  and สถานะครั้งก่อน <> 'rejected'
  and extract(epoch from (submitted_at - ครั้งก่อน)) < 300;

-- ดูรายการของเลขงานที่เพิ่งแก้ ว่าเหลือแถวเดียวจริง
select
  customer_case as "เลขงาน",
  count(*)      as "จำนวนไฟล์ที่เหลือ"
from job_form_submissions
group by customer_case
having count(*) > 1
order by customer_case;


-- === บล็อก D: ไฟล์กำพร้าใน Storage ===
-- หลังลบแถวแล้ว ตัวไฟล์ PDF ยังค้างอยู่ใน Storage — คำสั่งนี้บอกว่ามีกี่ไฟล์และชื่ออะไร
select
  o.name                                            as "ชื่อไฟล์ใน Storage (ลบทิ้งได้)",
  pg_size_pretty((o.metadata->>'size')::bigint)     as "ขนาด",
  to_char(o.created_at at time zone 'Asia/Bangkok',
          'DD/MM/YYYY HH24:MI')                     as "อัปโหลดเมื่อ"
from storage.objects o
where o.bucket_id = 'job-form-submissions'
  and not exists (
    select 1 from job_form_submissions s where s.drive_file_id = o.name
  )
order by o.created_at desc;


-- ==========================================================
-- ไฟล์ที่ขึ้นในบล็อก D ลบด้วย SQL ไม่ได้ ต้องไปลบที่หน้า Storage:
--   https://supabase.com/dashboard/project/hefnjozijflnhdunmewl/storage/buckets/job-form-submissions
-- เข้าโฟลเดอร์ตามชื่อเลขงาน แล้วลบไฟล์ตามชื่อที่เห็น
--
-- ไม่ลบก็ได้ ไม่มีผลอะไรกับระบบ แค่กินพื้นที่เปล่า ๆ ไม่มีลิงก์ชี้ไปหาแล้ว
-- ==========================================================
