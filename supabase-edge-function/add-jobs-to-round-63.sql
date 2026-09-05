-- ============================================================================
-- เพิ่มงาน 2 เลขงานเข้ารอบบิลที่ 63
--   1. CM20260904-0169
--   2. CM20260901-0258
--
-- ⚠ บล็อก C "เขียนข้อมูลจริง" ลงตาราง billing_documents
--   รันบล็อก A และ B (อ่านอย่างเดียว) ดูให้ครบก่อนเสมอ
--
-- ทำไมต้องใช้ SQL: ปุ่ม "จับคู่ข้อมูล" ในแอปจะขอเลขรอบใหม่จากระบบเสมอ (รอบ 64, 65, ...)
-- ใส่งานเข้ารอบที่มีอยู่แล้วอย่างรอบ 63 ไม่ได้ จึงต้องเพิ่มด้วยคำสั่งนี้แทน
--
-- คำสั่งนี้ทำงานเหมือนปุ่มจับคู่ข้อมูลทุกอย่าง ต่างแค่ล็อกเลขรอบไว้ที่ 63:
--   - 1 แถวต่อ 1 คู่ (เลขงาน + เลขทรัพย์สิน) เลขงานที่ปิดหลายทรัพย์สินจะได้หลายแถว
--   - ดึงสาขา/ประเภทงาน/วันที่ จาก open_issues + close_issues + branches ให้อัตโนมัติ
--   - เลขลำดับ (seq) นับต่อจากที่มีอยู่แล้วในรอบ 63 แยกตามผู้รับเหมา
--   - ช่องอะไหล่/ราคา เว้นว่างไว้ ให้ไปกดปุ่ม + เพิ่มอะไหล่ในแอปทีหลัง (เหมือนงานที่จับคู่ปกติ)
--   - ข้ามคู่ที่มีอยู่ในตารางวางบิลแล้ว จึงรันซ้ำได้ ไม่เกิดแถวซ้ำ
--
-- วิธีใช้: https://supabase.com/dashboard/project/hefnjozijflnhdunmewl/sql/new
-- ============================================================================


-- ---------------------------------------------------------------- บล็อก A
-- อ่านอย่างเดียว: เช็คก่อนว่ารอบ 63 มีอยู่จริงไหม และตอนนี้มีอะไรอยู่บ้าง
select
  round_no                                as "รอบบิล",
  round_period                            as "ช่วงรอบบิล",
  contractor                              as "ผู้รับเหมา",
  count(*)                                as "จำนวนแถว",
  max(seq)                                as "เลขลำดับสูงสุดตอนนี้"
from billing_documents
where round_no = 63
group by round_no, round_period, contractor
order by contractor;


-- ---------------------------------------------------------------- บล็อก B
-- อ่านอย่างเดียว: ดูว่าจะเพิ่มแถวอะไรบ้าง (ยังไม่เขียนลงฐานข้อมูล)
-- ถ้าคอลัมน์ "สถานะ" ขึ้นว่า "มีในตารางวางบิลแล้ว" แปลว่าคู่นั้นจะถูกข้าม
with เลขงานที่ต้องการ(job_id) as (
  values ('CM20260904-0169'), ('CM20260901-0258')
),
คู่งาน as (
  select c.job_id, coalesce(nullif(trim(c.asset_id), ''), '-') as asset_id,
         c.branch as close_branch, c.fix_date
  from close_issues c
  join เลขงานที่ต้องการ w on w.job_id = c.job_id
)
select
  p.job_id                                                        as "เลขงาน",
  p.asset_id                                                      as "เลขทรัพย์สิน",
  o.contractor                                                    as "ผู้รับเหมา",
  coalesce(nullif(trim(p.close_branch), ''), o.branch)            as "สาขา",
  coalesce(o.service_work, o.service_type, '-')                   as "งานบริการ",
  o.req_date                                                      as "วันที่ร้องขอ",
  p.fix_date                                                      as "วันที่เข้างาน",
  case
    when o.main_id is null then 'ไม่พบข้อมูลเปิดงาน (ต้องเปิดงานก่อน)'
    when exists (
      select 1 from billing_documents b
      where b.customer_case = p.job_id
        and coalesce(nullif(trim(b.asset_id), ''), '-') = p.asset_id
    ) then 'มีในตารางวางบิลแล้ว -> จะข้าม'
    else 'พร้อมเพิ่มเข้ารอบ 63'
  end                                                             as "สถานะ"
from คู่งาน p
left join open_issues o on o.main_id = p.job_id
order by p.job_id, p.asset_id;


-- ---------------------------------------------------------------- บล็อก C
-- ★ เพิ่มจริง ★ รันเมื่อดูบล็อก A และ B แล้วโอเค
begin;

