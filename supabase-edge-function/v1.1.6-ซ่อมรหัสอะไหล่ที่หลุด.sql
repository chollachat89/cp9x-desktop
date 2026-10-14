-- v1.1.6 — ซ่อมแถวที่ "รหัสอะไหล่หลุด" เพราะข้อความมีเลขลำดับนำหน้า
-- รันใน Supabase SQL Editor ของโปรเจกต์ maintenance-system (hefnjozijflnhdunmewl) เท่านั้น
--
-- อาการ: ปิดงานกรอก "1. P190-สารทำความเย็น = 1.57" -> ระบบแกะรหัสไม่ได้
--        -> part_code ว่าง · ราคาเป็น 0 · รายละเอียดเป็นข้อความดิบ "1.P190-..."
--
-- ไฟล์นี้แบ่งเป็น 3 ขั้น  ***ขั้นที่ 1 อ่านอย่างเดียว ไม่แก้อะไร — รันดูก่อนทุกครั้ง***
-- กติกาการตัดเลขลำดับตรงกับโค้ด stripPartLineNo ใน index.ts เป๊ะ ๆ
--   ตัดเฉพาะเมื่อ "หลังเลขลำดับไม่ใช่ตัวเลข"  => "2.5 นิ้ว" ไม่ถูกแตะ

-- กันรันผิดโปรเจกต์
do $$
begin
  if to_regclass('public.billing_documents') is null or to_regclass('public.parts') is null then
    raise exception 'ไม่พบตาราง billing_documents/parts — น่าจะเปิดผิดโปรเจกต์ (ต้องเป็น maintenance-system)';
  end if;
end $$;


-- ===================================================================
-- ขั้นที่ 1 — ดูก่อนว่ามีแถวไหนเสีย (อ่านอย่างเดียว ปลอดภัย)
-- ===================================================================
with cand as (
  select b.id, b.customer_case, b.asset_id, b.round_no,
         b.part_code, b.part_detail, b.qty, b.unit_price, b.unit_price_contractor,
         b.sent_to_contractor, (b.completed_at is not null) as done,
         -- ตัดเลขลำดับนำหน้าออกจากรายละเอียด แล้วแกะรหัสตัวแรก
         upper((regexp_match(
           regexp_replace(coalesce(b.part_detail,''), '^(\s*\d+\s*[.)]\s*)+(?=[^\d\s])', '', 'g'),
           '^([A-Za-z]{1,4}\s*[0-9][A-Za-z0-9]*)'
         ))[1]) as guess_code
  from public.billing_documents b
  where coalesce(trim(b.part_code), '') = ''        -- ยังไม่มีรหัส
    and coalesce(b.part_detail, '') <> ''
)
select c.*, p.code_cj as found_in_parts, p.unit_price as parts_cj, p."Unit Custumer" as parts_contractor,
       case
         when c.guess_code is null then 'แกะรหัสไม่ได้ (ต้องดูเอง)'
         when p.code_cj is null    then 'มีรหัสแต่ไม่มีในคลังอะไหล่'
         when c.done               then 'ตัดบิลแล้ว — ไม่แก้อัตโนมัติ'
         when coalesce(c.unit_price,0) <> 0 or coalesce(c.unit_price_contractor,0) <> 0
                                   then 'มีราคาอยู่แล้ว — เติมแค่รหัส'
         else 'ซ่อมได้: เติมรหัส + ราคา'
       end as plan
from cand c
left join public.parts p on upper(trim(p.code_cj)) = c.guess_code
order by c.done, c.round_no desc nulls last, c.customer_case;


-- ===================================================================
-- ขั้นที่ 2 — ล้างเลขลำดับใน close_issues (ต้นทาง) กันเกิดซ้ำตอนดึงเข้ารอบบิลใหม่
--            แก้ทั้งข้อความใน parts_json และเลขลำดับที่ซ้อนกันในคอลัมน์ parts
-- ===================================================================
-- 2.1 ข้อความในแต่ละรายการอะไหล่ (parts_json) + เติม partCode ที่หายไป
update public.close_issues c
set parts_json = sub.fixed
from (
  select c2.id,
         jsonb_agg(
           case
             when regexp_replace(coalesce(e->>'text',''), '^(\s*\d+\s*[.)]\s*)+(?=[^\d\s])', '', 'g') = coalesce(e->>'text','')
                  and coalesce(e->>'partCode','') <> ''
               then e                                        -- สะอาดอยู่แล้ว ไม่ต้องแตะ
             else jsonb_set(
                    jsonb_set(e, '{text}',
                      to_jsonb(regexp_replace(coalesce(e->>'text',''), '^(\s*\d+\s*[.)]\s*)+(?=[^\d\s])', '', 'g'))),
                    '{partCode}',
                    to_jsonb(coalesce(
                      nullif(upper(coalesce(e->>'partCode','')), ''),
                      upper((regexp_match(
                        regexp_replace(coalesce(e->>'text',''), '^(\s*\d+\s*[.)]\s*)+(?=[^\d\s])', '', 'g'),
                        '^([A-Za-z]{1,4}\s*[0-9][A-Za-z0-9]*)'))[1]),
                      '')))
           end
           order by (e->>'no')::int nulls last
         ) as fixed
  from public.close_issues c2,
       lateral jsonb_array_elements(c2.parts_json) e
  where c2.parts_json is not null
    and jsonb_typeof(c2.parts_json) = 'array'
    and jsonb_array_length(c2.parts_json) > 0
    and exists (
      select 1 from jsonb_array_elements(c2.parts_json) e2
      where regexp_replace(coalesce(e2->>'text',''), '^(\s*\d+\s*[.)]\s*)+(?=[^\d\s])', '', 'g') <> coalesce(e2->>'text','')
         or coalesce(e2->>'partCode','') = ''
    )
  group by c2.id
) sub
where c.id = sub.id;

