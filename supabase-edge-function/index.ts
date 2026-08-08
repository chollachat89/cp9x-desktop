import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// ไลบรารีสร้าง PDF/Excel มีขนาดใหญ่มาก ถ้า import ไว้ด้านบนสุด Edge Function จะต้องโหลดทุกไลบรารี
// ตั้งแต่ตอน "บูต" ทำให้ทุก request (แม้แต่ล็อกอิน) ช้าจนหมดเวลา (boot timeout)
// จึงเปลี่ยนมาโหลดแบบ lazy คือโหลดเฉพาะตอนที่ต้องสร้าง PDF/Excel จริงๆ เท่านั้น
let _pdfLibPromise: any = null;
function loadPdfLib(): Promise<any> {
  if (!_pdfLibPromise) _pdfLibPromise = import('https://esm.sh/pdf-lib@1.17.1?target=deno');
  return _pdfLibPromise;
}
let _fontkitPromise: any = null;
function loadFontkit(): Promise<any> {
  if (!_fontkitPromise) _fontkitPromise = import('https://esm.sh/@pdf-lib/fontkit@1.1.1?target=deno').then((m: any) => m.default ?? m);
  return _fontkitPromise;
}
let _exceljsPromise: any = null;
function loadExcelJS(): Promise<any> {
  if (!_exceljsPromise) _exceljsPromise = import('https://esm.sh/exceljs@4.4.0?target=deno').then((m: any) => m.default ?? m);
  return _exceljsPromise;
}

// pdf-lib ใช้ object รูปแบบ { type:'RGB', red, green, blue } เป็นค่าสี
// สร้างเองได้เลยโดยไม่ต้อง import pdf-lib ตั้งแต่ตอนบูต
function rgb(r: number, g: number, b: number): any {
  return { type: 'RGB', red: r, green: g, blue: b };
}

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

const AUTH_SALT = 'CR-MAINT-SYSTEM-SALT-2026';
const NOT_SUPPORTED_PREFIX = 'ฟังก์ชันนี้ต้องใช้ Google API (Docs/Sheets/Drive) ซึ่งยังไม่รองรับในเวอร์ชัน Supabase นี้: ';

async function hashPassword(password: string): Promise<string> {
  const data = new TextEncoder().encode(AUTH_SALT + password);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(hashBuffer)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

function genToken(): string {
  return crypto.randomUUID() + '-' + Date.now();
}

// ผู้ใช้กรอกวันเวลาเป็น "เวลาไทย" เสมอ แต่ Edge Function รันบนเครื่องที่ตั้งเป็น UTC
// ถ้าแปลงตรงๆ ด้วย new Date('2026-08-02T14:30:00') จะถูกอ่านเป็น 14:30 UTC = 21:30 น. เวลาไทย (เพี้ยนไป 7 ชม.)
// จึงระบุโซนเวลา +07:00 ให้ชัดเจน (ไทยไม่มี daylight saving จึงเป็น +7 คงที่ตลอดปี)
function bangkokIsoTimestamp(dateStr: any, timeStr: any): string | null {
  const d = (dateStr === null || dateStr === undefined) ? '' : dateStr.toString().trim();
  const t = (timeStr === null || timeStr === undefined) ? '' : timeStr.toString().trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) return null;
  if (!/^\d{1,2}:\d{1,2}$/.test(t)) return null;
  const parts = t.split(':');
  const hh = parts[0].padStart(2, '0');
  const mm = parts[1].padStart(2, '0');
  const dt = new Date(d + 'T' + hh + ':' + mm + ':00+07:00');
  if (isNaN(dt.getTime())) return null;
  return dt.toISOString();
}

function parseFixDateString(str: string | null): Date | null {
  if (!str) return null;
  const parts = str.toString().trim().split(/[-\/]/);
  if (parts.length !== 3) return null;
  const day = parseInt(parts[0], 10);
  const month = parseInt(parts[1], 10);
  let year = parseInt(parts[2], 10);
  if (!day || !month || !year) return null;
  if (year < 100) year += 2000;
  const d = new Date(year, month - 1, day);
  if (isNaN(d.getTime())) return null;
  return d;
}

// ==================== สร้าง PDF ตารางวางบิล (แทน Google Docs) ====================
// ใช้ pdf-lib + fontkit ฝังฟอนต์ไทย (Sarabun) รองรับข้อความไทยเต็มรูปแบบ
// ธีมสีเขียวเหมือนต้นฉบับ (นี่คือที่มาของคำว่า "ใบเขียว") พร้อมโลโก้บริษัท ฝังหัวกระดาษซ้ำทุกหน้า

const THAI_FONT_REGULAR_URL = 'https://github.com/google/fonts/raw/main/ofl/sarabun/Sarabun-Regular.ttf';
const THAI_FONT_BOLD_URL = 'https://github.com/google/fonts/raw/main/ofl/sarabun/Sarabun-Bold.ttf';

// โลโก้บริษัท (PNG, 200x176) ดึงมาจากค่าคงที่เดิมในระบบ Apps Script (CR_LOGO_BASE64) ฝังตรงเป็น base64
// แบ่งเป็นหลายส่วนเพื่อความสะดวกในการดูแลไฟล์เท่านั้น เนื้อหาจะถูกต่อกันตามลำดับ
const LOGO_PNG_BASE64 =
  'iVBORw0KGgoAAAANSUhEUgAAAMgAAACwCAMAAAB999EAAAABgFBMVEWhm6mwWmGasMu9Hh+zL0mFwJ/CKkDbfIHigX/xvsDN8979/f0FZTcFWzIBhcrpGiMxdlRMh2p0p4211sYma0kJfLnU6+inybjM5NgaZ0KYxa5XlHaRuaXZ8vLZGyMTgrlpm4P06efRJi3G29HntbbOMzrsqq4niLnnGh3MO0Jzt9T42NiFs5yMxdoBfsHPRkxil3yo2OdJnMan07uDq5jyx8naGB7ZZ2lVpspIfGOb0eQ3lcO44u/mmJmzzsG14sqSzOIETSp4tZbTVllorMssdamwNUradnfkiIo7hWHiZWs1kr1SZpPahYjldHc3gVxCeV2JSWqa0rQdc0lJl7t0VXdnjnp8wNqGu9XSW2FkW4TNyMk8baE9fmAojMG3MzqzRE6mu7DjISc8aptYXYm5KjSqzeHWsa/mfYHmnKDuwLz44NwdXUBCgF9fnYB9wuCZPVOZQlnSgH7ekpHXq7Tt3uQARB5KdaNBhbZToHpfoYJesNNwgqhzn7JgoX+PW3BFeuz8AAAAgHRSTlP//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////xUHpOoAABQySURBVHja7Z2He9rItsC9+/oTk4xGFUmAQMY4FJtmAzY27iWJE6dnk+13++3t9ffuv/5mRr2BBILNvZ/Pt8n6s2Obn06Zc84MZ9aYvxFZuwO5A7kDuQO5A7kDuQO5A/lbBxFlTlKIkL8lTi78tYHIk4nWfq2yLMznAAA5LPhveM2qqoo4WRb/CkBETmuqEMI8oJLziPUZHkK1qUniBwyCIXQW5kIEfjF5INvWOPFDBBElxPL5qQgBnBzPIkn+wEC4PsvnElM4MDmIWQofDIgoqcSgcnMIZdHkDwJE1lh+PgqbJQ8R97ODyGheZfhYoN77WUHkPsbIZSAA8Dr3s4HIzc+ywbC0goyfBUTU2OwwLJS+vHoQTuVBphwEJccqhdWCYB+fvXp7JXEEy8hVEoJIsVZlvuw8TwXnXND8KJ+UBoDPlJWBxKjD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';

async function pdfGetLogoImage(pdfDoc: any) {
  const logoBytes = Uint8Array.from(atob(LOGO_PNG_BASE64), (c) => c.charCodeAt(0));
  return await pdfDoc.embedPng(logoBytes);
}

const PDF_GREEN = rgb(0x1a / 255, 0x7a / 255, 0x3c / 255);
const PDF_GREEN_DARK = rgb(0x0f / 255, 0x4d / 255, 0x24 / 255);
const PDF_GREEN_LIGHT = rgb(0xea / 255, 0xfa / 255, 0xf0 / 255);
const PDF_GRAY_BORDER = rgb(0xb0 / 255, 0xbe / 255, 0xc5 / 255);
const PDF_YELLOW = rgb(0xfd / 255, 0xe0 / 255, 0x47 / 255);
const PDF_WHITE = rgb(1, 1, 1);
const PDF_GRAY_TEXT = rgb(0x33 / 255, 0x41 / 255, 0x55 / 255);
const PDF_DARK_RED = rgb(0x7a / 255, 0x1f / 255, 0x1f / 255);

function pdfTruncate(font: any, text: string, size: number, maxWidth: number): string {
  let t = (text === null || text === undefined) ? '' : String(text);
  if (font.widthOfTextAtSize(t, size) <= maxWidth) return t;
  while (t.length > 0 && font.widthOfTextAtSize(t + '…', size) > maxWidth) t = t.slice(0, -1);
  return t + '…';
}

function pdfDrawCellText(page: any, font: any, text: string, x: number, y: number, width: number, size: number, color: any, align: 'center' | 'right' | 'left', pad = 3) {
  const t = pdfTruncate(font, text, size, width - pad * 2);
  const w = font.widthOfTextAtSize(t, size);
  let drawX = x + pad;
  if (align === 'center') drawX = x + (width - w) / 2;
  else if (align === 'right') drawX = x + width - w - pad;
  page.drawText(t, { x: drawX, y, size, font, color });
}

function pdfCenterText(page: any, font: any, text: string, centerX: number, y: number, size: number, color: any) {
  const w = font.widthOfTextAtSize(text, size);
  page.drawText(text, { x: centerX - w / 2, y, size, font, color });
}

function thaiDateString(): string {
  const thaiMonths = ['มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน', 'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม'];
  const today = new Date();
  return today.getDate() + ' ' + thaiMonths[today.getMonth()] + ' ' + (today.getFullYear() + 543);
}

function pdfWrapText(font: any, text: string, size: number, maxWidth: number): string[] {
  const t = (text === null || text === undefined) ? '' : String(text);
  if (t === '') return [''];
  if (font.widthOfTextAtSize(t, size) <= maxWidth) return [t];

  let segmenter: any = null;
  try { segmenter = new (Intl as any).Segmenter('th', { granularity: 'grapheme' }); } catch (_e) { segmenter = null; }
  function graphemes(s: string): string[] {
    if (segmenter) {
      const out: string[] = [];
      for (const seg of segmenter.segment(s)) out.push(seg.segment);
      return out;
    }
    return Array.from(s);
  }
  function breakLongWord(word: string): string {
    let seg = '';
    for (const g of graphemes(word)) {
      const test = seg + g;
      if (seg === '' || font.widthOfTextAtSize(test, size) <= maxWidth) {
        seg = test;
      } else {
        lines.push(seg);
        seg = g;
      }
    }
    return seg;
  }

  const words = t.split(' ').filter((w) => w !== '');
  const lines: string[] = [];
  let current = '';
  function flush() { if (current) { lines.push(current); current = ''; } }

  for (const word of words) {
    const candidate = current ? current + ' ' + word : word;
    if (font.widthOfTextAtSize(candidate, size) <= maxWidth) {
      current = candidate;
    } else {
      flush();
      if (font.widthOfTextAtSize(word, size) <= maxWidth) {
        current = word;
      } else {
        current = breakLongWord(word);
      }
    }
  }
  flush();
  return lines.length ? lines : [''];
}

