-- =====================================================================
--  v1.2.0 — สร้าง "งาน RE" ไว้ทดสอบ  ★ รันในโปรเจกต์ทดสอบเท่านั้น ★
-- =====================================================================
--
--  ทำไมต้องมีไฟล์นี้: ข้อมูลงาน RE "ยังไม่มีอยู่ที่ไหนเลย" ในระบบ
--  จะคัดลอกมาจากโปรเจกต์จริงแบบขั้นที่ 4ข ไม่ได้ เพราะของจริงก็ยังไม่มีเหมือนกัน
--  ไฟล์นี้จึงปั้นขึ้นมาใหม่ ให้ครบทุกสถานะที่ต้องทดสอบ
--
--  ⚠ ต้องรัน v1.2.0-แยกงาน-RE-ออกจาก-CM.sql ให้เสร็จก่อน (ต้องมีตารางชุด RE แล้ว)
--
--  เลขงานที่สร้างขึ้นต้นด้วย RE-TEST- ทั้งหมด จึงลบทิ้งทีหลังได้สะอาด
--  (ดูบล็อกล้างข้อมูลท้ายไฟล์)
--
--  ข้อมูลอ้างอิง (สาขา · เลขทรัพย์สิน · รหัสอะไหล่) ไฟล์นี้ "หยิบจากฐานข้อมูลเอง"
--  ไม่ได้ฝังค่าตายตัวไว้ จึงไม่มีทางอ้างถึงสาขาหรืออะไหล่ที่ไม่มีอยู่จริง
-- =====================================================================


-- =====================================================================
--  ขั้นที่ 1 — ตรวจก่อน (อ่านอย่างเดียว)
-- =====================================================================
select
  case when to_regclass('public.re_open_issues') is null
       then '✗ ยังไม่มีตารางชุด RE — ต้องรัน v1.2.0-แยกงาน-RE-ออกจาก-CM.sql ก่อน'
       else '✓ มีตารางชุด RE แล้ว' end                                   as "ตารางชุด RE",
  (select count(*) from public.branches)::text                            as "สาขาในระบบ",
  (select count(*) from public.branch_assets)::text                       as "เลขทรัพย์สินในระบบ",
  (select count(*) from public.parts)::text                               as "อะไหล่ในระบบ",
  (select count(*) from public.contractors)::text                         as "ผู้ใช้ในระบบ",
  case when exists (select 1 from public.app_secrets where key = 'google_service_account_email')
       then '⛔ พบรหัสบัญชี Google = นี่คือโปรเจกต์จริง ห้ามรันขั้นที่ 2'
       else '✓ ไม่พบรหัสบัญชี Google (เป็นโปรเจกต์ทดสอบ)' end             as "ด่านกันรันผิดโปรเจกต์";

-- ต้องได้ครบ: มีตารางชุด RE · สาขา/ทรัพย์สิน/อะไหล่/ผู้ใช้ ไม่เป็น 0 · ด่านขึ้น ✓
-- ถ้าสาขาหรืออะไหล่เป็น 0 แปลว่ายังไม่ได้ทำ "ขั้นที่ 4 — คัดลอกข้อมูลตั้งต้น" ให้ทำก่อน


-- =====================================================================
--  ขั้นที่ 2 — สร้างงาน RE  (รันซ้ำได้ ลบของเดิมที่ขึ้นต้น RE-TEST- ให้ก่อนเสมอ)
-- =====================================================================
do $$
declare
  v_contractor text;
  v_part       record;
  v_b          record;
  v_asset      text;
  v_asset2     text;
  v_branches   text[] := '{}';
  v_i          int := 0;
  v_job        text;
  v_parts_text text;
  v_parts_json jsonb;
