-- ============================================================================
-- ข้อมูลตัวอย่างสำหรับทดสอบระบบ CP9X (ชุดวันที่ 1 กันยายน 2569)
--
-- ปลอดภัย: ทุกแถวใช้เลขงานชุด CM20260901-9001 ถึง -9006 ซึ่งเป็นเลขสมมติที่ไม่ชนกับงานจริง
-- ลบทิ้งทีหลังได้ด้วยบล็อก Z ท้ายไฟล์ (ลบเฉพาะเลขงานชุดนี้ ไม่แตะข้อมูลจริง)
--
-- ผู้รับเหมาที่ผูกไว้: 'ทีมพี่สมชาย' (ล็อกอินด้วย contractor11 / 1234)
--   ถ้ายังไม่ได้รันไฟล์ add-contractor-ทีมพี่สมชาย.sql ให้รันก่อน ไม่งั้นจะทดสอบฝั่งผู้รับเหมาไม่ได้
--
-- ชุดข้อมูลนี้ครอบคลุมของใหม่ทุกอย่างที่เพิ่งทำไป:
--   - 1 เลขงานมีหลายเลขทรัพย์สิน           -> CM20260901-9003 (2 ทรัพย์สิน)
--   - 1 เลขทรัพย์สินมีหลายอะไหล่           -> CM20260901-9002 (2 อะไหล่ คนละประเภทเก็บเงิน)
--   - อะไหล่นอกระบบรหัส NP                 -> NP001 / NP002
--   - เก็บเงินปกติ / เคลมอะไหล่ / เคลมประกัน 3 เดือน  -> ครบทั้ง 3 ประเภท
--   - พักงานที่มีหลายสาเหตุและหลายรายการ    -> CM20260901-9005
--   - งานที่ยังไม่ปิด                       -> CM20260901-9005 (พักอยู่)
--
-- วิธีใช้: https://supabase.com/dashboard/project/hefnjozijflnhdunmewl/sql/new
-- วางทั้งไฟล์ กด Run ครั้งเดียวจบ (รันซ้ำได้ ไม่เกิดข้อมูลซ้ำ เพราะมี where not exists)
-- ============================================================================


-- ---------------------------------------------------------------- บล็อก A: เปิดงาน 6 เลขงาน
insert into open_issues (main_id, service_type, contract_type, req_date, service_work, service_issue, branch, details, contractor, synced_to_sheet, created_at)
select 'CM20260901-9001', 'งานเครื่องเย็น', 'Service Contract', '01/09/2026, 08:15', 'F04_ตู้แช่หน้าเปิด', 'F04_ไม่เย็น/อุณหภูมิไม่ได้มาตรฐาน', '0064-โป่งดุสิต', 'ตู้แช่หน้าเปิดอุณหภูมิไม่ได้มาตรฐาน ของสดเริ่มเสีย', 'ทีมพี่สมชาย', false, timestamptz '2026-09-01 08:15:00+07'
where not exists (select 1 from open_issues where main_id = 'CM20260901-9001');
insert into open_issues (main_id, service_type, contract_type, req_date, service_work, service_issue, branch, details, contractor, synced_to_sheet, created_at)
select 'CM20260901-9002', 'งานเครื่องเย็น', 'Service Contract', '01/09/2026, 09:40', 'F10_เครื่องปรับอากาศ (แอร์)', 'F10_น้ำหยด', '0315-บ้านสร้าง', 'แอร์หน้าร้านมีน้ำหยดลงพื้นจำนวนมาก', 'ทีมพี่สมชาย', false, timestamptz '2026-09-01 09:40:00+07'
where not exists (select 1 from open_issues where main_id = 'CM20260901-9002');
insert into open_issues (main_id, service_type, contract_type, req_date, service_work, service_issue, branch, details, contractor, synced_to_sheet, created_at)
select 'CM20260901-9003', 'งานเครื่องเย็น', 'Service Contract', '01/09/2026, 10:05', 'F03_ห้องเย็น (ColdRoom)', 'F03_มีน้ำรั่วซึม', '1303-ละแม เมืองเก่า', 'ห้องเย็นมีน้ำรั่วซึมออกมาที่พื้น', 'ทีมพี่สมชาย', false, timestamptz '2026-09-01 10:05:00+07'
where not exists (select 1 from open_issues where main_id = 'CM20260901-9003');
insert into open_issues (main_id, service_type, contract_type, req_date, service_work, service_issue, branch, details, contractor, synced_to_sheet, created_at)
select 'CM20260901-9004', 'งานเครื่องเย็น', 'Service Contract', '01/09/2026, 11:20', 'F02_ตู้แช่หน้าปิด 2 ประตู/ 3 ประตู', 'F02_หลอดไฟดับ', '0787-วัดแจ้งลำหิน บึงคำพร้อย', 'หลอดไฟในตู้แช่หน้าปิดดับ 2 จุด', 'ทีมพี่สมชาย', false, timestamptz '2026-09-01 11:20:00+07'
where not exists (select 1 from open_issues where main_id = 'CM20260901-9004');
insert into open_issues (main_id, service_type, contract_type, req_date, service_work, service_issue, branch, details, contractor, synced_to_sheet, created_at)
select 'CM20260901-9005', 'งานเครื่องเย็น', 'Service Contract', '01/09/2026, 13:00', 'F01_ตู้แช่ข้าวกล่อง 1 ประตู (Frozen Food)', 'F01_มีเสียงดัง', '1732-เทพคุณากร', 'ตู้แช่ข้าวกล่องมีเสียงดังผิดปกติตลอดเวลา', 'ทีมพี่สมชาย', false, timestamptz '2026-09-01 13:00:00+07'
where not exists (select 1 from open_issues where main_id = 'CM20260901-9005');
insert into open_issues (main_id, service_type, contract_type, req_date, service_work, service_issue, branch, details, contractor, synced_to_sheet, created_at)
select 'CM20260901-9006', 'งานเครื่องเย็น', 'Service Contract', '01/09/2026, 14:30', 'F07_ตู้แช่ร้านกาแฟ', 'F07_ไม่เย็น/อุณหภูมิไม่ได้มาตรฐาน', '0059-วัดเพลง', 'ตู้แช่ร้านกาแฟไม่เย็น', 'ทีมพี่สมชาย', false, timestamptz '2026-09-01 14:30:00+07'
where not exists (select 1 from open_issues where main_id = 'CM20260901-9006');


