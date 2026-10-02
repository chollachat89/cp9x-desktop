-- =====================================================================
--  v1.0.95 — ปุ่ม "คืนงาน" ในตารางวางบิล (ตัดงานออกจากระบบวางบิล)
-- =====================================================================
--
--  ใช้ตอนไหน: งานที่ถูกดึงเข้ารอบบิลไปแล้ว แต่ไม่ควรวางบิล
--             เช่น ดึงผิดเลขงาน · ข้อมูลผิดทั้งชุด · งานซ้ำ · ไม่เก็บเงินงานนี้
--
--  ⚠ ทำไมต้องมีฟังก์ชัน ไม่ใช้ปุ่ม "ลบ" ที่มีอยู่แล้ว
--  ---------------------------------------------------------------
--  ปุ่ม "ลบ" เดิมลบแค่ "แถวเดียว" ใน billing_documents และ "ไม่แตะคีย์จองรอบบิล"
--  ผลคือเลขงานนั้นค้างอยู่ในทะเบียนจองตลอดไป = ดึงเข้ารอบบิลใหม่ไม่ได้อีกเลย
--  โดยไม่มีอะไรเตือน (เป็นต้นเหตุเดียวกับที่เคยไล่ตามว่า "ทำไมเลขงานนี้ดึงไม่ขึ้น")
--
--  "คืนงาน" จึงทำให้ครบวง และ "ตั้งใจ" ให้ไม่กลับเข้ามาอีก:
--    1. เก็บสำเนาแถวที่จะตัดไว้ก่อนทั้งหมด (กู้คืนได้ถ้ากดผิด)
--    2. ลบแถวของงานนั้นออกจากตารางวางบิล
--    3. "คง" คีย์จองไว้ตามเดิม = ระบบจะไม่ดึงงานนี้เข้ารอบบิลอีก (ตามที่สั่ง "ตัดออกจากระบบไปเลย")
--    4. บันทึกเหตุผล + คนกด และแจ้งผู้รับเหมาถ้าเคยส่งบิลไปแล้ว
--  ทุกขั้นอยู่ใน transaction เดียว — สำเร็จทั้งหมด หรือไม่แก้อะไรเลย
--
--  ⚠ แถวที่ "ตัดบิลแล้ว" (completed_at) คืนงานไม่ได้ เพราะเป็นหลักฐานทางการเงินที่จบไปแล้ว
--     ถ้าจำเป็นต้องแก้จริง ให้ใช้ปุ่ม "ย้อนสถานะ" ก่อน แล้วค่อยคืนงาน
--
--  ข้อผิดพลาดที่ตั้งใจโยน ขึ้นต้นด้วย "CP9X:" เสมอ (เซิร์ฟเวอร์ตัดคำนี้ออกแล้วส่งข้อความไทยให้ผู้ใช้)
-- =====================================================================


-- ---------------------------------------------------------------------
--  1. ที่เก็บงานที่ถูกคืน  (สำเนาเต็มของทุกแถวที่ตัดออก)
-- ---------------------------------------------------------------------
--  เก็บทั้งแถวเป็น jsonb ไม่แยกคอลัมน์ เพราะ billing_documents มีคอลัมน์เยอะและเพิ่มได้เรื่อย ๆ
--  ถ้าแยกคอลัมน์ไว้ พอวันหนึ่งเพิ่มคอลัมน์ใหม่แล้วลืมมาแก้ที่นี่ สำเนาจะขาดข้อมูลเงียบ ๆ
create table if not exists public.billing_removed_jobs (
  id             bigint generated always as identity primary key,
  job_id         text not null,
  asset_id       text not null default '',
  round_no       integer,
  contractor     text,
  reason         text not null,
  removed_by     text not null,
  removed_at     timestamptz not null default now(),
  rows_removed   integer not null default 0,
  was_sent       boolean not null default false,
  rows_backup    jsonb not null               -- สำเนาเต็มของทุกแถวที่ตัดออก ใช้กู้คืนได้
);

create index if not exists billing_removed_jobs_job_idx
  on public.billing_removed_jobs (job_id, asset_id, removed_at desc);

comment on table public.billing_removed_jobs is
  'งานที่ถูกกด "คืนงาน" ออกจากตารางวางบิล (v1.0.95) — rows_backup เก็บสำเนาเต็มไว้กู้คืนได้';

