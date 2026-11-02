-- =====================================================================
--  v1.3.1 — แปลง "รอบบิลเลขวิ่ง" ของเดิม ให้เป็น "รอบเดือน" แบบใหม่
-- =====================================================================
--
--  ตั้งแต่ v1.3.0 รอบบิลคือเดือนที่ปิดงาน เก็บเป็นเลข YYYYMM (เช่น 202610)
--  ไฟล์นี้ย้อนไปแปลงรอบเก่า (เลขวิ่ง 1, 2, 3, … 90) ที่มีอยู่แล้วให้เป็นรอบเดือนด้วย
--
--  ใช้ "วันที่เข้างาน" (visit_date) ของแต่ละแถวเป็นตัวตัดสินเดือน
--  ซึ่งคือค่าเดียวกับที่ v1.3.0 ใช้ตอนสร้างแถวใหม่ ผลลัพธ์จึงเป็นกติกาเดียวกันทั้งระบบ
--
--  ⚠ 1 รอบเก่า แตกเป็นหลายเดือนได้ เพราะรอบเก่ารวมงานข้ามเดือนไว้ด้วยกัน
--     ขั้นที่ 1 บอกให้ดูก่อนว่ารอบไหนแตกเป็นกี่เดือน
--
--  ⚠ แถวที่ "ตัดบิลแล้ว" ก็ถูกแปลงด้วย เพราะไม่งั้นรายงานย้อนหลังจะมีทั้งสองแบบปนกัน
--     ยอดเงินและข้อมูลทุกช่องไม่ถูกแตะ เปลี่ยนแค่ว่าแถวนั้นอยู่รอบไหน
--
--  ***ขั้นที่ 1 อ่านอย่างเดียว ไม่แก้อะไร — รันดูก่อนทุกครั้ง***
--  ขั้นที่ 2 สำรองค่าเดิมไว้ก่อนเสมอ → ย้อนกลับได้ (ดูท้ายไฟล์)
--
-- ---------------------------------------------------------------------
--  รันได้ทุกโปรเจกต์ ไม่ว่าจะเคยรัน v1.2.0 (แยกงาน RE) มาแล้วหรือยัง
-- ---------------------------------------------------------------------
--  ตารางชุด RE (re_billing_documents ฯลฯ) จะมีก็ต่อเมื่อรัน v1.2.0 มาแล้ว
--  ไฟล์นี้ตรวจก่อนทุกครั้งว่ามีหรือไม่ ถ้าไม่มีก็ข้ามไปเฉย ๆ ไม่ error
--
--  ตัวช่วยอ่านวันที่สร้างเป็น "ฟังก์ชันปกติ" ไม่ใช่ฟังก์ชันชั่วคราว (pg_temp)
--  เพราะ SQL Editor ของ Supabase ต่อผ่านตัวรวมคอนเนกชัน ของชั่วคราวจะหายไประหว่างคำสั่ง
--  แล้วขึ้น error ว่าไม่มี schema pg_temp — มีขั้นที่ 5 ไว้ลบทิ้งเมื่อใช้เสร็จ
-- =====================================================================


-- ---------------------------------------------------------------------
--  ตัวอ่านวันที่ — เลียนแบบ parseFixDateString ใน index.ts ให้ตรงเป๊ะ
--
--  กติกาของแอป: แยกด้วย - หรือ / เท่านั้น · ต้องได้ 3 ส่วน · ห้ามมีส่วนไหนเป็น 0
--  ปี < 100 บวก 2000 · และ "ล้นเดือนได้" แบบ JavaScript (31/02/2026 -> 3 มี.ค. 2026)
--  ถ้าไม่เลียนแบบการล้นเดือน บางงานจะย้ายไปผิดเดือนโดยไม่มีใครรู้
-- ---------------------------------------------------------------------
create or replace function public.cp9x_round_from_fixdate(p text) returns integer as $fn$
declare
  parts text[];
  d int; m int; y int;
  dt date;