-- ---------------------------------------------------------------- บล็อก B: ปิดงาน 6 ครั้ง (CM20260901-9003 ปิด 2 ครั้ง คนละเลขทรัพย์สิน)
insert into close_issues (job_id, branch, fix_date, parts, asset_id, action_taken, synced_to_sheet, created_at)
select 'CM20260901-9001', '0064-โป่งดุสิต', '1-9-2026', 'มอเตอร์พัดลม CDU', '130024031070', 'เปลี่ยนมอเตอร์พัดลม CDU ทดสอบแล้วอุณหภูมิลงปกติ', false, timestamptz '2026-09-01 15:10:00+07'
where not exists (select 1 from close_issues where job_id = 'CM20260901-9001' and asset_id = '130024031070');
insert into close_issues (job_id, branch, fix_date, parts, asset_id, action_taken, synced_to_sheet, created_at)
select 'CM20260901-9002', '0315-บ้านสร้าง', '1-9-2026', 'ฟิลเตอร์กรองฝุ่น', '130000019339', 'ล้างแอร์และเปลี่ยนฟิลเตอร์ น้ำไม่หยดแล้ว', false, timestamptz '2026-09-01 16:00:00+07'
where not exists (select 1 from close_issues where job_id = 'CM20260901-9002' and asset_id = '130000019339');
insert into close_issues (job_id, branch, fix_date, parts, asset_id, action_taken, synced_to_sheet, created_at)
select 'CM20260901-9003', '1303-ละแม เมืองเก่า', '1-9-2026', 'ชุดท่อน้ำทิ้ง', '130025048863', 'เปลี่ยนชุดท่อน้ำทิ้งคอยล์เย็นตัวที่ 1', false, timestamptz '2026-09-01 16:30:00+07'
where not exists (select 1 from close_issues where job_id = 'CM20260901-9003' and asset_id = '130025048863');
insert into close_issues (job_id, branch, fix_date, parts, asset_id, action_taken, synced_to_sheet, created_at)
select 'CM20260901-9003', '1303-ละแม เมืองเก่า', '1-9-2026', 'ชุดท่อน้ำทิ้ง', '130025048864', 'เปลี่ยนชุดท่อน้ำทิ้งคอยล์เย็นตัวที่ 2', false, timestamptz '2026-09-01 16:45:00+07'
where not exists (select 1 from close_issues where job_id = 'CM20260901-9003' and asset_id = '130025048864');
insert into close_issues (job_id, branch, fix_date, parts, asset_id, action_taken, synced_to_sheet, created_at)
select 'CM20260901-9004', '0787-วัดแจ้งลำหิน บึงคำพร้อย', '1-9-2026', 'หลอดไฟ LED', '130021002110', 'เปลี่ยนหลอดไฟ LED 2 หลอด', false, timestamptz '2026-09-01 17:00:00+07'
where not exists (select 1 from close_issues where job_id = 'CM20260901-9004' and asset_id = '130021002110');
insert into close_issues (job_id, branch, fix_date, parts, asset_id, action_taken, synced_to_sheet, created_at)
select 'CM20260901-9006', '0059-วัดเพลง', '1-9-2026', 'คอมเพรสเซอร์', '130024009655', 'เปลี่ยนคอมเพรสเซอร์ใหม่ (งานเคลมประกัน)', false, timestamptz '2026-09-01 17:30:00+07'
where not exists (select 1 from close_issues where job_id = 'CM20260901-9006' and asset_id = '130024009655');


