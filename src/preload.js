'use strict';

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('cp9x', {
  isDesktop: true,
  platform: process.platform,
  getVersion: () => ipcRenderer.invoke('app:getVersion'),
  // v1.1.2 — กล่องยืนยัน/แจ้งเตือนจากตัวโปรแกรมหลัก (ดูเหตุผลที่ main.js) — ต้องเป็นแบบรอคำตอบ เหมือน confirm() เดิม
  confirmSync: (message) => ipcRenderer.sendSync('dialog:confirm', String(message == null ? '' : message)),
  alertSync: (message) => ipcRenderer.sendSync('dialog:alert', String(message == null ? '' : message)),
  updater: {
    getState: () => ipcRenderer.invoke('updater:getState'),
    check: () => ipcRenderer.invoke('updater:check'),
    download: () => ipcRenderer.invoke('updater:download'),
    install: () => ipcRenderer.invoke('updater:install'),
    onState: (cb) => {
      const handler = (_e, state) => cb(state);
      ipcRenderer.on('updater:state', handler);
      return () => ipcRenderer.removeListener('updater:state', handler);
    }
  }
});
