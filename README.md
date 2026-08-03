# CP9X Desktop

แอปเดสก์ท็อป Windows (.exe) ของ CP9X — Electron + HTML + Supabase + Auto-Update ผ่าน GitHub Releases

---

## โครงสร้างโปรเจกต์

```
cp9x-desktop/
├─ package.json               ชื่อแอป / เวอร์ชัน / สคริปต์
├─ electron-builder.yml       ตั้งค่าการ build .exe และปลายทางอัปเดต
├─ build/
│  ├─ icon.ico                ไอคอนแอป (แทนที่ได้)
│  └─ icon.png
├─ src/
│  ├─ main.js                 กระบวนการหลัก + ตรรกะ auto-update
│  ├─ preload.js              สะพาน IPC ที่ปลอดภัย (contextIsolation)
│  └─ renderer/
│     ├─ index.html           = CP9X.html เดิม (ฝังในแอป)
│     └─ updater-ui.js        แถบแจ้งเตือน "มีเวอร์ชันใหม่"
└─ .github/workflows/release.yml   build + ปล่อย release อัตโนมัติ
```

---

## ครั้งแรก: ตั้งค่า 3 อย่าง

### 1. ใส่ชื่อ GitHub ของคุณ

แก้ `electron-builder.yml`:

```yaml
publish:
  - provider: github
    owner: ชื่อ-github-ของคุณ     # <-- แก้ตรงนี้
    repo: cp9x-desktop
```

### 2. ติดตั้ง dependencies

```powershell
cd cp9x-desktop
npm install
```

### 3. ทดสอบรัน (ยังไม่ build)

```powershell
npm run dev
```

---

## Build เป็น .exe

```powershell
npm run build
```

ได้ไฟล์ที่ `dist\CP9X-Setup-1.0.0.exe` (ตัวติดตั้ง NSIS) พร้อม `latest.yml` และ `.blockmap`

> ต้อง build บน Windows เท่านั้น (electron-builder ใช้ toolchain ของ Windows สำหรับ NSIS)

---

## ปล่อยเวอร์ชันใหม่ (Auto-Update)

### วิธี A — อัตโนมัติด้วย GitHub Actions (แนะนำ)

1. push โค้ดขึ้น GitHub repo ชื่อ `cp9x-desktop`
2. แก้เลขเวอร์ชันใน `package.json` เช่น `1.0.0` → `1.0.1`
3. commit แล้ว tag:

```bash
git add -A
git commit -m "v1.0.1"
git tag v1.0.1
git push origin main --tags
```

GitHub Actions จะ build บน `windows-latest` แล้วสร้าง Release พร้อมแนบ `.exe` + `latest.yml` ให้เอง
ผู้ใช้ที่เปิดแอปอยู่จะเห็นแถบแจ้งเตือนภายในไม่กี่นาที

### วิธี B — build เองแล้ว publish

```powershell
$env:GH_TOKEN="ghp_xxxxxxxx"     # Personal Access Token สิทธิ์ repo
npm run release
```

---

## Auto-Update ทำงานยังไง

| จังหวะ | พฤติกรรม |
|---|---|
| เปิดแอปครบ 5 วินาที | ตรวจหาอัปเดตครั้งแรก |
| ทุก 4 ชั่วโมง | ตรวจซ้ำอัตโนมัติ |
| เจอเวอร์ชันใหม่ | ดาวน์โหลดเบื้องหลัง + แสดงแถบความคืบหน้า |
| ดาวน์โหลดเสร็จ | ขึ้นปุ่ม **รีสตาร์ตตอนนี้** / **ไว้ทีหลัง** |
| ถ้ากด "ไว้ทีหลัง" | ติดตั้งให้เองตอนปิดโปรแกรมครั้งถัดไป |
| เมนู `ช่วยเหลือ → ตรวจหาอัปเดต` | ตรวจแบบสั่งเอง |

**ข้อสำคัญ:** auto-update ทำงานเฉพาะกับแอปที่ติดตั้งจาก `.exe` เท่านั้น — รันด้วย `npm run dev` จะข้ามการตรวจอัปเดต

`latest.yml` บน Release คือไฟล์ที่แอปใช้เทียบเวอร์ชัน ห้ามลบออกจาก Release

---

## Supabase

แอปเรียก Edge Function เดิมโดยตรงจากหน้าเว็บ:

```
https://hefnjozijflnhdunmewl.supabase.co/functions/v1/app-api
```

Edge Function ตั้ง `Access-Control-Allow-Origin: '*'` อยู่แล้ว จึงเรียกได้จาก `file://` ของ Electron ปกติ
คีย์ที่ฝังในหน้าเว็บเป็น **publishable key** (`sb_publishable_...`) ซึ่งออกแบบมาให้เปิดเผยได้ — แต่ต้องมั่นใจว่า RLS บนตารางเปิดใช้งานครบ เพราะไฟล์ในแอปเดสก์ท็อปถูกแกะดูได้

---

## แก้ปัญหาที่พบบ่อย

**Windows SmartScreen เตือน "Unknown publisher"**
เพราะยังไม่ได้เซ็นโค้ด กด *More info → Run anyway* ได้ ถ้าจะให้หายถาวรต้องซื้อ Code Signing Certificate (EV ประมาณ 10,000–20,000 บาท/ปี) แล้วเพิ่มใน `electron-builder.yml`:

```yaml
win:
  certificateFile: cert.pfx
  certificatePassword: ${env.CSC_KEY_PASSWORD}
```

**แอปไม่เจออัปเดต**
ตรวจว่า (1) `owner`/`repo` ถูกต้อง (2) repo เป็น public หรือใส่ `GH_TOKEN` แล้ว (3) Release ไม่ใช่ draft/pre-release (4) เลขเวอร์ชันใน `package.json` สูงกว่าตัวที่ติดตั้ง

**ดู log**
เมนู `ช่วยเหลือ → เปิดโฟลเดอร์ log` หรือที่
`%APPDATA%\CP9X\logs\main.log`

**เปลี่ยนหน้า UI**
แก้ `src/renderer/index.html` ตรง ๆ (อย่าลบบรรทัด `<script src="./updater-ui.js">` ท้ายไฟล์) แล้วขึ้นเวอร์ชันใหม่