-- ---------------------------------------------------------------- บล็อก C: พักงาน 1 งาน (หลายสาเหตุ + หลายรายการ)
-- ทดสอบช่องแบบหลายบรรทัดที่เพิ่งเพิ่มใน v1.0.40
insert into pause_records (main_id, reason, note, branch, service_type, cause, requested_item, paused_by, status, synced_to_sheet, paused_at)
select 'CM20260901-9005', 'รออะไหล่', 'ลูกค้ารับทราบแล้ว รออะไหล่เข้าประมาณ 5 วัน',
       '1732-เทพคุณากร', 'F01_ตู้แช่ข้าวกล่อง 1 ประตู (Frozen Food)',
       '- คอมเพรสเซอร์มีเสียงดังผิดปกติ' || chr(10) || '- ยางรองขาคอมเพรสเซอร์เสื่อมสภาพ' || chr(10) || '- พัดลมคอยล์ร้อนหมุนติดขัด',
       '- คอมเพรสเซอร์ 1 ตัว' || chr(10) || '- ยางรองขาคอมเพรสเซอร์ 4 ชิ้น' || chr(10) || '- มอเตอร์พัดลมคอยล์ร้อน 1 ตัว',
       'ทีมพี่สมชาย', 'paused', false, timestamptz '2026-09-01 15:45:00+07'
where not exists (select 1 from pause_records where main_id = 'CM20260901-9005');


