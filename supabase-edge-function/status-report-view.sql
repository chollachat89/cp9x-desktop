-- ============================================================================
-- สร้าง VIEW "status_report_view" ใน Supabase — รายงานสถานะแบบละเอียดที่สุด รวมทุกข้อมูลไว้ที่เดียว
-- (ตรรกะสถานะตรงกับหน้า "รายงานสถานะดำเนินการ" ในแอปทุกประการ แต่มีคอลัมน์ครบกว่ามาก)
--
-- รวมข้อมูลจาก 4 ตารางเข้าด้วยกัน: open_issues + close_issues + billing_documents + pause_records
--
-- นี่คือ VIEW ไม่ใช่ตารางจริง = ไม่มีข้อมูลซ้ำซ้อน ไม่ต้องซิงค์ ข้อมูลสดใหม่เสมอทุกครั้งที่เปิดดู
-- เปิดดูได้จาก Supabase Dashboard -> Table Editor -> เลือก "status_report_view"
-- (ถ้าไม่เห็นในลิสต์ ให้เลือก schema "public" แล้วมองหาไอคอน View)
--
-- กฎการนับแถว (เหมือนในแอปเป๊ะ ๆ):
--   - เลขงานที่ยังไม่เคยปิดงานเลย                = ออก 1 แถว (คอลัมน์ฝั่งปิดงานขึ้นว่า "ยังไม่ปิดงาน")
--   - เลขงานที่ปิดงานไปแล้ว 1 ครั้ง               = ออก 1 แถว
--   - เลขงานที่ปิดงานหลายครั้ง (คนละเลขทรัพย์สิน)  = ออกหลายแถว แถวละ 1 ครั้งที่ปิดงานจริง
--
-- การเติมข้อมูลให้ครบทุกช่อง (ไม่มีช่องว่าง/null ค้างให้งง):
--   - ช่องข้อความที่ไม่มีข้อมูล จะเติมข้อความบอกสาเหตุแทน เช่น "ยังไม่ปิดงาน" / "ยังไม่วางบิล" / "ไม่เคยพักงาน"
--   - ช่องตัวเลขที่ไม่มีข้อมูล จะเติม 0 ให้
--   - "รหัสสาขา"/"ชื่อสาขา" ถ้ายังไม่มีข้อมูลจากตารางบิล จะแยกออกมาจากช่อง "สาขา" ของงานเปิดให้อัตโนมัติ
--     (รูปแบบข้อมูลจริงคือ "0547-วังน้ำเขียว นครปฐม" = รหัส 4 หลัก + ขีด + ชื่อสาขา)
--   - ช่องวันเวลา (timestamp) ยังคงเป็นค่าว่างได้ตามจริง เพื่อให้เรียงลำดับ/คำนวณวันที่ต่อได้ถูกต้อง
--     แต่จะมีคอลัมน์ข้อความคู่กันบอกสถานะไว้ให้อ่านง่ายแทน
--
-- วิธีใช้: เปิด Supabase Dashboard ของโปรเจกต์ CP9X -> SQL Editor -> New query
-- แล้ววางโค้ดด้านล่างนี้ทั้งหมด กด Run (รันซ้ำได้อย่างปลอดภัย)
-- ============================================================================

-- ลบ VIEW เดิมทิ้งก่อนเสมอ (ถ้ามี) แล้วค่อยสร้างใหม่
-- เหตุผล: คำสั่ง CREATE OR REPLACE VIEW ของ Postgres "เปลี่ยนชื่อคอลัมน์เดิมไม่ได้" (error 42P16)
-- ทำได้แค่เพิ่มคอลัมน์ต่อท้ายเท่านั้น ถ้าเคยสร้าง VIEW นี้ไว้ด้วยชุดคอลัมน์แบบอื่นมาก่อนจะรันไม่ผ่าน
-- การ DROP ก่อนจึงปลอดภัยและรันซ้ำได้เสมอ (VIEW ไม่ได้เก็บข้อมูลจริง ลบแล้วสร้างใหม่ไม่มีข้อมูลสูญหาย)
drop view if exists public.status_report_view;

