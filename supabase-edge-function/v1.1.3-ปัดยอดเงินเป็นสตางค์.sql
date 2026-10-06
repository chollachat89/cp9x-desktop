-- v1.1.3 — ปัดยอดเงินที่มีเศษทศนิยมยาว ๆ ให้เป็นสตางค์ (2 ตำแหน่ง)
-- รันใน Supabase โปรเจกต์ maintenance-system (hefnjozijflnhdunmewl) เท่านั้น — ไม่ใช่ Inventory
--
-- ทำไม: จำนวน × ราคา ด้วยเลขทศนิยมของคอมพิวเตอร์ ได้ค่าแบบ 8.37 × 400 = 3347.9999999999995
--       ตารางวางบิลจึงโชว์ "3347.9999999999995" ขณะที่ที่อื่นโชว์ 3,348.00
-- ตรวจกับข้อมูลจริงเมื่อ 6 ต.ค. 2569 พบ 4 แถว (ยอดเงินไม่เปลี่ยน แค่ตัดเศษ 0.0000000000005 ทิ้ง):
--   CM20260902-0137  93.80000000000001   -> 93.80
--   CM20260922-0139  3347.9999999999995  -> 3348.00
--   CM20260912-0431  3452.0000000000005  -> 3452.00
--   CM20260913-0302  3920.0000000000005  -> 3920.00
-- รันซ้ำได้ ไม่มีผลเสีย (รอบที่ 2 จะไม่เจอแถวไหนแล้ว)

-- กันรันผิดโปรเจกต์: ถ้าไม่มีตาราง billing_documents จะหยุดทันที
do $$
begin
  if to_regclass('public.billing_documents') is null then
    raise exception 'ไม่พบตาราง billing_documents — น่าจะเปิดผิดโปรเจกต์ (ต้องเป็น maintenance-system)';
  end if;
end $$;

update public.billing_documents
set total_price_contractor = round(total_price_contractor, 2),
    total_price = round(total_price, 2)
where (total_price_contractor is not null and total_price_contractor <> round(total_price_contractor, 2))
   or (total_price is not null and total_price <> round(total_price, 2))
returning customer_case, qty, unit_price_contractor, total_price_contractor, total_price;
