/* CP9X Desktop — UI enhancements
   เพิ่มลูกเล่นให้หน้าเว็บโดยไม่แตะโค้ดเดิม: หัวข้อหน้าบนแถบบน, ปุ่มดู/ซ่อนรหัสผ่าน
   ถ้าไม่ต้องการ ลบ <script src="./ui-enhance.js"> ท้าย index.html ออกได้เลย */
(function () {
  'use strict';

  var TITLES = {
    open:        ['เปิดงาน',                 'fa-folder-open',   'บันทึกใบแจ้งซ่อมบำรุงใหม่'],
    close:       ['ปิดงาน',                  'fa-check-double',  'สรุปผลและปิดงานที่ดำเนินการเสร็จ'],
    pause:       ['พักงาน',                  'fa-pause',         'งานที่ถูกพักไว้ชั่วคราว'],
    billing:     ['ตารางวางบิล',             'fa-receipt',       'เอกสารวางบิลทั้งหมด'],
    jobforms:    ['ฟอร์มวางบิล',             'fa-file-arrow-up', 'ส่งฟอร์มและติดตามสถานะ'],
    openlist:    ['ตรวจสอบเปิดงาน',          'fa-magnifying-glass', 'รายการงานที่เปิดไว้'],
    closelist:   ['ตรวจสอบปิดงาน',           'fa-magnifying-glass', 'รายการงานที่ปิดแล้ว'],
    statusreport:['รายงานสถานะดำเนินการ',   'fa-chart-line',    'ภาพรวมความคืบหน้าแบบเรียลไทม์'],
    submissions: ['ไฟล์ผู้รับเหมาส่งกลับ',   'fa-inbox',         'ไฟล์ที่ผู้รับเหมาอัปโหลดเข้ามา'],
    completed:   ['งานที่เสร็จสิ้น',          'fa-circle-check',  'ประวัติงานที่ปิดครบถ้วนแล้ว']
  };

  function buildTitleSlot() {
    var bar = document.getElementById('topBar');
    if (!bar || document.getElementById('cp9xPageTitle')) return null;

    var left = bar.firstElementChild;           // กล่องซ้าย (ปุ่มแฮมเบอร์เกอร์ + คำอธิบาย)
    if (!left) return null;

    var oldDesc = left.querySelector('.hidden.md\\:block');
    if (oldDesc) oldDesc.remove();

    var slot = document.createElement('div');
    slot.id = 'cp9xPageTitle';
    slot.style.cssText = 'display:flex;align-items:center;gap:12px;min-width:0';
    slot.innerHTML =
      '<span id="cp9xPageIcon" style="width:38px;height:38px;flex:none;display:flex;' +
      'align-items:center;justify-content:center;border-radius:11px;font-size:15px;' +
      'background:rgba(255,255,255,.12);border:1px solid rgba(255,255,255,.16);' +
      'color:#86efac"><i class="fa-solid fa-folder-open"></i></span>' +
      '<span style="min-width:0">' +
      '<span id="cp9xPageName" style="display:block;font-size:15px;font-weight:600;' +
      'line-height:1.25;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">เปิดงาน</span>' +
      '<span id="cp9xPageDesc" style="display:block;font-size:11.5px;color:rgba(226,232,240,.62);' +
      'white-space:nowrap;overflow:hidden;text-overflow:ellipsis"></span>' +
      '</span>';
    left.appendChild(slot);
    return slot;
  }

  function setTitle(mode) {
    var info = TITLES[mode];
    if (!info) return;
    var icon = document.getElementById('cp9xPageIcon');
    var name = document.getElementById('cp9xPageName');
    var desc = document.getElementById('cp9xPageDesc');
    if (!icon || !name || !desc) return;
    icon.innerHTML = '<i class="fa-solid ' + info[1] + '"></i>';
    name.textContent = info[0];
    desc.textContent = info[2];
    name.style.animation = 'none';
    void name.offsetWidth;
    name.style.animation = 'cpRise .22s cubic-bezier(.22,.61,.36,1) both';
  }

  function currentMode() {
    var active = document.querySelector('#sidebar nav > button.bg-blood-600');
    if (!active || !active.id) return 'open';
    var map = {
      tabOpen: 'open', tabClose: 'close', tabPause: 'pause', tabBilling: 'billing',
      tabJobForms: 'jobforms', tabOpenList: 'openlist', tabCloseList: 'closelist',
      tabStatusReport: 'statusreport', tabSubmissions: 'submissions', tabCompleted: 'completed'
    };
    return map[active.id] || 'open';
  }

  function hookSwitchMode() {
    var orig = window.switchMode;
    if (typeof orig !== 'function' || orig.__cp9xWrapped) return;
    var wrapped = function (mode) {
      var r = orig.apply(this, arguments);
      try { setTitle(mode); } catch (e) { /* ไม่ให้กระทบการทำงานเดิม */ }
      return r;
    };
    wrapped.__cp9xWrapped = true;
    window.switchMode = wrapped;
  }

  /* ปุ่มดู/ซ่อนรหัสผ่านในหน้า login */
  function addPasswordToggle() {
    var pw = document.getElementById('loginPassword');
    if (!pw || pw.dataset.cp9xEye) return;
    pw.dataset.cp9xEye = '1';

    var wrap = document.createElement('div');
    wrap.style.cssText = 'position:relative';
    pw.parentNode.insertBefore(wrap, pw);
    wrap.appendChild(pw);
    pw.style.paddingRight = '44px';

    var btn = document.createElement('button');
    btn.type = 'button';
    btn.setAttribute('aria-label', 'แสดงหรือซ่อนรหัสผ่าน');
    btn.style.cssText = 'position:absolute;right:6px;top:50%;transform:translateY(-50%);' +
      'width:32px;height:32px;border:0;background:transparent;color:#94a3b8;cursor:pointer;' +
      'border-radius:8px;display:flex;align-items:center;justify-content:center';
    btn.innerHTML = '<i class="fa-regular fa-eye"></i>';
    btn.onmouseenter = function () { btn.style.color = '#16a34a'; };
    btn.onmouseleave = function () { btn.style.color = '#94a3b8'; };
    btn.onclick = function () {
      var show = pw.type === 'password';
      pw.type = show ? 'text' : 'password';
      btn.innerHTML = '<i class="fa-regular ' + (show ? 'fa-eye-slash' : 'fa-eye') + '"></i>';
      pw.focus();
    };
    wrap.appendChild(btn);
  }

  function init() {
    buildTitleSlot();
    hookSwitchMode();
    setTitle(currentMode());
    addPasswordToggle();

    // แถบบนคลุมทั้ง sidebar-toggle อยู่แล้ว — ผูก hook ซ้ำเผื่อสคริปต์เดิมโหลดช้ากว่า
    setTimeout(function () { hookSwitchMode(); setTitle(currentMode()); }, 800);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
