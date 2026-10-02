-- =====================================================================
--  v1.0.93 — แก้เลขทรัพย์สินที่กรอกผิด (แก้ 3 ที่พร้อมกัน ไม่ให้เก็บเงินซ้ำ)
-- =====================================================================
--
--  รันหลัง v1.0.69 เสมอ (เรียงตามเลขเวอร์ชัน) · รันซ้ำได้ ไม่พัง
--
--  ---------------------------------------------------------------
--  ทำไมต้องมีฟังก์ชันในฐานข้อมูล ไม่ใช่แก้ทีละตารางจากเซิร์ฟเวอร์
--  ---------------------------------------------------------------
--  เลขทรัพย์สินของงานหนึ่งอยู่ 3 ที่: close_issues · billing_documents · billing_job_registry
--  ระบบใช้ "เลขงาน + เลขทรัพย์สิน" จำว่างานไหนออกบิลไปแล้ว
--
--  ถ้าแก้ไม่ครบทั้ง 3 ที่ (เช่น แก้แค่ปิดงาน) ระบบจะเห็นคู่ "เลขงาน + เลขใหม่" เป็นงานที่ไม่เคยออกบิล
--  แล้วดึงเข้ารอบบิลถัดไปอีกรอบ = เก็บเงินงานเดียวกันซ้ำ 2 ครั้ง โดยไม่มี error ให้เห็น
--
--  ฟังก์ชันในฐานข้อมูลทำงานใน transaction เดียว = "สำเร็จทั้งหมด หรือไม่แก้อะไรเลย"
--  ถ้าพังกลางทาง (เน็ตหลุด / ข้อมูลชน) ทุกอย่างย้อนกลับเอง ไม่มีทางค้างครึ่ง ๆ กลาง ๆ
--  ทำจากเซิร์ฟเวอร์ทีละตารางทำแบบนี้ไม่ได้ (Supabase client ไม่มี transaction)
--
--  ---------------------------------------------------------------
--  แก้อะไรบ้าง
--  ---------------------------------------------------------------
--   1. close_issues.asset_id                    แถวปิดงานของเลขทรัพย์สินนั้น
--   2. billing_documents.asset_id               ทุกแถวบิลของเลขงาน + เลขเดิม (ทุกสถานะ รวมตัดบิลแล้ว)
--   3. billing_job_registry (คีย์จองรอบบิล)     ย้ายคีย์ไปเลขใหม่
--        ⚠ ถ้างานนี้ออกบิลไปแล้วแต่ไม่มีคีย์จองแบบมีเลขทรัพย์สิน (งานเก่า หรือเพิ่มด้วยกล่อง
--          "เพิ่มเลขงานเข้ารอบบิล") ต้อง "เพิ่ม" คีย์ให้เลขใหม่ — ตอนกดยืนยันสร้างรอบบิล
--          ระบบดูแค่ทะเบียนจองอย่างเดียว ถ้าไม่มีคีย์ งานนี้จะถูกดึงซ้ำ
--   4. sla_notifications (ถ้ามีตาราง)           ย้ายประวัติแจ้งเตือนไปเลขใหม่ กันแจ้ง Telegram ซ้ำ
--   5. billing_row_comments (ถ้าบิลส่งผู้รับเหมาแล้ว)  เพิ่มคอมเมนต์ให้ผู้รับเหมาเห็นว่าแก้อะไร
--   6. asset_change_log                         บันทึกประวัติ ใคร/เมื่อไร/เลขเดิม/เลขใหม่/เหตุผล
--
--  ไม่แตะ: ยอดเงิน · จำนวนเดือนประกัน (มาจากตารางอะไหล่) · ไฟล์ฟอร์มรูปที่ส่งมาแล้ว
--
--  เรียกได้เฉพาะเซิร์ฟเวอร์ (service_role) — ปิดสิทธิ์ anon ไว้ท้ายไฟล์
-- =====================================================================