create view public.status_report_view as
with billing_agg as (
  -- สรุปข้อมูลบิลของแต่ละเลขงาน (1 เลขงานอาจมีหลายแถวใน billing_documents ถ้ามีหลายอะไหล่/หลายเลขทรัพย์สิน)
  select
    customer_case,
    bool_or(sent_to_contractor)              as sent_to_contractor,
    bool_or(completed_at is not null)        as completed,
    max(completed_at)                        as completed_at,
    count(*)                                 as billing_line_count,
    sum(coalesce(total_price, 0))            as billing_total_cj,
    sum(coalesce(total_price_contractor, 0)) as billing_total_contractor,
    max(round_no)                            as round_no,
    max(round_period)                        as round_period,
    max(quotation_ref)                       as quotation_ref,
    max(branch_code)                         as branch_code,
    max(branch_name)                         as branch_name,
    max(visit_date)                          as visit_date,
    max(responsible)                         as responsible,
    max(company)                             as company,
    -- รวมรายชื่ออะไหล่ทุกชิ้นของเลขงานนี้ไว้ในช่องเดียว คั่นด้วย " | "
    string_agg(
      nullif(trim(coalesce(part_code, '') || ' ' || coalesce(part_detail, '')), ''),
      ' | ' order by seq nulls last
    ) as billing_parts_summary
  from billing_documents
  group by customer_case
),
pause_agg as (
  -- สรุปประวัติพักงานของแต่ละเลขงาน
  select
    main_id,
    count(*)                                        as pause_count,
    bool_or(status = 'paused')                      as is_paused,
    sum(extract(epoch from (coalesce(resumed_at, now()) - paused_at)) / 3600.0)
      filter (where paused_at is not null)          as pause_hours_total,
    min(paused_at)                                  as first_paused_at,
    max(paused_at)                                  as last_paused_at,
    max(resumed_at)                                 as last_resumed_at,
    (array_agg(reason      order by paused_at desc))[1] as last_pause_reason,
    (array_agg(note        order by paused_at desc))[1] as last_pause_note,
    (array_agg(paused_by   order by paused_at desc))[1] as last_paused_by,
    (array_agg(resumed_by  order by paused_at desc))[1] as last_resumed_by
  from pause_records
  group by main_id
),
close_agg as (
  -- นับว่าแต่ละเลขงานถูกปิดงานไปแล้วกี่ครั้ง (กี่เลขทรัพย์สิน)
  select job_id, count(*) as close_count
  from close_issues
  group by job_id
),
base as (
  -- ชั้นนี้ทำหน้าที่ join ทุกตารางเข้าด้วยกันก่อน แล้วค่อยไปจัดรูปแบบ/เติมค่าว่างในชั้นถัดไป
  -- (แยกเป็น 2 ชั้นเพื่อให้เขียน coalesce ได้สั้นและอ่านง่าย ไม่ต้องเขียน o.xxx / c.xxx ซ้ำ ๆ)
  select
    o.main_id, o.branch, o.service_type, o.service_work, o.contract_type,
    o.contractor, o.details, o.req_date, o.created_at as opened_at,
    c.id as close_id, c.asset_id, c.fix_date, c.created_at as closed_at,
    c.action_taken, c.parts, c.branch as close_branch, c.photo_form_link,
    ca.close_count,
    b.sent_to_contractor, b.completed, b.completed_at, b.billing_line_count,
    b.billing_total_cj, b.billing_total_contractor, b.round_no, b.round_period,
    b.quotation_ref, b.branch_code, b.branch_name, b.visit_date,
    b.responsible, b.company, b.billing_parts_summary,
    p.pause_count, p.is_paused, p.pause_hours_total, p.first_paused_at,
    p.last_paused_at, p.last_resumed_at, p.last_pause_reason,
    p.last_pause_note, p.last_paused_by, p.last_resumed_by
  from open_issues o
  left join close_issues c  on c.job_id        = o.main_id
  left join close_agg    ca on ca.job_id       = o.main_id
  left join billing_agg  b  on b.customer_case = o.main_id
  left join pause_agg    p  on p.main_id       = o.main_id
)
select
  ---------------------------------------------------------------- ข้อมูลเปิดงาน
  main_id                                                          as "เลขที่ใบแจ้งซ่อมบำรุง",
  coalesce(nullif(trim(branch), ''), '-')                          as "สาขา",
  -- รหัสสาขา: เอาจากตารางบิลก่อน ถ้ายังไม่มีบิล ให้แยกจากช่อง "สาขา" ของงานเปิด (รูปแบบ "0547-ชื่อสาขา")
  coalesce(
    nullif(trim(branch_code), ''),
    case when branch ~ '^\s*[0-9]+\s*-' then trim(split_part(branch, '-', 1)) end,
    '-'
  )                                                                as "รหัสสาขา",
  coalesce(
    nullif(trim(branch_name), ''),
    case
      when branch ~ '^\s*[0-9]+\s*-'
        then nullif(trim(substring(branch from position('-' in branch) + 1)), '')
      else nullif(trim(branch), '')
    end,
    '-'
  )                                                                as "ชื่อสาขา",
  coalesce(nullif(trim(service_type), ''), '-')                    as "Service Type",
  coalesce(nullif(trim(service_work), ''), '-')                    as "งานบริการ",
  coalesce(nullif(trim(contract_type), ''), 'ไม่ระบุประเภทสัญญา')     as "ประเภทสัญญา",
  coalesce(nullif(trim(contractor), ''), 'ยังไม่ระบุผู้รับเหมา')       as "ผู้รับเหมา",
  coalesce(nullif(trim(details), ''), '-')                         as "รายละเอียดปัญหาที่พบ",
  coalesce(nullif(trim(req_date), ''), '-')                        as "วันที่ร้องขอ",
  opened_at                                                        as "วันที่เปิดงาน",

  ---------------------------------------------------------------- ข้อมูลปิดงาน (1 แถว = 1 ครั้งที่ปิด)
  case when close_id is null then 'ยังไม่ปิดงาน'
       else coalesce(nullif(trim(asset_id), ''), '-') end          as "เลขทรัพย์สิน",
  case when close_id is null then 'ยังไม่ปิดงาน'
       else coalesce(nullif(trim(fix_date), ''), '-') end          as "วันที่เข้าแก้ไข",
  closed_at                                                        as "วันที่ปิดงาน",
  case when close_id is null then 'ยังไม่ปิดงาน'
       else coalesce(nullif(trim(action_taken), ''), '-') end      as "ดำเนินการแก้ไขแล้ว",
  case when close_id is null then 'ยังไม่ปิดงาน'
       else coalesce(nullif(trim(parts), ''), '-') end             as "รายการอะไหล่ที่เปลี่ยน",
  case when close_id is null then 'ยังไม่ปิดงาน'
       else coalesce(nullif(trim(close_branch), ''), '-') end      as "สาขา (ตอนปิดงาน)",
  case when close_id is null then 'ยังไม่ปิดงาน'
       else coalesce(nullif(trim(photo_form_link), ''), 'ไม่ได้แนบรูป') end as "ลิงก์แนบรูป",
  coalesce(close_count, 0)                                         as "จำนวนครั้งที่ปิดงานของเลขงานนี้",

  ---------------------------------------------------------------- ระยะเวลา
  case
    when closed_at is not null and opened_at is not null and closed_at >= opened_at
      then round((extract(epoch from (closed_at - opened_at)) / 3600.0)::numeric, 2)
    else null
  end                                                              as "ระยะเวลาดำเนินการ (ชม.)",
  case
    when closed_at is not null and opened_at is not null and closed_at >= opened_at
      then round((extract(epoch from (closed_at - opened_at)) / 86400.0)::numeric, 2)
    else null
  end                                                              as "ระยะเวลาดำเนินการ (วัน)",
  -- คอลัมน์ข้อความอ่านง่าย (ถ้ายังไม่ปิดงาน จะบอกว่าค้างมาแล้วกี่วันแทนการเว้นว่าง)
  case
    when closed_at is not null and opened_at is not null and closed_at >= opened_at
      then 'ใช้เวลา ' || round((extract(epoch from (closed_at - opened_at)) / 86400.0)::numeric, 1) || ' วัน'
    when opened_at is not null
      then 'ยังไม่ปิดงาน (ค้างมาแล้ว ' || round((extract(epoch from (now() - opened_at)) / 86400.0)::numeric, 1) || ' วัน)'
    else '-'
  end                                                              as "สรุประยะเวลา",

  ---------------------------------------------------------------- ข้อมูลพักงาน
  coalesce(pause_count, 0)                                         as "จำนวนครั้งที่พัก",
  round(coalesce(pause_hours_total, 0)::numeric, 2)                as "รวมชั่วโมงที่พัก",
  coalesce(is_paused, false)                                       as "กำลังพักอยู่ตอนนี้",
  first_paused_at                                                  as "วันเวลาที่พักครั้งแรก",
  last_paused_at                                                   as "วันเวลาที่พักครั้งล่าสุด",
  last_resumed_at                                                  as "วันเวลาที่กลับมาทำล่าสุด",
  case when coalesce(pause_count, 0) = 0 then 'ไม่เคยพักงาน'
       else coalesce(nullif(trim(last_pause_reason), ''), '-') end  as "เหตุผลที่พัก (ครั้งล่าสุด)",
  case when coalesce(pause_count, 0) = 0 then 'ไม่เคยพักงาน'
       else coalesce(nullif(trim(last_pause_note), ''), '-') end    as "หมายเหตุการพัก (ครั้งล่าสุด)",
  case when coalesce(pause_count, 0) = 0 then 'ไม่เคยพักงาน'
       else coalesce(nullif(trim(last_paused_by), ''), '-') end     as "ผู้พักงาน (ครั้งล่าสุด)",
  case when coalesce(pause_count, 0) = 0 then 'ไม่เคยพักงาน'
       when coalesce(is_paused, false)   then 'ยังพักอยู่ ยังไม่กลับมาทำ'
       else coalesce(nullif(trim(last_resumed_by), ''), '-') end    as "ผู้ทำรายการกลับมาทำ (ครั้งล่าสุด)",

  ---------------------------------------------------------------- ข้อมูลวางบิล
  coalesce(sent_to_contractor, false)                              as "ส่งมอบงานให้ผู้รับเหมาแล้ว",
  coalesce(completed, false)                                       as "เสร็จสิ้น (ตัดบิลแล้ว)",
  completed_at                                                     as "วันที่ตัดบิล",
  case when billing_line_count is null then 'ยังไม่วางบิล'
       when round_no is null           then '-'
       else round_no::text end                                     as "รอบบิลที่",
  case when billing_line_count is null then 'ยังไม่วางบิล'
       else coalesce(nullif(trim(round_period), ''), '-') end      as "ช่วงรอบบิล",
  case when billing_line_count is null then 'ยังไม่วางบิล'
       else coalesce(nullif(trim(quotation_ref), ''), '-') end     as "Quotation",
  case when billing_line_count is null then 'ยังไม่วางบิล'
       else coalesce(nullif(trim(visit_date), ''), '-') end        as "วันที่เข้างาน (จากบิล)",
  coalesce(billing_line_count, 0)                                  as "จำนวนรายการในบิล",
  round(coalesce(billing_total_cj, 0)::numeric, 2)                 as "ยอดรวมบิล (CJ)",
  round(coalesce(billing_total_contractor, 0)::numeric, 2)         as "ยอดรวมบิล (ผู้รับเหมา)",
  case when billing_line_count is null then 'ยังไม่วางบิล'
       else coalesce(nullif(trim(billing_parts_summary), ''), '-') end as "รายการอะไหล่ในบิล",
  case when billing_line_count is null then 'ยังไม่วางบิล'
       else coalesce(nullif(trim(responsible), ''), '-') end       as "ผู้รับผิดชอบ",
  case when billing_line_count is null then 'ยังไม่วางบิล'
       else coalesce(nullif(trim(company), ''), '-') end           as "บริษัท",

  ---------------------------------------------------------------- สถานะสรุป
  -- ลำดับความสำคัญ: เสร็จสิ้น > ส่งมอบงาน > ปิดงานแล้ว > พักงาน (ถ้ายังไม่ปิด) > รอดำเนินการ
  -- (ตรรกะเดียวกับ computeJobStatusReportRows() ในฝั่งเซิร์ฟเวอร์ทุกประการ)
  case
    when coalesce(completed, false)            then 'เสร็จสิ้น'
    when coalesce(sent_to_contractor, false)   then 'ส่งมอบงาน'
    when close_id is not null                  then 'ปิดงานแล้ว'
    when coalesce(is_paused, false)            then 'พักงาน'
    else 'รอดำเนินการ'
  end                                                              as "สถานะ"

