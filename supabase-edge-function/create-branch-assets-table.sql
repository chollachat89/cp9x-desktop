-- ============================================================================
-- ตารางทะเบียนเลขทรัพย์สินรายสาขา (branch_assets)
-- ใช้ทำ dropdown เลือกเลขทรัพย์สินในหน้า "ปิดงาน" เพื่อกันกรอกเลขผิด
--
-- ข้อมูล 39,186 แถว จาก 1,520 สาขา — ไม่ใส่ผ่าน SQL เพราะไฟล์ใหญ่เกินไป
-- ให้นำเข้าด้วยไฟล์ branch-assets.csv ผ่านหน้า Table Editor แทน (ดูขั้นตอนท้ายไฟล์)
--
-- ⚠ หมายเหตุสำคัญ: มีเลขทรัพย์สิน 1,210 เลขที่ปรากฏ 2 แถวในสาขาเดียวกัน
-- โดยมีคำอธิบายคนละอย่าง (เช่น "Compressor-Cold Room" กับ "CONDENSING Unit R404a")
-- ตามที่ตกลงกันไว้ให้แสดงแยก 2 บรรทัดใน dropdown จึง "ไม่ใส่ unique constraint"
-- บนคู่ (branch_code, asset_no) เพราะจะทำให้นำเข้าข้อมูลไม่ผ่าน
--
-- วิธีใช้: https://supabase.com/dashboard/project/hefnjozijflnhdunmewl/sql/new
-- ============================================================================

create table if not exists branch_assets (
    id           bigserial primary key,
    branch_code  text not null,
    branch_name  text,
    asset_no     text not null,
    description  text
);

-- ดัชนีตามรหัสสาขา — ตัวสำคัญที่สุด เพราะทุกครั้งที่เปิดหน้าปิดงานจะค้นด้วยรหัสสาขา
-- ถ้าไม่มีดัชนีนี้ ระบบต้องไล่อ่านทีละแถวจาก 39,186 แถว ทำให้ dropdown ขึ้นช้ามาก
create index if not exists branch_assets_branch_code_idx on branch_assets (branch_code);

-- ดัชนีตามเลขทรัพย์สิน — ใช้ตอนตรวจว่าเลขที่ดูดข้อความมามีอยู่ในสาขานั้นจริงไหม
create index if not exists branch_assets_asset_no_idx on branch_assets (asset_no);

-- ตรวจว่าสร้างสำเร็จ (ตอนนี้ยังไม่มีข้อมูล ต้องนำเข้า CSV ก่อน)
select count(*) as "จำนวนแถวในตาราง" from branch_assets;


-- ============================================================================
-- ขั้นตอนนำเข้าข้อมูล (ทำหลังจากรัน SQL ด้านบนแล้ว)
--
--   1. เปิด https://supabase.com/dashboard/project/hefnjozijflnhdunmewl/editor
--   2. เลือกตาราง branch_assets ที่เพิ่งสร้าง
--   3. กดปุ่ม Insert -> Import data from CSV
--   4. เลือกไฟล์ branch-assets.csv (อยู่โฟลเดอร์เดียวกับไฟล์นี้)
--   5. ตรวจว่าคอลัมน์จับคู่ตรงกัน: branch_code / branch_name / asset_no / description
--      (คอลัมน์ id ปล่อยว่างไว้ ระบบจะใส่เลขให้เอง)
--   6. กด Import — ใช้เวลาสักครู่เพราะมี 39,186 แถว
--
--   เสร็จแล้วรันคำสั่งนี้เพื่อตรวจ ควรได้ 39186 แถว และ 1520 สาขา:
--     select count(*) as "จำนวนแถว", count(distinct branch_code) as "จำนวนสาขา" from branch_assets;
--
-- ถ้าจะอัปเดตข้อมูลทะเบียนทรัพย์สินใหม่ทั้งชุดในอนาคต ให้ล้างตารางก่อนแล้วนำเข้าใหม่:
--     delete from branch_assets;
-- ============================================================================