with เลขงานที่ต้องการ(job_id) as (
  values ('CM20260904-0169'), ('CM20260901-0258')
),
-- ช่วงรอบบิลของรอบ 63 ดึงจากแถวที่มีอยู่แล้ว เพื่อให้ค่าตรงกันทั้งรอบ
ช่วงรอบ as (
  select coalesce(max(round_period), 'รอบบิลที่ 63') as round_period
  from billing_documents where round_no = 63
),
-- เลขลำดับสูงสุดของรอบ 63 แยกตามผู้รับเหมา ใช้เป็นจุดเริ่มนับต่อ
ลำดับเดิม as (
  select coalesce(contractor, '') as contractor_key, max(coalesce(seq, 0)) as max_seq
  from billing_documents where round_no = 63
  group by coalesce(contractor, '')
),
คู่งานใหม่ as (
  select
    c.job_id,
    coalesce(nullif(trim(c.asset_id), ''), '-')                        as asset_id,
    o.contractor,
    coalesce(nullif(trim(c.branch), ''), o.branch, '')                 as raw_branch,
    coalesce(o.service_work, o.service_type, '-')                      as service_type,
    coalesce(nullif(trim(o.req_date), ''), '-')                        as req_date,
    coalesce(nullif(trim(c.fix_date), ''), '-')                        as visit_date,
    c.created_at
  from close_issues c
  join เลขงานที่ต้องการ w on w.job_id = c.job_id
  join open_issues o      on o.main_id = c.job_id
  where not exists (
    select 1 from billing_documents b
    where b.customer_case = c.job_id
      and coalesce(nullif(trim(b.asset_id), ''), '-') = coalesce(nullif(trim(c.asset_id), ''), '-')
  )
),
พร้อมลำดับ as (
  select
    n.*,
    -- นับต่อจากเลขลำดับสูงสุดเดิมของผู้รับเหมารายนั้นในรอบ 63
    coalesce(s.max_seq, 0)
      + row_number() over (partition by coalesce(n.contractor, '') order by n.job_id, n.asset_id, n.created_at)
                                                                       as new_seq,
    -- แยกรหัสสาขา 4 หลักหน้าออกจากข้อความสาขา (รูปแบบจริงคือ "0064-โป่งดุสิต")
    nullif((regexp_match(n.raw_branch, '^(\d+)'))[1], '')              as branch_code
  from คู่งานใหม่ n
  left join ลำดับเดิม s on s.contractor_key = coalesce(n.contractor, '')
)
insert into billing_documents
  (seq, round_no, round_period, customer_case, branch_code, branch_name,
   service_type, asset_id, req_date, visit_date, contractor, synced_to_sheet)
select
  x.new_seq,
  63,
  (select round_period from ช่วงรอบ),
  x.job_id,
  x.branch_code,
  -- ชื่อสาขาเอาจากทะเบียนสาขาก่อน ถ้าไม่เจอค่อยใช้ข้อความที่กรอกไว้ในงาน
  coalesce(br.branch_name, nullif(x.raw_branch, '')),
  x.service_type,
  x.asset_id,
  x.req_date,
  x.visit_date,
  x.contractor,
  false
from พร้อมลำดับ x
left join branches br on br.branch_code = x.branch_code;

commit;


-- ---------------------------------------------------------------- บล็อก D
-- ตรวจหลังรัน: ต้องเห็น 2 เลขงานนี้อยู่ในรอบ 63 แล้ว
select
  seq            as "ลำดับ",
  customer_case  as "เลขงาน",
  asset_id       as "เลขทรัพย์สิน",
  branch_code    as "รหัสสาขา",
  branch_name    as "ชื่อสาขา",
  service_type   as "งานบริการ",
  contractor     as "ผู้รับเหมา",
  round_no       as "รอบบิล",
  round_period   as "ช่วงรอบบิล",
  part_code      as "รหัสอะไหล่ (ยังว่าง รอไปเพิ่มในแอป)"
from billing_documents
where customer_case in ('CM20260904-0169', 'CM20260901-0258')
order by contractor, seq;


-- ============================================================================
-- หลังรันเสร็จ ให้ไปทำต่อในแอป:
--   1. เข้าเมนู "ตารางวางบิล" -> เลือกรอบบิลที่ 63 -> กด "โหลด/รีเฟรชข้อมูล"
--   2. จะเห็น 2 เลขงานนี้เพิ่มเข้ามา โดยยังไม่มีอะไหล่
--   3. กดปุ่ม + ที่แถวนั้นเพื่อเพิ่มอะไหล่และราคา เหมือนงานอื่นทุกอย่าง
--   4. เพิ่มเสร็จแล้วค่อยกด "ส่งบิลให้ผู้รับเหมา" ตามปกติ
-- ============================================================================
