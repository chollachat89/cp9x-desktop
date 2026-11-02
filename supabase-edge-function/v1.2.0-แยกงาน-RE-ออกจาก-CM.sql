-- =====================================================================
--  v1.2.0 — แยกงาน RE ออกจากงาน CM แบบคนละตาราง
-- =====================================================================
--
--  ทำอะไร: สร้าง "ตารางชุด RE" ขึ้นมาใหม่ทั้งชุด คู่ขนานกับตารางชุด CM เดิม
--          งานที่เปิดด้วยเลข RE จะถูกเก็บในตารางชุดนี้เท่านั้น ไม่ปนกับ CM เลยสักแถว
--
--  ⚠ ไฟล์นี้ "ไม่แตะตารางเดิมสักตาราง" — สร้างของใหม่ล้วน
--     ถ้ารันแล้วไม่ถูกใจ ลบตารางชุด RE ทิ้งได้เลย ระบบ CM เดิมไม่กระทบอะไรทั้งสิ้น
--
--  ⚠ รันในโปรเจกต์ maintenance-system (hefnjozijflnhdunmewl) เท่านั้น
--     หรือโปรเจกต์ทดสอบ ถ้าจะลองก่อน
--
--  ***ขั้นที่ 1 อ่านอย่างเดียว ไม่แก้อะไร — รันดูก่อนทุกครั้ง***
--
-- ---------------------------------------------------------------------
--  ทำไมใช้ "create table (like ... including all)" ไม่เขียนคอลัมน์เอง
-- ---------------------------------------------------------------------
--  เพราะเขียนเองแปลว่าต้อง "เดา" ว่าตารางจริงมีคอลัมน์อะไรบ้าง ชนิดอะไร ค่า default อะไร
--  เดาพลาดแม้ช่องเดียว = ข้อมูลเพี้ยนแบบเงียบ ๆ ไปอีกนาน
--  including all คัดลอกให้ครบเอง: คอลัมน์ · ชนิด · default · not null · index · unique · primary key
--  แปลว่าโครงตาราง RE "ตรงกับ CM เป๊ะ ๆ เสมอ" โดยไม่ต้องรู้ว่าตารางจริงหน้าตายังไง
--
--  ของที่ including all ไม่คัดลอกให้ และไฟล์นี้ทำเพิ่มเอง: RLS · สิทธิ์ · ฟังก์ชัน (RPC)
--
-- ---------------------------------------------------------------------
--  ตารางที่ "ไม่แยก" โดยตั้งใจ (ใช้ร่วมกันทั้ง CM และ RE)
-- ---------------------------------------------------------------------
--  branches · branch_assets · parts · contractors · asset_warranty · app_secrets
--  เพราะเป็นข้อมูลหลักที่ใช้ร่วมกัน (สาขา ทรัพย์สิน อะไหล่ ผู้ใช้ ราคา)
--  ถ้าแยกด้วยจะกลายเป็นต้องอัปเดตราคาอะไหล่สองที่ทุกครั้ง = พลาดแน่นอนสักวัน
-- =====================================================================


-- =====================================================================
--  ขั้นที่ 1 — ตรวจก่อน (อ่านอย่างเดียว ปลอดภัย)
-- =====================================================================
--  ต้องเห็นครบทุกบรรทัดเป็น "มี" ก่อนถึงจะรันขั้นที่ 2 ได้
select t.ตาราง,
       case when to_regclass('public.' || t.ตาราง) is null then '✗ ไม่พบ — หยุด อย่ารันขั้นที่ 2'
            else '✓ มี' end as ต้นแบบ,
       case when to_regclass('public.re_' || t.ตาราง) is not null then '⚠ มีตาราง RE อยู่แล้ว (เคยรันไปแล้ว)'
            else 'ยังไม่มี — จะถูกสร้าง' end as ปลายทาง
from (values ('open_issues'), ('close_issues'), ('billing_documents'),
             ('billing_job_registry'), ('billing_removed_jobs'),
             ('billing_row_comments'), ('pause_records')) as t(ตาราง);


-- =====================================================================
--  ขั้นที่ 2 — สร้างตารางชุด RE  (รันซ้ำได้ ไม่พัง)
-- =====================================================================
create table if not exists public.re_open_issues          (like public.open_issues          including all);
create table if not exists public.re_close_issues         (like public.close_issues         including all);
create table if not exists public.re_billing_documents    (like public.billing_documents    including all);
create table if not exists public.re_billing_job_registry (like public.billing_job_registry including all);
create table if not exists public.re_billing_removed_jobs (like public.billing_removed_jobs including all);
create table if not exists public.re_billing_row_comments (like public.billing_row_comments including all);
create table if not exists public.re_pause_records        (like public.pause_records        including all);