async function generateBillingPdfBase64(rows: any[], isAdmin: boolean): Promise<any> {
  if (!rows || rows.length === 0) return { success: false, message: 'ไม่มีข้อมูลสำหรับสร้าง PDF' };

  try {
    const [regularBytes, boldBytes] = await Promise.all([
      fetch(THAI_FONT_REGULAR_URL).then((r) => r.arrayBuffer()),
      fetch(THAI_FONT_BOLD_URL).then((r) => r.arrayBuffer()),
    ]);

    const [{ PDFDocument }, fontkit] = await Promise.all([loadPdfLib(), loadFontkit()]);
    const pdfDoc = await PDFDocument.create();
    pdfDoc.registerFontkit(fontkit);
    const font = await pdfDoc.embedFont(regularBytes, { subset: true });
    const boldFont = await pdfDoc.embedFont(boldBytes, { subset: true });
    const logoImage = await pdfGetLogoImage(pdfDoc);
    const logoAspect = logoImage.height / logoImage.width;

    const PAGE_W = 1190.55, PAGE_H = 841.89; // A3 แนวนอน (point)
    const MARGIN = 24;
    const usableWidth = PAGE_W - MARGIN * 2;

    const contractorSet: Record<string, boolean> = {};
    rows.forEach((r) => { if (r.contractor) contractorSet[r.contractor] = true; });
    const contractorNames = Object.keys(contractorSet);
    const singleContractorName = contractorNames.length === 1 ? contractorNames[0] : null;

    function getDisplayPriceAndTotal(row: any) {
      const qty = parseFloat(row.qty) || 0;
      if (isAdmin) {
        const price = parseFloat(row.unit_price) || 0;
        const total = parseFloat(row.total_price) || (qty * price);
        return { price, total };
      }
      const hasContractorPrice = row.unit_price_contractor !== null && row.unit_price_contractor !== undefined && row.unit_price_contractor !== '';
      const price = hasContractorPrice ? (parseFloat(row.unit_price_contractor) || 0) : (parseFloat(row.unit_price) || 0);
      const total = hasContractorPrice ? (parseFloat(row.total_price_contractor) || (qty * price)) : (parseFloat(row.total_price) || (qty * price));
      return { price, total };
    }

    let grandTotal = 0;
    rows.forEach((r) => { grandTotal += getDisplayPriceAndTotal(r).total; });

    const headers = ['ลำดับ', 'Customer Case', 'รหัสสาขา', 'ชื่อสาขา', 'งานบริการ', 'เลขทรัพย์สิน', 'Part Code', 'รายละเอียดอะไหล่', 'ประกัน(ด.)', 'จำนวน', 'หน่วย', 'ราคา/หน่วย', 'ราคา/รวม', 'วันที่รับแจ้ง', 'วันที่เข้างาน', 'Quotation', 'อะไหล่เก่าคืน CJ', 'ผู้รับผิดชอบ', 'บริษัท'];
    const colWidths = [30, 85, 45, 85, 75, 65, 55, 130, 40, 35, 35, 55, 55, 60, 60, 55, 50, 60, 75];
    if (isAdmin) {
      headers.push('ราคา/หน่วย (ผู้รับเหมา)', 'ราคา/รวม (ผู้รับเหมา)', 'ผู้รับเหมา', 'รอบบิลที่', 'ช่วงรอบบิล');
      colWidths.push(70, 70, 65, 40, 90);
    }
    const rightAlignCols = isAdmin ? [9, 11, 12, 19, 20] : [9, 11, 12];
    const widthSum = colWidths.reduce((a, b) => a + b, 0);
    const scale = usableWidth / widthSum;
    const scaledWidths = colWidths.map((w) => w * scale);
    const colX: number[] = [];
    let acc = MARGIN;
    scaledWidths.forEach((w) => { colX.push(acc); acc += w; });

    const dataRows = rows.map((row) => {
      const { price, total } = getDisplayPriceAndTotal(row);
      const base = [
        row.seq !== null && row.seq !== undefined ? String(row.seq) : '',
        row.customer_case || '', row.branch_code || '', row.branch_name || '', row.service_type || '',
        row.asset_id || '', row.part_code || '', row.part_detail || '', row.warranty_months || '',
        row.qty !== null && row.qty !== undefined ? String(row.qty) : '', row.unit || '',
        price ? price.toLocaleString('th-TH', { minimumFractionDigits: 2 }) : '',
        total ? total.toLocaleString('th-TH', { minimumFractionDigits: 2 }) : '',
        row.req_date || '', row.visit_date || '', row.quotation_ref || '', row.return_old_part || '',
        row.responsible || '', row.company || '',
      ];
      if (isAdmin) {
        const priceContractor = parseFloat(row.unit_price_contractor) || 0;
        const totalContractor = parseFloat(row.total_price_contractor) || (parseFloat(row.qty) || 0) * priceContractor;
        base.push(
          priceContractor ? priceContractor.toLocaleString('th-TH', { minimumFractionDigits: 2 }) : '',
          totalContractor ? totalContractor.toLocaleString('th-TH', { minimumFractionDigits: 2 }) : '',
          row.contractor || '',
          row.round_no !== null && row.round_no !== undefined ? String(row.round_no) : '',
          row.round_period || '',
        );
      }
      return base;
    });

    // ซ่อนลำดับที่ซ้ำกับแถวก่อนหน้า (เช็คจาก Customer Case เหมือนต้นฉบับ)
    let prevCase: string | null = null;
    const displayRows = dataRows.map((r) => {
      const caseVal = r[1];
      const same = prevCase !== null && String(prevCase) === String(caseVal);
      prevCase = caseVal;
      if (same) { const copy = r.slice(); copy[0] = ''; return copy; }
      return r;
    });

    const HEADER_ROW_H = 22;
    const DATA_ROW_H = 18;
    const SUMMARY_H = 24;

    function drawPageHeader(page: any): number {
      let y = PAGE_H - MARGIN;
      // โลโก้บริษัท มุมซ้ายบน - เหมือนกันทุกหน้า เพราะฟังก์ชันนี้ถูกเรียกใหม่ทุกครั้งที่ขึ้นหน้าใหม่
      const logoH = 56;
      const logoW = logoH / logoAspect;
      page.drawImage(logoImage, { x: MARGIN, y: y - logoH, width: logoW, height: logoH });

      y -= 22;
      pdfCenterText(page, boldFont, 'สรุปเอกสารวางบิล CM', PAGE_W / 2, y, 20, PDF_GREEN_DARK);
      y -= 18;
      pdfCenterText(page, font, 'บริษัท ซีอาร์ เอ็นเนอร์จี คอนซัลแตนท์ จำกัด', PAGE_W / 2, y, 13, PDF_GREEN);
      y -= 14;
      pdfCenterText(page, font, '557-557/1 ถนน ไทยรามัญ แขวงสามวาตะวันตก เขตคลองสามวา กรุงเทพมหานคร 10510', PAGE_W / 2, y, 10, PDF_GRAY_TEXT);
      y -= 13;
      pdfCenterText(page, font, 'โทร 089-743-7111 : เลขประจำตัวผู้เสียภาษี 0105562019441', PAGE_W / 2, y, 10, PDF_GRAY_TEXT);
      if (singleContractorName) {
        y -= 16;
        pdfCenterText(page, boldFont, 'ใบวางบิลผู้รับเหมา: ' + singleContractorName, PAGE_W / 2, y, 14, PDF_DARK_RED);
      }
      // เส้นคั่นสีเขียวใต้หัวกระดาษ ให้ดูเป็นระเบียบ และซ้ำเหมือนกันทุกหน้า
      const dividerY = Math.min(y - 8, PAGE_H - MARGIN - logoH - 4);
      page.drawLine({ start: { x: MARGIN, y: dividerY }, end: { x: PAGE_W - MARGIN, y: dividerY }, thickness: 1.2, color: PDF_GREEN });
      return dividerY - 8;
    }

    function drawSummaryBar(page: any, y: number): number {
      const boxH = SUMMARY_H;
      const w1 = 300, w2 = 220, w3 = usableWidth - w1 - w2;
      page.drawRectangle({ x: MARGIN, y: y - boxH, width: w1, height: boxH, color: PDF_WHITE });
      page.drawText('วันที่พิมพ์: ' + thaiDateString(), { x: MARGIN + 4, y: y - boxH + 7, size: 11, font: boldFont, color: PDF_GRAY_TEXT });
      page.drawRectangle({ x: MARGIN + w1, y: y - boxH, width: w2, height: boxH, color: PDF_GREEN });
      pdfCenterText(page, boldFont, 'จำนวนรายการ: ' + rows.length, MARGIN + w1 + w2 / 2, y - boxH + 7, 11, PDF_WHITE);
      page.drawRectangle({ x: MARGIN + w1 + w2, y: y - boxH, width: w3, height: boxH, color: PDF_YELLOW });
      pdfCenterText(page, boldFont, 'รวมทั้งหมด: ' + grandTotal.toLocaleString('th-TH', { minimumFractionDigits: 2 }) + ' บาท', MARGIN + w1 + w2 + w3 / 2, y - boxH + 7, 11, rgb(0x3f / 255, 0x2d / 255, 0));
      return y - boxH - 6;
    }

    function drawTableHeader(page: any, y: number): number {
      page.drawRectangle({ x: MARGIN, y: y - HEADER_ROW_H, width: usableWidth, height: HEADER_ROW_H, color: PDF_GREEN_DARK });
      headers.forEach((h, c) => {
        pdfDrawCellText(page, boldFont, h, colX[c], y - HEADER_ROW_H + 7, scaledWidths[c], 8, PDF_WHITE, 'center');
      });
      let vx = MARGIN;
      scaledWidths.forEach((w) => { page.drawLine({ start: { x: vx, y }, end: { x: vx, y: y - HEADER_ROW_H }, thickness: 0.75, color: PDF_GRAY_BORDER }); vx += w; });
      page.drawLine({ start: { x: vx, y }, end: { x: vx, y: y - HEADER_ROW_H }, thickness: 0.75, color: PDF_GRAY_BORDER });
      return y - HEADER_ROW_H;
    }

    // ตัดคำแทนการตัดข้อความทิ้ง (…) เพื่อให้เห็นข้อความเต็มๆ ทุกช่อง โดยคำนวณความสูงแถวใหม่ตามจำนวนบรรทัดที่ต้องใช้จริง
    const CELL_PAD_H = 3;
    const LINE_H = 9;
    const MAX_LINES_PER_CELL = 6;
    const rowRenderInfo = displayRows.map((rowData) => {
      const colLines = rowData.map((val, c) => {
        let lines = pdfWrapText(font, val, 8, scaledWidths[c] - CELL_PAD_H * 2);
        if (lines.length > MAX_LINES_PER_CELL) lines = lines.slice(0, MAX_LINES_PER_CELL);
        return lines;
      });
      const maxLines = Math.max(1, ...colLines.map((l) => l.length));
      const rowHeight = Math.max(DATA_ROW_H, maxLines * LINE_H + 8);
      return { colLines, rowHeight };
    });

    function drawDataRow(page: any, yTop: number, rowIdx: number, colLines: string[][], rowHeight: number) {
      const bg = (rowIdx % 2 === 0) ? PDF_GREEN_LIGHT : PDF_WHITE;
      page.drawRectangle({ x: MARGIN, y: yTop - rowHeight, width: usableWidth, height: rowHeight, color: bg });
      colLines.forEach((lines, c) => {
        const align = rightAlignCols.indexOf(c) !== -1 ? 'right' : 'center';
        let baselineY = yTop - 4 - 7;
        lines.forEach((line) => {
          const w = font.widthOfTextAtSize(line, 8);
          let drawX = colX[c] + CELL_PAD_H;
          if (align === 'center') drawX = colX[c] + (scaledWidths[c] - w) / 2;
          else if (align === 'right') drawX = colX[c] + scaledWidths[c] - w - CELL_PAD_H;
          page.drawText(line, { x: drawX, y: baselineY, size: 8, font, color: rgb(0.15, 0.15, 0.15) });
          baselineY -= LINE_H;
        });
      });
      let vx = MARGIN;
      scaledWidths.forEach((w) => { page.drawLine({ start: { x: vx, y: yTop }, end: { x: vx, y: yTop - rowHeight }, thickness: 0.5, color: PDF_GRAY_BORDER }); vx += w; });
      page.drawLine({ start: { x: vx, y: yTop }, end: { x: vx, y: yTop - rowHeight }, thickness: 0.5, color: PDF_GRAY_BORDER });
      page.drawLine({ start: { x: MARGIN, y: yTop - rowHeight }, end: { x: MARGIN + usableWidth, y: yTop - rowHeight }, thickness: 0.5, color: PDF_GRAY_BORDER });
    }

    const footerReserve = 26;
    let pageIdx = 0;
    let rowCursor = 0;
    let page = pdfDoc.addPage([PAGE_W, PAGE_H]);
    let y = drawPageHeader(page);
    if (pageIdx === 0) y = drawSummaryBar(page, y);
    y = drawTableHeader(page, y);
    let rowsOnThisPage = 0;

    while (rowCursor < rowRenderInfo.length) {
      const info = rowRenderInfo[rowCursor];
      if (y - info.rowHeight < MARGIN + footerReserve) {
        pageIdx++;
        page = pdfDoc.addPage([PAGE_W, PAGE_H]);
        y = drawPageHeader(page);
        y = drawTableHeader(page, y);
        rowsOnThisPage = 0;
      }
      drawDataRow(page, y, rowsOnThisPage, info.colLines, info.rowHeight);
      y -= info.rowHeight;
      rowsOnThisPage++;
      rowCursor++;
    }

    pdfCenterText(page, font, 'บริษัท ซีอาร์ เอ็นเนอร์จี คอนซัลแตนท์ จำกัด', PAGE_W / 2, Math.max(y - 14, MARGIN), 9, rgb(0.4, 0.45, 0.5));

    const pdfBytes = await pdfDoc.save();
    let binary = '';
    for (let i = 0; i < pdfBytes.length; i++) binary += String.fromCharCode(pdfBytes[i]);
    const base64 = btoa(binary);
    return { success: true, base64, filename: 'ตารางวางบิล_' + new Date().toISOString().slice(0, 10) + '.pdf' };
  } catch (error) {
    return { success: false, message: 'สร้าง PDF ล้มเหลว: ' + String(error) };
  }
}

// ==================== สร้างไฟล์ "ฟอร์มวางบิล" .xlsx ต่อเลขงาน (แทน Google Sheets แม่แบบ) ====================
function xlsxApplyBoxStyle(ws: any, r1: number, c1: number, r2: number, c2: number) {
  for (let r = r1; r <= r2; r++) {
    for (let c = c1; c <= c2; c++) {
      const cell = ws.getCell(r, c);
      cell.border = {
        top: { style: 'thin', color: { argb: 'FF999999' } },
        bottom: { style: 'thin', color: { argb: 'FF999999' } },
        left: { style: 'thin', color: { argb: 'FF999999' } },
        right: { style: 'thin', color: { argb: 'FF999999' } },
      };
      cell.alignment = { horizontal: 'center', vertical: 'middle', wrapText: true };
      cell.font = { name: 'Arial', size: 10 };
    }
  }
}

async function generateJobFormXlsxBase64(job: any): Promise<any> {
  try {
    const ExcelJS = await loadExcelJS();
    const workbook = new ExcelJS.Workbook();
    const sheet = workbook.addWorksheet('Sheet1');

    const colWidthsPx = [70, 95, 95, 75, 95, 75, 95, 95, 65, 60];
    colWidthsPx.forEach((w, i) => { sheet.getColumn(i + 1).width = w / 7; });

    sheet.getRow(1).height = 30;
    sheet.getRow(2).height = 30;
    sheet.getRow(3).height = 20;
    for (let r = 4; r <= 43; r++) sheet.getRow(r).height = 26;

    function setText(addr: string, value: any) {
      sheet.getCell(addr).value = (value === null || value === undefined) ? '' : String(value);
    }

    setText('A1', 'รหัสสาขา'); setText('B1', job.branchCode);
    setText('C1', 'ชื่อสาขา'); sheet.mergeCells('D1:F1'); setText('D1', job.branchName);
    setText('G1', 'ประเภทงาน'); sheet.mergeCells('H1:J1'); setText('H1', job.serviceType);

    setText('A2', 'เลขที่งาน'); sheet.mergeCells('B2:C2'); setText('B2', job.customerCase);
    setText('D2', 'เลขทรัพย์สิน'); sheet.mergeCells('E2:J2'); setText('E2', job.assetId);

    sheet.mergeCells('A3:E3'); setText('A3', 'ก่อนทำ');
    sheet.mergeCells('F3:J3'); setText('F3', 'หลังทำ');

    const photoBlocks: [number, string, string][] = [
      [4, 'รูปชื่อสาขา', 'รูปเลข Asset\n(ถ่ายให้อ่านตัวเลขได้ชัดเจน)'],
      [12, 'รูปอะไหล่เก่าที่เปลี่ยน', 'รูปอะไหล่ใหม่ที่เปลี่ยน'],
      [20, 'รูปเทียบอะไหล่เก่าและใหม่\n(ถอดอะไหล่เก่าออกมาวางถ่ายรูป)', 'รูปขณะปฏิบัติงานที่เกี่ยวข้อง'],
      [28, 'รูปขณะปฏิบัติงานที่เกี่ยวข้อง', 'รูปขณะปฏิบัติงานที่เกี่ยวข้อง'],
      [36, 'รูปขณะปฏิบัติงานที่เกี่ยวข้อง', 'รูปขณะปฏิบัติงานที่เกี่ยวข้อง'],
    ];
    photoBlocks.forEach(([startRow, leftLabel, rightLabel]) => {
      sheet.mergeCells(startRow, 1, startRow + 7, 5);
      sheet.getCell(startRow, 1).value = leftLabel;
      sheet.mergeCells(startRow, 6, startRow + 7, 10);
      sheet.getCell(startRow, 6).value = rightLabel;
    });

    xlsxApplyBoxStyle(sheet, 1, 1, 43, 10);

    const buffer: ArrayBuffer = await workbook.xlsx.writeBuffer();
    const bytes = new Uint8Array(buffer);
    let binary = '';
    for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
    const base64 = btoa(binary);

    const jobIdForName = (job.customerCase || 'unknown').toString();
    const safeJobId = jobIdForName.replace(/[\\/:*?"<>|]/g, '_');
    return { success: true, base64, filename: 'ฟอร์มวางบิล_' + safeJobId + '.xlsx', customerCase: job.customerCase };
  } catch (error) {
    return { success: false, message: String(error), customerCase: job.customerCase };
  }
}

// ==================== Sync ไป Google Sheet จริงๆ ผ่าน Google Sheets API (Service Account, ไม่ผ่าน Google Docs/Apps Script) ====================
function base64UrlEncodeBytes(bytes: Uint8Array): string {
  let bin = '';
  bytes.forEach((b) => { bin += String.fromCharCode(b); });
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function base64UrlEncodeJson(obj: unknown): string {
  return base64UrlEncodeBytes(new TextEncoder().encode(JSON.stringify(obj)));
}

async function getGoogleAccessToken(supabase: any): Promise<{ token: string | null; error?: string; email?: string }> {
  const { data, error } = await supabase.from('app_secrets').select('key,value').in('key', ['google_service_account_email', 'google_service_account_private_key']);
  if (error || !data || data.length < 2) return { token: null, error: 'ไม่พบ Google Service Account credentials ในระบบ (ยังไม่ได้ตั้งค่า)' };
  const map: Record<string, string> = {};
  data.forEach((r: any) => { map[r.key] = r.value; });
  const email = map['google_service_account_email'];
  const pem = map['google_service_account_private_key'];
  if (!email || !pem) return { token: null, error: 'ข้อมูล credentials ไม่ครบ' };

  try {
    const pemBody = pem.replace('-----BEGIN PRIVATE KEY-----', '').replace('-----END PRIVATE KEY-----', '').replace(/\s/g, '');
    const binaryDer = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));
    const cryptoKey = await crypto.subtle.importKey('pkcs8', binaryDer.buffer, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);

    const now = Math.floor(Date.now() / 1000);
    const header = { alg: 'RS256', typ: 'JWT' };
    const claims = { iss: email, scope: 'https://www.googleapis.com/auth/spreadsheets', aud: 'https://oauth2.googleapis.com/token', exp: now + 3600, iat: now };
    const unsigned = base64UrlEncodeJson(header) + '.' + base64UrlEncodeJson(claims);
    const sigBuf = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', cryptoKey, new TextEncoder().encode(unsigned));
    const jwt = unsigned + '.' + base64UrlEncodeBytes(new Uint8Array(sigBuf));

    const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: 'grant_type=' + encodeURIComponent('urn:ietf:params:oauth:grant-type:jwt-bearer') + '&assertion=' + encodeURIComponent(jwt),
    });
    const tokenJson = await tokenRes.json();
    if (!tokenRes.ok || !tokenJson.access_token) return { token: null, error: 'ขอ access token จาก Google ล้มเหลว: ' + (tokenJson.error_description || tokenJson.error || JSON.stringify(tokenJson)) };
    return { token: tokenJson.access_token, email };
  } catch (e) {
    return { token: null, error: 'สร้าง JWT ล้มเหลว: ' + String(e) };
  }
}