from base
order by opened_at desc;


-- ============================================================================
-- ตัวอย่างการนำไปใช้ต่อ (คัดลอกไปรันแยกได้ตามต้องการ)
-- ============================================================================

-- ดูข้อมูล 20 แถวล่าสุด
select * from status_report_view limit 20;

-- สรุปยอดตามสถานะ
select "สถานะ", count(*) as "จำนวน"
from status_report_view
group by "สถานะ"
order by "จำนวน" desc;

-- สรุปตาม "งานบริการ" (รหัส F ต่าง ๆ)
select "งานบริการ", count(*) as "จำนวนงาน"
from status_report_view
group by "งานบริการ"
order by "จำนวนงาน" desc;

-- สรุปตาม "งานบริการ" แยกตามสถานะ (ดูว่างาน F แต่ละแบบค้างอยู่ขั้นไหนบ้าง)
select "งานบริการ", "สถานะ", count(*) as "จำนวน"
from status_report_view
group by "งานบริการ", "สถานะ"
order by "งานบริการ", "จำนวน" desc;

-- เฉพาะงานที่ยังค้าง (ยังไม่ปิดงาน) เรียงจากงานที่เปิดนานที่สุด
select "เลขที่ใบแจ้งซ่อมบำรุง", "สาขา", "งานบริการ", "ผู้รับเหมา", "วันที่เปิดงาน", "สรุประยะเวลา", "สถานะ"
from status_report_view
where "สถานะ" in ('รอดำเนินการ', 'พักงาน')
order by "วันที่เปิดงาน" asc;

-- ระยะเวลาดำเนินการเฉลี่ย แยกตามงานบริการ (นับเฉพาะงานที่ปิดแล้ว)
select
  "งานบริการ",
  count(*)                                        as "จำนวนงานที่ปิดแล้ว",
  round(avg("ระยะเวลาดำเนินการ (ชม.)"), 2)         as "เฉลี่ย (ชม.)",
  round(avg("ระยะเวลาดำเนินการ (วัน)"), 2)         as "เฉลี่ย (วัน)"
from status_report_view
where "ระยะเวลาดำเนินการ (ชม.)" is not null
group by "งานบริการ"
order by "เฉลี่ย (ชม.)" desc;