-- ---------------------------------------------------------------- บล็อก D: ตารางวางบิล (รอบบิลที่ 1)
-- ส่งบิลให้ผู้รับเหมาแล้ว (sent_to_contractor = true) แต่ยังไม่ตัดบิล (completed_at = null)
-- จึงจะเห็นได้ทั้งฝั่งแอดมินและฝั่งผู้รับเหมา และเห็นในแท็บ 'ฟอร์มวางบิล' ของผู้รับเหมาด้วย
insert into billing_documents (seq, round_no, round_period, customer_case, branch_code, branch_name, service_type, asset_id, part_code, part_detail, warranty_months, qty, unit, unit_price, total_price, unit_price_contractor, total_price_contractor, req_date, visit_date, quotation_ref, return_old_part, responsible, company, contractor, billing_type, sent_to_contractor, synced_to_sheet)
select 1, 1, '1 ก.ย. 2026 ถึง 30 ก.ย. 2026', 'CM20260901-9001', '0064', '0064-โป่งดุสิต', 'F04_ตู้แช่หน้าเปิด', '130024031070', 'P003', 'มอเตอร์พัดลม CDU - เครื่องปรับอากาศ HITACHI - รุ่น RPFC-B42TNT2NH', '3', 1, 'ชิ้น', 8500, 8500, 6800, 6800, '01/09/2026, 08:15', '1-9-2026', 'QT-2026-09-9001', 'YES', 'ทีมพี่สมชาย', 'บริษัท ซีอาร์ เอ็นเนอร์จี คอนซัลแตนท์ จำกัด', 'ทีมพี่สมชาย', 'normal', true, false
where not exists (select 1 from billing_documents where customer_case = 'CM20260901-9001' and asset_id = '130024031070' and part_code = 'P003');
insert into billing_documents (seq, round_no, round_period, customer_case, branch_code, branch_name, service_type, asset_id, part_code, part_detail, warranty_months, qty, unit, unit_price, total_price, unit_price_contractor, total_price_contractor, req_date, visit_date, quotation_ref, return_old_part, responsible, company, contractor, billing_type, sent_to_contractor, synced_to_sheet)
select 2, 1, '1 ก.ย. 2026 ถึง 30 ก.ย. 2026', 'CM20260901-9002', '0315', '0315-บ้านสร้าง', 'F10_เครื่องปรับอากาศ (แอร์)', '130000019339', 'P006', 'ฟิลเตอร์กรองฝุ่น - เครื่องปรับอากาศ HITACHI', '3', 2, 'ชิ้น', 1250, 2500, 1000, 2000, '01/09/2026, 09:40', '1-9-2026', 'QT-2026-09-9002', 'NO', 'ทีมพี่สมชาย', 'บริษัท ซีอาร์ เอ็นเนอร์จี คอนซัลแตนท์ จำกัด', 'ทีมพี่สมชาย', 'normal', true, false
where not exists (select 1 from billing_documents where customer_case = 'CM20260901-9002' and asset_id = '130000019339' and part_code = 'P006');
insert into billing_documents (seq, round_no, round_period, customer_case, branch_code, branch_name, service_type, asset_id, part_code, part_detail, warranty_months, qty, unit, unit_price, total_price, unit_price_contractor, total_price_contractor, req_date, visit_date, quotation_ref, return_old_part, responsible, company, contractor, billing_type, sent_to_contractor, synced_to_sheet)
select 2, 1, '1 ก.ย. 2026 ถึง 30 ก.ย. 2026', 'CM20260901-9002', '0315', '0315-บ้านสร้าง', 'F10_เครื่องปรับอากาศ (แอร์)', '130000019339', 'P008', 'ตะแกรง CDU - เครื่องปรับอากาศ HITACHI', '3', 1, 'ชิ้น', 800, 800, 650, 650, '01/09/2026, 09:40', '1-9-2026', 'QT-2026-09-9002', 'NO', 'ทีมพี่สมชาย', 'บริษัท ซีอาร์ เอ็นเนอร์จี คอนซัลแตนท์ จำกัด', 'ทีมพี่สมชาย', 'contractor_cr', true, false
where not exists (select 1 from billing_documents where customer_case = 'CM20260901-9002' and asset_id = '130000019339' and part_code = 'P008');
insert into billing_documents (seq, round_no, round_period, customer_case, branch_code, branch_name, service_type, asset_id, part_code, part_detail, warranty_months, qty, unit, unit_price, total_price, unit_price_contractor, total_price_contractor, req_date, visit_date, quotation_ref, return_old_part, responsible, company, contractor, billing_type, sent_to_contractor, synced_to_sheet)
select 3, 1, '1 ก.ย. 2026 ถึง 30 ก.ย. 2026', 'CM20260901-9003', '1303', '1303-ละแม เมืองเก่า', 'F03_ห้องเย็น (ColdRoom)', '130025048863', 'P005', 'มอเตอร์สวิง - เครื่องปรับอากาศ HITACHI', '3', 1, 'ชิ้น', 1000, 1000, 845, 845, '01/09/2026, 10:05', '1-9-2026', 'QT-2026-09-9003', 'YES', 'ทีมพี่สมชาย', 'บริษัท ซีอาร์ เอ็นเนอร์จี คอนซัลแตนท์ จำกัด', 'ทีมพี่สมชาย', 'normal', true, false
where not exists (select 1 from billing_documents where customer_case = 'CM20260901-9003' and asset_id = '130025048863' and part_code = 'P005');
insert into billing_documents (seq, round_no, round_period, customer_case, branch_code, branch_name, service_type, asset_id, part_code, part_detail, warranty_months, qty, unit, unit_price, total_price, unit_price_contractor, total_price_contractor, req_date, visit_date, quotation_ref, return_old_part, responsible, company, contractor, billing_type, sent_to_contractor, synced_to_sheet)
select 3, 1, '1 ก.ย. 2026 ถึง 30 ก.ย. 2026', 'CM20260901-9003', '1303', '1303-ละแม เมืองเก่า', 'F03_ห้องเย็น (ColdRoom)', '130025048864', 'NP001', 'ชุดท่อน้ำทิ้ง PVC พร้อมข้อต่อ (สั่งพิเศษนอกระบบ)', '3', 1, 'ชุด', 1800, 1800, 1400, 1400, '01/09/2026, 10:05', '1-9-2026', 'QT-2026-09-9003', 'NO', 'ทีมพี่สมชาย', 'บริษัท ซีอาร์ เอ็นเนอร์จี คอนซัลแตนท์ จำกัด', 'ทีมพี่สมชาย', 'normal', true, false
where not exists (select 1 from billing_documents where customer_case = 'CM20260901-9003' and asset_id = '130025048864' and part_code = 'NP001');
insert into billing_documents (seq, round_no, round_period, customer_case, branch_code, branch_name, service_type, asset_id, part_code, part_detail, warranty_months, qty, unit, unit_price, total_price, unit_price_contractor, total_price_contractor, req_date, visit_date, quotation_ref, return_old_part, responsible, company, contractor, billing_type, sent_to_contractor, synced_to_sheet)
select 4, 1, '1 ก.ย. 2026 ถึง 30 ก.ย. 2026', 'CM20260901-9004', '0787', '0787-วัดแจ้งลำหิน บึงคำพร้อย', 'F02_ตู้แช่หน้าปิด 2 ประตู/ 3 ประตู', '130021002110', 'NP002', 'หลอดไฟ LED T8 18W (สั่งพิเศษนอกระบบ)', '3', 2, 'หลอด', 450, 900, 320, 640, '01/09/2026, 11:20', '1-9-2026', 'QT-2026-09-9004', 'NO', 'ทีมพี่สมชาย', 'บริษัท ซีอาร์ เอ็นเนอร์จี คอนซัลแตนท์ จำกัด', 'ทีมพี่สมชาย', 'contractor_cr', true, false
where not exists (select 1 from billing_documents where customer_case = 'CM20260901-9004' and asset_id = '130021002110' and part_code = 'NP002');
insert into billing_documents (seq, round_no, round_period, customer_case, branch_code, branch_name, service_type, asset_id, part_code, part_detail, warranty_months, qty, unit, unit_price, total_price, unit_price_contractor, total_price_contractor, req_date, visit_date, quotation_ref, return_old_part, responsible, company, contractor, billing_type, sent_to_contractor, synced_to_sheet)
select 5, 1, '1 ก.ย. 2026 ถึง 30 ก.ย. 2026', 'CM20260901-9006', '0059', '0059-วัดเพลง', 'F07_ตู้แช่ร้านกาแฟ', '130024009655', 'P007', 'COMPRESSOR - เครื่องปรับอากาศ HITACHI (พร้อมอุปกรณ์ชุดสตาร์ท)', '3', 1, 'ชุด', 29500, 29500, 24000, 24000, '01/09/2026, 14:30', '1-9-2026', 'QT-2026-09-9006', 'YES', 'ทีมพี่สมชาย', 'บริษัท ซีอาร์ เอ็นเนอร์จี คอนซัลแตนท์ จำกัด', 'ทีมพี่สมชาย', 'claim', true, false
where not exists (select 1 from billing_documents where customer_case = 'CM20260901-9006' and asset_id = '130024009655' and part_code = 'P007');


