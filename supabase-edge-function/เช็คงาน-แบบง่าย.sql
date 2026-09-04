-- ============================================================================
-- เช็คเลขงานแบบง่าย — วางทั้งไฟล์ กด Run ได้เลย
-- อ่านอย่างเดียว ไม่แก้ไม่ลบอะไร
--
-- ถ้าจะเช็คเลขงานอื่น แก้แค่บรรทัดที่มี CM20260902-0137 (มีที่เดียว)
-- ============================================================================

with งาน as (
  select 'CM20260902-0137'::text as job
),
o as (select * from open_issues  where main_id = (select job from งาน)),
c as (select * from close_issues where job_id  = (select job from งาน)),
p as (select * from pause_records where main_id = (select job from งาน)),
b as (select * from billing_documents where customer_case = (select job from งาน))

select
  (select job from งาน)                                          as "เลขงาน",

  ---------------------------------------------------------------- สาขา
  coalesce((select branch from o), 'ไม่พบงานนี้ในระบบ')            as "สาขาที่กรอกไว้",
  (select case
     when not exists (select 1 from o) then '-'
     when (select branch from o) !~ '^\s*\d+\s*-' then 'พิมพ์เอง (ไม่ใช่รูปแบบ รหัส-ชื่อสาขา)'
     when not exists (
       select 1 from branches br
       where br.branch_code = (select (regexp_match(branch, '^\s*(\d+)'))[1] from o)
     ) then 'รหัสสาขานี้ไม่มีในระบบ (กรอกผิดหรือพิมพ์เอง)'
     when (select br.branch_name from branches br
           where br.branch_code = (select (regexp_match(branch, '^\s*(\d+)'))[1] from o))
          is distinct from
          (select trim(regexp_replace(branch, '^\s*\d+\s*-\s*', '')) from o)
       then 'รหัสถูก แต่ชื่อสาขาถูกแก้เอง'
     else 'สาขาถูกต้อง ตรงกับระบบ'
   end)                                                           as "ผลเช็คสาขา",

  ---------------------------------------------------------------- ใครดำเนินการ
  coalesce((select contractor from o), '-')                       as "ทีมที่ถูกมอบหมาย",
  coalesce((select paused_by from p order by paused_at desc limit 1), 'ไม่มีการพักงาน')
                                                                  as "ผู้พักงาน (พิมพ์เอง เชื่อไม่ได้ 100%)",
  coalesce((select resumed_by from p order by paused_at desc limit 1), '-')
                                                                  as "ผู้กดกลับมาทำงาน (เชื่อถือได้)",
  coalesce((select string_agg(distinct contractor, ', ') from job_form_submissions
            where customer_case = (select job from งาน)), '-')     as "บัญชีที่อัปโหลดฟอร์ม (เชื่อถือได้)",

  ---------------------------------------------------------------- กรอกมือไหม
  (select case
     when not exists (select 1 from o) then '-'
     when (select req_date from o) ~ '^\d{2}/\d{2}/\d{4}, \d{1,2}:\d{2}$' then 'ใช้ปุ่มดูดข้อความ'
     else 'พิมพ์เอง (รูปแบบวันที่ไม่ตรงกับที่ปุ่มดูดให้)'
   end)                                                           as "เปิดงาน กรอกยังไง",
  (select case
     when not exists (select 1 from c) then 'ยังไม่ปิดงาน'
     when bool_and(fix_date ~ '^\d{1,2}-\d{1,2}-\d{4}$') then 'รูปแบบปกติ'
     else 'พิมพ์เอง (รูปแบบวันที่เพี้ยน)'
   end from c)                                                    as "ปิดงาน กรอกยังไง",
  (select case
     when not exists (select 1 from b) then 'ยังไม่มีแถวบิล'
     when count(*) filter (where part_code ~* '^NP') > 0
       then 'มีอะไหล่กรอกเอง ' || count(*) filter (where part_code ~* '^NP') || ' รายการ (รหัส NP)'
     when count(*) filter (where part_code is not null and trim(part_code) <> ''
                             and not exists (select 1 from parts pa where pa.code_cj = billing_documents.part_code)) > 0
       then 'มีรหัสอะไหล่ที่ไม่มีในระบบ (พิมพ์เอง)'
     else 'อะไหล่มาจากระบบทั้งหมด'
   end from billing_documents where customer_case = (select job from งาน))
                                                                  as "อะไหล่ กรอกยังไง",

  ---------------------------------------------------------------- เวลา
  (select to_char(created_at at time zone 'Asia/Bangkok', 'DD/MM/YYYY HH24:MI') from o)
                                                                  as "เวลาที่บันทึกเปิดงาน",
  (select to_char(min(created_at) at time zone 'Asia/Bangkok', 'DD/MM/YYYY HH24:MI') from c)
                                                                  as "เวลาที่บันทึกปิดงาน",
  (select count(*) from c)                                        as "จำนวนครั้งที่ปิดงาน",
  (select count(*) from b)                                        as "จำนวนแถวในตารางวางบิล";