begin
  if p is null or btrim(p) = '' then return null; end if;
  parts := regexp_split_to_array(btrim(p), '[-/]');
  if array_length(parts, 1) is distinct from 3 then return null; end if;
  begin
    d := btrim(parts[1])::int; m := btrim(parts[2])::int; y := btrim(parts[3])::int;
  exception when others then return null;
  end;
  if d = 0 or m = 0 or y = 0 then return null; end if;
  if y < 100 then y := y + 2000; end if;
  begin
    dt := (make_date(y, 1, 1) + ((m - 1) * interval '1 month') + ((d - 1) * interval '1 day'))::date;
  exception when others then return null;
  end;
  return extract(year from dt)::int * 100 + extract(month from dt)::int;
end $fn$ language plpgsql;

create or replace function public.cp9x_round_label(r integer) returns text as $fn$
declare
  months text[] := array['มกราคม','กุมภาพันธ์','มีนาคม','เมษายน','พฤษภาคม','มิถุนายน',
                         'กรกฎาคม','สิงหาคม','กันยายน','ตุลาคม','พฤศจิกายน','ธันวาคม'];
  m int;
begin
  if r is null then return null; end if;
  if r >= 190001 and r <= 999912 then
    m := r % 100;
    if m between 1 and 12 then return 'รอบเดือน ' || months[m] || ' ' || (r / 100)::text; end if;
  end if;
  return 'รอบเก่าที่ ' || r::text;
end $fn$ language plpgsql;

-- รวมแถวบิลของทั้งสองชนิดมาให้ดูในคำสั่งเดียว — ไม่มีตารางชุด RE ก็คืนเฉพาะของ CM
-- (ใช้ execute เพราะถ้าอ้างชื่อตารางตรง ๆ Postgres จะตรวจตั้งแต่ตอนสร้างฟังก์ชัน แล้ว error ทันที
--  ซึ่งเป็นสาเหตุเดิมที่ไฟล์นี้รันไม่ผ่านในโปรเจกต์ที่ยังไม่ได้รัน v1.2.0)
create or replace function public.cp9x_round_rows()
returns table (src text, row_id uuid, round_no integer, round_period text, visit_date text,
               customer_case text, asset_id text, contractor text, completed_at timestamptz) as $fn$
begin
  return query
    select 'billing_documents'::text, b.id, b.round_no, b.round_period, b.visit_date,
           b.customer_case, b.asset_id, b.contractor, b.completed_at
    from public.billing_documents b;
  if to_regclass('public.re_billing_documents') is not null then
    return query execute
      'select ''re_billing_documents''::text, b.id, b.round_no, b.round_period, b.visit_date,
              b.customer_case, b.asset_id, b.contractor, b.completed_at
       from public.re_billing_documents b';
  end if;
end $fn$ language plpgsql;

-- ฟังก์ชันพวกนี้อยู่ใน public ซึ่ง PostgREST เปิดให้เรียกผ่าน API ได้
-- ปิดสิทธิ์ไว้ก่อน เป็นตัวช่วยสำหรับงานแปลงข้อมูลเท่านั้น ไม่ได้มีไว้ให้แอปเรียก
revoke execute on function public.cp9x_round_from_fixdate(text) from public, anon, authenticated;
revoke execute on function public.cp9x_round_label(integer) from public, anon, authenticated;
revoke execute on function public.cp9x_round_rows() from public, anon, authenticated;


-- =====================================================================
--  ขั้นที่ 1 — ดูก่อนว่าจะเกิดอะไรขึ้น (อ่านอย่างเดียว ปลอดภัย)
-- =====================================================================

-- 1.0 โปรเจกต์นี้มีตารางอะไรบ้าง
select 'billing_documents (งาน CM)' as "ตาราง",
       case when to_regclass('public.billing_documents') is null
            then '✗ ไม่พบ — หยุด อย่ารันขั้นต่อไป' else '✓ มี' end as "สถานะ"