-- ---------------------------------------------------------------- บล็อก E: ตรวจผล
select 'open_issues'   as "ตาราง", count(*) as "แถวตัวอย่าง" from open_issues   where main_id      like 'CM20260901-900%'
union all select 'close_issues',    count(*) from close_issues     where job_id       like 'CM20260901-900%'
union all select 'pause_records',   count(*) from pause_records    where main_id      like 'CM20260901-900%'
union all select 'billing_documents', count(*) from billing_documents where customer_case like 'CM20260901-900%';

-- แยกตามประเภทเก็บเงิน ควรได้ normal 4 / contractor_cr 2 / claim 1
select billing_type as "ประเภทเก็บเงิน", count(*) as "จำนวนแถว"
from billing_documents where customer_case like 'CM20260901-900%'
group by billing_type order by count(*) desc;


-- ---------------------------------------------------------------- บล็อก Z: ลบข้อมูลตัวอย่างทิ้ง
-- (รันเมื่อทดสอบเสร็จแล้ว ลบเฉพาะเลขงานชุดตัวอย่าง ไม่แตะข้อมูลจริงเลย)
-- begin;
-- delete from billing_documents where customer_case like 'CM20260901-900%';
-- delete from pause_records     where main_id       like 'CM20260901-900%';
-- delete from close_issues      where job_id        like 'CM20260901-900%';
-- delete from open_issues       where main_id       like 'CM20260901-900%';
-- commit;
