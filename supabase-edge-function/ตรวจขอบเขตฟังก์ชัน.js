// =====================================================================
//  ตรวจขอบเขตฟังก์ชันใน index.ts   —   node "supabase-edge-function/ตรวจขอบเขตฟังก์ชัน.js"
// =====================================================================
//
//  ทำไมต้องมีไฟล์นี้
//  ----------------
//  โค้ดเซิร์ฟเวอร์ทั้งก้อนอยู่ในไฟล์เดียว และแบ่งเป็น 2 ชั้น
//     ชั้นนอก (ระดับไฟล์)       ฟังก์ชันช่วยที่ไม่ต้องใช้ฐานข้อมูล
//     ชั้นใน  (ใน Deno.serve)   ทุกอย่างที่ต้องใช้ supabase / verifySession / jsonResponse
//
//  ชั้นนอก "มองไม่เห็น" ของในชั้นใน แต่ตอนเขียนโค้ดมันดูถูกต้องทุกอย่าง
//  ไม่มีเส้นใต้แดง ไม่มี error ตอน deploy — พอมีคนกดใช้งานจริงถึงพังเป็น
//     ReferenceError: verifySession is not defined
//
//  เรื่องนี้เกิดจริงแล้วครั้งหนึ่ง (v1.0.90 วาง adminGate ไว้ชั้นนอก ทำให้คำสั่งแอดมิน 18 ตัวพังหมด
//  โชคดีที่เจอก่อน deploy) ชุดทดสอบที่ใช้คำตอบจำลองจับเรื่องนี้ไม่ได้เลย เพราะไม่ได้รันโค้ดเซิร์ฟเวอร์จริง
//
//  ให้รันไฟล์นี้ทุกครั้งก่อนปล่อยเวอร์ชัน ใช้เวลาไม่ถึงวินาที
//  ออก 0 = ผ่าน · ออก 1 = มีจุดที่จะพังตอนรันจริง
// =====================================================================

'use strict';

const fs = require('fs');
const path = require('path');

const target = process.argv[2] || path.join(__dirname, 'index.ts');
if (!fs.existsSync(target)) {
  console.error('  หาไฟล์ไม่เจอ: ' + target);
  process.exit(1);
}
const lines = fs.readFileSync(target, 'utf8').split('\n');

const serveLine = lines.findIndex((l) => l.startsWith('Deno.serve('));
if (serveLine === -1) {
  console.error('  ไม่พบบรรทัด Deno.serve( ที่ต้นบรรทัด — โครงไฟล์เปลี่ยนไปแล้ว ให้ปรับตัวตรวจนี้ด้วย');
  process.exit(1);
}

// ---- ชื่อที่ประกาศในชั้นใน (ย่อหน้า 2 ช่องพอดี = ลูกตรงของ Deno.serve) ----
const inner = new Set();
for (let i = serveLine + 1; i < lines.length; i++) {
  const m = lines[i].match(/^  (?:async )?function ([A-Za-z_$][\w$]*)/)
    || lines[i].match(/^  (?:const|let|var) ([A-Za-z_$][\w$]*)\s*[=:]/);
  if (m) inner.add(m[1]);
}

// ---- ชื่อที่ประกาศในชั้นนอก ----
const top = new Set();
for (let i = 0; i < serveLine; i++) {
  const m = lines[i].match(/^(?:export )?(?:async )?function ([A-Za-z_$][\w$]*)/)
    || lines[i].match(/^(?:export )?(?:const|let|var) ([A-Za-z_$][\w$]*)\s*[=:]/);
  if (m) top.add(m[1]);
}

// ---- หาโค้ดชั้นนอกที่อ้างชื่อของชั้นใน ----
// ชื่อเดียวกันที่เป็นพารามิเตอร์ หรือตัวแปรที่ประกาศเองในฟังก์ชันนั้น ถือว่าคนละตัว (บังกันอยู่)
const hits = [];
let shadow = null;
for (let i = 0; i < serveLine; i++) {
  const raw = lines[i];
  const fnStart = raw.match(/^(?:export )?(?:async )?function [A-Za-z_$][\w$]*\(([^)]*)/);
  if (fnStart) {
    shadow = new Set(fnStart[1].split(',').map((p) => (p.split(':')[0] || '').trim()).filter(Boolean));
  }
  const localDecl = raw.match(/^\s+(?:const|let|var) ([A-Za-z_$][\w$]*)/);
  if (localDecl && shadow) shadow.add(localDecl[1]);

  const code = raw.replace(/\/\/.*$/, '');
  for (const name of inner) {
    if (top.has(name)) continue;
    if (shadow && shadow.has(name)) continue;
    if (new RegExp('(?<![\\w$.\'"])' + name + '\\s*[(.]').test(code)) {
      hits.push({ line: i + 1, name, text: raw.trim().slice(0, 110) });
    }
  }
}

console.log('\n  ตรวจขอบเขตฟังก์ชัน — ' + path.basename(target));
console.log('  Deno.serve เริ่มบรรทัด ' + (serveLine + 1) + ' · ชื่อในชั้นใน ' + inner.size + ' ตัว · ชั้นนอก ' + top.size + ' ตัว');

if (hits.length === 0) {
  console.log('\n  ผ่าน — ไม่มีโค้ดชั้นนอกเรียกของในชั้นใน\n');
  process.exit(0);
}
console.log('\n  ไม่ผ่าน — พบ ' + hits.length + ' จุด (จะพังตอนรันจริงเป็น ReferenceError):');
hits.forEach((h) => console.log('    บรรทัด ' + h.line + '  ใช้ ' + h.name + '  ->  ' + h.text));
console.log('\n  วิธีแก้: ย้ายฟังก์ชันที่มีปัญหาเข้าไปไว้ "ข้างใน" Deno.serve');
console.log('          หรือส่งของที่มันต้องใช้เข้าไปเป็นพารามิเตอร์แทน\n');
process.exit(1);