-- 2.2 คอลัมน์ parts (ข้อความรวม) — ลบเลขลำดับที่ซ้อนกัน เช่น "1. 1. P190" -> "1. P190"
--     เก็บเลขลำดับตัวแรกไว้ (เป็นเลขที่ระบบเติมให้เอง) ตัดเฉพาะตัวที่เกินมา
update public.close_issues
set parts = regexp_replace(parts,
      '(^|\n)(\s*\d+\s*[.)]\s*)((?:\s*\d+\s*[.)]\s*)+)(?=[^\d\s])', '\1\2', 'g')
where parts is not null
  and parts <> regexp_replace(parts,
      '(^|\n)(\s*\d+\s*[.)]\s*)((?:\s*\d+\s*[.)]\s*)+)(?=[^\d\s])', '\1\2', 'g');


-- ===================================================================
-- ขั้นที่ 3 — เติมรหัส (+ ราคา) ให้แถวในตารางวางบิลที่หลุดไป
--            เงื่อนไขกันพลาด: ไม่แตะแถวที่ตัดบิลแล้ว
--            และเติมราคาเฉพาะแถวที่ยังไม่มีราคาเลย (ไม่ทับราคาที่แอดมินแก้เอง)
-- ===================================================================
with cand as (
  select b.id, b.qty, b.unit_price, b.unit_price_contractor,
         upper((regexp_match(
           regexp_replace(coalesce(b.part_detail,''), '^(\s*\d+\s*[.)]\s*)+(?=[^\d\s])', '', 'g'),
           '^([A-Za-z]{1,4}\s*[0-9][A-Za-z0-9]*)'))[1]) as guess_code
  from public.billing_documents b
  where coalesce(trim(b.part_code), '') = ''
    and coalesce(b.part_detail, '') <> ''
    and b.completed_at is null
)
update public.billing_documents b
set part_code   = replace(c.guess_code, ' ', ''),
    -- เติมรายละเอียด/หน่วย/ประกัน/ราคา จากคลัง เฉพาะแถวที่ยังไม่มีราคาเลย
    part_detail = case when nofee then concat_ws(' - ', p.name, p.brand, p.model) else b.part_detail end,
    unit        = case when nofee then p.unit            else b.unit end,
    warranty_months = case when nofee then p.warranty_months else b.warranty_months end,
    return_old_part = case when nofee then p.return_old_part else b.return_old_part end,
    company     = case when nofee then p.company         else b.company end,
    unit_price  = case when nofee then p.unit_price      else b.unit_price end,
    total_price = case when nofee then round(coalesce(b.qty,0) * coalesce(p.unit_price,0), 2) else b.total_price end,
    unit_price_contractor  = case when nofee then p."Unit Custumer" else b.unit_price_contractor end,
    total_price_contractor = case when nofee then round(coalesce(b.qty,0) * coalesce(p."Unit Custumer",0), 2) else b.total_price_contractor end
from cand c
join public.parts p on upper(trim(p.code_cj)) = c.guess_code,
     lateral (select (coalesce(c.unit_price,0) = 0 and coalesce(c.unit_price_contractor,0) = 0) as nofee) z
where b.id = c.id and c.guess_code is not null;

-- ตรวจผลหลังซ่อม: ต้องไม่เหลือแถวที่รายละเอียดขึ้นต้นด้วยเลขลำดับแล้วไม่มีรหัส
select count(*) as ยังเหลือต้องดูเอง
from public.billing_documents
where coalesce(trim(part_code), '') = ''
  and part_detail ~ '^(\s*\d+\s*[.)]\s*)+[A-Za-z]';
