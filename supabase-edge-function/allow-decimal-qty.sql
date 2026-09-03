-- ============================================================================
-- รองรับ "จำนวน" ที่เป็นทศนิยม ในตารางวางบิล (billing_documents)
--
-- ทำไมต้องมี: อะไหล่บางรายการขายเป็น เมตร หรือ กก. แต่เวลาใช้จริงไม่ลงตัวเสมอ
-- เช่น เติมน้ำยา 1.6 กก. หรือ เดินท่อ 0.7 เมตร
-- ถ้าคอลัมน์ qty เป็นชนิดจำนวนเต็ม (integer) ฐานข้อมูลจะปัดเศษทิ้งหรือปฏิเสธค่าไปเลย
-- ทำให้ยอดเงินคลาดเคลื่อนโดยไม่มีใครรู้ตัว
--
-- คอลัมน์ที่เกี่ยวข้องทั้งหมด 5 คอลัมน์:
--   qty                     จำนวนที่ใช้จริง
--   unit_price              ราคา/หน่วย ฝั่ง CJ
--   total_price             = qty x unit_price
--   unit_price_contractor   ราคา/หน่วย ฝั่งผู้รับเหมา
--   total_price_contractor  = qty x unit_price_contractor
--
-- ไฟล์นี้จะเปลี่ยนชนิดคอลัมน์เป็น numeric "เฉพาะตัวที่ยังเป็นจำนวนเต็มอยู่" เท่านั้น
-- ตัวที่เป็น numeric/double อยู่แล้วจะข้ามไป ไม่ทำอะไรซ้ำ (รันซ้ำได้ปลอดภัย)
-- การเปลี่ยนจาก integer เป็น numeric ไม่ทำให้ข้อมูลเดิมหาย ค่าเดิมยังเท่าเดิมทุกแถว
--
-- วิธีใช้: https://supabase.com/dashboard/project/hefnjozijflnhdunmewl/sql/new
-- ============================================================================


-- ---------------------------------------------------------------- บล็อก A
-- ดูก่อนว่าตอนนี้แต่ละคอลัมน์เป็นชนิดอะไร
-- ถ้าคอลัมน์ไหนขึ้นว่า integer / bigint / smallint แปลว่ายังเก็บทศนิยมไม่ได้ ต้องรันบล็อก B
select column_name as "คอลัมน์", data_type as "ชนิดข้อมูลตอนนี้",
       case when data_type in ('integer','bigint','smallint') then 'ต้องแก้ (เก็บทศนิยมไม่ได้)'
            else 'ใช้ได้อยู่แล้ว' end as "สถานะ"
from information_schema.columns
where table_schema = 'public' and table_name = 'billing_documents'
  and column_name in ('qty','unit_price','total_price','unit_price_contractor','total_price_contractor')
order by column_name;


-- ---------------------------------------------------------------- บล็อก B
-- เปลี่ยนชนิดเป็น numeric เฉพาะคอลัมน์ที่ยังเป็นจำนวนเต็มอยู่
do $$
declare
  c text;
  t text;
begin
  foreach c in array array['qty','unit_price','total_price','unit_price_contractor','total_price_contractor']
  loop
    select data_type into t
    from information_schema.columns
    where table_schema = 'public' and table_name = 'billing_documents' and column_name = c;

    if t in ('integer','bigint','smallint') then
      execute format('alter table billing_documents alter column %I type numeric using %I::numeric', c, c);
      raise notice 'แก้คอลัมน์ % จาก % เป็น numeric แล้ว', c, t;
    else
      raise notice 'ข้ามคอลัมน์ % (เป็น % อยู่แล้ว)', c, t;
    end if;
  end loop;
end $$;


-- ---------------------------------------------------------------- บล็อก C
-- ตรวจหลังรัน: คอลัมน์ "สถานะ" ต้องขึ้นว่า "ใช้ได้อยู่แล้ว" ครบทั้ง 5 แถว
select column_name as "คอลัมน์", data_type as "ชนิดข้อมูล",
       case when data_type in ('integer','bigint','smallint') then 'ยังแก้ไม่สำเร็จ'
            else 'ใช้ได้อยู่แล้ว' end as "สถานะ"
from information_schema.columns
where table_schema = 'public' and table_name = 'billing_documents'
  and column_name in ('qty','unit_price','total_price','unit_price_contractor','total_price_contractor')
order by column_name;


-- ---------------------------------------------------------------- บล็อก D
-- ทดสอบว่าเก็บทศนิยมได้จริง (ไม่แตะข้อมูลจริง แค่คำนวณให้ดู)
-- ตัวอย่างตามที่ใช้งานจริง: น้ำยา R32 1.6 กก. ราคา 575/กก. และ ท่อ 0.7 เมตร ราคา 800/เมตร
select 1.6::numeric as "จำนวน (กก.)", 575::numeric as "ราคา/หน่วย", (1.6 * 575)::numeric as "ราคารวมที่ควรได้"
union all
select 0.7, 800, (0.7 * 800)::numeric;
