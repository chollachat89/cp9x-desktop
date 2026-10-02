-- ============================================================================
--  v1.0.75 — แจ้งเตือน SLA เข้า Telegram อัตโนมัติ
-- ============================================================================
--
--  รันในโปรเจกต์ที่จะใช้งาน (ทดสอบก่อน แล้วค่อยของจริง)
--  รันซ้ำได้ ไม่พัง
--
--  ต้อง deploy index.ts ตัวใหม่ก่อน แล้วค่อยรันไฟล์นี้
--
--  ---------------------------------------------------------------
--  ภาพรวม
--  ---------------------------------------------------------------
--  ระบบจะยิงข้อความเข้ากลุ่ม/แชท Telegram เมื่องานถึงเกณฑ์เวลา (SLA)
--      🟡 ใกล้ครบกำหนด (เหลือง)   — แจ้ง 1 ครั้งตอนถึงเส้นเตือน
--      🔴 เกินกำหนด (แดง)         — แจ้งอีก 1 ครั้งตอนเลยเส้นกำหนด
--      🔁 ตีกลับ → ส่งใหม่        — เตือนซ้ำทุก 30 นาที จนกว่าจะส่ง (ตามกติกาเดิม)
--
--  ตัวนับเวลาเป็นตัวเดียวกับที่โชว์ในรายงานสถานะ (หยุดนับตอนพักงาน, นาฬิกาจริง 24 ชม.)
--
--  ไฟล์นี้ทำ 3 อย่าง
--      1. ตาราง sla_notifications  — จำว่าแจ้งอะไรไปแล้ว กันยิงซ้ำทุกรอบ
--      2. ใส่ค่าตั้งค่า Telegram ลง app_secrets (คุณกรอกค่าจริงเอง)
--      3. ตั้ง pg_cron ให้เรียกทุก 15 นาที (ทำงานแม้ไม่มีใครเปิดแอป)
-- ============================================================================


-- ---------------------------------------------------------------------------
--  1. ตารางจำสถานะการแจ้งเตือน (กันสแปม)
-- ---------------------------------------------------------------------------
--  1 แถว = 1 งาน + 1 เลขทรัพย์สิน + 1 ช่วงเวลา
--  เก็บว่าแจ้งไปถึงระดับไหนแล้ว และรอบเตือนซ้ำ (ของช่วงตีกลับ) ถึงรอบที่เท่าไหร่
--
--  stage_started_at = เวลาเริ่มของช่วงนั้น ใช้จับว่าช่วงถูก "เริ่มใหม่" หรือยัง
--  เช่น รูปถูกตีกลับรอบสอง เวลาเริ่มจะเปลี่ยน โค้ดจะรีเซ็ตแล้วเริ่มนับเตือนใหม่

create table if not exists sla_notifications (
  main_id          text not null,
  asset_id         text not null default '',   -- '' = ช่วงที่ไม่ผูกกับเลขทรัพย์สิน (เช่น เปิดงาน→ปิดงาน ก่อนมีเลขทรัพย์)
  stage_key        text not null,              -- close / photoSubmit / photoReview / resend
  last_level       text,                        -- ระดับล่าสุดที่แจ้งไป: warning / overdue
  last_reminder    integer not null default 0,  -- รอบเตือนซ้ำล่าสุด (ใช้กับช่วงตีกลับ)
  stage_started_at timestamptz,                 -- เวลาเริ่มของช่วง ใช้ตรวจว่าช่วงถูกรีสตาร์ท
  last_sent_at     timestamptz,
  primary key (main_id, asset_id, stage_key)
);

comment on table sla_notifications is
  'กันแจ้งเตือน SLA ซ้ำ: จำว่างาน+เลขทรัพย์สิน+ช่วงเวลาไหน แจ้งเข้า Telegram ไปถึงระดับใดแล้ว';


-- ---------------------------------------------------------------------------
--  2. ค่าตั้งค่า Telegram  ★ แก้ค่าในบรรทัดล่างก่อนรัน
-- ---------------------------------------------------------------------------
--  วิธีหาค่า
--      telegram_bot_token   : ทักหา @BotFather ใน Telegram -> /newbot -> ได้โทเคนหน้าตา 1234:AbC...
--      telegram_sla_chat_id : เชิญบอทเข้ากลุ่มก่อน แล้วส่งข้อความในกลุ่ม 1 ที
--                             เปิด https://api.telegram.org/bot<โทเคน>/getUpdates จะเห็น "chat":{"id":-100...}
--                             เลขนั้นแหละ (กลุ่มมักขึ้นต้นด้วยเครื่องหมายลบ)
--      telegram_cron_secret : ตั้งเองเป็นข้อความสุ่มยาว ๆ เช่น พิมพ์มั่ว 30-40 ตัว ใช้ให้ pg_cron เรียกได้
--
--  ⚠ โปรเจกต์ทดสอบ: "ไม่ต้อง" ใส่ค่าจริง ปล่อยว่างไว้ ระบบจะเงียบเอง (จะได้ไม่ยิงหาทีมจริง)

