-- ==========================================================
-- เพิ่มดัชนี (index) ให้ CP9X รองรับข้อมูล 2-3 ปีโดยไม่ช้าลง
--
-- ปัญหาที่แก้: ตารางหลักไม่มีดัชนีเลยนอกจาก primary key
-- ทุกครั้งที่ค้นด้วยเลขงาน/รอบบิล/ผู้รับเหมา Postgres ต้องไล่อ่านทุกแถว
--
-- ปลอดภัย 100% — ดัชนีไม่แก้ ไม่ลบ ไม่เปลี่ยนข้อมูลใด ๆ
-- เป็นแค่ "สารบัญ" ที่สร้างไว้ข้าง ๆ เพื่อค้นให้เร็วขึ้น ลบทิ้งได้ทุกเมื่อ
--
-- รอบนี้แก้ 2 อย่างจากไฟล์เดิมที่รันแล้ว error:
--   1. เส้นคั่นคอมเมนต์ยาวเกินจนตอนคัดลอกไปวางแล้วขาด กลายเป็นบรรทัดลอย
--      -> เปลี่ยนเป็นเส้นสั้น ๆ ทั้งไฟล์
--   2. เดาชื่อคอลัมน์ผิด (parts ไม่มีคอลัมน์ part_code)
--      -> เปลี่ยนเป็นเช็คก่อนสร้างทุกตัว ถ้าไม่มีคอลัมน์จะข้ามให้เองพร้อมบอกเหตุผล
--
-- วิธีใช้: วางทั้งไฟล์ กด Run ครั้งเดียว (รันซ้ำได้ ไม่เกิดดัชนีซ้ำ)
--   https://supabase.com/dashboard/project/hefnjozijflnhdunmewl/sql/new
-- ==========================================================


-- ตัวช่วย: สร้างดัชนีเฉพาะเมื่อ "ตารางมีอยู่จริง และคอลัมน์ครบจริง"
-- ถ้าขาดอะไรจะข้ามให้เงียบ ๆ พร้อมขึ้นข้อความบอกใน Messages ไม่ทำให้ทั้งไฟล์ล้ม
create or replace function _cp9x_make_index(
  p_index   text,
  p_table   text,
  p_columns text,
  p_where   text default null
) returns text language plpgsql as $$
declare
  col   text;
  cols  text[];
  ddl   text;
begin
  if to_regclass('public.' || p_table) is null then
    return 'ข้าม ' || p_index || ' — ไม่มีตาราง ' || p_table;
  end if;

  -- ตรวจทุกคอลัมน์ที่จะใช้ทำดัชนี ต้องมีอยู่จริงครบทุกตัว
  -- ⚠ ห้ามลบช่องว่างทิ้งทั้งก้อนก่อน ไม่งั้น 'created_at desc' จะติดกันเป็น 'created_atdesc'
  --   แล้วหาคอลัมน์ไม่เจอ ดัชนีจะถูกข้ามทั้งที่คอลัมน์มีอยู่จริง
  --   ต้องแยกด้วยจุลภาคก่อน แล้วค่อยตัดช่องว่างและคำว่า asc/desc ท้ายชื่อทีละตัว
  cols := string_to_array(p_columns, ',');
  foreach col in array cols loop
    col := btrim(col);
    col := regexp_replace(col, '\s+(asc|desc)$', '', 'i');
    col := btrim(col);
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = p_table and column_name = col
    ) then
      return 'ข้าม ' || p_index || ' — ตาราง ' || p_table || ' ไม่มีคอลัมน์ ' || col;
    end if;
  end loop;

  if exists (select 1 from pg_indexes where schemaname = 'public' and indexname = p_index) then
    return 'มีอยู่แล้ว ' || p_index;
  end if;

  ddl := format('create index %I on public.%I (%s)', p_index, p_table, p_columns);
  if p_where is not null then
    ddl := ddl || ' where ' || p_where;
  end if;
  execute ddl;
  return 'สร้างแล้ว ' || p_index;
end;
$$;