-- ---------------------------------------------------------------------
--  1. ตารางประวัติการแก้เลขทรัพย์สิน
-- ---------------------------------------------------------------------
create table if not exists public.asset_change_log (
  id               bigint generated always as identity primary key,
  job_id           text not null,
  old_asset_id     text not null,
  new_asset_id     text not null,
  reason           text not null,
  changed_by       text not null,
  changed_at       timestamptz not null default now(),
  billing_rows     integer not null default 0,   -- แถวบิลที่ถูกแก้ตามไปด้วย
  billing_state    text,                         -- สถานะบิลตอนแก้ (ยังไม่เข้ารอบ / ยังไม่ส่ง / ส่งแล้ว / ตัดบิลแล้ว)
  registry_action  text                          -- ทำอะไรกับคีย์จองรอบบิล
);
create index if not exists asset_change_log_job_idx on public.asset_change_log (job_id, changed_at desc);

comment on table public.asset_change_log is
  'ประวัติการแก้เลขทรัพย์สิน (v1.0.93) — แก้ผ่านฟังก์ชัน change_asset_number เท่านั้น';

-- ข้อมูลภายใน: เซิร์ฟเวอร์อ่าน/เขียนได้ (service_role ข้าม RLS) คนนอกอ่านไม่ได้
alter table public.asset_change_log enable row level security;
revoke all on public.asset_change_log from anon, authenticated;


-- ---------------------------------------------------------------------
--  2. ฟังก์ชันแก้เลขทรัพย์สิน — ทุกขั้นอยู่ใน transaction เดียว
-- ---------------------------------------------------------------------
--  ข้อผิดพลาดที่ตั้งใจโยน ขึ้นต้นด้วย "CP9X:" เสมอ
--  เซิร์ฟเวอร์ตัดคำนี้ออกแล้วส่งข้อความไทยที่เหลือให้ผู้ใช้เห็นตรง ๆ

create or replace function public.change_asset_number(
  p_job_id     text,
  p_old_asset  text,
  p_new_asset  text,
  p_reason     text,
  p_changed_by text
)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_job       text := btrim(coalesce(p_job_id, ''));
  v_old       text := btrim(coalesce(p_old_asset, ''));
  v_new       text := btrim(coalesce(p_new_asset, ''));
  v_reason    text := btrim(coalesce(p_reason, ''));
  v_by        text := btrim(coalesce(p_changed_by, ''));
  v_close_id  uuid;
  v_total     integer := 0;
  v_sent      integer := 0;
  v_done      integer := 0;
  v_round     integer;
  v_state     text;
  v_reg       text := 'ไม่เกี่ยว (ยังไม่เข้ารอบบิล)';
  v_old_key   text;
  v_new_key   text;
  v_comments  integer := 0;
  v_msg       text;
