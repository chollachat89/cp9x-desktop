-- =====================================================================
--  ตรวจ: ทำไม 3 เลขงานนี้ไม่ขึ้นในใบเขียวผู้รับเหมา (เมนูตารางวางบิล ฝั่งแอดมิน)
--     CM20261018-0290  · สาขา 1915-การเคหะบึงพระ
--     CM20261016-0198  · สาขา 1796-ตลาดวัดจุฬามณี พิษณุโลก
--     CM20261022-0210  · สาขา 1797-ไชยานุภาพ
--
--  ⚠ ไฟล์นี้ "อ่านอย่างเดียว" ไม่มีคำสั่งแก้ข้อมูลแม้แต่คำสั่งเดียว รันได้ปลอดภัย
--  รันในโปรเจกต์ maintenance-system แล้วส่งผลทั้ง 4 ตารางกลับมา
--
-- ---------------------------------------------------------------------
--  กติกาจริงของแอป v1.1.6 (ถอดจากโค้ดที่ใช้งานอยู่)
-- ---------------------------------------------------------------------
--  ปุ่มใบเขียวสร้าง PDF จาก "แถวที่โหลดอยู่ในตารางตอนนั้น" เท่านั้น
--  ไม่ได้ไปดึงใหม่จากฐานข้อมูล แถวจะหายได้ 2 ชั้น
--
--  ชั้นที่ 1 — ตอนโหลดตาราง (ฝั่งเซิร์ฟเวอร์)
--    ก. เลือก "ทุกรอบ" + ไม่ได้เลือกผู้รับเหมา  (ค่าเริ่มต้น)
--         completed_at IS NULL  และ  (sent_to_contractor IS NULL หรือ false)
--         => ตัดบิลแล้ว หรือ ส่งบิลไปแล้ว = ไม่โหลดมา
--    ข. เลือก "ทุกรอบ" + เลือกผู้รับเหมา
--         completed_at IS NULL  และ  contractor = คนที่เลือก
--         => ส่งบิลแล้วก็ยังเห็น (ข้อนี้ต่างจาก ก. ตรงนี้เป็นจุดที่คนงงบ่อยที่สุด)
--    ค. เลือกรอบบิลเจาะจง
--         round_no = รอบที่เลือก  (ไม่สนว่าตัดบิล/ส่งบิลไปแล้วหรือยัง)
--
--  ชั้นที่ 2 — ตอนกดปุ่มใบเขียว (ฝั่งหน้าจอ)
--    ตัดประเภทที่ผู้รับเหมาไม่เก็บเงินออก: 'claim' (เคลมประกัน 3 เดือน) และ 'quotation' (ใบเสนอราคา)
-- =====================================================================


-- =====================================================================
--  ตารางที่ 1 — ภาพรวมรายเลขงาน: มีแถวบิลไหม ปิดงานหรือยัง ถูกคืนงานไหม
-- =====================================================================
with want(job) as (
  values ('CM20261018-0290'), ('CM20261016-0198'), ('CM20261022-0210')
)
select w.job                                                            as "เลขงาน",
       (select count(*) from public.open_issues o  where o.main_id = w.job)   as "แถวเปิดงาน",
       (select count(*) from public.close_issues c where c.job_id  = w.job)   as "แถวปิดงาน",
       (select count(*) from public.billing_documents b where b.customer_case = w.job) as "แถวในตารางวางบิล",
       (select count(*) from public.billing_job_registry r
         where split_part(r.customer_case, '__asset__', 1) = w.job)           as "คีย์จองรอบบิล",
       coalesce((select count(*) from public.billing_removed_jobs m where m.job_id = w.job), 0) as "เคยถูกคืนงาน",
       (select string_agg(distinct o.contractor, ' · ') from public.open_issues o where o.main_id = w.job) as "ผู้รับเหมา (จากเปิดงาน)"
from want w
order by w.job;


