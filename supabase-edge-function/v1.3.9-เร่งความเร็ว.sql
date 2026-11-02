-- ==========================================================================
-- v1.3.9 — เร่งความเร็วระบบ (ย้ายการ "นับ" ไปทำในฐานข้อมูล)
--
-- วัดจากระบบจริงก่อนแก้ (2 พ.ย. 2569):
--   · 1 คำขอที่แตะฐานข้อมูล = 0.7-1.15 วินาที (จากกรุงเทพฯ ไปเซิร์ฟเวอร์ที่ซิดนีย์)
--   · SQL เองใช้เวลาแค่ 0.1-30 มิลลิวินาที  = เวลาเกือบทั้งหมดหมดไปกับการ "วิ่งไปกลับ"
--   · ป้ายแจ้งเตือนของแอดมินดึงทั้งตาราง open_issues + close_issues + pause_records
--     (ราว 2,200 แถว) ทุก 30 วินาที เพื่อเอาเลข 2 ตัว
--   · temp file ของฐานข้อมูล 370 GB ใน 110 วัน = ผลจากการดึงทั้งตารางแล้วห่อเป็น JSON ก้อนใหญ่
--
-- ไฟล์นี้จึงเพิ่มฟังก์ชัน "นับให้เสร็จในฐานข้อมูล" แล้วส่งกลับแค่ตัวเลข
-- ทั้ง 2 ฟังก์ชันเป็นการอ่านอย่างเดียว ไม่แก้ไขข้อมูลใด ๆ
--
-- ⚠ รันไฟล์นี้ได้ก่อนหรือหลังการ deploy Edge Function ก็ได้
--   ฝั่งเซิร์ฟเวอร์เขียนเผื่อไว้แล้วว่า "ถ้ายังไม่มีฟังก์ชันนี้ ให้นับแบบเดิมไปก่อน"
--   จึงไม่มีช่วงไหนที่ระบบใช้งานไม่ได้
-- ==========================================================================

-- --------------------------------------------------------------------------
-- 1) นับเลขป้ายแจ้งเตือนของแอดมิน
--    pending_count = งานที่เปิดแล้วยังไม่มีการปิดงาน (นับตามเลขงาน ไม่ซ้ำ)
--    paused_count  = งานที่กำลังพักอยู่
--    นับรวมทั้งงาน CM และงาน RE เหมือนที่ฝั่งแอปทำอยู่เดิมเป๊ะ ๆ
--
--    ตาราง re_* ใช้ to_regclass กันไว้ เผื่อฐานข้อมูลที่ยังไม่ได้สร้างตารางฝั่ง RE
--    (ไม่มีตาราง = ถือว่าไม่มีงาน RE ไม่ใช่ error)
-- --------------------------------------------------------------------------
create or replace function public.cp9x_badge_counts()
returns table (pending_count integer, paused_count integer)
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_pending integer := 0;
  v_paused  integer := 0;
  n         integer;
begin
  -- งาน CM
  select count(*) into n from (
    select distinct o.main_id
    from open_issues o
    where o.main_id is not null
      and not exists (select 1 from close_issues c where c.job_id = o.main_id)
  ) t;
  v_pending := v_pending + coalesce(n, 0);

  select count(*) into n from pause_records p where p.status = 'paused';
  v_paused := v_paused + coalesce(n, 0);

  -- งาน RE (ถ้ามีตาราง)
  if to_regclass('public.re_open_issues') is not null
     and to_regclass('public.re_close_issues') is not null then
    execute $q$
      select count(*) from (
        select distinct o.main_id
        from re_open_issues o
        where o.main_id is not null
          and not exists (select 1 from re_close_issues c where c.job_id = o.main_id)
      ) t
    $q$ into n;
    v_pending := v_pending + coalesce(n, 0);
  end if;

  if to_regclass('public.re_pause_records') is not null then
    execute $q$ select count(*) from re_pause_records p where p.status = 'paused' $q$ into n;
    v_paused := v_paused + coalesce(n, 0);
  end if;

  return query select v_pending, v_paused;
end;
$fn$;

-- --------------------------------------------------------------------------
-- 2) รายการรอบบิลที่มีอยู่ (สำหรับ dropdown "เลือกรอบบิล" ฝั่งแอดมิน)
--    เดิมดึงคอลัมน์ round_no ของทุกแถวในตารางบิล (1,406 แถว) มานับเองที่เซิร์ฟเวอร์
--    ตอนนี้ให้ฐานข้อมูลสรุปเหลือแถวละ 1 รอบ (ราว 5 แถว) ก่อนส่งกลับ
--
--    p_kind รับได้แค่ 'CM' หรือ 'RE' เท่านั้น แปลงเป็นชื่อตารางข้างในฟังก์ชันเอง
--    (ไม่รับชื่อตารางจากข้างนอก กัน SQL injection)
--    ฝั่งผู้รับเหมาไม่ได้ใช้ฟังก์ชันนี้ เพราะต้องกรองตามชื่อผู้รับเหมา/สถานะการส่งบิล
--    ซึ่งแถวของผู้รับเหมาแต่ละเจ้ามีไม่มาก ใช้วิธีเดิมเร็วพออยู่แล้ว
-- --------------------------------------------------------------------------
create or replace function public.cp9x_billing_round_options(p_kind text default 'CM')
returns table (round_no integer, round_period text)
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  tbl text;
begin
  tbl := case upper(coalesce(p_kind, 'CM'))
           when 'RE' then 'public.re_billing_documents'
           else 'public.billing_documents'
         end;
  if to_regclass(tbl) is null then return; end if;

  return query execute format(
    'select b.round_no::integer, coalesce(max(b.round_period), '''')::text
       from %s b
      where b.round_no is not null
      group by b.round_no
      order by b.round_no desc', tbl);
end;
$fn$;

-- --------------------------------------------------------------------------
-- 3) ลบ index ที่ซ้ำกันเป๊ะ ๆ
--    re_billing_job_registry มี unique index บน (customer_case) อยู่ 2 ตัว
--    ตัวหนึ่งคือ primary key อีกตัวสร้างซ้ำไว้ตอน v1.2.0
--    = ทุกครั้งที่จองเลขงานเข้ารอบบิล ต้องเขียน index 2 ชุดโดยไม่ได้อะไรเพิ่ม
--
--    ปลอดภัย: primary key ยังกันเลขงานซ้ำไว้เหมือนเดิมทุกกรณี
--    และ claim_re_billing_jobs ใช้ "on conflict (customer_case)" ซึ่งอ้างคอลัมน์
--    ไม่ได้อ้างชื่อ constraint จึงไม่กระทบ
-- --------------------------------------------------------------------------
drop index if exists public.re_billing_job_registry_case_uniq;

-- --------------------------------------------------------------------------
-- ตรวจผลหลังรัน (อ่านอย่างเดียว ไม่บังคับ)
-- --------------------------------------------------------------------------
-- select * from public.cp9x_badge_counts();
-- select * from public.cp9x_billing_round_options('CM');
-- select * from public.cp9x_billing_round_options('RE');