-- กฎห้ามจองเลขงานซ้ำ — ฟังก์ชันจองรอบบิล (ข้อ 4.2) พึ่งกฎนี้ในการกันแอดมิน 2 คนกดพร้อมกัน
-- สร้างตรง ๆ ไม่พึ่งว่าตารางต้นแบบมีให้ copy มาหรือเปล่า (ตรวจจากที่นี่ไม่ได้ว่ามี)
create unique index if not exists re_billing_job_registry_case_uniq
  on public.re_billing_job_registry (customer_case);

comment on table public.re_open_issues          is 'งาน RE — เปิดงาน (v1.2.0) แยกจาก open_issues คนละตาราง';
comment on table public.re_close_issues         is 'งาน RE — ปิดงาน (v1.2.0) แยกจาก close_issues คนละตาราง';
comment on table public.re_billing_documents    is 'งาน RE — ตารางวางบิล (v1.2.0) รอบบิลแยกจาก CM คนละชุดเลข';
comment on table public.re_billing_job_registry is 'งาน RE — ทะเบียนจองรอบบิล (v1.2.0)';
comment on table public.re_billing_removed_jobs is 'งาน RE — งานที่ถูกคืนออกจากบิล (v1.2.0)';
comment on table public.re_billing_row_comments is 'งาน RE — บันทึกโต้ตอบ ผรม./แอดมิน ในบิล (v1.2.0)';
comment on table public.re_pause_records        is 'งาน RE — พักงาน (v1.2.0)';


-- =====================================================================
--  ขั้นที่ 3 — ความปลอดภัย: เปิด RLS และไม่ใส่ policy (เหมือนตารางเดิมทุกตาราง)
--             = ฝั่งแอป (anon/authenticated) อ่านตรงไม่ได้ ต้องผ่าน Edge Function เท่านั้น
-- =====================================================================
do $$
declare t text;
begin
  foreach t in array array['re_open_issues','re_close_issues','re_billing_documents',
                           're_billing_job_registry','re_billing_removed_jobs',
                           're_billing_row_comments','re_pause_records']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;


-- =====================================================================
--  ขั้นที่ 4 — ฟังก์ชันรอบบิลของฝั่ง RE  (คนละชุดเลขรอบกับ CM)
-- =====================================================================

-- ---------------------------------------------------------------------
--  4.1 ขอเลขรอบบิลถัดไปของฝั่ง RE
--      เริ่มนับ 1 ใหม่ ไม่ต่อจากเลขรอบของ CM (คนละระบบ คนละชุดเลข ตามที่สั่ง)
-- ---------------------------------------------------------------------
create or replace function public.next_re_billing_round_no()
returns integer
language plpgsql
set search_path = public
as $fn$
declare v_next integer;
begin
  -- ล็อกทั้งตารางกันแอดมิน 2 คนขอเลขรอบพร้อมกันแล้วได้เลขเดียวกัน
  lock table public.re_billing_job_registry in exclusive mode;
  -- ดูทั้ง "ตารางบิล" และ "ทะเบียนจอง" — เพราะตอนขอเลขรอบ ยังไม่มีแถวในตารางบิลเลยสักแถว
  -- ถ้าดูแค่ตารางบิล แอดมินคนที่ 2 ที่กดตามมาติด ๆ จะได้เลขรอบเดียวกัน แล้วงานสองชุดจะปนเป็นรอบเดียว
  select greatest(
           coalesce((select max(round_no) from public.re_billing_documents), 0),
           coalesce((select max(round_no) from public.re_billing_job_registry), 0)
         ) + 1 into v_next;
  return v_next;
end;
$fn$;

revoke execute on function public.next_re_billing_round_no() from public, anon, authenticated;
grant  execute on function public.next_re_billing_round_no() to service_role;


-- ---------------------------------------------------------------------
--  4.2 จองเลขงาน RE เข้ารอบบิล (กันแอดมิน 2 คนดึงงานเดียวกันพร้อมกัน)
--      คืนเฉพาะ "คีย์ที่จองได้จริงรอบนี้" — คีย์ที่คนอื่นจองไปแล้วจะไม่ถูกคืนกลับมา
--      สัญญาเดียวกับ claim_billing_jobs ของฝั่ง CM เป๊ะ ๆ (เซิร์ฟเวอร์ใช้โค้ดชุดเดียวกัน)
-- ---------------------------------------------------------------------
create or replace function public.claim_re_billing_jobs(job_ids text[], p_round_no integer)
returns table (customer_case text, round_no integer)
language plpgsql
set search_path = public
as $fn$
-- ชื่อคอลัมน์ที่คืนออกไป (customer_case, round_no) ชนกับชื่อคอลัมน์ในตารางพอดี
-- บรรทัดนี้สั่งให้ถือว่าเป็น "คอลัมน์ของตาราง" เสมอ ไม่งั้น Postgres ปฏิเสธว่ากำกวม
#variable_conflict use_column
begin
  return query
  insert into public.re_billing_job_registry (customer_case, round_no, claimed_at)
  select unnest(job_ids), p_round_no, now()
  on conflict (customer_case) do nothing
  returning re_billing_job_registry.customer_case, re_billing_job_registry.round_no;
