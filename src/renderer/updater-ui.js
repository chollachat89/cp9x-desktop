/* CP9X Desktop — แถบแจ้งเตือนอัปเดต (ทำงานเฉพาะตอนรันในแอป Electron) */
(function () {
  'use strict';
  if (!window.cp9x || !window.cp9x.isDesktop) return;

  var style = document.createElement('style');
  style.textContent = [
    '#cp9x-upd{position:fixed;right:16px;bottom:16px;z-index:2147483000;',
    'font-family:Kanit,system-ui,-apple-system,"Segoe UI",sans-serif;font-size:14px;',
    'max-width:340px;background:#0f172a;color:#e2e8f0;border:1px solid #1e293b;',
    'border-radius:12px;box-shadow:0 12px 32px rgba(2,6,23,.45);padding:14px 16px;',
    'display:none;line-height:1.5}',
    '#cp9x-upd.show{display:block;animation:cp9xUp .25s ease-out}',
    '@keyframes cp9xUp{from{opacity:0;transform:translateY(8px)}to{opacity:1;transform:none}}',
    '#cp9x-upd .t{font-weight:600;color:#4ade80;margin-bottom:4px;display:flex;',
    'align-items:center;gap:8px;justify-content:space-between}',
    '#cp9x-upd .x{cursor:pointer;color:#64748b;font-size:18px;line-height:1;background:none;border:0}',
    '#cp9x-upd .x:hover{color:#e2e8f0}',
    '#cp9x-upd .m{color:#cbd5e1;font-size:13px}',
    '#cp9x-upd .bar{height:6px;background:#1e293b;border-radius:99px;overflow:hidden;margin-top:10px}',
    '#cp9x-upd .bar>i{display:block;height:100%;width:0;background:linear-gradient(90deg,#22c55e,#22d3ee);',
    'transition:width .3s ease}',
    '#cp9x-upd .acts{margin-top:12px;display:flex;gap:8px}',
    '#cp9x-upd button.b{flex:1;cursor:pointer;border:0;border-radius:8px;padding:8px 12px;',
    'font-family:inherit;font-size:13px;font-weight:600}',
    '#cp9x-upd button.p{background:#22c55e;color:#052e16}',
    '#cp9x-upd button.p:hover{background:#16a34a}',
    '#cp9x-upd button.s{background:#1e293b;color:#94a3b8}',
    '#cp9x-upd button.s:hover{background:#334155;color:#e2e8f0}',
    '#cp9x-ver{position:fixed;left:10px;bottom:8px;z-index:2147482000;font-size:11px;',
    'color:#94a3b8;font-family:Kanit,system-ui,sans-serif;pointer-events:none;opacity:.75}'
  ].join('');
  document.head.appendChild(style);

  var box = document.createElement('div');
  box.id = 'cp9x-upd';
  box.innerHTML =
    '<div class="t"><span id="cp9x-upd-title">อัปเดต</span>' +
    '<button class="x" id="cp9x-upd-close" title="ปิด">&times;</button></div>' +
    '<div class="m" id="cp9x-upd-msg"></div>' +
    '<div class="bar" id="cp9x-upd-bar" style="display:none"><i></i></div>' +
    '<div class="acts" id="cp9x-upd-acts"></div>';
  document.body.appendChild(box);

  var badge = document.createElement('div');
  badge.id = 'cp9x-ver';
  document.body.appendChild(badge);
  window.cp9x.getVersion().then(function (v) { badge.textContent = 'v' + v; });

  var elTitle = box.querySelector('#cp9x-upd-title');
  var elMsg = box.querySelector('#cp9x-upd-msg');
  var elBar = box.querySelector('#cp9x-upd-bar');
  var elFill = elBar.querySelector('i');
  var elActs = box.querySelector('#cp9x-upd-acts');
  box.querySelector('#cp9x-upd-close').onclick = function () { box.classList.remove('show'); };

  function fmtMB(n) { return (n / 1048576).toFixed(1) + ' MB'; }

  function render(s) {
    if (!s) return;
    elActs.innerHTML = '';
    elBar.style.display = 'none';

    if (s.status === 'available') {
      elTitle.textContent = 'มีเวอร์ชันใหม่';
      elMsg.textContent = 'เวอร์ชัน ' + s.newVersion + ' กำลังดาวน์โหลดอัตโนมัติ...';
      box.classList.add('show');
    } else if (s.status === 'downloading') {
      elTitle.textContent = 'กำลังดาวน์โหลดอัปเดต';
      elMsg.textContent = (s.percent || 0) + '%' +
        (s.total ? ' — ' + fmtMB(s.transferred) + ' / ' + fmtMB(s.total) : '');
      elBar.style.display = 'block';
      elFill.style.width = (s.percent || 0) + '%';
      box.classList.add('show');
    } else if (s.status === 'downloaded') {
      elTitle.textContent = 'พร้อมติดตั้ง';
      elMsg.textContent = 'ดาวน์โหลดเวอร์ชัน ' + s.newVersion + ' เสร็จแล้ว รีสตาร์ตเพื่อใช้งาน';
      var b1 = document.createElement('button');
      b1.className = 'b p'; b1.textContent = 'รีสตาร์ตตอนนี้';
      b1.onclick = function () { window.cp9x.updater.install(); };
      var b2 = document.createElement('button');
      b2.className = 'b s'; b2.textContent = 'ไว้ทีหลัง';
      b2.onclick = function () { box.classList.remove('show'); };
      elActs.appendChild(b1); elActs.appendChild(b2);
      box.classList.add('show');
    } else if (s.status === 'error') {
      elTitle.textContent = 'อัปเดตไม่สำเร็จ';
      elMsg.textContent = s.message || 'เชื่อมต่อเซิร์ฟเวอร์อัปเดตไม่ได้';
      box.classList.add('show');
      setTimeout(function () { box.classList.remove('show'); }, 8000);
    } else {
      box.classList.remove('show');
    }
  }

  window.cp9x.updater.onState(render);
  window.cp9x.updater.getState().then(render);
})();
