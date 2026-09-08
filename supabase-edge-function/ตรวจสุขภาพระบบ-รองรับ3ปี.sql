-- ============================================================================
-- ตรวจสุขภาพระบบ CP9X — วัดของจริงว่าตอนนี้ข้อมูลเท่าไหร่ และ 3 ปีจะเป็นยังไง
--
-- ไฟล์นี้ "อ่านอย่างเดียวทั้งไฟล์" ไม่แก้ ไม่ลบ ไม่เขียนอะไรเลย รันได้ปลอดภัย 100%
--
-- วิธีใช้: https://supabase.com/dashboard/project/hefnjozijflnhdunmewl/sql/new
--          รันทีละบล็อก แล้วส่งผลลัพธ์กลับมา จะได้ประเมินจากตัวเลขจริงไม่ใช่เดา
-- ============================================================================


-- ---------------------------------------------------------------- บล็อก 1
-- จำนวนแถวจริงของทุกตาราง + ขนาดที่กินจริงบนดิสก์
select
  c.relname                                              as "ตาราง",
  to_char(c.reltuples::bigint, 'FM999,999,999')          as "จำนวนแถว (ประมาณ)",
  pg_size_pretty(pg_total_relation_size(c.oid))          as "ขนาดรวม",
  pg_size_pretty(pg_relation_size(c.oid))                as "ขนาดข้อมูล",
  pg_size_pretty(pg_indexes_size(c.oid))                 as "ขนาดดัชนี"
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r'
order by pg_total_relation_size(c.oid) desc;


-- ---------------------------------------------------------------- บล็อก 2
-- นับแถวแบบแม่นยำ (ช้ากว่าบล็อก 1 แต่ได้ตัวเลขเป๊ะ)
select 'open_issues'          as "ตาราง", count(*) as "แถว" from open_issues
union all select 'close_issues',          count(*) from close_issues
union all select 'billing_documents',     count(*) from billing_documents
union all select 'pause_records',         count(*) from pause_records
union all select 'job_form_submissions',  count(*) from job_form_submissions
union all select 'pm_billing_documents',  count(*) from pm_billing_documents
union all select 'branches',              count(*) from branches
union all select 'branch_assets',         count(*) from branch_assets
union all select 'asset_warranty',        count(*) from asset_warranty
union all select 'parts',                 count(*) from parts
union all select 'contractors',           count(*) from contractors
order by "แถว" desc;


-- ---------------------------------------------------------------- บล็อก 3
-- อัตราโตต่อเดือน — ตัวเลขนี้สำคัญที่สุด ใช้คูณ 36 เดือนเพื่อประเมิน 3 ปี
select
  to_char(created_at, 'YYYY-MM')                  as "เดือน",
  count(*) filter (where src = 'open')            as "เปิดงาน",
  count(*) filter (where src = 'close')           as "ปิดงาน",
  count(*) filter (where src = 'billing')         as "แถววางบิล",
  count(*) filter (where src = 'submission')      as "ไฟล์ที่ผรม.ส่งกลับ"
from (
  select created_at, 'open'::text     as src from open_issues
  union all select created_at, 'close'      from close_issues
  union all select created_at, 'billing'    from billing_documents
  union all select submitted_at, 'submission' from job_form_submissions
) t
where created_at is not null
group by 1
order by 1;


-- ---------------------------------------------------------------- บล็อก 4
-- ⚠ จุดที่ต้องดูที่สุด: ดัชนี (index) ที่มีอยู่จริงตอนนี้
-- ตารางที่ใช้บ่อยแต่ไม่มีดัชนีเลย = ทุกครั้งที่ค้นหา Postgres ต้องไล่อ่านทุกแถว
select
  t.relname                        as "ตาราง",
  coalesce(i.relname, '— ไม่มีดัชนีเลย —') as "ชื่อดัชนี",
  coalesce(
    (select string_agg(a.attname, ', ' order by k.ord)
     from unnest(ix.indkey) with ordinality k(attnum, ord)
     join pg_attribute a on a.attrelid = t.oid and a.attnum = k.attnum),
    '-') as "คอลัมน์"
from pg_class t
join pg_namespace n on n.oid = t.relnamespace
left join pg_index ix on ix.indrelid = t.oid
left join pg_class i on i.oid = ix.indexrelid
where n.nspname = 'public' and t.relkind = 'r'
  and t.relname in ('open_issues','close_issues','billing_documents','pause_records',
                    'job_form_submissions','pm_billing_documents','branches','parts')
order by t.relname, i.relname;