end;
$fn$;

revoke execute on function public.claim_re_billing_jobs(text[], integer) from public, anon, authenticated;
grant  execute on function public.claim_re_billing_jobs(text[], integer) to service_role;


-- ---------------------------------------------------------------------
--  4.3 คืนงาน RE ออกจากรอบบิล — ตรรกะเดียวกับ remove_billing_job ของฝั่ง CM ทุกข้อ
--      (เก็บสำเนาก่อนลบ · ห้ามคืนงานที่ตัดบิลแล้ว · คงคีย์จองไว้ · แจ้ง ผรม. ถ้าส่งไปแล้ว)
-- ---------------------------------------------------------------------
create or replace function public.remove_re_billing_job(
  p_job_id text, p_asset_id text, p_round_no integer, p_reason text, p_by text)
returns jsonb
language plpgsql
set search_path = public
as $fn$
declare
  v_job   text := btrim(coalesce(p_job_id, ''));
  v_asset text := btrim(coalesce(p_asset_id, ''));
  v_reason text := btrim(coalesce(p_reason, ''));
  v_by    text := btrim(coalesce(p_by, ''));
  v_rows  jsonb;
  v_count integer := 0;
  v_sent  integer := 0;
  v_done  integer := 0;
  v_contr text;
  v_comments integer := 0;
  v_msg   text;
begin
  if v_job = ''    then raise exception 'CP9X:ไม่ได้ระบุเลขงาน'; end if;
  if v_reason = '' then raise exception 'CP9X:กรุณาระบุเหตุผลที่คืนงาน'; end if;
  if v_by = ''     then raise exception 'CP9X:ไม่ทราบชื่อผู้ทำรายการ'; end if;

  perform 1 from public.re_billing_documents
  where customer_case = v_job
    and coalesce(asset_id, '') = v_asset
    and (p_round_no is null or round_no is not distinct from p_round_no)
  for update;

  select count(*),
         count(*) filter (where sent_to_contractor is true),
         count(*) filter (where completed_at is not null),
         max(contractor)
    into v_count, v_sent, v_done, v_contr
  from public.re_billing_documents
  where customer_case = v_job
    and coalesce(asset_id, '') = v_asset
    and (p_round_no is null or round_no is not distinct from p_round_no);

  if v_count = 0 then
    raise exception 'CP9X:ไม่พบแถวของเลขงาน % ในตารางวางบิล RE (อาจถูกคืนไปแล้ว ลองโหลดหน้าใหม่)', v_job;
  end if;
  if v_done > 0 then
    raise exception 'CP9X:งานนี้ตัดบิลไปแล้ว % แถว คืนงานไม่ได้ — ถ้าจำเป็นต้องแก้ ให้กด "ย้อนสถานะ" ก่อน แล้วค่อยคืนงาน', v_done;
  end if;

  select coalesce(jsonb_agg(to_jsonb(b)), '[]'::jsonb) into v_rows
  from public.re_billing_documents b
  where b.customer_case = v_job
    and coalesce(b.asset_id, '') = v_asset
    and (p_round_no is null or b.round_no is not distinct from p_round_no);

  if v_sent > 0 and to_regclass('public.re_billing_row_comments') is not null then
    v_msg := 'บริษัทคืนงานนี้ออกจากรอบบิล' || E'\nเหตุผล: ' || v_reason;
    insert into public.re_billing_row_comments
      (billing_id, customer_case, revision_no, author_role, author_name, action, message)
    select b.id::text, b.customer_case, b.revision_no, 'admin', v_by, 'job_removed', v_msg
    from public.re_billing_documents b
    where b.customer_case = v_job
      and coalesce(b.asset_id, '') = v_asset
      and (p_round_no is null or b.round_no is not distinct from p_round_no)
      and b.sent_to_contractor is true;
    get diagnostics v_comments = row_count;
  end if;

  insert into public.re_billing_removed_jobs
    (job_id, asset_id, round_no, contractor, reason, removed_by, rows_removed, was_sent, rows_backup)
  values (v_job, v_asset, p_round_no, v_contr, v_reason, v_by, v_count, v_sent > 0, v_rows);

  delete from public.re_billing_documents
  where customer_case = v_job
    and coalesce(asset_id, '') = v_asset
    and (p_round_no is null or round_no is not distinct from p_round_no);

  -- คีย์จองรอบบิล: "คงไว้" โดยตั้งใจ เหมือนฝั่ง CM (งานที่คืนแล้วจะไม่ถูกดึงกลับเข้ารอบอีก)
  return jsonb_build_object(
    'job_id', v_job, 'asset_id', v_asset, 'round_no', p_round_no,
    'rows_removed', v_count, 'was_sent', v_sent > 0, 'comments', v_comments,
    'contractor', coalesce(v_contr, ''));