union all
select 're_billing_documents (งาน RE)',
       case when to_regclass('public.re_billing_documents') is null
            then 'ยังไม่มี — ข้ามส่วนของ RE ให้เอง (ยังไม่ได้รัน v1.2.0)' else '✓ มี' end;

-- 1.1 ภาพรวม (รวมทั้งสองชนิดถ้ามี)
select
  count(*) filter (where round_no < 190001)                                   as "แถวรอบเก่า (จะถูกแปลง)",
  count(*) filter (where round_no >= 190001)                                  as "แถวรอบเดือนอยู่แล้ว (ไม่แตะ)",
  count(*) filter (where round_no < 190001
                     and public.cp9x_round_from_fixdate(visit_date) is null)  as "อ่านวันที่เข้างานไม่ออก (ไม่แปลง)",
  count(*) filter (where completed_at is not null and round_no < 190001)      as "ในนั้นเป็นแถวที่ตัดบิลแล้ว"
from public.cp9x_round_rows();

-- 1.2 รอบเก่าแต่ละรอบ จะกลายเป็นเดือนอะไรบ้าง (รอบที่แตกหลายเดือน ให้ดูให้ดี)
select r.src                                                        as "ตาราง",
       r.round_no                                                   as "รอบเดิม",
       count(*)                                                     as "จำนวนแถว",
       count(distinct public.cp9x_round_from_fixdate(r.visit_date)) as "แตกเป็นกี่เดือน",
       string_agg(distinct coalesce(
         public.cp9x_round_label(public.cp9x_round_from_fixdate(r.visit_date)),
         'อ่านวันที่ไม่ออก'), ' · ' order by coalesce(
         public.cp9x_round_label(public.cp9x_round_from_fixdate(r.visit_date)),
         'อ่านวันที่ไม่ออก'))                                        as "จะกลายเป็น"
from public.cp9x_round_rows() r
where r.round_no < 190001
group by r.src, r.round_no
order by r.src, r.round_no;

-- 1.3 แถวที่อ่านวันที่เข้างานไม่ออก — ต้องแก้ visit_date เองก่อน ไม่งั้นจะคงรอบเดิมไว้
select src as "ตาราง", round_no as "รอบเดิม", customer_case as "เลขงาน",
       asset_id as "เลขทรัพย์สิน", visit_date as "วันที่เข้างาน (อ่านไม่ออก)", contractor as "ผู้รับเหมา"
from public.cp9x_round_rows()
where round_no < 190001 and public.cp9x_round_from_fixdate(visit_date) is null
order by src, round_no, customer_case
limit 200;


-- =====================================================================
--  ขั้นที่ 2 — สำรองค่าเดิมไว้ก่อน (ย้อนกลับได้)
-- =====================================================================
create table if not exists public.backup_round_before_v131 (
  src_table    text not null,
  id           uuid not null,
  round_no     integer,
  round_period text,
  saved_at     timestamptz not null default now(),
  primary key (src_table, id)
);
alter table public.backup_round_before_v131 enable row level security;
revoke all on public.backup_round_before_v131 from anon, authenticated;

insert into public.backup_round_before_v131 (src_table, id, round_no, round_period)
select src, row_id, round_no, round_period
from public.cp9x_round_rows()
where round_no < 190001
on conflict (src_table, id) do nothing;

select count(*) as "สำรองไว้แล้วกี่แถว" from public.backup_round_before_v131;


-- =====================================================================
--  ขั้นที่ 3 — แปลงจริง  (แปลงเฉพาะแถวที่อ่านวันที่ออกเท่านั้น)
--             ตารางชุด RE ไม่มี = ข้ามให้เอง ไม่ error
-- =====================================================================
do $$
declare
  t text;
  reg text;
