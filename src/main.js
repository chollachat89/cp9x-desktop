'use strict';

const { app, BrowserWindow, shell, ipcMain, dialog, Menu } = require('electron');
const path = require('node:path');
const log = require('electron-log');
const { autoUpdater } = require('electron-updater');

// ---------- Logging ----------
log.transports.file.level = 'info';
autoUpdater.logger = log;
log.info(`CP9X starting v${app.getVersion()}`);

const isDev = process.argv.includes('--dev') || !app.isPackaged;

// ---------- Auto-update behaviour ----------
autoUpdater.autoDownload = true;          // ดาวน์โหลดอัตโนมัติเมื่อเจอเวอร์ชันใหม่
autoUpdater.autoInstallOnAppQuit = true;  // ติดตั้งตอนปิดแอปถ้าผู้ใช้ไม่กด restart
autoUpdater.allowPrerelease = false;

let mainWindow = null;
let updateState = { status: 'idle', version: app.getVersion() };

// ---------- Single instance ----------
if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.focus();
    }
  });
}

function send(channel, payload) {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send(channel, payload);
  }
}

function setUpdateState(status, extra = {}) {
  updateState = { status, version: app.getVersion(), ...extra };
  send('updater:state', updateState);
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1440,
    height: 900,
    minWidth: 1024,
    minHeight: 640,
    show: false,
    backgroundColor: '#f8fafc',
    autoHideMenuBar: true,
    icon: path.join(__dirname, '..', 'build', 'icon.ico'),
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
      spellcheck: false
    }
  });

  mainWindow.once('ready-to-show', () => {
    mainWindow.show();
    if (isDev) mainWindow.webContents.openDevTools({ mode: 'detach' });
  });

  mainWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));

  // เปิดลิงก์ภายนอกด้วยเบราว์เซอร์ของเครื่อง ไม่เปิดหน้าต่าง Electron ใหม่
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https?:\/\//i.test(url)) shell.openExternal(url);
    return { action: 'deny' };
  });

  mainWindow.webContents.on('will-navigate', (event, url) => {
    const current = mainWindow.webContents.getURL();
    if (url !== current) {
      event.preventDefault();
      if (/^https?:\/\//i.test(url)) shell.openExternal(url);
    }
  });

  mainWindow.on('closed', () => { mainWindow = null; });
}