end;
$fn$;

revoke execute on function public.remove_re_billing_job(text, text, integer, text, text) from public, anon, authenticated;
grant  execute on function public.remove_re_billing_job(text, text, integer, text, text) to service_role;


-- ---------------------------------------------------------------------
--  4.4 กู้คืนงาน RE ที่คืนไปแล้ว (เผื่อกดผิด)
-- ---------------------------------------------------------------------
create or replace function public.restore_removed_re_billing_job(p_removed_id bigint, p_by text)
returns jsonb
language plpgsql
set search_path = public
as $fn$
declare
  v_rec   record;
  v_count integer := 0;
begin
  select * into v_rec from public.re_billing_removed_jobs where id = p_removed_id for update;
  if v_rec is null then raise exception 'CP9X:ไม่พบรายการคืนงานหมายเลข %', p_removed_id; end if;

  if exists (select 1 from public.re_billing_documents
             where customer_case = v_rec.job_id and coalesce(asset_id,'') = v_rec.asset_id) then
    raise exception 'CP9X:เลขงาน % มีแถวอยู่ในตารางวางบิลแล้ว กู้คืนซ้ำไม่ได้', v_rec.job_id;
  end if;

  insert into public.re_billing_documents
  select * from jsonb_populate_recordset(null::public.re_billing_documents, v_rec.rows_backup);
  get diagnostics v_count = row_count;

  delete from public.re_billing_removed_jobs where id = p_removed_id;

  return jsonb_build_object('job_id', v_rec.job_id, 'asset_id', v_rec.asset_id,
                            'rows_restored', v_count, 'by', p_by);
end;
$fn$;

revoke execute on function public.restore_removed_re_billing_job(bigint, text) from public, anon, authenticated;
grant  execute on function public.restore_removed_re_billing_job(bigint, text) to service_role;


-- =====================================================================
--  ขั้นที่ 5 — ตรวจผล (ต้องได้ "✓ ครบ" ทุกบรรทัด)
-- =====================================================================
select 'ตารางชุด RE (ต้องได้ 7)' as รายการ,
       count(*)::text || ' / 7' as ผล,
       case when count(*) = 7 then '✓ ครบ' else '✗ ขาด' end as สรุป
from information_schema.tables
where table_schema = 'public' and table_name like 're\_%'
union all
select 'ฟังก์ชันฝั่ง RE (ต้องได้ 4)',
       count(*)::text || ' / 4',
       case when count(*) = 4 then '✓ ครบ' else '✗ ขาด' end
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('next_re_billing_round_no','claim_re_billing_jobs',
                    'remove_re_billing_job','restore_removed_re_billing_job')
union all
select 'ตาราง RE ที่เปิด RLS แล้ว (ต้องได้ 7)',
       count(*)::text || ' / 7',
       case when count(*) = 7 then '✓ ครบ' else '✗ ขาด' end
from pg_tables
where schemaname = 'public' and tablename like 're\_%' and rowsecurity = true
union all
-- โครงตาราง RE ต้องมีจำนวนคอลัมน์เท่าต้นแบบเป๊ะ ๆ ทุกคู่
select 'โครงตารางตรงกับต้นแบบ',
       count(*) filter (where n_re = n_cm)::text || ' / ' || count(*)::text,
       case when count(*) filter (where n_re = n_cm) = count(*) then '✓ ตรง' else '✗ ไม่ตรง' end
from (
  select c.relname,
         (select count(*) from information_schema.columns
           where table_schema='public' and table_name = c.relname) as n_re,
         (select count(*) from information_schema.columns
           where table_schema='public' and table_name = substring(c.relname from 4)) as n_cm
  from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
  where ns.nspname='public' and c.relkind='r' and c.relname like 're\_%'
) x;


-- =====================================================================
--  ถ้าอยากยกเลิกทั้งหมด (ลบตารางชุด RE ทิ้ง) — ระบบ CM เดิมไม่กระทบ
-- =====================================================================
--  drop table if exists public.re_pause_records,
--    public.re_billing_row_comments, public.re_billing_removed_jobs,
--    public.re_billing_job_registry, public.re_billing_documents,
--    public.re_close_issues, public.re_open_issues cascade;
--  drop function if exists public.next_re_billing_round_no();
--  drop function if exists public.claim_re_billing_jobs(text[], integer);
--  drop function if exists public.remove_re_billing_job(text, text, integer, text, text);
--  drop function if exists public.restore_removed_re_billing_job(bigint, text);