insert into app_secrets (key, value) values
  ('telegram_bot_token',   'ใส่โทเคนบอทที่นี่'),
  ('telegram_sla_chat_id', 'ใส่ chat id ที่นี่'),
  ('telegram_cron_secret', 'ใส่รหัสลับสุ่มยาวๆ ที่นี่')
on conflict (key) do nothing;   -- รันซ้ำจะไม่ทับค่าที่คุณกรอกไว้แล้ว

--  ถ้าจะแก้ค่าทีหลัง ใช้ (แก้ทีละ key):
--     update app_secrets set value = 'ค่าใหม่' where key = 'telegram_bot_token';


-- ---------------------------------------------------------------------------
--  3. ตั้ง pg_cron ให้เรียกทุก 15 นาที  ★ แก้ 2 จุดในบล็อกล่างก่อนรัน
-- ---------------------------------------------------------------------------
--  ต้องเปิด 2 ส่วนขยายก่อน (Supabase เปิดให้ในแดชบอร์ด Database > Extensions ก็ได้)
create extension if not exists pg_cron;
create extension if not exists pg_net;

--  แก้ 2 จุดนี้ให้เป็นของโปรเจกต์คุณ
--     <<PROJECT_REF>>       : เช่น hefnjozijflnhdunmewl (ดูใน URL ของโปรเจกต์)
--     <<PUBLISHABLE_KEY>>   : คีย์ sb_publishable_... ตัวเดียวกับที่ใช้ในแอป (ไม่ใช่ service_role)
--     <<CRON_SECRET>>       : ให้ตรงกับ telegram_cron_secret ที่ตั้งไว้ข้อ 2 เป๊ะ ๆ
--
--  ไม่ใช้คีย์ service_role ที่นี่โดยตั้งใจ — ถ้าหลุดจะเข้าถึงฐานข้อมูลทั้งหมดได้
--  ใช้ publishable key (เปิดเผยได้) + รหัสลับใน body แทน ปลอดภัยกว่า

-- ยกเลิกตัวเก่าก่อน (กันซ้ำเวลารันไฟล์นี้หลายรอบ) — ครั้งแรกจะ error ว่าไม่เจอ ไม่เป็นไร ข้ามได้
select cron.unschedule('cp9x-sla-telegram') where exists (
  select 1 from cron.job where jobname = 'cp9x-sla-telegram'
);

select cron.schedule(
  'cp9x-sla-telegram',
  '*/15 * * * *',            -- ทุก 15 นาที
  $$
  select net.http_post(
    url     := 'https://<<PROJECT_REF>>.supabase.co/functions/v1/app-api',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer <<PUBLISHABLE_KEY>>',
      'apikey',        '<<PUBLISHABLE_KEY>>'
    ),
    body    := jsonb_build_object(
      'fnName', 'runSlaNotifications',
      'args',   jsonb_build_array('<<CRON_SECRET>>')
    )
  );
  $$
);


-- ---------------------------------------------------------------------------
--  ตรวจผล
-- ---------------------------------------------------------------------------
select
  (select count(*) from information_schema.tables
    where table_schema = 'public' and table_name = 'sla_notifications')
    as "ตาราง sla_notifications (ต้องได้ 1)",
  (select count(*) from app_secrets
    where key in ('telegram_bot_token','telegram_sla_chat_id','telegram_cron_secret'))
    as "ค่าตั้งค่า Telegram (ต้องได้ 3)",
  (select count(*) from cron.job where jobname = 'cp9x-sla-telegram')
    as "ตารางเวลา cron (ต้องได้ 1)";

--  หลังรันเสร็จ: เปิดแอป ล็อกอินแอดมิน -> ปุ่ม "ตรวจความพร้อมระบบ" -> กด "ทดสอบ Telegram"
--  ต้องมีข้อความเด้งเข้ากลุ่ม ถ้าไม่เข้า เช็คว่าเชิญบอทเข้ากลุ่มแล้ว และ chat id ถูกต้อง