// ---------- Menu (ย่อ ๆ พร้อมปุ่มเช็คอัปเดต) ----------
function buildMenu() {
  const template = [
    {
      label: 'ไฟล์',
      submenu: [
        { role: 'reload', label: 'โหลดใหม่' },
        { role: 'toggleDevTools', label: 'เครื่องมือนักพัฒนา' },
        { type: 'separator' },
        { role: 'quit', label: 'ออกจากโปรแกรม' }
      ]
    },
    {
      label: 'แก้ไข',
      submenu: [
        { role: 'undo', label: 'เลิกทำ' },
        { role: 'redo', label: 'ทำซ้ำ' },
        { type: 'separator' },
        { role: 'cut', label: 'ตัด' },
        { role: 'copy', label: 'คัดลอก' },
        { role: 'paste', label: 'วาง' },
        { role: 'selectAll', label: 'เลือกทั้งหมด' }
      ]
    },
    {
      label: 'มุมมอง',
      submenu: [
        { role: 'resetZoom', label: 'ขนาดปกติ' },
        { role: 'zoomIn', label: 'ขยาย' },
        { role: 'zoomOut', label: 'ย่อ' },
        { type: 'separator' },
        { role: 'togglefullscreen', label: 'เต็มจอ' }
      ]
    },
    {
      label: 'ช่วยเหลือ',
      submenu: [
        {
          label: 'ตรวจหาอัปเดต',
          click: () => checkForUpdates(true)
        },
        {
          label: 'เปิดโฟลเดอร์ log',
          click: () => shell.showItemInFolder(log.transports.file.getFile().path)
        },
        {
          label: `เกี่ยวกับ CP9X (v${app.getVersion()})`,
          click: () => {
            dialog.showMessageBox(mainWindow, {
              type: 'info',
              title: 'เกี่ยวกับ CP9X',
              message: 'CP9X Desktop',
              detail: `เวอร์ชัน ${app.getVersion()}\nElectron ${process.versions.electron}\nChromium ${process.versions.chrome}`
            });
          }
        }
      ]
    }
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

// ---------- Updater events ----------
let manualCheck = false;

autoUpdater.on('checking-for-update', () => setUpdateState('checking', { manual: manualCheck }));

autoUpdater.on('update-available', (info) => {
  setUpdateState('available', { newVersion: info.version, manual: manualCheck });
});

autoUpdater.on('update-not-available', () => {
  setUpdateState('not-available', { manual: manualCheck });
  manualCheck = false;
});

// แปลง error ดิบ (ที่มักมี header/JSON ยาวเป็นหน้ากระดาษ) ให้เหลือแค่ประโยคเดียวที่อ่านง่าย
function friendlyUpdateError(err) {
  const raw = String((err && err.message) || err || '');
  if (/net::ERR_INTERNET_DISCONNECTED|ENOTFOUND|ECONNREFUSED|ETIMEDOUT/i.test(raw)) {
    return 'ไม่มีการเชื่อมต่ออินเทอร์เน็ต';
  }
  if (/404/.test(raw)) return 'ยังไม่พบไฟล์อัปเดตบนเซิร์ฟเวอร์';
  if (/403|401/.test(raw)) return 'ไม่มีสิทธิ์เข้าถึงเซิร์ฟเวอร์อัปเดต';
  return 'เชื่อมต่อเซิร์ฟเวอร์อัปเดตไม่ได้';
}

autoUpdater.on('download-progress', (p) => {
  setUpdateState('downloading', {
    percent: Math.round(p.percent),
    bytesPerSecond: p.bytesPerSecond,
    transferred: p.transferred,
    total: p.total,
    manual: manualCheck
  });
});

autoUpdater.on('update-downloaded', (info) => {
  setUpdateState('downloaded', { newVersion: info.version, manual: manualCheck });
});

// error ทั้งหมดแสดงผลผ่านแผงในแอปเท่านั้น (ไม่ใช้ dialog ของ Windows ที่บล็อกหน้าจอ)
// รายละเอียดดิบยังถูกบันทึกลง log ไฟล์ไว้เผื่อต้องตรวจสอบภายหลัง
autoUpdater.on('error', (err) => {
  log.error('updater error', err);
  setUpdateState('error', { message: friendlyUpdateError(err), manual: manualCheck });
  manualCheck = false;
});

function checkForUpdates(manual = false) {
  manualCheck = manual;
  if (isDev) {
    log.info('dev mode — ข้ามการตรวจหาอัปเดต');
    if (manual) setUpdateState('dev-skip', { manual: true });
    manualCheck = false;
    return;
  }
  autoUpdater.checkForUpdates().catch((e) => log.error(e));
}

// ---------- IPC ----------
ipcMain.handle('app:getVersion', () => app.getVersion());
ipcMain.handle('updater:getState', () => updateState);
ipcMain.handle('updater:check', () => { checkForUpdates(true); });
ipcMain.handle('updater:download', () => autoUpdater.downloadUpdate());
ipcMain.handle('updater:install', () => {
  setImmediate(() => autoUpdater.quitAndInstall(false, true));
});

// ---------- App lifecycle ----------
app.whenReady().then(() => {
  buildMenu();
  createWindow();

  // ตรวจอัปเดตครั้งแรกหลังเปิดแอป 5 วินาที แล้วทุก 30 นาที
  // (เดิมตรวจทุก 4 ชั่วโมง ทำให้เครื่องที่เปิดแอปค้างไว้ได้อัปเดตช้ากว่าเครื่องอื่นมาก
  //  ลดเหลือ 30 นาที เพื่อให้ทุกเครื่องได้เวอร์ชันใหม่ไล่เลี่ยกันหลังปล่อยอัปเดต)
  setTimeout(() => checkForUpdates(false), 5000);
  setInterval(() => checkForUpdates(false), 30 * 60 * 1000);

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