-- ---------------------------------------------------------------- บล็อก 5
-- ขนาดไฟล์ที่ผู้รับเหมาส่งกลับ (เก็บใน Storage) — ตัวนี้บวมเร็วที่สุดในระบบ
select
  count(*)                                                as "จำนวนไฟล์",
  pg_size_pretty(sum((metadata->>'size')::bigint))        as "ขนาดรวมตอนนี้",
  pg_size_pretty(avg((metadata->>'size')::bigint)::bigint) as "ขนาดเฉลี่ยต่อไฟล์",
  pg_size_pretty(max((metadata->>'size')::bigint))        as "ไฟล์ใหญ่สุด"
from storage.objects
where bucket_id = 'job-form-submissions';

-- แยกตามเดือน เพื่อดูอัตราโตของ Storage
select
  to_char(created_at, 'YYYY-MM')                    as "เดือน",
  count(*)                                          as "จำนวนไฟล์",
  pg_size_pretty(sum((metadata->>'size')::bigint))  as "ขนาดรวมเดือนนั้น"
from storage.objects
where bucket_id = 'job-form-submissions'
group by 1
order by 1;


-- ---------------------------------------------------------------- บล็อก 6
-- ไฟล์กำพร้าใน Storage (ลบแถวในฐานข้อมูลไปแล้ว แต่ไฟล์ยังค้างอยู่)
-- ถ้าเคยรัน "ลบประวัติฟอร์มที่ผู้รับเหมาส่งกลับ.sql" ตัวเลขนี้จะไม่เป็นศูนย์
select
  count(*)                                          as "ไฟล์กำพร้า (ลบทิ้งได้)",
  pg_size_pretty(coalesce(sum((metadata->>'size')::bigint), 0)) as "พื้นที่ที่ได้คืนถ้าลบ"
from storage.objects o
where o.bucket_id = 'job-form-submissions'
  and not exists (
    select 1 from job_form_submissions s where s.drive_file_id = o.name
  );


-- ---------------------------------------------------------------- บล็อก 7
-- ตารางวางบิลโตยังไง แยกตามรอบบิล — ใช้ดูว่ารอบหนึ่งมีกี่แถว
select
  count(distinct round_no)                          as "จำนวนรอบบิลทั้งหมด",
  count(*)                                          as "แถวทั้งหมด",
  round(count(*)::numeric / nullif(count(distinct round_no), 0), 1) as "เฉลี่ยแถวต่อรอบ",
  min(round_no)                                     as "รอบแรก",
  max(round_no)                                     as "รอบล่าสุด"
from billing_documents
where round_no is not null;


-- ---------------------------------------------------------------- บล็อก 8
-- ข้อมูลที่ "ตัดบิลจบแล้ว" มีสัดส่วนเท่าไหร่
-- ถ้าเยอะมาก = ข้อมูลเก่าที่ไม่ต้องดึงมาทุกครั้ง แต่ระบบยังดึงมาอยู่
select
  count(*)                                                          as "แถวทั้งหมด",
  count(*) filter (where completed_at is not null)                  as "ตัดบิลแล้ว (ข้อมูลเก่า)",
  count(*) filter (where completed_at is null and sent_to_contractor) as "ส่งบิลแล้ว รอตัด",
  count(*) filter (where completed_at is null and not sent_to_contractor) as "ยังไม่ส่งบิล (งานปัจจุบัน)",
  round(100.0 * count(*) filter (where completed_at is not null) / nullif(count(*), 0), 1) as "% ที่เป็นข้อมูลเก่า"
from billing_documents;


-- ============================================================================
-- หลังรันครบ 8 บล็อก ให้ส่งผลลัพธ์กลับมา โดยเฉพาะ:
--   บล็อก 3 (อัตราโตต่อเดือน)  -> ใช้ประเมิน 3 ปี
--   บล็อก 4 (ดัชนีที่มี)        -> ใช้ตัดสินว่าต้องเพิ่มดัชนีตัวไหน
--   บล็อก 5 (ขนาด Storage)     -> ตัวที่บวมเร็วที่สุด
--
-- และช่วยเช็คค่านี้ในหน้าเว็บให้ด้วย 1 ค่า (SQL อ่านไม่ได้):
--   Settings -> API -> "Max rows"  ค่าปัจจุบันคือเท่าไหร่?
--   ค่านี้คือเพดานจำนวนแถวสูงสุดที่ API จะคืนได้ในครั้งเดียว
--   ถ้าตั้งไว้ต่ำ (เช่น 1000) โค้ดที่ดึงข้อมูลทั้งตารางจะ "ได้ไม่ครบแบบเงียบ ๆ" ไม่ขึ้น error
-- ============================================================================
