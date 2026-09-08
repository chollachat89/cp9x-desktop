-- ============================================================================
-- ตารางข้อมูลรับประกันทรัพย์สิน (asset_warranty)
-- ใช้เติมช่อง "วันเริ่มรับประกัน / วันหมดประกัน" ในฟอร์มแนบรูปที่ผู้รับเหมาดาวน์โหลด
--
-- ข้อมูล 54,866 เลขทรัพย์สิน จากไฟล์ "ฟอล์มส่งรูปวางบิล.xlsx" ชีต _Asset
-- (คอลัมน์ S = Warranty Start Date, T = Number of Months Warranty, U = Warranty Expire Date)
--
-- ⚠ ไม่ใส่ข้อมูลผ่าน SQL เพราะไฟล์ใหญ่ 2 MB ให้นำเข้าด้วย asset-warranty.csv
--   ผ่านหน้า Table Editor แทน (ดูขั้นตอนท้ายไฟล์)
--
-- หมายเหตุเรื่องข้อมูลต้นทาง:
--   - ในไฟล์ต้นฉบับมีทรัพย์สิน 61,464 แถว แต่มีวันรับประกันจริงแค่ 54,866 เลข
--     ที่เหลือช่องว่างเปล่า ฟอร์มจะขึ้นเป็น "-" ให้กรอกมือ
--   - มี 166 เลขที่ปรากฏซ้ำโดยวันรับประกันไม่ตรงกัน เลือกเก็บ "แถวที่วันหมดประกันช้าที่สุด"
--     เพราะทรัพย์สินอาจถูกต่อประกันหรือเปลี่ยนสัญญา ข้อมูลใหม่กว่าคือตัวที่ใช้จริงตอนเคลม
--   - เก็บแยกเป็นตารางของตัวเอง ไม่ไปรวมกับ branch_assets เพราะ branch_assets
--     มี 1,210 เลขที่ตั้งใจให้ซ้ำได้ (คนละคำอธิบายในสาขาเดียวกัน) ถ้ารวมกันข้อมูลรับประกันจะซ้ำตาม
--
-- วิธีใช้: https://supabase.com/dashboard/project/hefnjozijflnhdunmewl/sql/new
-- ============================================================================


-- ---------------------------------------------------------------- ขั้นที่ 1
-- สร้างตาราง (รันบล็อกนี้ก่อน)
create table if not exists asset_warranty (
    asset_no         text primary key,
    warranty_start   date,
    warranty_expire  date,
    warranty_months  integer
);

-- ดัชนีตามวันหมดประกัน — เผื่ออนาคตอยากดึงรายการ "ทรัพย์สินที่ใกล้หมดประกัน"
create index if not exists asset_warranty_expire_idx on asset_warranty (warranty_expire);

comment on table asset_warranty is 'วันรับประกันรายเลขทรัพย์สิน ใช้เติมหัวฟอร์มแนบรูปที่ผู้รับเหมาดาวน์โหลด';

-- เปิดให้ Edge Function อ่านได้ (ใช้ service role key อยู่แล้ว แต่ตั้ง policy ไว้ให้ชัดเจน)
alter table asset_warranty enable row level security;

drop policy if exists asset_warranty_read on asset_warranty;
create policy asset_warranty_read on asset_warranty for select using (true);


-- ---------------------------------------------------------------- ขั้นที่ 2
-- นำเข้าข้อมูลจากไฟล์ asset-warranty.csv (ไม่ต้องรัน SQL — ทำผ่านหน้าเว็บ)
--
--   1. เข้า https://supabase.com/dashboard/project/hefnjozijflnhdunmewl/editor
--   2. เลือกตาราง asset_warranty ทางแถบซ้าย
--   3. กดปุ่ม "Insert" → "Import data from CSV"
--   4. เลือกไฟล์ asset-warranty.csv (อยู่โฟลเดอร์เดียวกับไฟล์นี้)
--   5. ตรวจว่าชื่อคอลัมน์จับคู่กันครบทั้ง 4 ช่อง แล้วกด Import
--   6. รอจนขึ้นว่าเสร็จ (ไฟล์ 2 MB ใช้เวลาราว 1-2 นาที)


-- ---------------------------------------------------------------- ขั้นที่ 3
-- ตรวจหลังนำเข้า: ต้องได้ 54,866 แถว และตัวอย่างข้อมูลต้องอ่านออกเป็นวันที่จริง
select
  count(*)                                      as "จำนวนแถวทั้งหมด",
  count(warranty_start)                         as "มีวันเริ่มประกัน",
  count(warranty_expire)                        as "มีวันหมดประกัน",
  min(warranty_start)                           as "วันเริ่มเก่าสุด",
  max(warranty_expire)                          as "วันหมดช้าสุด",
  count(*) filter (where warranty_expire >= current_date) as "ยังอยู่ในประกัน"
from asset_warranty;

-- ดูตัวอย่าง 10 แถว
select asset_no       as "เลขทรัพย์สิน",
       warranty_start as "วันเริ่มประกัน",
       warranty_expire as "วันหมดประกัน",
       warranty_months as "จำนวนเดือน"
from asset_warranty
order by asset_no
limit 10;


-- ---------------------------------------------------------------- ขั้นที่ 4 (ไม่บังคับ)
-- เช็คว่าทรัพย์สินที่ใช้งานจริงในระบบ มีข้อมูลรับประกันครอบคลุมแค่ไหน
select
  count(distinct b.asset_id)                                        as "เลขทรัพย์สินที่เคยวางบิล",
  count(distinct b.asset_id) filter (where w.asset_no is not null)  as "ที่มีข้อมูลรับประกัน",
  count(distinct b.asset_id) filter (where w.asset_no is null)      as "ที่ไม่มี (ฟอร์มจะขึ้น -)"
from billing_documents b
left join asset_warranty w on w.asset_no = b.asset_id
where b.asset_id is not null and trim(b.asset_id) <> '' and b.asset_id <> '-';


-- ============================================================================
-- อัปเดตข้อมูลรอบหน้า: ถ้าได้ไฟล์ _Asset ใหม่มา ให้บอกให้สร้าง CSV ชุดใหม่
-- แล้วนำเข้าทับด้วยวิธีเดียวกัน (ตารางนี้ใช้ asset_no เป็น primary key
-- การ Import ซ้ำจะขึ้น error เรื่องคีย์ซ้ำ ให้ล้างตารางก่อนด้วย truncate asset_warranty;)
-- ============================================================================