begin
  -- ---------- ด่านกันรันผิดโปรเจกต์ ----------
  -- โปรเจกต์ทดสอบ "ห้าม" มี app_secrets ของ Google (ตามคู่มือตั้งระบบทดสอบ)
  -- ถ้ามี แปลว่านี่คือโปรเจกต์จริง หยุดทันที
  if exists (select 1 from public.app_secrets where key = 'google_service_account_email') then
    raise exception 'หยุด: โปรเจกต์นี้มีรหัสบัญชี Google อยู่ = เป็นโปรเจกต์จริง ไม่ใช่โปรเจกต์ทดสอบ';
  end if;
  if to_regclass('public.re_open_issues') is null then
    raise exception 'หยุด: ยังไม่มีตารางชุด RE — รัน v1.2.0-แยกงาน-RE-ออกจาก-CM.sql ก่อน';
  end if;
  if not exists (select 1 from public.branches) then
    raise exception 'หยุด: ตาราง branches ว่าง — ทำขั้นที่ 4 (คัดลอกข้อมูลตั้งต้น) ก่อน';
  end if;

  -- ---------- ล้างของเดิมก่อน (ให้รันซ้ำได้ผลเหมือนเดิมทุกครั้ง) ----------
  delete from public.re_pause_records  where main_id like 'RE-TEST-%';
  delete from public.re_close_issues   where job_id  like 'RE-TEST-%';
  delete from public.re_open_issues    where main_id like 'RE-TEST-%';

  -- ---------- หยิบค่าอ้างอิงจริงจากฐานข้อมูล ----------
  -- ผู้รับเหมา: เอาคนที่บทบาทเป็น contractor ถ้าไม่มีก็เอาใครก็ได้
  select coalesce(display_name, username) into v_contractor
  from public.contractors
  where role = 'contractor' order by username limit 1;
  if v_contractor is null then
    select coalesce(display_name, username) into v_contractor from public.contractors order by username limit 1;
  end if;
  if v_contractor is null then
    raise exception 'หยุด: ไม่มีผู้ใช้ในตาราง contractors เลย — ทำขั้นที่ 4 ก่อน';
  end if;

  -- อะไหล่: เอาตัวที่มีราคาทั้งสองฝั่ง จะได้ทดสอบยอดเงินได้จริง
  select code_cj, name, brand, model into v_part
  from public.parts
  where coalesce(unit_price, 0) > 0 and coalesce("Unit Custumer", 0) > 0
  order by code_cj limit 1;
  if v_part.code_cj is null then
    select code_cj, name, brand, model into v_part from public.parts order by code_cj limit 1;
  end if;
  if v_part.code_cj is null then
    raise exception 'หยุด: ตาราง parts ว่าง — ทำขั้นที่ 4 ก่อน';
  end if;

  v_parts_text := '1. ' || v_part.code_cj || '-' || coalesce(v_part.name, 'อะไหล่') || ' = 1';
  v_parts_json := jsonb_build_array(jsonb_build_object(
    'no', 1, 'text', v_part.code_cj || '-' || coalesce(v_part.name, 'อะไหล่') || ' = 1',
    'partCode', upper(v_part.code_cj), 'qty', 1, 'billingType', 'normal'));

  -- 5 สาขาที่ "มีเลขทรัพย์สินจริง" อยู่ด้วย (ไม่งั้นทดสอบการจับคู่ทรัพย์สินไม่ได้)
  for v_b in
    select b.branch_code, b.branch_name
    from public.branches b
    where exists (select 1 from public.branch_assets a where a.branch_code = b.branch_code)
    order by b.branch_code
    limit 5
  loop
    v_branches := v_branches || v_b.branch_name;
  end loop;
  if array_length(v_branches, 1) is null then
    raise exception 'หยุด: ไม่มีสาขาไหนมีเลขทรัพย์สินเลย — ทำขั้นที่ 4 บล็อก E ก่อน';
  end if;
  -- มีสาขาไม่ถึง 5 ก็ยังทดสอบได้ — เติมด้วยสาขาแรกซ้ำ ดีกว่าปล่อยให้ช่องสาขาเป็นค่าว่าง
  while array_length(v_branches, 1) < 5 loop
    v_branches := v_branches || v_branches[1];
  end loop;

  -- ตัวช่วยหยิบเลขทรัพย์สินของสาขาหนึ่ง
  -- (เขียนเป็น subquery ซ้ำ ๆ แทนฟังก์ชัน เพื่อให้ไฟล์นี้ไม่ทิ้งอะไรค้างไว้ในฐานข้อมูล)

  -- ================= งานที่ 1: เปิดงานอย่างเดียว (ยังไม่ปิด) =================
  v_job := 'RE-TEST-0001';
  insert into public.re_open_issues
    (main_id, service_type, req_date, service_work, service_issue, branch, details, contract_type, contractor, synced_to_sheet, created_at)
  values (v_job, 'CM', to_char(now() - interval '3 day', 'DD/MM/YYYY') || ', 09:00', 'F10',
          'ตู้แช่ไม่เย็น', v_branches[1], 'ทดสอบ RE: เปิดงานแล้วยังไม่ปิด', 'MA', v_contractor, false,
          now() - interval '3 day');

  -- ================= งานที่ 2: เปิด + ปิด พร้อมอะไหล่ (พร้อมวางบิล) =================
  v_job := 'RE-TEST-0002';
  select asset_no into v_asset from public.branch_assets
   where branch_code = split_part(v_branches[2], '-', 1) order by asset_no limit 1;
  insert into public.re_open_issues
    (main_id, service_type, req_date, service_work, service_issue, branch, details, contract_type, contractor, synced_to_sheet, created_at)
  values (v_job, 'CM', to_char(now() - interval '2 day', 'DD/MM/YYYY') || ', 10:30', 'F10',
          'ขอบยางประตูชำรุด', v_branches[2], 'ทดสอบ RE: ปิดงานแล้ว มีอะไหล่', 'MA', v_contractor, false,
          now() - interval '2 day');
  insert into public.re_close_issues
    (job_id, branch, fix_date, parts, parts_json, asset_id, action_taken, synced_to_sheet, created_at)
  values (v_job, v_branches[2], to_char(now() - interval '1 day', 'DD/MM/YYYY'),
          v_parts_text, v_parts_json, coalesce(v_asset, '-'), 'เปลี่ยนอะไหล่', false, now() - interval '1 day');

  -- ================= งานที่ 3: เปิด + ปิด แบบไม่มีอะไหล่ (ไม่ต้องส่งรูป) =================
  v_job := 'RE-TEST-0003';
  select asset_no into v_asset from public.branch_assets
   where branch_code = split_part(v_branches[3], '-', 1) order by asset_no limit 1;
  insert into public.re_open_issues
    (main_id, service_type, req_date, service_work, service_issue, branch, details, contract_type, contractor, synced_to_sheet, created_at)
  values (v_job, 'CM', to_char(now() - interval '2 day', 'DD/MM/YYYY') || ', 13:00', 'F10',
          'ตรวจเช็คทั่วไป', v_branches[3], 'ทดสอบ RE: ปิดงานแบบไม่มีอะไหล่', 'MA', v_contractor, false,
          now() - interval '2 day');
  insert into public.re_close_issues
    (job_id, branch, fix_date, parts, parts_json, asset_id, action_taken, synced_to_sheet, created_at)
  values (v_job, v_branches[3], to_char(now() - interval '1 day', 'DD/MM/YYYY'),
          '-', '[]'::jsonb, coalesce(v_asset, '-'), 'ตรวจเช็ค ไม่ได้เปลี่ยนอะไหล่', false, now() - interval '1 day');

  -- ================= งานที่ 4: เปิด + พักงาน (รออะไหล่) =================
  v_job := 'RE-TEST-0004';
  insert into public.re_open_issues
    (main_id, service_type, req_date, service_work, service_issue, branch, details, contract_type, contractor, synced_to_sheet, created_at)
  values (v_job, 'CM', to_char(now() - interval '5 day', 'DD/MM/YYYY') || ', 08:00', 'F10',
          'คอมเพรสเซอร์เสีย', v_branches[4], 'ทดสอบ RE: ถูกพักงานอยู่', 'MA', v_contractor, false,
          now() - interval '5 day');
  insert into public.re_pause_records
    (main_id, reason, note, paused_at, paused_by, status, synced_to_sheet, created_at, branch, service_type, cause, requested_item)
  values (v_job, 'รออะไหล่', 'ทดสอบ RE: พักงานรออะไหล่', now() - interval '4 day', 'admin', 'paused', false,
          now() - interval '4 day', v_branches[4], 'CM', 'คอมเพรสเซอร์เสีย', v_part.code_cj);

  -- ================= งานที่ 5: เปิด + ปิด 2 เลขทรัพย์สินในเลขงานเดียว =================
  v_job := 'RE-TEST-0005';
  select asset_no into v_asset  from public.branch_assets
   where branch_code = split_part(v_branches[5], '-', 1) order by asset_no limit 1;
  select asset_no into v_asset2 from public.branch_assets
   where branch_code = split_part(v_branches[5], '-', 1) order by asset_no offset 1 limit 1;
  insert into public.re_open_issues
    (main_id, service_type, req_date, service_work, service_issue, branch, details, contract_type, contractor, synced_to_sheet, created_at)
  values (v_job, 'CM', to_char(now() - interval '2 day', 'DD/MM/YYYY') || ', 15:00', 'F10',
          'ตู้แช่เสีย 2 ตู้', v_branches[5], 'ทดสอบ RE: 1 เลขงาน 2 เลขทรัพย์สิน', 'MA', v_contractor, false,
          now() - interval '2 day');
  insert into public.re_close_issues
    (job_id, branch, fix_date, parts, parts_json, asset_id, action_taken, synced_to_sheet, created_at)
  values (v_job, v_branches[5], to_char(now() - interval '1 day', 'DD/MM/YYYY'),
          v_parts_text, v_parts_json, coalesce(v_asset, '-'), 'เปลี่ยนอะไหล่ ตู้ที่ 1', false, now() - interval '1 day');
  if v_asset2 is not null and v_asset2 <> coalesce(v_asset, '') then
    insert into public.re_close_issues
      (job_id, branch, fix_date, parts, parts_json, asset_id, action_taken, synced_to_sheet, created_at)
    values (v_job, v_branches[5], to_char(now() - interval '1 day', 'DD/MM/YYYY'),
            v_parts_text, v_parts_json, v_asset2, 'เปลี่ยนอะไหล่ ตู้ที่ 2', false, now() - interval '1 day');
  end if;

  raise notice 'สร้างงาน RE ทดสอบเรียบร้อย — ผู้รับเหมา: % · อะไหล่ที่ใช้: %', v_contractor, v_part.code_cj;