begin
  -- ---------- ตรวจค่าที่ส่งมา ----------
  if v_job = '' then raise exception 'CP9X:ไม่ได้ระบุเลขงาน'; end if;
  if v_old = '' then raise exception 'CP9X:ไม่ได้ระบุเลขทรัพย์สินเดิม'; end if;
  if v_new !~ '^[0-9]{12}$' then
    raise exception 'CP9X:เลขทรัพย์สินใหม่ต้องเป็นตัวเลข 12 หลัก (ได้รับ "%")', v_new;
  end if;
  if v_new = v_old then raise exception 'CP9X:เลขทรัพย์สินใหม่เหมือนเลขเดิม ไม่มีอะไรต้องแก้'; end if;
  if v_reason = '' then raise exception 'CP9X:กรุณาระบุเหตุผลที่แก้เลขทรัพย์สิน'; end if;
  if v_by = '' then raise exception 'CP9X:ไม่ทราบชื่อผู้แก้'; end if;

  -- ---------- ล็อกแถวที่จะแก้ กันแอดมิน 2 คนแก้งานเดียวกันพร้อมกัน ----------
  select id into v_close_id
  from close_issues where job_id = v_job and asset_id = v_old
  for update;
  if v_close_id is null then
    raise exception 'CP9X:ไม่พบงานปิดของเลขงาน % เลขทรัพย์สิน % (อาจถูกแก้ไปแล้ว ลองโหลดหน้าใหม่)', v_job, v_old;
  end if;

  -- ---------- เลขใหม่ต้องไม่ชนกับของที่มีอยู่แล้วในงานเดียวกัน ----------
  if exists (select 1 from close_issues where job_id = v_job and asset_id = v_new) then
    raise exception 'CP9X:เลขงาน % มีเลขทรัพย์สิน % อยู่แล้ว ใช้ซ้ำไม่ได้', v_job, v_new;
  end if;
  if exists (select 1 from billing_documents where customer_case = v_job and asset_id = v_new) then
    raise exception 'CP9X:ตารางวางบิลของเลขงาน % มีเลขทรัพย์สิน % อยู่แล้ว ใช้ซ้ำไม่ได้', v_job, v_new;
  end if;

  -- ---------- สถานะบิลตอนนี้ (ล็อกแถวบิลด้วย) ----------
  perform 1 from billing_documents where customer_case = v_job and asset_id = v_old for update;
  select count(*),
         count(*) filter (where sent_to_contractor is true),
         count(*) filter (where completed_at is not null),
         max(round_no)
    into v_total, v_sent, v_done, v_round
  from billing_documents where customer_case = v_job and asset_id = v_old;

  v_state := case
    when v_total = 0 then 'ยังไม่เข้ารอบบิล'
    when v_done  > 0 then 'ตัดบิลแล้ว'
    when v_sent  > 0 then 'ส่งผู้รับเหมาแล้ว'
    else 'อยู่ในรอบบิล ยังไม่ส่ง'
  end;

  -- ---------- 1) ปิดงาน ----------
  update close_issues set asset_id = v_new where id = v_close_id;

  -- ---------- 2) แถวบิลทุกแถวของคู่นี้ ----------
  update billing_documents set asset_id = v_new
  where customer_case = v_job and asset_id = v_old;

  -- ---------- 3) คีย์จองรอบบิล ----------
  v_old_key := v_job || '__asset__' || v_old;
  v_new_key := v_job || '__asset__' || v_new;
  if exists (select 1 from billing_job_registry where customer_case = v_old_key) then
    if exists (select 1 from billing_job_registry where customer_case = v_new_key) then
      -- เลขใหม่ถูกจองไว้แล้ว (จองค้างจากเหตุการณ์อื่น) — คงตัวใหม่ไว้ ลบตัวเก่า
      delete from billing_job_registry where customer_case = v_old_key;
      v_reg := 'เลขใหม่มีคีย์จองอยู่แล้ว ลบคีย์ของเลขเดิม';
    else
      update billing_job_registry set customer_case = v_new_key where customer_case = v_old_key;
      v_reg := 'ย้ายคีย์จองไปเลขใหม่';
    end if;
  elsif v_total > 0 then
    -- ออกบิลไปแล้วแต่ไม่มีคีย์จองแบบมีเลขทรัพย์สิน -> ต้องเพิ่มให้ ไม่งั้นจะถูกดึงซ้ำ
    insert into billing_job_registry (customer_case, round_no)
    values (v_new_key, coalesce(v_round, 0))
    on conflict (customer_case) do nothing;
    v_reg := 'เพิ่มคีย์จองให้เลขใหม่ (เดิมไม่มีคีย์แบบมีเลขทรัพย์สิน)';
  end if;

  -- ---------- 4) ประวัติแจ้งเตือน SLA (มีตารางเมื่อรัน v1.0.75 แล้วเท่านั้น) ----------
  if to_regclass('public.sla_notifications') is not null then
    -- ช่วงที่เลขใหม่มีประวัติอยู่แล้ว ให้คงของเลขใหม่ไว้ แล้วทิ้งของเลขเดิม (กันชน primary key)
    execute 'delete from sla_notifications s where s.main_id = $1 and s.asset_id = $2
             and exists (select 1 from sla_notifications t
                         where t.main_id = $1 and t.asset_id = $3 and t.stage_key = s.stage_key)'
      using v_job, v_old, v_new;
    execute 'update sla_notifications set asset_id = $3 where main_id = $1 and asset_id = $2'
      using v_job, v_old, v_new;
  end if;

  -- ---------- 5) คอมเมนต์ให้ผู้รับเหมาเห็น (เฉพาะแถวที่ส่งให้เขาแล้ว) ----------
  if v_sent > 0 and to_regclass('public.billing_row_comments') is not null then
    v_msg := 'แก้เลขทรัพย์สินจาก ' || v_old || ' เป็น ' || v_new || E'\nเหตุผล: ' || v_reason;
    if exists (select 1 from information_schema.columns
               where table_schema = 'public' and table_name = 'billing_documents' and column_name = 'revision_no') then
      execute 'insert into billing_row_comments (billing_id, customer_case, revision_no, author_role, author_name, action, message)
               select b.id::text, b.customer_case, b.revision_no, ''admin'', $1, ''asset_changed'', $2
               from billing_documents b
               where b.customer_case = $3 and b.asset_id = $4 and b.sent_to_contractor is true'
        using v_by, v_msg, v_job, v_new;
    else
      execute 'insert into billing_row_comments (billing_id, customer_case, author_role, author_name, action, message)
               select b.id::text, b.customer_case, ''admin'', $1, ''asset_changed'', $2
               from billing_documents b
               where b.customer_case = $3 and b.asset_id = $4 and b.sent_to_contractor is true'
        using v_by, v_msg, v_job, v_new;
    end if;
    get diagnostics v_comments = row_count;
  end if;

  -- ---------- 6) ประวัติ ----------
  insert into asset_change_log (job_id, old_asset_id, new_asset_id, reason, changed_by, billing_rows, billing_state, registry_action)
  values (v_job, v_old, v_new, v_reason, v_by, v_total, v_state, v_reg);

  return jsonb_build_object(
    'job_id', v_job, 'old_asset', v_old, 'new_asset', v_new,
    'close_rows', 1, 'billing_rows', v_total, 'sent_rows', v_sent, 'done_rows', v_done,
    'state', v_state, 'registry', v_reg, 'comments', v_comments
  );