alter table public.billing_removed_jobs enable row level security;
revoke all on public.billing_removed_jobs from anon, authenticated;


-- ---------------------------------------------------------------------
--  2. ฟังก์ชันคืนงาน
-- ---------------------------------------------------------------------
create or replace function public.remove_billing_job(
  p_job_id    text,
  p_asset_id  text,
  p_round_no  integer,
  p_reason    text,
  p_by        text
)
returns jsonb
language plpgsql
set search_path = public
as $fn$
declare
  v_job     text := btrim(coalesce(p_job_id, ''));
  v_asset   text := btrim(coalesce(p_asset_id, ''));
  v_reason  text := btrim(coalesce(p_reason, ''));
  v_by      text := btrim(coalesce(p_by, ''));
  v_rows    jsonb;
  v_count   integer := 0;
  v_sent    integer := 0;
  v_done    integer := 0;
  v_contr   text;
  v_comments integer := 0;
  v_msg     text;
begin
  if v_job = ''    then raise exception 'CP9X:ไม่ได้ระบุเลขงาน'; end if;
  if v_reason = '' then raise exception 'CP9X:กรุณาระบุเหตุผลที่คืนงาน'; end if;
  if v_by = ''     then raise exception 'CP9X:ไม่ทราบชื่อผู้ทำรายการ'; end if;

  -- ล็อกแถวที่จะตัด กันแอดมิน 2 คนกดงานเดียวกันพร้อมกัน
  perform 1 from billing_documents
  where customer_case = v_job
    and coalesce(asset_id, '') = v_asset
    and (p_round_no is null or round_no is not distinct from p_round_no)
  for update;

  select count(*),
         count(*) filter (where sent_to_contractor is true),
         count(*) filter (where completed_at is not null),
         max(contractor)
    into v_count, v_sent, v_done, v_contr
  from billing_documents
  where customer_case = v_job
    and coalesce(asset_id, '') = v_asset
    and (p_round_no is null or round_no is not distinct from p_round_no);

  if v_count = 0 then
    raise exception 'CP9X:ไม่พบแถวของเลขงาน % ในตารางวางบิล (อาจถูกคืนไปแล้ว ลองโหลดหน้าใหม่)', v_job;
  end if;

  -- ตัดบิลแล้ว = หลักฐานทางการเงินที่จบไปแล้ว ห้ามคืน
  if v_done > 0 then
    raise exception 'CP9X:งานนี้ตัดบิลไปแล้ว % แถว คืนงานไม่ได้ — ถ้าจำเป็นต้องแก้ ให้กด "ย้อนสถานะ" ก่อน แล้วค่อยคืนงาน', v_done;
  end if;

  -- ---------- 1) เก็บสำเนาเต็มไว้ก่อนลบ ----------
  select coalesce(jsonb_agg(to_jsonb(b)), '[]'::jsonb) into v_rows
  from billing_documents b
  where b.customer_case = v_job
    and coalesce(b.asset_id, '') = v_asset
    and (p_round_no is null or b.round_no is not distinct from p_round_no);

  -- ---------- 2) แจ้งผู้รับเหมา (ทำก่อนลบ เพราะต้องอ้าง id ของแถว) ----------
  if v_sent > 0 and to_regclass('public.billing_row_comments') is not null then
    v_msg := 'บริษัทคืนงานนี้ออกจากรอบบิล' || E'\nเหตุผล: ' || v_reason;
    insert into billing_row_comments (billing_id, customer_case, revision_no, author_role, author_name, action, message)
    select b.id::text, b.customer_case, b.revision_no, 'admin', v_by, 'job_removed', v_msg
    from billing_documents b
    where b.customer_case = v_job
      and coalesce(b.asset_id, '') = v_asset
      and (p_round_no is null or b.round_no is not distinct from p_round_no)
      and b.sent_to_contractor is true;
    get diagnostics v_comments = row_count;
  end if;

  -- ---------- 3) บันทึกประวัติ ----------
  insert into billing_removed_jobs (job_id, asset_id, round_no, contractor, reason, removed_by, rows_removed, was_sent, rows_backup)
  values (v_job, v_asset, p_round_no, v_contr, v_reason, v_by, v_count, v_sent > 0, v_rows);

  -- ---------- 4) ตัดแถวออกจากตารางวางบิล ----------
  delete from billing_documents
  where customer_case = v_job
    and coalesce(asset_id, '') = v_asset
    and (p_round_no is null or round_no is not distinct from p_round_no);

  -- ---------- 5) คีย์จองรอบบิล: "คงไว้" โดยตั้งใจ ----------
  --  ไม่ลบคีย์จอง = ระบบจะไม่ดึงงานนี้เข้ารอบบิลอีก ตรงกับความหมายของ "ตัดออกจากระบบไปเลย"
  --  ถ้าวันหลังอยากให้กลับเข้ามาได้ ต้องลบคีย์จองเองด้วยคำสั่งท้ายไฟล์นี้
  --  (เขียนเป็นคอมเมนต์ไว้เพื่อให้คนอ่านโค้ดรู้ว่า "ไม่ลบ" เป็นความตั้งใจ ไม่ใช่ลืม)

  return jsonb_build_object(
    'job_id', v_job, 'asset_id', v_asset, 'round_no', p_round_no,
    'rows_removed', v_count, 'was_sent', v_sent > 0, 'comments', v_comments,
    'contractor', coalesce(v_contr, '')
  );