begin
  foreach t in array array['billing_documents', 're_billing_documents']
  loop
    if to_regclass('public.' || t) is null then
      raise notice 'ข้าม % (ยังไม่มีตารางนี้)', t;
      continue;
    end if;
    execute format($q$
      update public.%I b
      set round_no = public.cp9x_round_from_fixdate(b.visit_date),
          round_period = public.cp9x_round_label(public.cp9x_round_from_fixdate(b.visit_date))
      where b.round_no < 190001
        and public.cp9x_round_from_fixdate(b.visit_date) is not null
    $q$, t);

    -- ทะเบียนจองรอบบิล: คอลัมน์ round_no ในนี้เป็นข้อมูลประกอบอย่างเดียว
    -- (การกันซ้ำใช้ customer_case เป็นคีย์) แต่ถ้าไม่อัปเดตตามจะอ่านแล้วสับสนว่าคนละรอบกัน
    reg := case when t = 'billing_documents' then 'billing_job_registry' else 're_billing_job_registry' end;
    if to_regclass('public.' || reg) is not null then
      execute format($q$
        update public.%I r
        set round_no = s.round_no
        from (
          select split_part(customer_case, '__asset__', 1) as job, min(round_no) as round_no
          from public.%I group by 1
        ) s
        where split_part(r.customer_case, '__asset__', 1) = s.job
          and r.round_no is distinct from s.round_no
      $q$, reg, t);
    end if;
  end loop;
end $$;


-- =====================================================================
--  ขั้นที่ 4 — ตรวจผล
-- =====================================================================
select
  count(*) filter (where round_no >= 190001)                              as "แถวที่เป็นรอบเดือนแล้ว",
  count(*) filter (where round_no < 190001)                               as "ยังเป็นรอบเก่า (อ่านวันที่ไม่ออก)",
  count(*) filter (where round_no >= 190001
                     and round_period is distinct from public.cp9x_round_label(round_no))
                                                                          as "ชื่อรอบไม่ตรงกับเลขรอบ"
from public.cp9x_round_rows();

select src as "ตาราง", public.cp9x_round_label(round_no) as "รอบ",
       count(*) as "จำนวนแถว", count(distinct customer_case) as "จำนวนเลขงาน"
from public.cp9x_round_rows()
group by src, round_no
order by src, round_no;


-- =====================================================================
--  ขั้นที่ 5 — เก็บกวาด (รันเมื่อใช้เสร็จแล้ว)
-- =====================================================================
--  ลบตัวช่วยอ่านวันที่ทิ้ง ไม่ต้องเก็บไว้ในฐานข้อมูล
--  ⚠ ถ้ายังอยากรันขั้นที่ 1 ดูผลซ้ำ ให้ข้ามขั้นนี้ไปก่อน แล้วค่อยกลับมารันทีหลัง
--  (ตารางสำรอง backup_round_before_v131 ยังต้องเก็บไว้ อย่าเพิ่งลบ เผื่อต้องย้อนกลับ)
drop function if exists public.cp9x_round_rows();
drop function if exists public.cp9x_round_from_fixdate(text);
drop function if exists public.cp9x_round_label(integer);


-- =====================================================================
--  ย้อนกลับ (ถ้าผลไม่ถูกใจ) — คืนค่าเดิมจากตารางสำรอง
-- =====================================================================
--  do $$
--  declare t text;
--  begin
--    foreach t in array array['billing_documents', 're_billing_documents'] loop
--      if to_regclass('public.' || t) is null then continue; end if;
--      execute format($q$
--        update public.%I b set round_no = k.round_no, round_period = k.round_period
--        from public.backup_round_before_v131 k
--        where k.src_table = %L and k.id = b.id
--      $q$, t, t);
--    end loop;
--  end $$;
--
--  -- คืนเสร็จแล้วค่อยลบตารางสำรองทิ้ง
--  -- drop table public.backup_round_before_v131;