-- === สร้างดัชนีทั้งหมด ===
-- ผลลัพธ์จะบอกทีละบรรทัดว่าตัวไหน "สร้างแล้ว" / "มีอยู่แล้ว" / "ข้าม (เพราะอะไร)"
select * from (values

  -- billing_documents — ตารางที่ใช้หนักที่สุด (โค้ดเรียก 28 จุด)
  (_cp9x_make_index('billing_documents_customer_case_idx', 'billing_documents', 'customer_case')),
  (_cp9x_make_index('billing_documents_round_no_idx',      'billing_documents', 'round_no')),
  (_cp9x_make_index('billing_documents_contractor_idx',    'billing_documents', 'contractor')),
  (_cp9x_make_index('billing_documents_case_asset_idx',    'billing_documents', 'customer_case, asset_id')),
  -- "งานที่ยังไม่ตัดบิล" = หน้าจอที่เปิดบ่อยที่สุด
  -- partial index เก็บเฉพาะแถวที่ยังไม่ตัดบิล ข้อมูลเก่า 3 ปีจึงไม่ถ่วงดัชนีนี้เลย
  (_cp9x_make_index('billing_documents_active_idx',        'billing_documents', 'contractor, round_no', 'completed_at is null')),

  -- open_issues
  (_cp9x_make_index('open_issues_main_id_idx',    'open_issues', 'main_id')),
  (_cp9x_make_index('open_issues_created_at_idx', 'open_issues', 'created_at desc')),

  -- close_issues
  (_cp9x_make_index('close_issues_job_id_idx',     'close_issues', 'job_id')),
  (_cp9x_make_index('close_issues_job_asset_idx',  'close_issues', 'job_id, asset_id')),
  (_cp9x_make_index('close_issues_created_at_idx', 'close_issues', 'created_at desc')),

  -- pause_records
  (_cp9x_make_index('pause_records_main_id_idx', 'pause_records', 'main_id')),
  (_cp9x_make_index('pause_records_active_idx',  'pause_records', 'main_id', 'resumed_at is null')),

  -- job_form_submissions
  (_cp9x_make_index('job_form_submissions_customer_case_idx', 'job_form_submissions', 'customer_case')),
  (_cp9x_make_index('job_form_submissions_submitted_at_idx',  'job_form_submissions', 'submitted_at desc')),
  -- "ยังไม่อ่าน" = เลขแจ้งเตือนสีแดงที่แท็บ ยิงทุกครั้งที่เปิดแอป
  (_cp9x_make_index('job_form_submissions_unread_idx',        'job_form_submissions', 'is_read', 'is_read = false')),
  -- "อนุมัติแล้วรอสิ้นสุดงาน" = กองงานของผู้ตรวจสอบ (v1.0.56)
  (_cp9x_make_index('job_form_submissions_wait_finish_idx',   'job_form_submissions', 'reviewed_at', 'status = ''approved'' and finished_at is null')),

  -- pm_billing_documents (ตรวจแล้ว: ตารางนี้ใช้ round_no / seq / pm_visit_id ไม่ใช่ customer_case)
  (_cp9x_make_index('pm_billing_documents_round_no_seq_idx', 'pm_billing_documents', 'round_no, seq')),
  (_cp9x_make_index('pm_billing_documents_pm_visit_id_idx',  'pm_billing_documents', 'pm_visit_id')),

  -- branches
  (_cp9x_make_index('branches_branch_code_idx', 'branches', 'branch_code'))

) as t("ผลการสร้างดัชนี");


-- === อัปเดตสถิติให้ Postgres เลือกใช้ดัชนีได้ถูกตัว ===
analyze billing_documents;
analyze open_issues;
analyze close_issues;
analyze pause_records;
analyze job_form_submissions;


-- === เก็บกวาดตัวช่วย (ไม่ต้องเหลือค้างไว้ในฐานข้อมูล) ===
drop function if exists _cp9x_make_index(text, text, text, text);


-- === ตรวจผล: ต้องเห็นดัชนีใหม่ครบ ===
select
  tablename as "ตาราง",
  indexname as "ชื่อดัชนี",
  pg_size_pretty(pg_relation_size(indexname::regclass)) as "ขนาด"
from pg_indexes
where schemaname = 'public' and indexname like '%_idx'
order by tablename, indexname;


-- ==========================================================
-- หมายเหตุ 2 เรื่อง
--
-- 1) ตาราง parts ตัดออกจากไฟล์นี้แล้ว
--    ไฟล์เดิมพยายามสร้างดัชนีบน parts(part_code) แต่ตารางนี้ใช้ชื่อคอลัมน์ว่า code_cj
--    และถึงสร้างบน code_cj ก็ไม่ช่วยอยู่ดี เพราะโค้ดค้นด้วย ilike ซึ่งดัชนีธรรมดาใช้ไม่ได้
--    อีกอย่างตารางนี้มีแค่ราว 600 แถว ไล่อ่านทั้งตารางก็เร็วอยู่แล้ว ไม่ต้องมีดัชนี
--
-- 2) ถ้าหลังสร้างเสร็จลอง explain แล้วยังขึ้น Seq Scan อยู่ = เรื่องปกติ
--    ตอนนี้ข้อมูลยังน้อย Postgres เลยมองว่าอ่านทั้งตารางเร็วกว่าใช้ดัชนี
--    พอข้อมูลโตขึ้นมันจะเปลี่ยนมาใช้ดัชนีเองอัตโนมัติ
--
--    ลองดูได้ด้วย:
--      explain analyze select * from billing_documents where customer_case = 'CM20260904-0169';
-- ==========================================================