end $$;


-- =====================================================================
--  ขั้นที่ 3 — ดูผล
-- =====================================================================
select o.main_id            as "เลขงาน",
       o.branch             as "สาขา",
       o.service_issue      as "อาการ",
       o.contractor         as "ผู้รับเหมา",
       (select count(*) from public.re_close_issues c where c.job_id = o.main_id) as "ปิดงานแล้ว (ทรัพย์สิน)",
       case when exists (select 1 from public.re_pause_records p
                          where p.main_id = o.main_id and p.status = 'paused')
            then 'พักงานอยู่' else '-' end as "พักงาน"
from public.re_open_issues o
where o.main_id like 'RE-TEST-%'
order by o.main_id;

-- ยืนยันว่าไม่มีอะไรหลุดไปฝั่ง CM เลยสักแถว (ทั้ง 3 บรรทัดต้องได้ 0)
select 'งาน RE ที่หลุดไปตาราง CM (ต้องได้ 0)' as "ตรวจ",
       (select count(*) from public.open_issues  where main_id like 'RE-%')::text as "เปิดงาน",
       (select count(*) from public.close_issues where job_id  like 'RE-%')::text as "ปิดงาน",
       (select count(*) from public.pause_records where main_id like 'RE-%')::text as "พักงาน";


-- =====================================================================
--  ล้างข้อมูลทดสอบทิ้ง (รันเมื่อไหร่ก็ได้ ไม่แตะงานอื่นเลย)
-- =====================================================================
--  delete from public.re_pause_records  where main_id like 'RE-TEST-%';
--  delete from public.re_close_issues   where job_id  like 'RE-TEST-%';
--  delete from public.re_open_issues    where main_id like 'RE-TEST-%';
