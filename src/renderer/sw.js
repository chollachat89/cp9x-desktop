/* CP9X — Service Worker
 *
 * มีไว้เพื่อให้ Chrome บน Android เสนอปุ่ม "ติดตั้งแอป" ได้
 * Chrome ตั้งเงื่อนไขว่าเว็บต้องมี service worker ที่ดักเหตุการณ์ fetch ถึงจะถือว่าติดตั้งได้
 * (iOS ไม่มีเงื่อนไขนี้ กด "เพิ่มไปยังหน้าจอโฮม" ได้เลย จึงดูเหมือน Android ใช้ยากกว่า)
 *
 * ⚠ ตั้งใจให้ "ไม่แคชไฟล์แอปเลย" ห้ามเพิ่มการแคชไฟล์แอปเข้ามาทีหลัง
 *   ถ้าแคช ผู้ใช้จะค้างอยู่กับเวอร์ชันเก่าแม้ deploy ตัวใหม่ไปแล้ว
 *   กลายเป็นบั๊กที่ตามยากที่สุดแบบหนึ่ง เพราะแก้โค้ดถูกแล้วแต่เครื่องผู้ใช้ยังเห็นของเดิม
 *   และขัดกับ Cache-Control: no-cache ที่ตั้งไว้ในไฟล์ _headers ด้วย
 *
 * หน้าที่ทั้งหมดของไฟล์นี้: ส่งทุก request ต่อไปที่เน็ตตรง ๆ และตอบข้อความให้เวลาเน็ตหลุด
 */

// ติดตั้งเสร็จแล้วให้ทำงานทันที ไม่ต้องรอปิดแท็บเก่าทั้งหมดก่อน
self.addEventListener('install', function (event) {
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    // ล้างแคชเก่าทุกตัวทิ้ง เผื่อเคยมีเวอร์ชันที่แคชไฟล์ไว้หลงเหลืออยู่ในเครื่องผู้ใช้
    caches.keys()
      .then(function (names) { return Promise.all(names.map(function (n) { return caches.delete(n); })); })
      .then(function () { return self.clients.claim(); })
  );
});

self.addEventListener('fetch', function (event) {
  // ยุ่งเฉพาะการเปิดหน้าเว็บ (navigate) ที่เหลือปล่อยผ่านให้เบราว์เซอร์จัดการเองตามปกติ
  // โดยเฉพาะการยิงไป Supabase ต้องไม่ถูกแตะ ไม่งั้นจะไปกวนพฤติกรรม CORS และ error ที่แอปอ่านอยู่
  if (event.request.mode !== 'navigate') return;

  event.respondWith(
    fetch(event.request).catch(function () {
      return new Response(
        '<!DOCTYPE html><html lang="th"><head><meta charset="utf-8">' +
        '<meta name="viewport" content="width=device-width, initial-scale=1">' +
        '<title>CP9X — ไม่มีอินเทอร์เน็ต</title></head>' +
        '<body style="font-family:system-ui,sans-serif;background:#14532d;color:#fff;' +
        'display:flex;align-items:center;justify-content:center;height:100vh;margin:0;padding:24px;text-align:center">' +
        '<div><h1 style="font-size:20px;margin:0 0 8px">ไม่มีอินเทอร์เน็ต</h1>' +
        '<p style="opacity:.8;margin:0 0 20px;font-size:14px">CP9X ต้องต่ออินเทอร์เน็ตเพื่อดึงข้อมูลจากเซิร์ฟเวอร์</p>' +
        '<button onclick="location.reload()" style="background:#15803d;color:#fff;border:0;' +
        'padding:12px 24px;border-radius:8px;font-size:15px">ลองใหม่</button></div></body></html>',
        { headers: { 'Content-Type': 'text/html; charset=utf-8' } }
      );
    })
  );
});