end;
$$;

-- เรียกได้เฉพาะเซิร์ฟเวอร์ — ถ้าไม่ปิด ใครถือ key ในแอปก็เรียกแก้เลขทรัพย์สินได้ตรง ๆ
revoke execute on function public.change_asset_number(text, text, text, text, text) from public, anon, authenticated;
grant  execute on function public.change_asset_number(text, text, text, text, text) to service_role;


-- ---------------------------------------------------------------------
--  3. ตรวจผล — ต้องได้ ✓ ทุกบรรทัด
-- ---------------------------------------------------------------------
select 'ตาราง asset_change_log' as "รายการ",
       case when to_regclass('public.asset_change_log') is not null then '✓ มี' else '✗ ไม่มี' end as "ผล"
union all
select 'ฟังก์ชัน change_asset_number',
       case when to_regprocedure('public.change_asset_number(text, text, text, text, text)') is not null then '✓ มี' else '✗ ไม่มี' end
union all
select 'คนนอก (anon) เรียกฟังก์ชันไม่ได้',
       case when has_function_privilege('anon', 'public.change_asset_number(text, text, text, text, text)', 'execute')
            then '✗ ยังเรียกได้' else '✓ เรียกไม่ได้' end
union all
select 'เซิร์ฟเวอร์ (service_role) เรียกได้',
       case when has_function_privilege('service_role', 'public.change_asset_number(text, text, text, text, text)', 'execute')
            then '✓ เรียกได้' else '✗ เรียกไม่ได้' end;