async function getSpreadsheetSheetNames(spreadsheetId: string, accessToken: string): Promise<string[]> {
  const res = await fetch('https://sheets.googleapis.com/v4/spreadsheets/' + spreadsheetId + '?fields=sheets.properties', {
    headers: { Authorization: 'Bearer ' + accessToken },
  });
  const json = await res.json();
  if (!res.ok) throw new Error(json.error?.message || 'ดึงข้อมูล spreadsheet ล้มเหลว');
  return (json.sheets || []).map((s: any) => s.properties.title);
}

function hexToRgbFraction(hex: string) {
  const h = hex.replace('#', '');
  return { red: parseInt(h.substring(0, 2), 16) / 255, green: parseInt(h.substring(2, 4), 16) / 255, blue: parseInt(h.substring(4, 6), 16) / 255 };
}

async function ensureSheetTab(spreadsheetId: string, sheetName: string, headers: string[], colorHex: string, accessToken: string) {
  const addRes = await fetch('https://sheets.googleapis.com/v4/spreadsheets/' + spreadsheetId + ':batchUpdate', {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + accessToken, 'Content-Type': 'application/json' },
    body: JSON.stringify({ requests: [{ addSheet: { properties: { title: sheetName } } }] }),
  });
  const addJson = await addRes.json();
  if (!addRes.ok) throw new Error('สร้างชีต ' + sheetName + ' ล้มเหลว: ' + (addJson.error?.message || ''));
  const sheetId = addJson.replies[0].addSheet.properties.sheetId;

  const fullHeaders = ['Timestamp'].concat(headers);
  await fetch('https://sheets.googleapis.com/v4/spreadsheets/' + spreadsheetId + '/values/' + encodeURIComponent(sheetName) + '!A1:append?valueInputOption=USER_ENTERED', {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + accessToken, 'Content-Type': 'application/json' },
    body: JSON.stringify({ values: [fullHeaders] }),
  });
  await fetch('https://sheets.googleapis.com/v4/spreadsheets/' + spreadsheetId + ':batchUpdate', {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + accessToken, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      requests: [
        { repeatCell: { range: { sheetId, startRowIndex: 0, endRowIndex: 1, startColumnIndex: 0, endColumnIndex: fullHeaders.length }, cell: { userEnteredFormat: { backgroundColor: hexToRgbFraction(colorHex), textFormat: { bold: true }, horizontalAlignment: 'CENTER' } }, fields: 'userEnteredFormat(backgroundColor,textFormat,horizontalAlignment)' } },
        { updateSheetProperties: { properties: { sheetId, gridProperties: { frozenRowCount: 1 } }, fields: 'gridProperties.frozenRowCount' } },
      ],
    }),
  });
}