-- =====================================================================
--  ตารางที่ 2 — ★ ตัวตอบคำถามหลัก: แต่ละแถวบิลจะขึ้นใบเขียวไหม และเพราะอะไร
-- =====================================================================
select b.customer_case                                   as "เลขงาน",
       b.asset_id                                        as "เลขทรัพย์สิน",
       b.round_no                                        as "รอบบิล",
       b.contractor                                      as "ผู้รับเหมา",
       b.part_code                                       as "รหัสอะไหล่",
       b.qty                                             as "จำนวน",
       b.total_price_contractor                          as "ยอด ผรม.",
       coalesce(nullif(btrim(b.billing_type), ''), 'normal') as "ประเภทเก็บเงิน",
       case coalesce(nullif(btrim(b.billing_type), ''), 'normal')
         when 'normal'        then 'เก็บเงินปกติ'
         when 'claim'         then 'เคลมประกัน 3 เดือน'
         when 'contractor_cr' then 'เคลมอะไหล่'
         when 'quotation'     then 'ใบเสนอราคา'
         else coalesce(b.billing_type, '(ว่าง)') end     as "ประเภท (ไทย)",
       case when b.sent_to_contractor is true then 'ส่งแล้ว' else 'ยังไม่ส่ง' end as "ส่งบิลให้ ผรม.",
       case when b.completed_at is not null then 'ตัดบิลแล้ว' else 'ยังไม่ตัดบิล' end as "สถานะตัดบิล",

       -- ---- คำตัดสินทีละชั้น ----
       case
         when coalesce(nullif(btrim(b.billing_type), ''), 'normal') in ('claim', 'quotation')
           then '✗ ไม่มีวันขึ้นใบเขียว — ประเภทนี้ไม่เก็บเงินฝั่ง ผรม.'
         when b.completed_at is not null
           then '△ ขึ้นได้เฉพาะตอนเลือกรอบบิลเจาะจง (ตัดบิลแล้ว)'
         when b.sent_to_contractor is true
           then '△ ขึ้นได้เมื่อเลือกผู้รับเหมา หรือเลือกรอบบิลเจาะจง (ส่งบิลไปแล้ว)'
         else '✓ ขึ้นได้ในมุมมองค่าเริ่มต้น (ทุกรอบ)'
       end                                               as "★ สรุป",

       -- ---- ขึ้นไหมในแต่ละมุมมอง ----
       case when coalesce(nullif(btrim(b.billing_type), ''), 'normal') in ('claim','quotation') then 'ไม่'
            when b.completed_at is null and b.sent_to_contractor is not true then 'ขึ้น' else 'ไม่' end
                                                         as "ก. ทุกรอบ ไม่เลือก ผรม.",
       case when coalesce(nullif(btrim(b.billing_type), ''), 'normal') in ('claim','quotation') then 'ไม่'
            when b.completed_at is null then 'ขึ้น' else 'ไม่' end
                                                         as "ข. ทุกรอบ + เลือก ผรม.",
       case when coalesce(nullif(btrim(b.billing_type), ''), 'normal') in ('claim','quotation') then 'ไม่'
            else 'ขึ้น' end                              as "ค. เลือกรอบบิลเจาะจง",

       -- กรอกครบไหม (ไม่ครบ = ส่งบิลไม่ได้ แต่ยังขึ้นใบเขียวได้)
       case when coalesce(btrim(b.part_code), '') = '' or coalesce(b.qty, 0) <= 0
            then '⚠ ยังกรอก Part Code/จำนวนไม่ครบ' else '' end as "หมายเหตุ",
       b.sent_at                                         as "วันที่ส่งบิล",
       b.completed_at                                    as "วันที่ตัดบิล"
from public.billing_documents b
where b.customer_case in ('CM20261018-0290', 'CM20261016-0198', 'CM20261022-0210')
order by b.customer_case, b.round_no, b.seq, b.asset_id;


-- =====================================================================
--  ตารางที่ 3 — ถ้าตารางที่ 2 ว่างเปล่า (ยังไม่มีแถวบิลเลย) ให้ดูตรงนี้
--               ว่าติดที่ขั้นตอนไหน: ยังไม่ปิดงาน / ยังไม่ยืนยันรูป / ถูกคืนงาน
-- =====================================================================
with want(job) as (
  values ('CM20261018-0290'), ('CM20261016-0198'), ('CM20261022-0210')
)
select w.job                                     as "เลขงาน",
       c.asset_id                                as "เลขทรัพย์สิน",
       c.fix_date                                as "วันที่เข้าแก้ไข",
       c.parts                                   as "อะไหล่ที่กรอกตอนปิดงาน",
       coalesce((select s.status from public.job_form_submissions s
                  where s.customer_case = w.job order by s.submitted_at desc limit 1),
                '(ยังไม่ส่งฟอร์มรูป)')            as "สถานะฟอร์มรูปล่าสุด",
       case when exists (select 1 from public.billing_removed_jobs m
                          where m.job_id = w.job and coalesce(m.asset_id,'') = coalesce(c.asset_id,''))
            then '⚠ คู่นี้เคยถูกกดคืนงาน — จะไม่ถูกดึงเข้ารอบบิลอีก' else '' end as "ถูกคืนงานไหม",
       case when exists (select 1 from public.billing_documents b
                          where b.customer_case = w.job and coalesce(b.asset_id,'-') = coalesce(c.asset_id,'-'))
            then 'มีแถวบิลแล้ว' else '✗ ยังไม่มีแถวบิลของคู่นี้' end as "มีแถวบิลหรือยัง"
from want w
left join public.close_issues c on c.job_id = w.job
order by w.job, c.asset_id;


-- =====================================================================
--  ตารางที่ 4 — ถ้าแถวมีอยู่แต่ "ผู้รับเหมาไม่ตรง" ก็จะไม่ขึ้นตอนกรองผู้รับเหมา
--               เทียบชื่อผู้รับเหมาในแถวบิล กับในเปิดงาน และกับรายชื่อผู้ใช้
-- =====================================================================
select b.customer_case                         as "เลขงาน",
       b.contractor                            as "ผู้รับเหมาในแถวบิล",
       o.contractor                            as "ผู้รับเหมาในเปิดงาน",
       case when b.contractor is distinct from o.contractor
            then '⚠ ไม่ตรงกัน — กรองตามผู้รับเหมาแล้วจะไม่เจอ' else 'ตรงกัน' end as "ตรงกันไหม",
       case when exists (select 1 from public.contractors u
                          where u.display_name = b.contractor)
            then 'มีผู้ใช้ชื่อนี้' else '⚠ ไม่มีผู้ใช้ชื่อนี้ในระบบ' end as "มีบัญชีผู้ใช้ไหม"
from public.billing_documents b
left join public.open_issues o on o.main_id = b.customer_case
where b.customer_case in ('CM20261018-0290', 'CM20261016-0198', 'CM20261022-0210')
group by b.customer_case, b.contractor, o.contractor
order by b.customer_case;
