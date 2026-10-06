-- ตรวจว่าทำไมเลขงาน CM20260905-0289 ดึงใบเขียวผู้รับเหมาไม่ได้ (อ่านอย่างเดียว ไม่แก้ข้อมูล)
-- รันใน SQL Editor ของโปรเจกต์ maintenance-system แล้วก๊อปผลลัพธ์ทั้งตารางมาให้ Claude
-- ใช้ ilike + ตัดช่องว่าง เผื่อเลขงานในตารางมีช่องว่าง/ตัวอักษรแฝงติดมา (สาเหตุที่ค้นตรงตัวแล้วไม่เจอ)
select 'เปิดงาน' as src, main_id as job, null as asset, contractor, null as billing_type, null::boolean as sent,
       null as review, null::text as done, null::text as round, length(main_id) as len, created_at::text as at
from open_issues where main_id ilike '%20260905-0289%'
union all
select 'ปิดงาน', job_id, asset_id, null, null, null, null, null, null, length(job_id), created_at::text
from close_issues where job_id ilike '%20260905-0289%'
union all
select 'บิล', customer_case, asset_id, contractor, coalesce(billing_type, '(ว่าง)'), sent_to_contractor,
       contractor_review_status, completed_at::text, round_no::text || ' / เข้างาน ' || coalesce(visit_date, '-'),
       length(customer_case), created_at::text
from billing_documents where customer_case ilike '%20260905-0289%'
union all
select 'คืนงาน', job_id, asset_id, removed_by, reason, null, null, null, round_no::text, length(job_id), removed_at::text
from billing_removed_jobs where job_id ilike '%20260905-0289%'
union all
select 'จองรอบบิล', customer_case, null, null, null, null, null, null, null, length(customer_case), null
from billing_job_registry where customer_case ilike '%20260905-0289%'
order by 1, 11;