end;
$fn$;

revoke execute on function public.remove_billing_job(text, text, integer, text, text) from public, anon, authenticated;
grant  execute on function public.remove_billing_job(text, text, integer, text, text) to service_role;


-- ---------------------------------------------------------------------
--  3. ฟังก์ชันกู้คืนงานที่คืนไปแล้ว (เผื่อกดผิด)
-- ---------------------------------------------------------------------
create or replace function public.restore_removed_billing_job(p_removed_id bigint, p_by text)
returns jsonb
language plpgsql
set search_path = public
as $fn$
declare
  v_rec   record;
  v_count integer := 0;
begin
  select * into v_rec from billing_removed_jobs where id = p_removed_id for update;
  if v_rec is null then raise exception 'CP9X:ไม่พบรายการคืนงานหมายเลข %', p_removed_id; end if;

  -- มีแถวของงานนี้อยู่ในตารางวางบิลแล้ว = เคยถูกดึงกลับเข้าไปใหม่ ห้ามใส่ซ้ำ
  if exists (select 1 from billing_documents
             where customer_case = v_rec.job_id and coalesce(asset_id,'') = v_rec.asset_id) then
    raise exception 'CP9X:เลขงาน % มีแถวอยู่ในตารางวางบิลแล้ว กู้คืนซ้ำไม่ได้', v_rec.job_id;
  end if;

  insert into billing_documents
  select * from jsonb_populate_recordset(null::billing_documents, v_rec.rows_backup);
  get diagnostics v_count = row_count;

  delete from billing_removed_jobs where id = p_removed_id;

  return jsonb_build_object('job_id', v_rec.job_id, 'asset_id', v_rec.asset_id, 'rows_restored', v_count, 'by', p_by);
end;
$fn$;

revoke execute on function public.restore_removed_billing_job(bigint, text) from public, anon, authenticated;
grant  execute on function public.restore_removed_billing_job(bigint, text) to service_role;


-- ---------------------------------------------------------------------
--  ตรวจผล
-- ---------------------------------------------------------------------
select
  (select count(*) from information_schema.tables
    where table_schema = 'public' and table_name = 'billing_removed_jobs')  as "ตาราง billing_removed_jobs (ต้องได้ 1)",
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'remove_billing_job')        as "ฟังก์ชันคืนงาน (ต้องได้ 1)",
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'restore_removed_billing_job') as "ฟังก์ชันกู้คืน (ต้องได้ 1)";


-- ---------------------------------------------------------------------
--  อยากให้งานที่คืนไปแล้วกลับเข้ารอบบิลได้อีก (ไม่ใช่พฤติกรรมปกติ)
-- ---------------------------------------------------------------------
--  ต้องลบคีย์จองออกเองด้วย ไม่งั้นระบบจะยังไม่ดึงเข้ารอบให้
--
--  delete from billing_job_registry
--  where customer_case = 'CM20260101-0001'
--     or customer_case = 'CM20260101-0001__asset__130021005807';