async function appendRowsToSheetTab(spreadsheetId: string, sheetName: string, rows: any[][], accessToken: string) {
  const res = await fetch('https://sheets.googleapis.com/v4/spreadsheets/' + spreadsheetId + '/values/' + encodeURIComponent(sheetName) + '!A1:append?valueInputOption=USER_ENTERED', {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + accessToken, 'Content-Type': 'application/json' },
    body: JSON.stringify({ values: rows }),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(json.error?.message || 'เขียนข้อมูลลง Sheet ล้มเหลว');
}

// ล้างข้อมูลแถวเก่าทั้งหมดในแท็บ (เว้นแถวหัวตารางแถวที่ 1 ไว้) ก่อนเขียนทับใหม่ทุกครั้ง
// ทำแบบนี้เพื่อให้ Sheet "ตรงกับฐานข้อมูลเป๊ะเสมอ" ไม่ว่าจะมีการแก้ไข/ลบข้อมูลใน DB ภายหลัง
// หรือมีคนไปลบแถวใน Sheet เอง (รอบซิงค์ถัดไปจะคืนข้อมูลที่ถูกต้องกลับมาให้เองอัตโนมัติ)
async function clearSheetTabBody(spreadsheetId: string, sheetName: string, accessToken: string) {
  const range = encodeURIComponent(sheetName) + '!A2:ZZ200000';
  const res = await fetch('https://sheets.googleapis.com/v4/spreadsheets/' + spreadsheetId + '/values/' + range + ':clear', {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + accessToken, 'Content-Type': 'application/json' },
    body: JSON.stringify({}),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(json.error?.message || 'ล้างข้อมูลเก่าใน Sheet ล้มเหลว');
}

// เขียนข้อมูลทั้งหมดทับตั้งแต่แถวที่ 2 เป็นต้นไป (ต้องเรียก clearSheetTabBody ก่อนเสมอ เพื่อไม่ให้มีเศษแถวเก่าตกค้าง)
async function writeRowsToSheetTab(spreadsheetId: string, sheetName: string, rows: any[][], accessToken: string) {
  if (rows.length === 0) return;
  const range = encodeURIComponent(sheetName) + '!A2';
  const res = await fetch('https://sheets.googleapis.com/v4/spreadsheets/' + spreadsheetId + '/values/' + range + '?valueInputOption=USER_ENTERED', {
    method: 'PUT',
    headers: { Authorization: 'Bearer ' + accessToken, 'Content-Type': 'application/json' },
    body: JSON.stringify({ values: rows }),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(json.error?.message || 'เขียนข้อมูลลง Sheet ล้มเหลว');
}

// ทำสำเนา "มิเรอร์เต็มรูปแบบ" ของตารางหนึ่งไปยังแท็บหนึ่งใน Google Sheet: สร้างแท็บถ้ายังไม่มี, ล้างของเก่าทิ้ง,
// เขียนข้อมูลปัจจุบันทั้งหมดจาก DB ทับใหม่ - รับประกันว่า Sheet ตรงกับฐานข้อมูล ไม่มีข้อมูลซ้ำ ไม่มีข้อมูลเก่าค้าง
async function mirrorRowsToSheetTab(
  spreadsheetId: string, accessToken: string, existingNames: string[],
  sheetName: string, color: string, headers: string[], rows: any[][]
): Promise<string> {
  if (existingNames.indexOf(sheetName) === -1) {
    await ensureSheetTab(spreadsheetId, sheetName, headers, color, accessToken);
    existingNames.push(sheetName);
  }
  await clearSheetTabBody(spreadsheetId, sheetName, accessToken);
  if (rows.length === 0) return sheetName + ': ไม่มีข้อมูล (ล้างชีตให้ว่างตรงกับฐานข้อมูลแล้ว)';
  await writeRowsToSheetTab(spreadsheetId, sheetName, rows, accessToken);
  return sheetName + ': ซิงค์ครบ ' + rows.length + ' แถว (ตรงกับฐานข้อมูลล่าสุด)';
}

// แท็บพิเศษที่ไม่ได้มาจากตารางดิบตารางเดียว แต่เป็นรายงานที่รวมข้อมูลหลายตารางเข้าด้วยกัน (เหมือนหน้า "รายงานสถานะดำเนินการ" ในแอป)
const STATUS_REPORT_SHEET = {
  sheetName: 'รายงานสถานะดำเนินการ',
  color: '#dbeafe',
  headers: ['เลขที่ใบแจ้งซ่อมบำรุง', 'สาขา', 'Service Type', 'ประเภทสัญญา', 'ผู้รับเหมา', 'รายละเอียดปัญหาที่พบ',
    'วันที่ร้องขอ', 'วันที่เปิดงาน', 'วันที่เข้าแก้ไข', 'วันที่ปิดงาน', 'ดำเนินการแก้ไขแล้ว',
    'ระยะเวลาดำเนินการ (ชม.)', 'จำนวนครั้งที่พัก', 'รวมชั่วโมงที่พัก', 'ส่งมอบงานให้ผู้รับเหมาแล้ว', 'เสร็จสิ้น (ตัดบิลแล้ว)', 'สถานะ'],
  mapRow: (r: any) => [
    r.main_id, r.branch, r.service_type, r.contract_type ?? '', r.contractor, r.details,
    r.req_date, r.opened_at, r.fix_date, r.closed_at, r.action_taken,
    r.duration_hours, r.pause_count, r.pause_hours_total,
    r.sent_to_contractor ? 'ใช่' : 'ยังไม่ส่ง', r.completed ? 'ใช่' : 'ยังไม่เสร็จ', r.status,
  ],
};

const SYNC_TABLE_REGISTRY: { table: string; sheetName: string; color: string; headers: string[]; mapRow: (r: any) => any[] }[] = [
  { table: 'open_issues', sheetName: 'เปิดงาน', color: '#e0e7ff', headers: ['เลขที่ใบแจ้งซ่อมบำรุง', 'Service Type', 'ประเภทสัญญา', 'วันที่ร้องขอ', 'งานบริการ', 'รหัส-ชื่อสาขา', 'รายละเอียดปัญหาที่พบ'], mapRow: (r) => [r.main_id, r.service_type, r.contract_type ?? '', r.req_date, r.service_work, r.branch, r.details] },
  { table: 'close_issues', sheetName: 'ปิดงาน', color: '#d1fae5', headers: ['เลขงาน', 'สาขา', 'วันที่เข้าแก้ไข', 'รายการอะไหล่ที่เปลี่ยน', 'เลขทรัพย์สิน', 'ดำเนินการ', 'ลิงก์แนบรูป'], mapRow: (r) => [r.job_id, r.branch, r.fix_date, r.parts, r.asset_id, r.action_taken, r.photo_form_link] },
  { table: 'quotations', sheetName: 'ใบเสนอราคา', color: '#fef3c7', headers: ['ชุดที่', 'วันที่', 'Customer Case', 'Branch Code', 'Branch', 'Type', 'Asset No.', 'Part Code', 'Detail', 'ระยะเวลารับประกัน(เดือน)', 'จำนวน', 'หน่วย', 'ราคา/หน่วย', 'ราคา/รวม', 'วันที่รับแจ้งงาน', 'วันที่เข้างาน', 'Quotation', 'อะไหล่เก่าส่งคืน CJ', 'ผู้รับผิดชอบ', 'บริษัท'], mapRow: (r) => [r.set_no ?? null, r.quote_date ?? null, r.customer_case, r.branch_code, r.branch_name, r.work_type ?? null, r.asset_id, r.part_code, r.part_name, r.warranty_months, r.qty, r.unit, r.unit_price, r.total_price, r.req_date, r.visit_date, r.quotation_ref, r.return_old_part, r.responsible, r.company] },
  { table: 'billing_documents', sheetName: 'ตารางวางบิล', color: '#fbecec', headers: ['ลำดับ', 'Customer Case', 'รหัสสาขา', 'ชื่อสาขา', 'งานบริการ', 'เลขทรัพย์สิน', 'Part Code', 'รายละเอียดอะไหล่', 'ระยะเวลาประกัน(เดือน)', 'จำนวน', 'หน่วย', 'ราคา/หน่วย (CJ)', 'ราคา/รวม (CJ)', 'ราคา/หน่วย (ผู้รับเหมา)', 'ราคา/รวม (ผู้รับเหมา)', 'วันที่รับแจ้ง', 'วันที่เข้างาน', 'Quotation', 'อะไหล่เก่าส่งคืน CJ', 'ผู้รับผิดชอบ', 'บริษัท', 'ผู้รับเหมา', 'รอบบิลที่', 'ช่วงรอบบิล'], mapRow: (r) => [r.seq, r.customer_case, r.branch_code, r.branch_name, r.service_type, r.asset_id, r.part_code, r.part_detail, r.warranty_months, r.qty, r.unit, r.unit_price, r.total_price, r.unit_price_contractor, r.total_price_contractor, r.req_date, r.visit_date, r.quotation_ref, r.return_old_part, r.responsible, r.company, r.contractor, r.round_no, r.round_period] },
  { table: 'pause_records', sheetName: 'พักงาน', color: '#fde68a', headers: ['เลขที่ใบแจ้งซ่อมบำรุง', 'เหตุผลที่พัก', 'หมายเหตุ', 'วันเวลาที่พัก', 'ผู้พักงาน', 'วันเวลาที่กลับมาทำ', 'ผู้ทำรายการกลับมาทำ', 'สถานะ'], mapRow: (r) => [r.main_id, r.reason, r.note, r.paused_at, r.paused_by, r.resumed_at, r.resumed_by, r.status] },
];

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  );

  function jsonResponse(body: unknown, status = 200) {
    return new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  async function verifySession(username: string, token: string): Promise<any> {
    if (!username || !token) return { valid: false };
    const { data, error } = await supabase.from('contractors').select('*').eq('username', username).limit(1);
    if (error || !data || data.length === 0) return { valid: false };
    const user = data[0];
    if (!user.session_token || user.session_token !== token) return { valid: false };
    return { valid: true, role: user.role, displayName: user.display_name, username: user.username };
  }

  async function checkOpenIssueExists(jobId: string): Promise<any> {
    try {
      if (!jobId) return { exists: false };
      const { data, error } = await supabase.from('open_issues').select('id').eq('main_id', jobId).limit(1);
      if (error) return { error: error.message };
      return { exists: !!(data && data.length > 0) };
    } catch (e) { return { error: String(e) }; }
  }

  async function checkCloseIssueExists(jobId: string): Promise<any> {
    try {
      if (!jobId) return { exists: false };
      const { data, error } = await supabase.from('close_issues').select('id').eq('job_id', jobId).limit(1);
      if (error) return { error: error.message };
      return { exists: !!(data && data.length > 0) };
    } catch (e) { return { error: String(e) }; }
  }

  async function checkIssuePausedStatus(mainId: string): Promise<any> {
    try {
      const id = (mainId || '').toString().trim();
      if (!id) return { paused: false };
      const { data, error } = await supabase.from('pause_records').select('id').eq('main_id', id).eq('status', 'paused').limit(1);
      if (error) return { paused: false, error: error.message };
      return { paused: !!(data && data.length > 0) };
    } catch (e) { return { paused: false, error: String(e) }; }
  }

  async function invalidateAdminBadgeCountsCache(): Promise<void> { /* ไม่มี shared cache ฝั่ง Edge Function - คำนวณสดทุกครั้งแทน (ดู getAdminBadgeCounts) */ }
  // หาเลขงาน "ที่ตรงเงื่อนไข" สำหรับสร้างรอบบิล (ใช้ร่วมกันทั้งตอน "ดูตัวอย่าง" (previewBillingCandidates)
  // และตอน "ยืนยันบันทึกรอบบิล" (generateBillingDocumentsForAllClosedJobs) เพื่อให้ผลลัพธ์ตรงกันเป๊ะทั้งสองขั้น)
  async function resolveBillingCandidateJobIds(startDate: string | null, endDate: string | null, jobIds: string[] | null): Promise<{ candidateJobIds: string[]; roundPeriod: string; error?: string }> {
    if ((!jobIds || jobIds.length === 0) && (!startDate || !endDate)) {
      return { candidateJobIds: [], roundPeriod: '', error: 'ต้องระบุช่วงวันที่ (ตั้งแต่วันที่ และ ถึงวันที่) หรือระบุเลขงานเจาะจง ก่อนถึงจะจับคู่ข้อมูลได้' };
    }
    if (jobIds && jobIds.length > 0) {
      const candidateJobIds = Array.from(new Set(jobIds.map((j: string) => (j || '').toString().trim()).filter(Boolean))) as string[];
      const roundPeriod = 'ระบุเลขงานเจาะจง (' + new Date().toISOString().slice(0, 10) + ')';
      return { candidateJobIds, roundPeriod };
    }
    const roundPeriod = startDate + ' ถึง ' + endDate;
    const { data: closeData, error: closeErr } = await supabase.from('close_issues').select('job_id,fix_date').order('created_at', { ascending: true });
    if (closeErr) return { candidateJobIds: [], roundPeriod: '', error: 'ดึงข้อมูล close_issues ล้มเหลว: ' + closeErr.message };
    const startD = new Date(startDate + 'T00:00:00');
    const endD = new Date(endDate + 'T23:59:59');
    const seenJob = new Set();
    const candidateJobIds: string[] = [];
    (closeData || []).forEach((r: any) => {
      if (!r.job_id || seenJob.has(r.job_id)) return;
      const fx = parseFixDateString(r.fix_date);
      if (!fx || fx < startD || fx > endD) return;
      seenJob.add(r.job_id);
      candidateJobIds.push(r.job_id);
    });
    return { candidateJobIds, roundPeriod };
  }


  // คำนวณแถวรายงานสถานะดำเนินการ (ใช้ร่วมกันทั้ง fnName 'getJobStatusReport' และตอนซิงค์ลง Google Sheet
  // เพื่อให้ตรรกะสถานะ/ระยะเวลา/ข้อมูลพักงาน ตรงกันเป๊ะทั้งสองที่ ไม่มีวันเพี้ยนต่างกัน)
  async function computeJobStatusReportRows(startDate?: string | null, endDate?: string | null): Promise<any[]> {
    let openQuery = supabase.from('open_issues').select('main_id,branch,service_type,contract_type,contractor,details,req_date,created_at').order('created_at', { ascending: false });
    if (startDate) openQuery = openQuery.gte('created_at', startDate + 'T00:00:00');
    if (endDate) openQuery = openQuery.lte('created_at', endDate + 'T23:59:59');
    const [openRes, closeRes, billingRes, pauseRes] = await Promise.all([
      openQuery,
      supabase.from('close_issues').select('job_id,fix_date,created_at,action_taken').order('created_at', { ascending: true }),
      supabase.from('billing_documents').select('customer_case,sent_to_contractor,completed_at'),
      supabase.from('pause_records').select('main_id,reason,note,status,paused_at,resumed_at,paused_by,resumed_by').order('paused_at', { ascending: true }),
    ]);
    if (openRes.error) throw new Error(openRes.error.message);
    if (closeRes.error) throw new Error(closeRes.error.message);
    if (billingRes.error) throw new Error(billingRes.error.message);
    if (pauseRes.error) throw new Error(pauseRes.error.message);
    const closeMap: Record<string, any> = {};
    (closeRes.data || []).forEach((c: any) => { closeMap[c.job_id] = c; });
    const billingMap: Record<string, any> = {};
    (billingRes.data || []).forEach((b: any) => {
      if (!billingMap[b.customer_case]) billingMap[b.customer_case] = { sent: false, completed: false };
      if (b.sent_to_contractor) billingMap[b.customer_case].sent = true;
      if (b.completed_at) billingMap[b.customer_case].completed = true;
    });
    // จัดกลุ่มประวัติพักงานตามเลขที่งาน เพื่อฝังเข้าไปในแต่ละแถวของรายงาน (ให้หน้า "ดูรายละเอียด" แสดงช่วงเวลาพักได้
    // และให้รู้ว่าเลขงานนี้ "กำลังพักอยู่ตอนนี้" หรือไม่ สำหรับคำนวณสถานะ "พักงาน")
    const pauseMap: Record<string, any[]> = {};
    (pauseRes.data || []).forEach((p: any) => {
      if (!pauseMap[p.main_id]) pauseMap[p.main_id] = [];
      pauseMap[p.main_id].push(p);
    });
    return (openRes.data || []).map((o: any) => {
      const closeRec = closeMap[o.main_id];
      const billingInfo = billingMap[o.main_id];
      const pausePeriods = pauseMap[o.main_id] || [];
      const isCurrentlyPaused = pausePeriods.some((p: any) => p.status === 'paused');
      let durationHours = null;
      if (closeRec && closeRec.created_at && o.created_at) {
        const openedMs = new Date(o.created_at).getTime();
        const closedMs = new Date(closeRec.created_at).getTime();
        if (!isNaN(openedMs) && !isNaN(closedMs) && closedMs >= openedMs) {
          durationHours = Math.round(((closedMs - openedMs) / (1000 * 60 * 60)) * 100) / 100;
        }
      }
      let pauseHoursTotal = 0;
      pausePeriods.forEach((p: any) => {
        const startMs = p.paused_at ? new Date(p.paused_at).getTime() : null;
        const endMs = p.resumed_at ? new Date(p.resumed_at).getTime() : Date.now();
        if (startMs && !isNaN(startMs) && !isNaN(endMs) && endMs >= startMs) {
          pauseHoursTotal += (endMs - startMs) / (1000 * 60 * 60);
        }
      });
      // ลำดับความสำคัญของสถานะ: เสร็จสิ้น > ส่งมอบงาน > ปิดงานแล้ว > พักงาน (ถ้ายังไม่ปิด) > รอดำเนินการ
      let status = 'รอดำเนินการ';
      if (billingInfo && billingInfo.completed) status = 'เสร็จสิ้น';
      else if (billingInfo && billingInfo.sent) status = 'ส่งมอบงาน';
      else if (closeRec) status = 'ปิดงานแล้ว';
      else if (isCurrentlyPaused) status = 'พักงาน';
      return {
        main_id: o.main_id, branch: o.branch, service_type: o.service_type, contract_type: o.contract_type, contractor: o.contractor,
        details: o.details, req_date: o.req_date, opened_at: o.created_at,
        fix_date: closeRec ? closeRec.fix_date : null, closed_at: closeRec ? closeRec.created_at : null,
        action_taken: closeRec ? closeRec.action_taken : null, duration_hours: durationHours,
        sent_to_contractor: !!(billingInfo && billingInfo.sent), completed: !!(billingInfo && billingInfo.completed), status,
        is_paused: isCurrentlyPaused,
        pause_periods: pausePeriods.map((p: any) => ({
          paused_at: p.paused_at, resumed_at: p.resumed_at, reason: p.reason, note: p.note,
          paused_by: p.paused_by, resumed_by: p.resumed_by, status: p.status,
        })),
        pause_count: pausePeriods.length,
        pause_hours_total: Math.round(pauseHoursTotal * 100) / 100,
      };
    });
  }

  let body: any = {};
  try {
    if (req.method === 'POST') {
      body = await req.json();
    } else {
      const url = new URL(req.url);
      const raw = Object.fromEntries(url.searchParams.entries());
      body = { fnName: raw.fnName, args: raw.args ? JSON.parse(raw.args) : [] };
    }
  } catch (_e) {
    body = {};
  }

  const fnName: string = body.fnName || body.action || '';
  const args: any[] = Array.isArray(body.args) ? body.args : [];

  try {
    switch (fnName) {
      // ==================== Auth ====================
      case 'loginUser': {
        const [username, password] = args;
        if (!username || !password) return jsonResponse({ success: false, message: 'กรุณากรอกชื่อผู้ใช้และรหัสผ่าน' });
        const { data, error } = await supabase.from('contractors').select('*').eq('username', username).limit(1);
        if (error) return jsonResponse({ success: false, message: 'เชื่อมต่อล้มเหลว: ' + error.message });
        if (!data || data.length === 0) return jsonResponse({ success: false, message: 'ไม่พบชื่อผู้ใช้นี้ในระบบ' });
        const user = data[0];
        const hash = await hashPassword(password);
        if (hash !== user.password_hash) return jsonResponse({ success: false, message: 'รหัสผ่านไม่ถูกต้อง' });
        const token = genToken();
        await supabase.from('contractors').update({ session_token: token, session_created_at: new Date().toISOString() }).eq('id', user.id);
        return jsonResponse({ success: true, token, username: user.username, role: user.role, displayName: user.display_name });
      }

      case 'logoutUser': {
        const [username, token] = args;
        const session = await verifySession(username, token);
        if (session.valid) {
          const { data } = await supabase.from('contractors').select('id').eq('username', username).limit(1);
          if (data && data.length > 0) await supabase.from('contractors').update({ session_token: null }).eq('id', data[0].id);
        }
        return jsonResponse({ success: true });
      }

      case 'verifySession': {
        const [username, token] = args;
        return jsonResponse(await verifySession(username, token));
      }

      case 'getContractorsList': {
        const { data, error } = await supabase.from('contractors').select('display_name').eq('role', 'contractor').order('display_name');
        if (error) return jsonResponse({ error: error.message });
        return jsonResponse((data || []).map((r: any) => r.display_name));
      }

      // ==================== Lookup อัตโนมัติ (ดูดข้อความ) ====================
      case 'checkOpenIssueExists': {
        const [jobId] = args;
        return jsonResponse(await checkOpenIssueExists(jobId));
      }

      case 'checkCloseIssueExists': {
        const [jobId] = args;
        return jsonResponse(await checkCloseIssueExists(jobId));
      }

      case 'lookupBranch': {
        const [code] = args;
        try {
          if (!code) return jsonResponse({ found: false });
          const match = code.toString().trim().match(/^\d+/);
          const searchCode = match ? match[0] : code.toString().trim();
          const { data, error } = await supabase.from('branches').select('branch_code,branch_name').eq('branch_code', searchCode).limit(1);
          if (error) return jsonResponse({ error: error.message });
          if (!data || data.length === 0) return jsonResponse({ found: false });
          return jsonResponse({ found: true, branchCode: data[0].branch_code || '', branchName: data[0].branch_name || '' });
        } catch (e) { return jsonResponse({ error: String(e) }); }
      }

      case 'lookupPart': {
        const [code] = args;
        const c = (code || '').toString().trim();
        if (!c) return jsonResponse({ found: false });
        const { data, error } = await supabase.from('parts').select('*').ilike('code_cj', c).limit(1);
        if (error) return jsonResponse({ error: error.message });
        if (!data || data.length === 0) return jsonResponse({ found: false });
        const p = data[0];
        return jsonResponse({
          found: true, name: p.name || '', brand: p.brand || '', model: p.model || '', unit: p.unit || '',
          price: p.unit_price || 0, priceContractor: p['Unit Custumer'] || 0, warranty: p.warranty_months || '',
          returnOldPart: p.return_old_part || '', company: p.company || '',
        });
      }

      // ==================== เปิดงาน / ปิดงาน ====================
      case 'saveOpenIssue': {
        const [formData] = args;
        const f = formData || {};
        if (!f.contractor) return jsonResponse({ success: false, message: 'กรุณาเลือกผู้รับเหมาก่อนบันทึกเปิดงาน' });
        const mainId = (f.mainId || '').toString().trim();
        if (!mainId) return jsonResponse({ success: false, message: 'กรุณากรอกเลขที่ใบแจ้งซ่อมบำรุง' });
        // กันเปิดงานซ้ำ (คนละคนกรอกเลขเดียวกัน) - เช็คก่อนบันทึกเป็นด่านแรก
        // ยังมีโอกาสชนกันได้ถ้ากดบันทึกพร้อมกันเป๊ะ ๆ จึงดักจับ error 23505 (unique_violation) จาก DB อีกชั้นด้านล่าง
        // (ต้องสร้าง UNIQUE INDEX บนคอลัมน์ open_issues.main_id ไว้ก่อน ดู add-unique-constraints.sql)
        const dupCheck = await checkOpenIssueExists(mainId);
        if (dupCheck.error) return jsonResponse({ success: false, message: 'ตรวจสอบเลขงานล้มเหลว: ' + dupCheck.error });
        if (dupCheck.exists) return jsonResponse({ success: false, message: 'เลขที่ใบแจ้งซ่อมบำรุง "' + mainId + '" ถูกเปิดงานไปแล้ว ห้ามเปิดซ้ำ' });
        const row: any = {
          main_id: mainId, service_type: f.serviceType || '-', req_date: f.reqDate || '-',
          service_work: f.serviceWork || '-', branch: f.branch || '-', details: f.details || '-',
          contract_type: (f.contractType || '').toString().trim() || null,
          contractor: f.contractor, synced_to_sheet: false,
        };
        const openedIso = bangkokIsoTimestamp(f.openDate, f.openTime);
        if (openedIso) row.created_at = openedIso;
        const { error } = await supabase.from('open_issues').insert(row);
        if (error) {
          if ((error as any).code === '23505') {
            return jsonResponse({ success: false, message: 'เลขที่ใบแจ้งซ่อมบำรุง "' + mainId + '" ถูกเปิดงานไปแล้ว (มีคนบันทึกซ้ำในเวลาไล่เลี่ยกัน) ห้ามเปิดซ้ำ' });
          }
          return jsonResponse({ success: false, message: 'บันทึกล้มเหลว: ' + error.message });
        }
        await invalidateAdminBadgeCountsCache();
        return jsonResponse({ success: true, message: 'บันทึกข้อมูล เปิดงาน เรียบร้อย! (Sheet จะอัปเดตเป็นรอบ ๆ ภายในไม่กี่นาที)' });
      }

      case 'saveCloseIssue': {
        const [formData] = args;
        const f = formData || {};
        const jobId = (f.kissflowId || '').toString().trim();
        if (!jobId) return jsonResponse({ success: false, message: 'กรุณากรอกเลขที่ใบแจ้งซ่อมบำรุง' });
        const openCheck = await checkOpenIssueExists(jobId);
        if (openCheck.error) return jsonResponse({ success: false, message: 'ตรวจสอบเลขงานล้มเหลว: ' + openCheck.error });
        if (!openCheck.exists) return jsonResponse({ success: false, message: 'ไม่พบการเปิดงานเลขที่ "' + jobId + '" ในระบบ กรุณาบันทึก "เปิดงาน" ก่อน แล้วค่อยปิดงาน' });
        // กันปิดงานซ้ำ (คนละคนกดปิดเลขเดียวกัน) - เช็คก่อนบันทึกเป็นด่านแรก
        // ยังมีโอกาสชนกันได้ถ้ากดบันทึกพร้อมกันเป๊ะ ๆ จึงดักจับ error 23505 (unique_violation) จาก DB อีกชั้นด้านล่าง
        // (ต้องสร้าง UNIQUE INDEX บนคอลัมน์ close_issues.job_id ไว้ก่อน ดู add-unique-constraints.sql)
        const closeDupCheck = await checkCloseIssueExists(jobId);
        if (closeDupCheck.error) return jsonResponse({ success: false, message: 'ตรวจสอบสถานะปิดงานล้มเหลว: ' + closeDupCheck.error });
        if (closeDupCheck.exists) return jsonResponse({ success: false, message: 'เลขที่ใบแจ้งซ่อมบำรุง "' + jobId + '" ถูกปิดงานไปแล้ว ห้ามปิดซ้ำ' });
        const pauseCheck = await checkIssuePausedStatus(jobId);
        if (pauseCheck.error) return jsonResponse({ success: false, message: 'ตรวจสอบสถานะพักงานล้มเหลว: ' + pauseCheck.error });
        if (pauseCheck.paused) return jsonResponse({ success: false, message: 'เลขงาน "' + jobId + '" กำลังถูกพักงานอยู่ ไม่สามารถปิดงานได้ กรุณากด "กลับมาทำงาน" ในแท็บพักงานก่อน' });
        const row: any = {
          job_id: jobId, branch: f.branch || '-', fix_date: f.fixDate || '-', parts: f.parts || '-',
          asset_id: f.assetId || '-', action_taken: f.actionTaken || '-', synced_to_sheet: false,
        };
        // เดิมระบบไม่เคยใช้ค่าวันเวลาที่ผู้ใช้เลือกในหน้าปิดงานเลย ทำให้เวลาปิดงานเป็น "เวลาที่กดบันทึก" เสมอ
        // (ย้อนหลังไม่ได้) ตอนนี้บันทึกตามที่ผู้ใช้เลือกจริง โดยตีความเป็นเวลาไทยเหมือนหน้าเปิดงาน
        const closedIso = bangkokIsoTimestamp(f.closeDate, f.closeTime);
        if (closedIso) row.created_at = closedIso;
        const { error } = await supabase.from('close_issues').insert(row);
        if (error) {
          if ((error as any).code === '23505') {
            return jsonResponse({ success: false, message: 'เลขที่ใบแจ้งซ่อมบำรุง "' + jobId + '" ถูกปิดงานไปแล้ว (มีคนบันทึกซ้ำในเวลาไล่เลี่ยกัน) ห้ามปิดซ้ำ' });
          }
          return jsonResponse({ success: false, message: 'บันทึกล้มเหลว: ' + error.message });
        }
        await invalidateAdminBadgeCountsCache();
        return jsonResponse({ success: true, message: 'บันทึกข้อมูล ปิดงาน เรียบร้อย! (Sheet จะอัปเดตเป็นรอบ ๆ ภายในไม่กี่นาที)' });
      }

      case 'getOpenIssuesList': {
        const { data, error } = await supabase.from('open_issues').select('*').order('created_at', { ascending: false }).limit(1000);
        if (error) return jsonResponse({ error: error.message });
        return jsonResponse(data);
      }

      case 'getCloseIssuesList': {
        const { data, error } = await supabase.from('close_issues').select('*').order('created_at', { ascending: false }).limit(1000);
        if (error) return jsonResponse({ error: error.message });
        return jsonResponse(data);
      }

      // ==================== รายงานสถานะ ====================
      case 'getJobStatusReport': {
        const [startDate, endDate] = args;
        const rows = await computeJobStatusReportRows(startDate, endDate);
        return jsonResponse(rows);
      }

      // ==================== ตารางวางบิล ====================
      case 'getBillingDocuments': {
        const [username, token, contractorFilter, jobIdsFilter, roundFilter] = args;
        const session = await verifySession(username, token);
        if (!session.valid) return jsonResponse({ error: 'กรุณาเข้าสู่ระบบใหม่ (session หมดอายุหรือไม่ถูกต้อง)' });
        const isHistoryMode = roundFilter !== undefined && roundFilter !== null && roundFilter !== '';
        let q = supabase.from('billing_documents').select('*');
        if (isHistoryMode) {
          q = q.eq('round_no', roundFilter).order('contractor', { ascending: true }).order('seq', { ascending: true });
          if (session.role === 'admin') {
            if (contractorFilter) q = q.eq('contractor', contractorFilter);
          } else {
            q = q.eq('contractor', session.displayName).eq('sent_to_contractor', true);
          }
        } else {
          q = q.order('round_no', { ascending: true }).order('contractor', { ascending: true }).order('seq', { ascending: true }).limit(1000);
          if (session.role === 'admin') {
            q = q.is('completed_at', null);
            if (contractorFilter) q = q.eq('contractor', contractorFilter);
            else q = q.or('sent_to_contractor.is.null,sent_to_contractor.eq.false');
          } else {
            q = q.eq('contractor', session.displayName).eq('sent_to_contractor', true).is('completed_at', null);
          }
          if (jobIdsFilter && jobIdsFilter.length > 0) q = q.in('customer_case', jobIdsFilter);
        }
        const { data, error } = await q;
        if (error) return jsonResponse({ error: error.message });
        return jsonResponse(data);
      }

      case 'updateBillingDocumentRow': {
        const [username, token, id, fields] = args;
        const session = await verifySession(username, token);
        if (!session.valid) return jsonResponse({ success: false, message: 'กรุณาเข้าสู่ระบบใหม่' });
        if (session.role !== 'admin') return jsonResponse({ success: false, message: 'เฉพาะแอดมินเท่านั้นที่แก้ไขข้อมูลได้' });
        const numericColumns = ['qty', 'unit_price', 'total_price', 'seq', 'unit_price_contractor', 'total_price_contractor'];
        const clean: any = {};
        Object.keys(fields || {}).forEach((key) => {
          if (numericColumns.includes(key)) {
            clean[key] = (fields[key] === '' || fields[key] === null || fields[key] === undefined) ? null : parseFloat(fields[key]);
          } else {
            clean[key] = fields[key] === '' ? null : fields[key];
          }
        });
        if (clean.qty !== undefined || clean.unit_price !== undefined) {
          const qty = clean.qty ?? parseFloat(fields.qty) ?? 0;
          const unitPrice = clean.unit_price ?? parseFloat(fields.unit_price) ?? 0;
          clean.total_price = (qty || 0) * (unitPrice || 0);
        }
        if (clean.qty !== undefined || clean.unit_price_contractor !== undefined) {
          const qty = clean.qty ?? parseFloat(fields.qty) ?? 0;
          const unitPriceContractor = clean.unit_price_contractor ?? parseFloat(fields.unit_price_contractor) ?? 0;
          clean.total_price_contractor = (qty || 0) * (unitPriceContractor || 0);
        }
        const { error } = await supabase.from('billing_documents').update(clean).eq('id', id);
        if (error) return jsonResponse({ success: false, message: error.message });
        return jsonResponse({ success: true });
      }

      case 'deleteBillingDocumentRow': {
        const [username, token, id] = args;
        const session = await verifySession(username, token);
        if (!session.valid) return jsonResponse({ success: false, message: 'กรุณาเข้าสู่ระบบใหม่' });
        if (session.role !== 'admin') return jsonResponse({ success: false, message: 'เฉพาะแอดมินเท่านั้นที่ลบข้อมูลได้' });
        const { error } = await supabase.from('billing_documents').delete().eq('id', id);
        if (error) return jsonResponse({ success: false, message: error.message });
        return jsonResponse({ success: true });
      }

      case 'markBillingRowsAsSent': {
        const [username, token, ids] = args;
        const session = await verifySession(username, token);
        if (!session.valid) return jsonResponse({ success: false, message: 'กรุณาเข้าสู่ระบบใหม่' });
        if (session.role !== 'admin') return jsonResponse({ success: false, message: 'เฉพาะแอดมินเท่านั้นที่ส่งบิลได้' });
        if (!ids || ids.length === 0) return jsonResponse({ success: false, message: 'ไม่มีแถวให้ส่ง กรุณาโหลดข้อมูลก่อน' });
        const { data: checkData, error: checkErr } = await supabase.from('billing_documents').select('id,sent_to_contractor,part_code,qty').in('id', ids);
        if (checkErr) return jsonResponse({ success: false, message: checkErr.message });
        let alreadySent = 0, incomplete = 0;
        const rowById: Record<string, any> = {};
        (checkData || []).forEach((r: any) => { rowById[r.id] = r; });
        const idsToSend = ids.filter((id: string) => {
          const r = rowById[id];
          if (!r) return false;
          if (r.sent_to_contractor) { alreadySent++; return false; }
          const hasPart = r.part_code && String(r.part_code).trim() !== '';
          const hasQty = r.qty !== null && r.qty !== undefined && parseFloat(r.qty) > 0;
          if (!hasPart || !hasQty) { incomplete++; return false; }
          return true;
        });
        if (idsToSend.length === 0) {
          const reasons: string[] = [];
          if (alreadySent > 0) reasons.push(alreadySent + ' แถวส่งไปแล้วก่อนหน้านี้');
          if (incomplete > 0) reasons.push(incomplete + ' แถวยังกรอก Part Code/จำนวนไม่ครบ');
          return jsonResponse({ success: false, message: 'ไม่มีแถวใหม่ให้ส่ง' + (reasons.length ? ' (' + reasons.join(', ') + ')' : '') });
        }
        const { error } = await supabase.from('billing_documents').update({ sent_to_contractor: true, sent_at: new Date().toISOString() }).in('id', idsToSend);
        if (error) return jsonResponse({ success: false, message: 'ส่งบิลล้มเหลว: ' + error.message });
        const notes: string[] = [];
        if (alreadySent > 0) notes.push('ข้าม ' + alreadySent + ' แถวที่ส่งไปแล้วก่อนหน้านี้');
        if (incomplete > 0) notes.push('ข้าม ' + incomplete + ' แถวที่ยังกรอก Part Code/จำนวนไม่ครบ');
        return jsonResponse({ success: true, message: 'ส่งบิลให้ผู้รับเหมาเรียบร้อยแล้ว (' + idsToSend.length + ' แถวใหม่' + (notes.length ? ', ' + notes.join(', ') : '') + ')' });
      }

      case 'getBillingRoundOptions': {
        const [username, token] = args;
        const session = await verifySession(username, token);
        if (!session.valid) return jsonResponse({ error: 'กรุณาเข้าสู่ระบบใหม่' });
        let q = supabase.from('billing_documents').select('round_no,round_period').not('round_no', 'is', null);
        if (session.role !== 'admin') q = q.eq('contractor', session.displayName).eq('sent_to_contractor', true);
        const { data, error } = await q;
        if (error) return jsonResponse({ error: error.message });
        const seen = new Set(); const options: any[] = [];
        (data || []).forEach((r: any) => { if (seen.has(r.round_no)) return; seen.add(r.round_no); options.push({ round_no: r.round_no, round_period: r.round_period || '' }); });
        options.sort((a: any, b: any) => b.round_no - a.round_no);
        return jsonResponse(options);
      }

      case 'getBillingRoundsHistory': {
        const [username, token] = args;
        const session = await verifySession(username, token);
        if (!session.valid) return jsonResponse({ error: 'กรุณาเข้าสู่ระบบใหม่ (session หมดอายุหรือไม่ถูกต้อง)' });
        let q = supabase.from('billing_documents').select('round_no,round_period,contractor,total_price,total_price_contractor,sent_at,completed_at,sent_to_contractor').not('round_no', 'is', null);
        if (session.role === 'admin') {
          q = q.or('sent_to_contractor.eq.true,completed_at.not.is.null');
        } else {
          q = q.eq('contractor', session.displayName).eq('sent_to_contractor', true);
        }
        const { data, error } = await q;
        if (error) return jsonResponse({ error: error.message });
        const groups: Record<string, any> = {};
        (data || []).forEach((r: any) => {
          const key = r.round_no + '||' + (r.contractor || '');
          if (!groups[key]) groups[key] = { round_no: r.round_no, round_period: r.round_period || '', contractor: r.contractor || '', item_count: 0, total_cj: 0, total_contractor: 0, sent_at: null, completed_at: null, any_completed: false, all_completed: true };
          const g = groups[key];
          g.item_count++;
          g.total_cj += parseFloat(r.total_price) || 0;
          g.total_contractor += parseFloat(r.total_price_contractor) || 0;
          if (r.sent_at && (!g.sent_at || r.sent_at < g.sent_at)) g.sent_at = r.sent_at;
          if (r.completed_at) { g.any_completed = true; if (!g.completed_at || r.completed_at > g.completed_at) g.completed_at = r.completed_at; }
          else { g.all_completed = false; }
        });
        const list = Object.keys(groups).map((k) => {
          const g = groups[k];
          g.status = g.any_completed ? (g.all_completed ? 'ตัดบิลแล้วทั้งหมด' : 'ตัดบิลแล้วบางส่วน') : 'ส่งบิลแล้ว รอตัดบิล';
          delete g.all_completed; delete g.any_completed;
          return g;
        });
        list.sort((a: any, b: any) => b.round_no - a.round_no || (a.contractor || '').localeCompare(b.contractor || '', 'th'));
        return jsonResponse(list);
      }

      // ดูตัวอย่างก่อนบันทึกรอบบิลจริง (ไม่เขียนอะไรลงฐานข้อมูลเลย - อ่านอย่างเดียว)
      // ใช้เงื่อนไขจับคู่แบบเดียวกับตอนบันทึกจริงเป๊ะ (resolveBillingCandidateJobIds) เพื่อให้สิ่งที่เห็นตรงกับสิ่งที่จะถูกบันทึก
      case 'previewBillingCandidates': {
        const [username, token, startDate, endDate, jobIds] = args;
        const session = await verifySession(username, token);
        if (!session.valid) return jsonResponse({ success: false, message: 'กรุณาเข้าสู่ระบบใหม่' });
        if (session.role !== 'admin') return jsonResponse({ success: false, message: 'เฉพาะแอดมินเท่านั้นที่ทำรายการนี้ได้' });
        const candResult = await resolveBillingCandidateJobIds(startDate, endDate, jobIds);
        if (candResult.error) return jsonResponse({ success: false, message: candResult.error });
        const candidateJobIds = candResult.candidateJobIds;
        const roundPeriod = candResult.roundPeriod;
        if (candidateJobIds.length === 0) {
          return jsonResponse({ success: true, roundPeriod, candidates: [], alreadyBilledCount: 0 });
        }
        // เลขงานที่มีรอบบิลอยู่แล้ว (ถูกจับคู่ไปก่อนหน้า) ไม่นับเป็นตัวอย่างซ้ำ - ให้เห็นแต่ของใหม่จริง ๆ
        const { data: alreadyBilledData, error: alreadyBilledErr } = await supabase.from('billing_documents').select('customer_case').in('customer_case', candidateJobIds);
        if (alreadyBilledErr) return jsonResponse({ success: false, message: 'ตรวจสอบรอบบิลเดิมล้มเหลว: ' + alreadyBilledErr.message });
        const alreadyBilledSet = new Set((alreadyBilledData || []).map((r: any) => r.customer_case));
        const newJobIds = candidateJobIds.filter((id) => !alreadyBilledSet.has(id));
        if (newJobIds.length === 0) {
          return jsonResponse({ success: true, roundPeriod, candidates: [], alreadyBilledCount: alreadyBilledSet.size });
        }
        const [openRes, closeRes, branchesRes] = await Promise.all([
          supabase.from('open_issues').select('main_id,branch,service_work,service_type,req_date,contractor').in('main_id', newJobIds),
          supabase.from('close_issues').select('job_id,branch,asset_id,fix_date').in('job_id', newJobIds).order('created_at', { ascending: false }),
          supabase.from('branches').select('branch_code,branch_name'),
        ]);
        if (openRes.error) return jsonResponse({ success: false, message: openRes.error.message });
        if (closeRes.error) return jsonResponse({ success: false, message: closeRes.error.message });
        const openByJob: Record<string, any> = {};
        (openRes.data || []).forEach((o: any) => { if (!openByJob[o.main_id]) openByJob[o.main_id] = o; });
        const closeByJob: Record<string, any> = {};
        (closeRes.data || []).forEach((c: any) => { if (!closeByJob[c.job_id]) closeByJob[c.job_id] = c; });
        const branchMap: Record<string, string> = {};
        (branchesRes.data || []).forEach((b: any) => { if (b.branch_code) branchMap[b.branch_code] = b.branch_name; });
        const candidates = newJobIds.map((jobId) => {
          const openRecord = openByJob[jobId] || null;
          const closeRecord = closeByJob[jobId] || null;
          const rawBranchText = (closeRecord && closeRecord.branch) || (openRecord && openRecord.branch) || '';
          let branchCode: string | null = null; let branchName: string | null = null;
          const codeMatch = rawBranchText.toString().match(/^\d+/);
          if (codeMatch) { branchCode = codeMatch[0]; branchName = branchMap[branchCode] || rawBranchText; }
          else if (rawBranchText) { branchName = rawBranchText; }
          return {
            job_id: jobId, branch_code: branchCode, branch_name: branchName,
            service_type: openRecord ? (openRecord.service_work || openRecord.service_type || '-') : '-',
            asset_id: closeRecord ? (closeRecord.asset_id || '-') : '-',
            req_date: openRecord ? (openRecord.req_date || '-') : '-',
            visit_date: closeRecord ? (closeRecord.fix_date || '-') : '-',
            contractor: openRecord ? (openRecord.contractor || null) : null,
            has_open_record: !!openRecord, has_close_record: !!closeRecord,
          };
        });
        return jsonResponse({ success: true, roundPeriod, candidates, alreadyBilledCount: alreadyBilledSet.size });
      }

      case 'generateBillingDocumentsForAllClosedJobs': {
        const [username, token, startDate, endDate, jobIds] = args;
        const session = await verifySession(username, token);
        if (!session.valid) return jsonResponse({ success: false, message: 'กรุณาเข้าสู่ระบบใหม่' });
        if (session.role !== 'admin') return jsonResponse({ success: false, message: 'เฉพาะแอดมินเท่านั้นที่ทำรายการนี้ได้' });
        if ((!jobIds || jobIds.length === 0) && (!startDate || !endDate)) {
          return jsonResponse({ success: false, message: 'ต้องระบุช่วงวันที่ (ตั้งแต่วันที่ และ ถึงวันที่) หรือระบุเลขงานเจาะจง ก่อนถึงจะจับคู่ข้อมูลได้' });
        }
        const candResult = await resolveBillingCandidateJobIds(startDate, endDate, jobIds);
        if (candResult.error) return jsonResponse({ success: false, message: candResult.error });
        const candidateJobIds = candResult.candidateJobIds;
        const roundPeriod = candResult.roundPeriod;
        if (candidateJobIds.length === 0) {
          return jsonResponse({ success: true, message: 'ไม่มีข้อมูลรายการปิดงานในช่วงที่เลือก', created: 0, skipped: 0, matchedJobIds: [] });
        }
        const { data: roundNoData, error: roundNoErr } = await supabase.rpc('next_billing_round_no');
        if (roundNoErr) return jsonResponse({ success: false, message: 'ขอเลขรอบบิลล้มเหลว: ' + roundNoErr.message });
        const roundNo = roundNoData as number;
        const { data: claimedRows, error: claimErr } = await supabase.rpc('claim_billing_jobs', { job_ids: candidateJobIds, p_round_no: roundNo });
        if (claimErr) return jsonResponse({ success: false, message: 'จองเลขงานล้มเหลว: ' + claimErr.message });
        const claimedJobIds: string[] = (claimedRows || []).map((r: any) => r.customer_case);
        const skippedAlreadyClaimed = candidateJobIds.length - claimedJobIds.length;
        if (claimedJobIds.length === 0) {
          return jsonResponse({ success: true, message: 'ไม่มีเลขงานใหม่ให้สร้าง (ทั้งหมดถูกสร้างบิลไปแล้ว/มีแอดมินคนอื่นเพิ่งสร้างไปพร้อมกัน)', created: 0, skipped: skippedAlreadyClaimed, matchedJobIds: [] });
        }
        const [openRes, closeRes] = await Promise.all([
          supabase.from('open_issues').select('*').in('main_id', claimedJobIds),
          supabase.from('close_issues').select('*').in('job_id', claimedJobIds).order('created_at', { ascending: false }),
        ]);
        if (openRes.error) return jsonResponse({ success: false, message: openRes.error.message });
        if (closeRes.error) return jsonResponse({ success: false, message: closeRes.error.message });
        const openByJob: Record<string, any> = {};
        (openRes.data || []).forEach((o: any) => { if (!openByJob[o.main_id]) openByJob[o.main_id] = o; });
        const closeByJob: Record<string, any> = {};
        (closeRes.data || []).forEach((c: any) => { if (!closeByJob[c.job_id]) closeByJob[c.job_id] = c; });
        const { data: branchesData } = await supabase.from('branches').select('branch_code,branch_name');
        const branchMap: Record<string, string> = {};
        (branchesData || []).forEach((b: any) => { if (b.branch_code) branchMap[b.branch_code] = b.branch_name; });
        const contractorSeqCounters: Record<string, number> = {};
        const rowsToInsert: any[] = [];
        claimedJobIds.forEach((jobId) => {
          const openRecord = openByJob[jobId] || null;
          const closeRecord = closeByJob[jobId] || null;
          const contractorKey = (openRecord && openRecord.contractor) || '__ไม่มีผู้รับเหมา__';
          contractorSeqCounters[contractorKey] = (contractorSeqCounters[contractorKey] || 0) + 1;
          const seq = contractorSeqCounters[contractorKey];
          const rawBranchText = (closeRecord && closeRecord.branch) || (openRecord && openRecord.branch) || '';
          let branchCode: string | null = null; let branchName: string | null = null;
          const codeMatch = rawBranchText.toString().match(/^\d+/);
          if (codeMatch) { branchCode = codeMatch[0]; branchName = branchMap[branchCode] || rawBranchText; }
          else if (rawBranchText) { branchName = rawBranchText; }
          rowsToInsert.push({
            seq, round_no: roundNo, round_period: roundPeriod, customer_case: jobId, branch_code: branchCode, branch_name: branchName,
            service_type: openRecord ? (openRecord.service_work || openRecord.service_type || '-') : '-',
            asset_id: closeRecord ? (closeRecord.asset_id || '-') : '-', req_date: openRecord ? (openRecord.req_date || '-') : '-',
            visit_date: closeRecord ? (closeRecord.fix_date || '-') : '-', contractor: openRecord ? (openRecord.contractor || null) : null, synced_to_sheet: false,
          });
        });
        const { error: insertErr } = await supabase.from('billing_documents').insert(rowsToInsert);
        if (insertErr) {
          await supabase.from('billing_job_registry').delete().in('customer_case', claimedJobIds);
          return jsonResponse({ success: false, message: 'สร้างแถวตารางวางบิลล้มเหลว: ' + insertErr.message });
        }
        const message = 'สร้างสำเร็จ ' + claimedJobIds.length + ' เลขงาน (รอบบิลที่ ' + roundNo + ')' + (skippedAlreadyClaimed > 0 ? ' | ข้าม ' + skippedAlreadyClaimed + ' เลขงานที่มีบิลอยู่แล้ว' : '');
        return jsonResponse({ success: true, message, created: claimedJobIds.length, skipped: skippedAlreadyClaimed, matchedJobIds: claimedJobIds, roundNo });
      }

      case 'fixBillingSeqNumbers': {
        const [username, token] = args;
        const session = await verifySession(username, token);
        if (!session.valid) return jsonResponse({ success: false, message: 'กรุณาเข้าสู่ระบบใหม่' });
        if (session.role !== 'admin') return jsonResponse({ success: false, message: 'เฉพาะแอดมินเท่านั้นที่ทำรายการนี้ได้' });
        const { data: rows, error } = await supabase.from('billing_documents').select('id,customer_case,seq,round_no,contractor').order('round_no', { ascending: true }).order('seq', { ascending: true }).order('created_at', { ascending: true });
        if (error) return jsonResponse({ success: false, message: 'ดึงข้อมูลล้มเหลว: ' + error.message });
        const seqMapPerGroup: Record<string, Record<string, number>> = {};
        const nextSeqPerGroup: Record<string, number> = {};
        const updateBatches: Record<string, { seq: number; ids: string[] }> = {};
        let changedCount = 0;
        (rows || []).forEach((r: any) => {
          const groupKey = (r.round_no !== null && r.round_no !== undefined ? r.round_no : 'ไม่มีรอบ') + '||' + (r.contractor || 'ไม่มีผู้รับเหมา');
          if (!seqMapPerGroup[groupKey]) seqMapPerGroup[groupKey] = {};
          if (!nextSeqPerGroup[groupKey]) nextSeqPerGroup[groupKey] = 1;
          const jobId = r.customer_case || ('__blank__' + r.id);
          if (!seqMapPerGroup[groupKey][jobId]) { seqMapPerGroup[groupKey][jobId] = nextSeqPerGroup[groupKey]; nextSeqPerGroup[groupKey]++; }
          const newSeq = seqMapPerGroup[groupKey][jobId];
          if (String(r.seq) !== String(newSeq)) {
            const batchKey = groupKey + '::' + newSeq;
            if (!updateBatches[batchKey]) updateBatches[batchKey] = { seq: newSeq, ids: [] };
            updateBatches[batchKey].ids.push(r.id);
            changedCount++;
          }
        });
        for (const key of Object.keys(updateBatches)) {
          await supabase.from('billing_documents').update({ seq: updateBatches[key].seq }).in('id', updateBatches[key].ids);
        }
        const totalGroups = Object.keys(nextSeqPerGroup).length;
        const message = 'จัดลำดับใหม่เรียบร้อย: แก้ไข ' + changedCount + ' แถว จากทั้งหมด ' + (rows || []).length + ' แถว (แยกคำนวณตามรอบบิล+ผู้รับเหมา รวม ' + totalGroups + ' กลุ่ม)';
        return jsonResponse({ success: true, message });
      }

      case 'addBillingLineItems': {
        const [username, token, sourceId, items] = args;
        const session = await verifySession(username, token);
        if (!session.valid) return jsonResponse({ success: false, message: 'กรุณาเข้าสู่ระบบใหม่' });
        if (session.role !== 'admin') return jsonResponse({ success: false, message: 'เฉพาะแอดมินเท่านั้นที่ทำรายการนี้ได้' });
        const { data: sourceData, error: sourceErr } = await supabase.from('billing_documents').select('*').eq('id', sourceId).limit(1);
        if (sourceErr || !sourceData || sourceData.length === 0) return jsonResponse({ success: false, message: 'ไม่พบแถวต้นฉบับ' });
        const src = sourceData[0];
        const { data: emptyRowData } = await supabase.from('billing_documents').select('id').eq('customer_case', src.customer_case).is('part_code', null).limit(1);
        let emptyRowId: string | null = (emptyRowData && emptyRowData.length > 0) ? emptyRowData[0].id : null;
        let created = 0;
        const errors: string[] = [];
        for (const item of (items || [])) {
          const partCode = (item.partCode || '').toString().trim();
          if (!partCode) continue;
          const { data: partData } = await supabase.from('parts').select('*').ilike('code_cj', partCode).limit(1);
          const part = (partData && partData.length > 0) ? partData[0] : null;
          const qty = parseFloat(item.qty) || 0;
          const unitPrice = part ? (parseFloat(part.unit_price) || 0) : 0;
          const unitPriceContractor = part ? (parseFloat(part['Unit Custumer']) || 0) : 0;
          const partFields: any = {
            part_code: partCode,
            part_detail: part ? [part.name, part.brand, part.model].filter(Boolean).join(' - ') : '-',
            warranty_months: part ? part.warranty_months : '-', qty, unit: part ? part.unit : '-',
            unit_price: unitPrice, total_price: qty * unitPrice, unit_price_contractor: unitPriceContractor,
            total_price_contractor: qty * unitPriceContractor, quotation_ref: item.quotationRef || '-',
            return_old_part: part ? part.return_old_part : '-', company: part ? part.company : '-',
          };
          if (emptyRowId) {
            const { error: updErr } = await supabase.from('billing_documents').update(partFields).eq('id', emptyRowId);
            if (!updErr) created++; else errors.push(partCode + ': ' + updErr.message);
            emptyRowId = null;
          } else {
            const row = Object.assign({
              seq: src.seq, round_no: src.round_no, round_period: src.round_period, customer_case: src.customer_case,
              branch_code: src.branch_code, branch_name: src.branch_name, service_type: src.service_type, asset_id: src.asset_id,
              req_date: src.req_date, visit_date: src.visit_date, responsible: src.responsible, contractor: src.contractor, synced_to_sheet: false,
            }, partFields);
            const { error: insErr } = await supabase.from('billing_documents').insert(row);
            if (!insErr) created++; else errors.push(partCode + ': ' + insErr.message);
          }
        }
        const message = 'เพิ่มสินค้าสำเร็จ ' + created + ' ชิ้น (เลขงาน ' + src.customer_case + ')' + (errors.length ? ' | ข้อผิดพลาด: ' + errors.join(' ; ') : '');
        return jsonResponse({ success: created > 0, message });
      }

      // ==================== งานที่เสร็จสิ้น (บิลรอบ) ====================
      case 'getCompletedBillingRounds': {
        const [username, token] = args;
        const session = await verifySession(username, token);
        if (!session.valid) return jsonResponse({ error: 'กรุณาเข้าสู่ระบบใหม่' });
        if (session.role !== 'admin') return jsonResponse({ error: 'เฉพาะแอดมินเท่านั้นที่ดูรายการนี้ได้' });
        const { data, error } = await supabase.from('billing_documents').select('round_no,round_period,contractor,total_price,total_price_contractor,completed_at').not('completed_at', 'is', null).order('completed_at', { ascending: false });
        if (error) return jsonResponse({ error: error.message });
        const groups: Record<string, any> = {};
        (data || []).forEach((r: any) => {
          const key = r.round_no + '||' + (r.contractor || '');
          if (!groups[key]) groups[key] = { round_no: r.round_no, round_period: r.round_period || '', contractor: r.contractor || '', item_count: 0, total_cj: 0, total_contractor: 0, completed_at: r.completed_at };
          const g = groups[key];
          g.item_count++;
          g.total_cj += parseFloat(r.total_price) || 0;
          g.total_contractor += parseFloat(r.total_price_contractor) || 0;
          if (r.completed_at && r.completed_at > g.completed_at) g.completed_at = r.completed_at;
        });
        const list = Object.values(groups);
        list.sort((a: any, b: any) => b.round_no - a.round_no || (a.contractor || '').localeCompare(b.contractor || '', 'th'));
        return jsonResponse(list);
      }

      case 'getCompletedRoundDetail': {
        const [username, token, roundNo, contractor] = args;
        const session = await verifySession(username, token);
        if (!session.valid) return jsonResponse({ error: 'กรุณาเข้าสู่ระบบใหม่' });
        if (session.role !== 'admin') return jsonResponse({ error: 'เฉพาะแอดมินเท่านั้นที่ดูรายการนี้ได้' });
        if (roundNo === undefined || roundNo === null || roundNo === '') return jsonResponse({ error: 'ไม่พบเลขรอบบิล' });
        const { data, error } = await supabase.from('billing_documents').select('*').eq('round_no', roundNo).eq('contractor', contractor || '').not('completed_at', 'is', null).order('seq', { ascending: true });
        if (error) return jsonResponse({ error: error.message });
        const rows = data || [];
        const jobIds = Array.from(new Set(rows.map((r: any) => r.customer_case).filter(Boolean)));
        let approvedByJob: Record<string, any> = {};
        if (jobIds.length > 0) {
          const { data: subs } = await supabase.from('job_form_submissions').select('*').in('customer_case', jobIds).eq('status', 'approved').order('reviewed_at', { ascending: true });
          (subs || []).forEach((s: any) => { approvedByJob[s.customer_case] = s; });
        }
        const merged = rows.map((r: any) => {
          const sub = approvedByJob[r.customer_case];
          return { ...r, approved_file_url: sub ? sub.file_url : null, approved_file_name: sub ? sub.file_name : null, reviewed_by: sub ? sub.reviewed_by : null };
        });
        return jsonResponse(merged);
      }

      // ==================== ตัวเลขแจ้งเตือนแอดมิน ====================
      case 'getAdminBadgeCounts': {
        const [username, token] = args;
        const session = await verifySession(username, token);
        if (!session.valid || session.role !== 'admin') return jsonResponse({ pendingCount: 0, pausedCount: 0 });
        const [openRes, closeRes, pausedRes] = await Promise.all([
          supabase.from('open_issues').select('main_id'),
          supabase.from('close_issues').select('job_id'),
          supabase.from('pause_records').select('id').eq('status', 'paused'),
        ]);
        let pendingCount = 0;
        if (!openRes.error && !closeRes.error) {
          const closedSet = new Set((closeRes.data || []).map((r: any) => r.job_id).filter(Boolean));
          const seenOpen = new Set();
          (openRes.data || []).forEach((r: any) => { if (r.main_id && !closedSet.has(r.main_id) && !seenOpen.has(r.main_id)) { seenOpen.add(r.main_id); pendingCount++; } });
        }
        const pausedCount = (!pausedRes.error && pausedRes.data) ? pausedRes.data.length : 0;
        return jsonResponse({ pendingCount, pausedCount });
      }

      // ==================== พักงาน ====================
      case 'pauseIssue': {
        const [formData] = args;
        const f = formData || {};
        const mainId = (f.mainId || '').toString().trim();
        const reason = (f.reason || '').toString().trim();
        if (!mainId) return jsonResponse({ success: false, message: 'กรุณาระบุเลขที่ใบแจ้งซ่อมบำรุง' });
        if (!reason) return jsonResponse({ success: false, message: 'กรุณาระบุเหตุผลที่พักงาน' });
        const openCheck = await checkOpenIssueExists(mainId);
        if (openCheck.error) return jsonResponse({ success: false, message: 'ตรวจสอบเลขงานล้มเหลว: ' + openCheck.error });
        if (!openCheck.exists) return jsonResponse({ success: false, message: 'ไม่พบการเปิดงานเลขที่ "' + mainId + '" ในระบบ กรุณาบันทึก "เปิดงาน" ก่อน' });
        const { data: activeData } = await supabase.from('pause_records').select('id').eq('main_id', mainId).eq('status', 'paused').limit(1);
        if (activeData && activeData.length > 0) return jsonResponse({ success: false, message: 'เลขงาน "' + mainId + '" ถูกพักอยู่แล้ว ไม่สามารถพักซ้ำได้ กรุณากด "กลับมาทำงาน" ก่อน' });
        const row = {
          main_id: mainId, reason, note: (f.note || '').toString().trim() || null, branch: (f.branch || '').toString().trim() || null,
          service_type: (f.serviceType || '').toString().trim() || null, cause: (f.cause || '').toString().trim() || null,
          requested_item: (f.request || '').toString().trim() || null, paused_by: (f.pausedBy || '').toString().trim() || null,
          status: 'paused', synced_to_sheet: false,
        };
        const { error } = await supabase.from('pause_records').insert(row);
        if (error) return jsonResponse({ success: false, message: 'บันทึกล้มเหลว: ' + error.message });
        await invalidateAdminBadgeCountsCache();
        return jsonResponse({ success: true, message: 'บันทึกพักงานเรียบร้อย! (Sheet จะอัปเดตเป็นรอบ ๆ ภายในไม่กี่นาที)' });
      }

      case 'resumeIssue': {
        const [mainId, resumedBy] = args;
        if (!mainId) return jsonResponse({ success: false, message: 'ต้องระบุเลขที่งาน' });
        const { data: active, error: activeErr } = await supabase.from('pause_records').select('id').eq('main_id', mainId).eq('status', 'paused').order('paused_at', { ascending: false }).limit(1);
        if (activeErr) return jsonResponse({ success: false, message: activeErr.message });
        if (!active || active.length === 0) return jsonResponse({ success: false, message: 'ไม่พบรายการพักงานที่ยังเปิดอยู่สำหรับเลขงานนี้' });
        const { error } = await supabase.from('pause_records').update({ status: 'resumed', resumed_at: new Date().toISOString(), resumed_by: resumedBy || null }).eq('id', active[0].id);
        if (error) return jsonResponse({ success: false, message: error.message });
        await invalidateAdminBadgeCountsCache();
        return jsonResponse({ success: true, message: 'บันทึกกลับมาทำงานเรียบร้อย!' });
      }

      case 'getActivePausedList': {
        const { data, error } = await supabase.from('pause_records').select('*').eq('status', 'paused').order('paused_at', { ascending: false }).limit(1000);
        if (error) return jsonResponse({ error: error.message });
        return jsonResponse(data);
      }

      case 'getPauseHistory': {
        const [mainId] = args;
        if (!mainId) return jsonResponse({ error: 'ต้องระบุเลขที่งาน' });
        const { data, error } = await supabase.from('pause_records').select('*').eq('main_id', mainId).order('paused_at', { ascending: false }).limit(200);
        if (error) return jsonResponse({ error: error.message });
        return jsonResponse(data);
      }

      case 'updatePauseRecordFields': {
        const [pauseId, mainId, fields] = args;
        const id = (pauseId || '').toString().trim();
        const jobId = (mainId || '').toString().trim();
        if (!id || !jobId) return jsonResponse({ success: false, message: 'ต้องระบุรายการพักงานและเลขที่งาน' });
        const { data: active, error: activeErr } = await supabase.from('pause_records').select('id').eq('id', id).eq('main_id', jobId).eq('status', 'paused').limit(1);
        if (activeErr) return jsonResponse({ success: false, message: activeErr.message });
        if (!active || active.length === 0) return jsonResponse({ success: false, message: 'ไม่พบรายการพักงานนี้ หรือเลขงานนี้กลับมาทำงานไปแล้ว จึงแก้ไขไม่ได้' });
        const allowedKeys = ['reason', 'note', 'branch', 'service_type', 'cause', 'requested_item'];
        const patch: any = {};
        allowedKeys.forEach((key) => { if (fields && Object.prototype.hasOwnProperty.call(fields, key)) patch[key] = fields[key] || null; });
        const { error } = await supabase.from('pause_records').update(patch).eq('id', id);
        if (error) return jsonResponse({ success: false, message: 'แก้ไขล้มเหลว: ' + error.message });
        return jsonResponse({ success: true, message: 'แก้ไขข้อมูลพักงานเรียบร้อย!' });
      }

      case 'updateOpenIssueWhilePaused': {
        const [mainId, fields] = args;
        const id = (mainId || '').toString().trim();
        if (!id) return jsonResponse({ success: false, message: 'ต้องระบุเลขที่งาน' });
        const pauseCheck = await checkIssuePausedStatus(id);
        if (pauseCheck.error) return jsonResponse({ success: false, message: 'ตรวจสอบสถานะพักงานล้มเหลว: ' + pauseCheck.error });
        if (!pauseCheck.paused) return jsonResponse({ success: false, message: 'แก้ไขข้อมูลเปิดงานได้เฉพาะตอนที่เลขงานนี้ "กำลังพักงานอยู่" เท่านั้น' });
        const { data: existing, error: existErr } = await supabase.from('open_issues').select('id').eq('main_id', id).order('created_at', { ascending: false }).limit(1);
        if (existErr) return jsonResponse({ success: false, message: existErr.message });
        if (!existing || existing.length === 0) return jsonResponse({ success: false, message: 'ไม่พบข้อมูลเปิดงานของเลขที่ "' + id + '"' });
        const allowedKeys = ['service_type', 'contract_type', 'req_date', 'service_work', 'branch', 'details', 'contractor'];
        const patch: any = {};
        allowedKeys.forEach((key) => { if (fields && Object.prototype.hasOwnProperty.call(fields, key)) patch[key] = fields[key]; });
        const { error } = await supabase.from('open_issues').update(patch).eq('id', existing[0].id);
        if (error) return jsonResponse({ success: false, message: 'แก้ไขล้มเหลว: ' + error.message });
        return jsonResponse({ success: true, message: 'แก้ไขข้อมูลเปิดงานเรียบร้อย!' });
      }

      case 'saveEditWhilePaused': {
        const [mainId, pauseId, openFields, pauseFields] = args;
        const notes: string[] = [];
        let overallSuccess = true;
        // เรียกฟังก์ชันภายในตรงๆ (เลี่ยงจำลอง HTTP self-call)
        async function updateOpenWhilePausedInner(mid: string, flds: any) {
          const id = (mid || '').toString().trim();
          if (!id) return { success: false, message: 'ต้องระบุเลขที่งาน' };
          const pc = await checkIssuePausedStatus(id);
          if (pc.error) return { success: false, message: 'ตรวจสอบสถานะพักงานล้มเหลว: ' + pc.error };
          if (!pc.paused) return { success: false, message: 'แก้ไขข้อมูลเปิดงานได้เฉพาะตอนที่เลขงานนี้ "กำลังพักงานอยู่" เท่านั้น' };
          const { data: existing, error: existErr } = await supabase.from('open_issues').select('id').eq('main_id', id).order('created_at', { ascending: false }).limit(1);
          if (existErr) return { success: false, message: existErr.message };
          if (!existing || existing.length === 0) return { success: false, message: 'ไม่พบข้อมูลเปิดงานของเลขที่ "' + id + '"' };
          const allowedKeys = ['service_type', 'contract_type', 'req_date', 'service_work', 'branch', 'details', 'contractor'];
          const patch: any = {};
          allowedKeys.forEach((key) => { if (flds && Object.prototype.hasOwnProperty.call(flds, key)) patch[key] = flds[key]; });
          const { error } = await supabase.from('open_issues').update(patch).eq('id', existing[0].id);
          if (error) return { success: false, message: 'แก้ไขล้มเหลว: ' + error.message };
          return { success: true, message: 'แก้ไขข้อมูลเปิดงานเรียบร้อย!' };
        }
        async function updatePauseFieldsInner(pid: string, mid: string, flds: any) {
          const id = (pid || '').toString().trim();
          const jobId = (mid || '').toString().trim();
          if (!id || !jobId) return { success: false, message: 'ต้องระบุรายการพักงานและเลขที่งาน' };
          const { data: active, error: activeErr } = await supabase.from('pause_records').select('id').eq('id', id).eq('main_id', jobId).eq('status', 'paused').limit(1);
          if (activeErr) return { success: false, message: activeErr.message };
          if (!active || active.length === 0) return { success: false, message: 'ไม่พบรายการพักงานนี้ หรือเลขงานนี้กลับมาทำงานไปแล้ว จึงแก้ไขไม่ได้' };
          const allowedKeys = ['reason', 'note', 'branch', 'service_type', 'cause', 'requested_item'];
          const patch: any = {};
          allowedKeys.forEach((key) => { if (flds && Object.prototype.hasOwnProperty.call(flds, key)) patch[key] = flds[key] || null; });
          const { error } = await supabase.from('pause_records').update(patch).eq('id', id);
          if (error) return { success: false, message: 'แก้ไขล้มเหลว: ' + error.message };
          return { success: true, message: 'แก้ไขข้อมูลพักงานเรียบร้อย!' };
        }
        if (openFields && Object.keys(openFields).length > 0) {
          const r1 = await updateOpenWhilePausedInner(mainId, openFields);
          if (!r1.success) overallSuccess = false;
          notes.push('ข้อมูลเปิดงาน: ' + r1.message);
        }
        if (pauseFields && Object.keys(pauseFields).length > 0) {
          const r2 = await updatePauseFieldsInner(pauseId, mainId, pauseFields);
          if (!r2.success) overallSuccess = false;
          notes.push('ข้อมูลพักงาน: ' + r2.message);
        }
        if (notes.length === 0) return jsonResponse({ success: false, message: 'ไม่มีข้อมูลที่ต้องการแก้ไข' });
        return jsonResponse({ success: overallSuccess, message: notes.join(' | ') });
      }

      case 'getOpenIssueByMainId': {
        const [mainId] = args;
        const id = (mainId || '').toString().trim();
        if (!id) return jsonResponse({ error: 'ต้องระบุเลขที่งาน' });
        const { data, error } = await supabase.from('open_issues').select('*').eq('main_id', id).order('created_at', { ascending: false }).limit(1);
        if (error) return jsonResponse({ error: error.message });
        return jsonResponse(data && data.length > 0 ? data[0] : null);
      }

      case 'checkIssuePausedStatus': {
        const [mainId] = args;
        return jsonResponse(await checkIssuePausedStatus(mainId));
      }

      // ==================== ฟอร์มวางบิล / ไฟล์ผู้รับเหมาส่งกลับ (เก็บไฟล์ใน Supabase Storage แทน Google Drive) ====================
      case 'getMyBillingJobsWithSubmissionStatus': {
        const [username, token] = args;
        const session = await verifySession(username, token);
        if (!session.valid) return jsonResponse({ error: 'กรุณาเข้าสู่ระบบใหม่' });
        let jobsQ = supabase.from('billing_documents').select('customer_case,branch_code,branch_name,service_type,asset_id,contractor,created_at').eq('sent_to_contractor', true).is('completed_at', null).order('created_at', { ascending: true }).limit(2000);
        if (session.role !== 'admin') jobsQ = jobsQ.eq('contractor', session.displayName);
        const { data: jobsData, error: jobsErr } = await jobsQ;
        if (jobsErr) return jsonResponse({ error: jobsErr.message });
        const seen = new Set(); const jobs: any[] = [];
        (jobsData || []).forEach((r: any) => {
          if (!r.customer_case || seen.has(r.customer_case)) return;
          seen.add(r.customer_case);
          jobs.push({ customerCase: r.customer_case, branchCode: r.branch_code, branchName: r.branch_name, serviceType: r.service_type, assetId: r.asset_id, contractor: r.contractor });
        });
        if (jobs.length === 0) return jsonResponse([]);
        const jobIds = jobs.map((j) => j.customerCase);
        let subQ = supabase.from('job_form_submissions').select('*').in('customer_case', jobIds).order('submitted_at', { ascending: true });
        if (session.role !== 'admin') subQ = subQ.eq('contractor', session.displayName);
        const { data: subData } = await subQ;
        const latestByJob: Record<string, any> = {};
        (subData || []).forEach((s: any) => { latestByJob[s.customer_case] = s; });
        const result = jobs.map((job) => {
          const sub = latestByJob[job.customerCase];
          return {
            customerCase: job.customerCase, branchCode: job.branchCode, branchName: job.branchName, serviceType: job.serviceType, assetId: job.assetId, contractor: job.contractor,
            submissionStatus: sub ? sub.status : 'none', adminRemark: sub ? sub.admin_remark : null, submittedAt: sub ? sub.submitted_at : null,
            fileUrl: sub ? sub.file_url : null, fileName: sub ? sub.file_name : null,
          };
        });
        return jsonResponse(result);
      }

      case 'getJobFormSubmissions': {
        const [username, token] = args;
        const session = await verifySession(username, token);
        if (!session.valid) return jsonResponse({ error: 'กรุณาเข้าสู่ระบบใหม่' });
        if (session.role !== 'admin') return jsonResponse({ error: 'เฉพาะแอดมินเท่านั้นที่ดูรายการนี้ได้' });
        const { data, error } = await supabase.from('job_form_submissions').select('*').order('submitted_at', { ascending: false }).limit(500);
        if (error) return jsonResponse({ error: error.message });
        const unreadIds = (data || []).filter((r: any) => r.is_read === false).map((r: any) => r.id);
        if (unreadIds.length > 0) {
          await supabase.from('job_form_submissions').update({ is_read: true, read_at: new Date().toISOString() }).in('id', unreadIds);
        }
        return jsonResponse(data);
      }

      case 'getUnreadJobFormSubmissionCount': {
        const [username, token] = args;
        const session = await verifySession(username, token);
        if (!session.valid || session.role !== 'admin') return jsonResponse({ count: 0 });
        const { count, error } = await supabase.from('job_form_submissions').select('id', { count: 'exact', head: true }).eq('is_read', false);
        if (error) return jsonResponse({ count: 0 });
        return jsonResponse({ count: count || 0 });
      }

      case 'markAllJobFormSubmissionsRead': {
        const [username, token] = args;
        const session = await verifySession(username, token);
        if (!session.valid) return jsonResponse({ success: false, message: 'กรุณาเข้าสู่ระบบใหม่' });
        if (session.role !== 'admin') return jsonResponse({ success: false, message: 'เฉพาะแอดมินเท่านั้นที่ทำรายการนี้ได้' });
        const { error } = await supabase.from('job_form_submissions').update({ is_read: true, read_at: new Date().toISOString() }).eq('is_read', false);
        if (error) return jsonResponse({ success: false, message: error.message });
        return jsonResponse({ success: true });
      }

      case 'reviewJobFormSubmission': {
        const [username, token, submissionId, decision, remark] = args;
        const session = await verifySession(username, token);
        if (!session.valid) return jsonResponse({ success: false, message: 'กรุณาเข้าสู่ระบบใหม่' });
        if (session.role !== 'admin') return jsonResponse({ success: false, message: 'เฉพาะแอดมินเท่านั้นที่ตรวจสอบได้' });
        if (decision !== 'approved' && decision !== 'rejected') return jsonResponse({ success: false, message: 'สถานะไม่ถูกต้อง' });
        if (decision === 'rejected' && (!remark || !remark.toString().trim())) return jsonResponse({ success: false, message: 'กรุณาระบุหมายเหตุ/เหตุผลที่ตีกลับ ก่อนดำเนินการ' });
        const { data: subCheck } = await supabase.from('job_form_submissions').select('customer_case').eq('id', submissionId).limit(1);
        const jobId = (subCheck && subCheck.length > 0) ? subCheck[0].customer_case : null;
        const fields = { status: decision, admin_remark: remark ? remark.toString().trim() : null, reviewed_at: new Date().toISOString(), reviewed_by: session.displayName, is_read: true };
        const { error } = await supabase.from('job_form_submissions').update(fields).eq('id', submissionId);
        if (error) return jsonResponse({ success: false, message: error.message });
        if (decision === 'approved' && jobId) {
          const { error: closeErr } = await supabase.from('billing_documents').update({ completed_at: new Date().toISOString() }).eq('customer_case', jobId);
          if (closeErr) return jsonResponse({ success: true, message: 'อนุมัติเรียบร้อยแล้ว แต่ตัดบิลไม่สำเร็จ: ' + closeErr.message + ' (กรุณาตรวจสอบตารางวางบิลอีกครั้ง)' });
        }
        return jsonResponse({ success: true, message: decision === 'approved' ? 'อนุมัติเรียบร้อยแล้ว - ตัดบิลรอบนี้ออกจากตารางวางบิลของผู้รับเหมาแล้ว' : 'ตีกลับเรียบร้อยแล้ว - ผู้รับเหมาจะเห็นหมายเหตุนี้และต้องส่งฟอร์มใหม่' });
      }

      case 'uploadJobFormSubmission': {
        const [username, token, jobId, fileBase64, fileName] = args;
        const session = await verifySession(username, token);
        if (!session.valid) return jsonResponse({ success: false, message: 'กรุณาเข้าสู่ระบบใหม่' });
        if (!jobId || !fileBase64) return jsonResponse({ success: false, message: 'ข้อมูลไม่ครบ (ต้องมีเลขงานและไฟล์)' });
        try {
          const { data: jobRows, error: jobErr } = await supabase.from('billing_documents').select('customer_case,contractor,branch_name,sent_to_contractor').eq('customer_case', jobId).limit(1);
          if (jobErr) return jsonResponse({ success: false, message: jobErr.message });
          if (!jobRows || jobRows.length === 0) return jsonResponse({ success: false, message: 'ไม่พบเลขงาน "' + jobId + '" ในระบบ' });
          const jobRecord = jobRows[0];
          if (session.role !== 'admin') {
            if (jobRecord.contractor !== session.displayName) return jsonResponse({ success: false, message: 'คุณไม่มีสิทธิ์ส่งไฟล์สำหรับเลขงานนี้' });
            if (jobRecord.sent_to_contractor !== true) return jsonResponse({ success: false, message: 'เลขงานนี้ยังไม่ถูกส่งบิลให้คุณ' });
          }

          const safeOriginalName = (fileName || (jobId + '.pdf')).toString();
          const ext = (safeOriginalName.split('.').pop() || '').toLowerCase();
          const imageExts = ['jpg', 'jpeg', 'png'];
          const isImage = imageExts.indexOf(ext) !== -1;
          const rawBytes = Uint8Array.from(atob(fileBase64), (c) => c.charCodeAt(0));

          let pdfBytes: Uint8Array;
          if (isImage) {
            // แปลงรูปภาพที่ผู้รับเหมาถ่ายมา ให้เป็นไฟล์ PDF จริงๆ (แทนการใช้ Google Docs แบบเดิม) โดยฝังรูปลงหน้ากระดาษ A4 ให้พอดีความกว้าง
            const { PDFDocument } = await loadPdfLib();
            const pdfDoc = await PDFDocument.create();
            const image = ext === 'png' ? await pdfDoc.embedPng(rawBytes) : await pdfDoc.embedJpg(rawBytes);
            const maxWidth = 570; // จุด (point) - ความกว้างใช้งานจริงของหน้า A4 แนวตั้งหลังหักขอบ
            const scale = image.width > maxWidth ? maxWidth / image.width : 1;
            const drawWidth = image.width * scale;
            const drawHeight = image.height * scale;
            const page = pdfDoc.addPage([612, 792]); // Letter/A4-ish ขนาดมาตรฐาน point
            page.drawImage(image, { x: (612 - drawWidth) / 2, y: Math.max(792 - drawHeight - 20, 10), width: drawWidth, height: drawHeight });
            pdfBytes = await pdfDoc.save();
          } else {
            pdfBytes = rawBytes;
          }

          const baseNameNoExt = safeOriginalName.replace(/\.(pdf|jpe?g|png)$/i, '');
          const finalFileName = jobId + '_' + baseNameNoExt + '.pdf';
          // ตัวคีย์ที่ใช้เก็บจริงใน Supabase Storage ต้องเป็น ASCII ล้วน (Storage ปฏิเสธ key ที่มีอักษรไทย/ยูนิโค้ด
          // ทำให้เจอ error "Invalid key" ตอนอัปโหลด) - ชื่อไฟล์ภาษาไทยที่อ่านง่ายยังคงเก็บแยกไว้ที่คอลัมน์ file_name
          // สำหรับใช้ตอนดาวน์โหลด/แสดงผลบนหน้าเว็บตามปกติ ไม่กระทบผู้ใช้เลย
          const safeJobIdForPath = jobId.toString().replace(/[^a-zA-Z0-9._-]/g, '_');
          const storagePath = safeJobIdForPath + '/' + Date.now() + '_' + Math.random().toString(36).slice(2, 8) + '.pdf';

          const { error: uploadErr } = await supabase.storage.from('job-form-submissions').upload(storagePath, pdfBytes, { contentType: 'application/pdf', upsert: false });
          if (uploadErr) return jsonResponse({ success: false, message: 'อัปโหลดไฟล์ล้มเหลว: ' + uploadErr.message });
          const { data: publicUrlData } = supabase.storage.from('job-form-submissions').getPublicUrl(storagePath);
          const fileUrl = publicUrlData ? publicUrlData.publicUrl : null;

          const row = {
            customer_case: jobId, contractor: jobRecord.contractor || session.displayName, branch_name: jobRecord.branch_name || '',
            file_name: finalFileName, drive_file_id: storagePath, file_url: fileUrl, submitted_at: new Date().toISOString(),
            is_read: false, status: 'pending', admin_remark: null, reviewed_at: null, reviewed_by: null,
          };
          const { error: insertErr } = await supabase.from('job_form_submissions').insert(row);
          if (insertErr) return jsonResponse({ success: false, message: 'บันทึกข้อมูลล้มเหลว: ' + insertErr.message });

          return jsonResponse({ success: true, message: 'ส่งไฟล์ฟอร์มเลขงาน "' + jobId + '" กลับสำเร็จแล้ว รอแอดมินตรวจสอบ', fileUrl: row.file_url, fileName: row.file_name, submittedAt: row.submitted_at });
        } catch (e) {
          return jsonResponse({ success: false, message: String(e) });
        }
      }

      // ==================== PDF ตารางวางบิล / ใบเขียว (สร้างจริงด้วย pdf-lib แทน Google Docs) ====================
      case 'generateBillingPdfBase64': {
        const [rowsArg, isAdminArg] = args;
        const result = await generateBillingPdfBase64(rowsArg, !!isAdminArg);
        return jsonResponse(result);
      }

      case 'downloadBillingRoundPdf': {
        const [username, token, roundNo, contractor] = args;
        const session = await verifySession(username, token);
        if (!session.valid) return jsonResponse({ success: false, message: 'กรุณาเข้าสู่ระบบใหม่' });
        const contractorName = (contractor || '').toString();
        if (session.role !== 'admin' && contractorName !== session.displayName) {
          return jsonResponse({ success: false, message: 'ไม่มีสิทธิ์ดูข้อมูลรอบบิลของผู้รับเหมาอื่น' });
        }
        if (roundNo === undefined || roundNo === null || roundNo === '') return jsonResponse({ success: false, message: 'ไม่พบเลขรอบบิล' });
        let q = supabase.from('billing_documents').select('*').eq('round_no', roundNo).eq('contractor', contractorName).order('seq', { ascending: true }).order('created_at', { ascending: true });
        if (session.role === 'admin') q = q.or('sent_to_contractor.eq.true,completed_at.not.is.null');
        else q = q.eq('sent_to_contractor', true);
        const { data, error } = await q;
        if (error) return jsonResponse({ success: false, message: 'ดึงข้อมูลรอบบิลล้มเหลว: ' + error.message });
        if (!data || data.length === 0) return jsonResponse({ success: false, message: 'ไม่พบข้อมูลของรอบบิลนี้ (อาจถูกลบหรือแก้ไขไปแล้ว)' });
        const isAdmin = session.role === 'admin';
        const pdfResult = await generateBillingPdfBase64(data, isAdmin);
        if (pdfResult.success) {
          const safeContractor = contractorName ? contractorName.replace(/[\\/:*?"<>|]/g, '_') : 'ไม่มีผู้รับเหมา';
          pdfResult.filename = 'ตารางวางบิล_รอบ' + roundNo + '_' + safeContractor + '.pdf';
        }
        return jsonResponse(pdfResult);
      }

      case 'downloadJobBillingPdf': {
        const [username, token, jobId] = args;
        const session = await verifySession(username, token);
        if (!session.valid) return jsonResponse({ success: false, message: 'กรุณาเข้าสู่ระบบใหม่' });
        const cleanJobId = (jobId || '').toString().trim();
        if (!cleanJobId) return jsonResponse({ success: false, message: 'ไม่พบเลขที่ใบแจ้งซ่อมบำรุง' });
        let q = supabase.from('billing_documents').select('*').eq('customer_case', cleanJobId).order('seq', { ascending: true }).order('created_at', { ascending: true });
        if (session.role === 'admin') q = q.or('sent_to_contractor.eq.true,completed_at.not.is.null');
        else q = q.eq('contractor', session.displayName).eq('sent_to_contractor', true);
        const { data, error } = await q;
        if (error) return jsonResponse({ success: false, message: 'ดึงข้อมูลบิลล้มเหลว: ' + error.message });
        if (!data || data.length === 0) return jsonResponse({ success: false, message: 'งานนี้ยังไม่มีใบวางบิล (ใบเขียว) หรือยังไม่ถูกส่งบิลให้ผู้รับเหมา' });
        const isAdmin = session.role === 'admin';
        const pdfResult = await generateBillingPdfBase64(data, isAdmin);
        if (pdfResult.success) {
          const safeJobId = cleanJobId.replace(/[\\/:*?"<>|]/g, '_');
          pdfResult.filename = 'ใบเขียว_' + safeJobId + '.pdf';
        }
        return jsonResponse(pdfResult);
      }

      // ==================== ฟอร์มวางบิล .xlsx (สร้างจริงด้วย ExcelJS แทน Google Sheets แม่แบบ) ====================
      case 'generateJobFormsForBilling': {
        const [username, token, jobIds] = args;
        const session = await verifySession(username, token);
        if (!session.valid) return jsonResponse({ success: false, message: 'กรุณาเข้าสู่ระบบใหม่' });
        if (!jobIds || jobIds.length === 0) return jsonResponse({ success: false, message: 'ไม่มีเลขงานให้สร้างฟอร์ม' });
        let q = supabase.from('billing_documents').select('customer_case,branch_code,branch_name,service_type,asset_id,contractor,sent_to_contractor').in('customer_case', jobIds).order('created_at', { ascending: true });
        if (session.role !== 'admin') q = q.eq('contractor', session.displayName).eq('sent_to_contractor', true);
        const { data, error } = await q;
        if (error) return jsonResponse({ success: false, message: 'ดึงข้อมูลล้มเหลว: ' + error.message });
        const seen = new Set(); const jobs: any[] = [];
        (data || []).forEach((r: any) => {
          if (!r.customer_case || seen.has(r.customer_case)) return;
          seen.add(r.customer_case);
          jobs.push({ customerCase: r.customer_case, branchCode: r.branch_code, branchName: r.branch_name, serviceType: r.service_type, assetId: r.asset_id });
        });
        if (jobs.length === 0) return jsonResponse({ success: false, message: 'ไม่พบข้อมูลเลขงานที่ระบุ (หรือไม่ใช่งานของคุณ / ยังไม่ถูกส่งบิล)' });
        const files: any[] = []; const errors: string[] = [];
        for (const job of jobs) {
          const result = await generateJobFormXlsxBase64(job);
          if (result.success) files.push({ filename: result.filename, base64: result.base64, customerCase: result.customerCase });
          else errors.push((job.customerCase || '-') + ': ' + result.message);
        }
        const message = files.length > 0
          ? ('สร้างฟอร์มสำเร็จ ' + files.length + ' ไฟล์' + (errors.length ? (' | ล้มเหลว: ' + errors.join(' ; ')) : ''))
          : ('สร้างฟอร์มล้มเหลวทั้งหมด: ' + errors.join(' ; '));
        return jsonResponse({ success: files.length > 0, files, message });
      }

      // ==================== Sync ไป Google Sheet จริง (ผ่าน Google Sheets API ด้วย Service Account) ====================
      case 'manualSyncToSheets': {
        const [username, token] = args;
        const session = await verifySession(username, token);
        if (!session.valid) return jsonResponse({ success: false, message: 'กรุณาเข้าสู่ระบบใหม่' });
        if (session.role !== 'admin') return jsonResponse({ success: false, message: 'เฉพาะแอดมินเท่านั้นที่สั่งซิงค์ข้อมูลได้' });

        const { data: secretRows, error: secretErr } = await supabase.from('app_secrets').select('key,value');
        if (secretErr) return jsonResponse({ success: false, message: 'อ่านค่า secret ล้มเหลว: ' + secretErr.message });
        const secretMap: Record<string, string> = {};
        (secretRows || []).forEach((r: any) => { secretMap[r.key] = r.value; });
        const spreadsheetId = secretMap['google_sync_spreadsheet_id'];
        if (!spreadsheetId) return jsonResponse({ success: false, message: 'ยังไม่ได้ตั้งค่า Google Sheet ปลายทาง (google_sync_spreadsheet_id)' });

        const tokenResult = await getGoogleAccessToken(supabase);
        if (!tokenResult.token) return jsonResponse({ success: false, message: tokenResult.error || 'ขอ Google access token ล้มเหลว' });
        const accessToken = tokenResult.token;
        const sheetUrl = 'https://docs.google.com/spreadsheets/d/' + spreadsheetId + '/edit';

        let existingNames: string[];
        try {
          existingNames = await getSpreadsheetSheetNames(spreadsheetId, accessToken);
        } catch (e) {
          return jsonResponse({ success: false, message: 'เปิด Google Sheet ล้มเหลว: ' + String(e) + ' (ตรวจสอบว่าแชร์สิทธิ์ Editor ให้อีเมล ' + (tokenResult.email || '') + ' แล้วหรือยัง)' });
        }

        // ซิงค์แบบ "มิเรอร์เต็มรูปแบบ" ทุกครั้ง: ดึงข้อมูลทั้งหมดจาก DB ปัจจุบัน แล้วเขียนทับ Sheet ทั้งแท็บใหม่เสมอ
        // (ไม่ใช่ append เฉพาะแถวใหม่แบบเดิม) เพื่อให้ Sheet ตรงกับฐานข้อมูลเป๊ะทุกครั้งที่กดซิงค์:
        // - ไม่มีข้อมูลซ้ำ (เขียนทับหมดทุกรอบ ไม่ใช่ต่อท้ายเรื่อย ๆ)
        // - ถ้ามีคนไปลบแถวใน Sheet เอง รอบซิงค์ถัดไปจะคืนข้อมูลที่ถูกต้องกลับมาให้อัตโนมัติ
        // - ถ้าข้อมูลใน DBถูกแก้ไข/ลบภายหลัง (เช่น แก้ราคาบิล, ลบเลขงานที่กรอกผิด) Sheet จะอัปเดตตามทันทีที่ซิงค์รอบถัดไป
        const results: string[] = [];
        let totalSynced = 0;
        for (const t of SYNC_TABLE_REGISTRY) {
          try {
            const { data: rows, error } = await supabase.from(t.table).select('*').order('created_at', { ascending: true }).limit(5000);
            if (error) { results.push(t.table + ': ดึงข้อมูลล้มเหลว (' + error.message + ')'); continue; }
            const timestamp = new Date().toISOString();
            const values = (rows || []).map((r: any) => [timestamp, ...t.mapRow(r)]);
            const msg = await mirrorRowsToSheetTab(spreadsheetId, accessToken, existingNames, t.sheetName, t.color, t.headers, values);
            totalSynced += (rows || []).length;
            results.push(msg + (values.length === 5000 ? ' (ถึงลิมิต 5000 แถว อาจมีข้อมูลเก่ากว่านี้ตกหล่น)' : ''));
          } catch (e) {
            results.push(t.table + ': ล้มเหลว (' + String(e) + ')');
          }
        }

        // แท็บ "รายงานสถานะดำเนินการ" - เป็นรายงานรวมข้อมูล ไม่ใช่ตารางดิบตารางเดียว จึงคำนวณแยกต่างหาก
        try {
          const reportRows = await computeJobStatusReportRows(null, null);
          const timestamp = new Date().toISOString();
          const values = reportRows.map((r: any) => [timestamp, ...STATUS_REPORT_SHEET.mapRow(r)]);
          const msg = await mirrorRowsToSheetTab(
            spreadsheetId, accessToken, existingNames,
            STATUS_REPORT_SHEET.sheetName, STATUS_REPORT_SHEET.color, STATUS_REPORT_SHEET.headers, values
          );
          totalSynced += reportRows.length;
          results.push(msg);
        } catch (e) {
          results.push(STATUS_REPORT_SHEET.sheetName + ': ล้มเหลว (' + String(e) + ')');
        }

        return jsonResponse({ success: true, message: 'ซิงค์ข้อมูลไป Google Sheet เสร็จสิ้น (รวม ' + totalSynced + ' แถว)\n' + results.join(' | ') + '\nลิงก์ Google Sheet: ' + sheetUrl });
      }

      default:
        return jsonResponse({ error: 'ไม่รู้จักฟังก์ชัน: ' + fnName }, 400);
    }
  } catch (err) {
    return jsonResponse({ error: String(err) }, 500);
  }
});
