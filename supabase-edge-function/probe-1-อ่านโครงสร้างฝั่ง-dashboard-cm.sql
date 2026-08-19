-- ============================================================================
-- PROBE 1 — อ่านโครงสร้างฝั่ง Dashboard CM (โปรเจกต์ vzyhueinaeulsxfpilrv)
--
-- ไฟล์นี้ "อ่านอย่างเดียว" ไม่แก้ ไม่ลบ ไม่เพิ่มข้อมูลใด ๆ ทั้งสิ้น รันซ้ำได้ปลอดภัย
--
-- วิธีใช้:
--   1. เปิด https://supabase.com/dashboard/project/vzyhueinaeulsxfpilrv/sql/new
--   2. วางทีละบล็อก (A, B, C) แล้วกด Run
--   3. คัดลอกผลลัพธ์ของแต่ละบล็อกกลับมาวางในแชท
--
-- ต้องได้ผลครบทั้ง 3 บล็อก ผมถึงจะเขียนสคริปต์ย้ายข้อมูลให้ตรงคอลัมน์เขาได้
-- ============================================================================


-- ---------------------------------------------------------------- บล็อก A
-- มีตารางอะไรบ้าง และแต่ละตารางมีกี่แถว
select
  c.relname                                   as "ตาราง",
  case c.relkind when 'r' then 'table' when 'v' then 'view' when 'm' then 'matview' else c.relkind::text end as "ชนิด",
  coalesce(s.n_live_tup, 0)                   as "จำนวนแถวโดยประมาณ"
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
left join pg_stat_user_tables s on s.relid = c.oid
where n.nspname = 'public'
  and c.relkind in ('r', 'v', 'm')
order by c.relkind, c.relname;


-- ---------------------------------------------------------------- บล็อก B
-- คอลัมน์ทั้งหมดของทุกตารางใน public (ชื่อ / ชนิดข้อมูล / ว่างได้ไหม / ค่าเริ่มต้น)
select
  table_name                                  as "ตาราง",
  ordinal_position                            as "ลำดับ",
  column_name                                 as "คอลัมน์",
  data_type                                   as "ชนิดข้อมูล",
  is_nullable                                 as "ว่างได้",
  coalesce(column_default, '')                as "ค่าเริ่มต้น"
from information_schema.columns
where table_schema = 'public'
order by table_name, ordinal_position;


-- ---------------------------------------------------------------- บล็อก C
-- Primary key และ unique constraint ที่มีอยู่
-- (จำเป็นมาก เพราะคำสั่ง ON CONFLICT DO NOTHING ที่ใช้ "ข้ามอันที่ซ้ำ"
--  จะทำงานได้ก็ต่อเมื่อมี unique index บนคอลัมน์เลขงานฝั่งเขาอยู่แล้ว
--  ถ้ายังไม่มี ผมจะเขียนคำสั่งสร้างให้ในสคริปต์รอบถัดไป)
select
  con.conrelid::regclass::text                as "ตาราง",
  con.conname                                 as "ชื่อ constraint",
  case con.contype when 'p' then 'PRIMARY KEY' when 'u' then 'UNIQUE' else con.contype::text end as "ชนิด",
  pg_get_constraintdef(con.oid)               as "นิยาม"
from pg_constraint con
join pg_namespace n on n.oid = con.connamespace
where n.nspname = 'public'
  and con.contype in ('p', 'u')
order by 1, 3;
