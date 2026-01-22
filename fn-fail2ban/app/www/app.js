const $ = (id) => document.getElementById(id);

const I18N = {
  zh: {
    "title.page": "Fail2Ban 管理面板",
    "btn.new": "新建",
    "btn.delete": "删除",
    "btn.edit": "编辑",
    "btn.reload": "重载",
    "btn.refresh": "刷新",
    "modal.editTitle": "编辑 Jail",
    "modal.save": "保存",
    "modal.cancel": "取消",
    "modal.msg": "消息",
    "placeholder.jailContent": "在此编辑 / 粘贴 jail 配置",
    "default.jailContent": "[DEFAULT]\n",
    "msg.multipleJailsDetected": "请保持有且仅有一个 jail 名称！",
    "msg.selectFirst": "请先选择一个 jail",
    "msg.deleteConfirm": "确认删除 jail: {jail} ?",
    "msg.deleteSuccess": "删除成功",
    "msg.deleteFail": "删除失败",
    "msg.saveSuccess": "保存成功",
    "msg.saveFail": "保存失败: {err}",
    "msg.reloadSuccess": "重载成功",
    "msg.reloadFail": "重载失败: {err}",
    "msg.fetchStatusFail": "获取状态失败: {err}",
    "msg.nameExists": "名称已存在: {name}",
    "msg.formMissing": "配置信息无效，请重新编辑。",
    "label.jailName": "jail 名称:",
    "lang.zh": "中文",
    "lang.en": "English",
    "theme.system": "跟随系统",
    "theme.light": "亮模式",
    "theme.dark": "暗模式",
    "aria.langSelect": "语言",
    "aria.themeSelect": "主题",
    "col.name": "名称",
    "col.state": "状态",
    "col.count": "被封 IP 数",
    "col.list": "被封 IP 列表",
    "state.enabled": "已启用",
    "state.disabled": "已禁用",
    "none": "-",
    "btn.close": "关闭"
    , "btn.confirm": "确认"
    , "btn.cancel": "取消"
    , "btn.add": "添加"
    , "btn.clear": "清空"
    , "msg.clearSuccess": "清空完成"
    , "msg.clearFail": "部分解除封禁失败"
    , "placeholder.banInput": "输入 IP 地址 或 CIDR"
    , "btn.export": "导出"
    , "btn.import": "导入"
    , "msg.importSuccess": "导入完成"
    , "msg.importFail": "导入过程中出现错误"
    , "msg.exportFail": "导出失败"
    , "btn.audit": "审计"
    , "modal.auditTitle": "审计日志"
  },
  en: {
    "title.page": "Fail2Ban Manager",
    "btn.new": "New",
    "btn.delete": "Delete",
    "btn.edit": "Edit",
    "btn.reload": "Reload",
    "btn.refresh": "Refresh",
    "modal.editTitle": "Edit Jail",
    "modal.save": "Save",
    "modal.cancel": "Cancel",
    "modal.msg": "Message",
    "placeholder.jailContent": "Edit / paste jail configuration here",
    "default.jailContent": "[DEFAULT]\n",
    "msg.multipleJailsDetected": "Please keep only one jail name!",
    "msg.selectFirst": "Please select a jail first",
    "msg.deleteConfirm": "Delete jail: {jail} ?",
    "msg.deleteSuccess": "Deleted",
    "msg.deleteFail": "Delete failed",
    "msg.saveSuccess": "Saved",
    "msg.saveFail": "Save failed: {err}",
    "msg.reloadSuccess": "Reload succeeded",
    "msg.reloadFail": "Reload failed: {err}",
    "msg.fetchStatusFail": "Failed to fetch status: {err}",
    "msg.nameExists": "Name already exists: {name}",
    "msg.formMissing": "Invalid configuration, please edit again.",
    "label.jailName": "Jail Name:",
    "lang.zh": "中文",
    "lang.en": "English",
    "theme.system": "System",
    "theme.light": "Light",
    "theme.dark": "Dark",
    "aria.langSelect": "Language",
    "aria.themeSelect": "Theme",
    "col.name": "Name",
    "col.state": "State",
    "col.count": "Banned Count",
    "col.list": "Banned List",
    "state.enabled": "Enabled",
    "state.disabled": "Disabled",
    "none": "-",
    "btn.close": "Close"
    , "btn.confirm": "Confirm"
    , "btn.cancel": "Cancel"
    , "btn.add": "Add"
    , "btn.clear": "Clear"
    , "msg.clearSuccess": "Cleared"
    , "msg.clearFail": "Some unban operations failed"
    , "placeholder.banInput": "Enter IP address or CIDR"
    , "btn.export": "Export"
    , "btn.import": "Import"
    , "msg.importSuccess": "Import completed"
    , "msg.importFail": "Import encountered errors"
    , "msg.exportFail": "Export failed"
    , "btn.audit": "Audit"
    , "modal.auditTitle": "Audit Log"
  }
};

let currentLang = (localStorage.getItem("lang") || "").toString();
if (!currentLang) currentLang = (navigator.language || "").toLowerCase().startsWith("zh") ? "zh" : "en";
if (!I18N[currentLang]) currentLang = "zh";

function t(key, vars = {}) {
  const dict = I18N[currentLang] || I18N.zh;
  const v = (dict[key] != null) ? dict[key] : (I18N.zh[key] != null ? I18N.zh[key] : key);
  if (typeof v !== "string") return v;
  return v.replace(/\{([a-zA-Z0-9_]+)\}/g, (_, k) => (vars[k] ?? "").toString());
}

let themeMode = (localStorage.getItem("theme") || "system").toString();
function applyTheme() {
  const prefersDark = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
  const mode = themeMode === "system" ? (prefersDark ? "dark" : "light") : themeMode;
  const v = mode === "dark" ? "dark" : "light";
  document.documentElement.setAttribute("data-theme", v);
  document.body.setAttribute("data-theme", v);
  const sel = $("themeSelect"); if (sel) sel.value = themeMode;
}

function applyI18nStatic() {
  document.querySelectorAll("[data-i18n]").forEach((el) => {
    const key = el.getAttribute("data-i18n");
    if (!key) return;
    const val = t(key);
    if (typeof val === "string") el.textContent = val;
  });
  document.querySelectorAll("[data-i18n-placeholder]").forEach((el) => {
    const key = el.getAttribute("data-i18n-placeholder");
    if (!key) return;
    const val = t(key);
    if (typeof val === "string") el.setAttribute("placeholder", val);
  });
  document.querySelectorAll("[data-i18n-aria-label]").forEach((el) => {
    const key = el.getAttribute("data-i18n-aria-label");
    if (!key) return;
    const val = t(key);
    if (typeof val === "string") el.setAttribute("aria-label", val);
  });
  const langSel = $("langSelect"); if (langSel) langSel.value = currentLang;
  // Update option labels for language and theme selects
  try {
    const optZh = langSel ? langSel.querySelector('option[value="zh"]') : null;
    const optEn = langSel ? langSel.querySelector('option[value="en"]') : null;
    if (optZh) optZh.textContent = t('lang.zh');
    if (optEn) optEn.textContent = t('lang.en');
  } catch (e) { }
  try {
    const themeSel = $("themeSelect");
    if (themeSel) {
      const optSys = themeSel.querySelector('option[value="system"]');
      const optLight = themeSel.querySelector('option[value="light"]');
      const optDark = themeSel.querySelector('option[value="dark"]');
      if (optSys) optSys.textContent = t('theme.system');
      if (optLight) optLight.textContent = t('theme.light');
      if (optDark) optDark.textContent = t('theme.dark');
    }
  } catch (e) { }
}

let currentSelected = null;

// modal stacking counter: when opening a modal we raise its z-index
let _modalStackTop = 10000;

// jail name is entered manually in the `#jail-name` input

function getCgiUrl() {
  let p = window.location.pathname;
  if (!p.endsWith('/')) p = p.replace(/[^/]*$/, '');
  return p + '../www/api.cgi';
}

function postApi(body) {
  return fetch(getCgiUrl(), { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
    .then(res => res.json());
}

function fetchStatus() {
  postApi({ action: 'status' })
    .then(data => {
      renderJails(data.jails || []);
    }).catch((e) => {
      showMsgModal(t('msg.fetchStatusFail', { err: (e && e.message) || '' }));
    });
}

function renderJails(jails) {
  const tbody = document.querySelector('#jail-table tbody');
  tbody.innerHTML = '';
  // clear selection and update toolbar state
  currentSelected = null;
  setToolbarState(false);
  jails.forEach(j => {
    const tr = document.createElement('tr');
    tr.dataset.jail = j.name || '';

    const nameTd = document.createElement('td');
    nameTd.textContent = j.name || '';
    tr.appendChild(nameTd);

    const stateTd = document.createElement('td');
    stateTd.innerHTML = j.enabled ? ('<span class="badge enabled">' + t('state.enabled') + '</span>') : ('<span class="badge disabled">' + t('state.disabled') + '</span>');
    tr.appendChild(stateTd);

    const curTd = document.createElement('td');
    curTd.textContent = (j.curBan != null) ? j.curBan : '0';
    tr.appendChild(curTd);

    const listTd = document.createElement('td');
    // show a button to open the banned-IP modal for this jail
    const btn = document.createElement('button');
    btn.textContent = t('col.list');
    btn.addEventListener('click', (ev) => {
      ev.stopPropagation();
      openBanModal(j.name, j.banIPs);
    });
    listTd.appendChild(btn);
    tr.appendChild(listTd);

    tr.addEventListener('click', () => {
      selectRow(tr);
    });

    tbody.appendChild(tr);
  });
}

function parseBanIPs(raw) {
  if (!raw) return [];
  if (Array.isArray(raw)) return raw.slice();
  return raw.toString().split(/[\s,;]+/).map(s => s.trim()).filter(Boolean);
}

function openBanModal(jailName, banIPsRaw) {
  const modal = document.getElementById('modal-ban');
  const title = document.getElementById('modal-ban-title');
  const listEl = document.getElementById('ban-list');
  const input = document.getElementById('ban-input');
  const addBtn = document.getElementById('ban-add');

  if (!modal || !listEl) return;
  title.textContent = (jailName || '') + ' - ' + t('col.list');
  listEl.innerHTML = '';
  const items = parseBanIPs(banIPsRaw);
  if (items.length) {
    items.forEach(ip => {
      const li = document.createElement('li');
      li.style.display = 'flex'; li.style.justifyContent = 'space-between'; li.style.alignItems = 'center'; li.style.padding = '6px 4px';
      const span = document.createElement('span'); span.textContent = ip; span.style.wordBreak = 'break-all';
      const del = document.createElement('button'); del.textContent = t('btn.delete'); del.style.marginLeft = '8px'; del.addEventListener('click', () => {
        // call unban API
        postApi({ action: 'unban', jail: jailName, ip: ip }).then(res => {
          if (res && res.success) showMsgModal(res.message || 'OK');
          else showMsgModal((res && res.message) || 'Unban failed');
          fetchStatus();
          try { li.remove(); } catch (e) { }
        }).catch(e => { showMsgModal('Unban failed: ' + ((e && e.message) || '')); fetchStatus(); });
      });
      li.appendChild(span); li.appendChild(del);
      listEl.appendChild(li);
    });
  }

  function clickAdd() {
    const val = (input && input.value || '').toString().trim();
    if (!val) return;
    postApi({ action: 'ban', jail: jailName, ip: val }).then(res => {
      if (res && res.success) {
        showMsgModal(res.message || 'OK');
        fetchStatus();
        input.value = '';
        const li = document.createElement('li'); li.style.display = 'flex'; li.style.justifyContent = 'space-between'; li.style.alignItems = 'center'; li.style.padding = '6px 4px';
        const span = document.createElement('span'); span.textContent = val; span.style.wordBreak = 'break-all';
        const del = document.createElement('button'); del.textContent = t('btn.delete'); del.style.marginLeft = '8px'; del.addEventListener('click', () => {
          postApi({ action: 'unban', jail: jailName, ip: val }).then(res2 => { fetchStatus(); try { li.remove(); } catch (e) { } }).catch(() => { });
        });
        li.appendChild(span); li.appendChild(del); listEl.appendChild(li);
      } else {
        showMsgModal((res && res.message) || 'Ban failed');
      }
    }).catch(e => { showMsgModal('Ban failed: ' + ((e && e.message) || '')); });
  }

  if (modal._cleanupBan) { try { modal._cleanupBan(); } catch (e) { } }
  input.value = '';
  addBtn.onclick = clickAdd;
  // export / import controls
  const exportBtn = document.getElementById('ban-export');
  const importBtn = document.getElementById('ban-import');
  const importFile = document.getElementById('ban-import-file');

  function downloadFile(filename, content, mime) {
    try {
      const blob = new Blob([content], { type: mime || 'application/octet-stream' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a'); a.href = url; a.download = filename; document.body.appendChild(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 5000);
    } catch (e) { showMsgModal(t('msg.exportFail') + ': ' + ((e && e.message) || '')); }
  }

  if (exportBtn) {
    exportBtn.onclick = () => {
      try {
        const items = Array.from(listEl.querySelectorAll('li > span')).map(s => (s.textContent || '').toString());
        const filename = 'banned-' + (jailName || 'list') + '.json';
        downloadFile(filename, JSON.stringify(items, null, 2), 'application/json');
      } catch (e) { showMsgModal(t('msg.exportFail') + ': ' + ((e && e.message) || '')); }
    };
  }

  if (importBtn && importFile) {
    importBtn.onclick = () => { importFile.click(); };
    importFile.onchange = (ev) => {
      const f = (ev.target && ev.target.files && ev.target.files[0]) ? ev.target.files[0] : null;
      if (!f) return;
      const reader = new FileReader();
      reader.onload = function (evt) {
        try {
          const text = (evt.target.result || '').toString();
          let ips = [];
          const name = (f.name || '').toLowerCase();
          if (name.endsWith('.json')) {
            const parsed = JSON.parse(text);
            if (Array.isArray(parsed)) ips = parsed.map(s => (s || '').toString());
            else if (typeof parsed === 'object') ips = Object.values(parsed).map(s => (s || '').toString());
          } else {
            ips = text.split(/\r?\n|[,;]+/).map(s => s.trim()).filter(Boolean);
          }
          ips = ips.map(s => s.trim()).filter(Boolean);
          const uniq = Array.from(new Set(ips));
          if (!uniq.length) { showMsgModal(t('msg.importFail')); importFile.value = ''; return; }
          const origButtons = { exp: exportBtn ? exportBtn.disabled : false, imp: importBtn ? importBtn.disabled : false, add: addBtn.disabled };
          if (exportBtn) exportBtn.disabled = true; if (importBtn) importBtn.disabled = true; addBtn.disabled = true;
          // use bulkban endpoint to reduce number of requests
          postApi({ action: 'bulkban', jail: jailName, ips: uniq }).then(res => {
            if (!res) { showMsgModal(t('msg.importFail')); return; }
            if (res.success) {
              showMsgModal(t('msg.importSuccess'));
            } else {
              const failedCount = (res.failed && res.failed.length) ? res.failed.length : 0;
              showMsgModal(t('msg.importFail') + (failedCount ? (' (' + failedCount + ')') : ''));
            }
            // append successful ones to list: determine failed IPs
            const failedIps = (res.failed || []).map(f => f.ip).filter(Boolean);
            const succeeded = uniq.filter(ip => failedIps.indexOf(ip) === -1);
            succeeded.forEach(ip => {
              const li = document.createElement('li'); li.style.display = 'flex'; li.style.justifyContent = 'space-between'; li.style.alignItems = 'center'; li.style.padding = '6px 4px';
              const span = document.createElement('span'); span.textContent = ip; span.style.wordBreak = 'break-all';
              const del = document.createElement('button'); del.textContent = t('btn.delete'); del.style.marginLeft = '8px'; del.addEventListener('click', () => {
                postApi({ action: 'unban', jail: jailName, ip: ip }).then(r2 => { fetchStatus(); try { li.remove(); } catch (e) { } }).catch(() => { });
              });
              li.appendChild(span); li.appendChild(del); listEl.appendChild(li);
            });
            fetchStatus();
          }).catch(e => { showMsgModal(t('msg.importFail') + ': ' + ((e && e.message) || '')); }).finally(() => {
            if (exportBtn) exportBtn.disabled = origButtons.exp; if (importBtn) importBtn.disabled = origButtons.imp; addBtn.disabled = origButtons.add;
            importFile.value = '';
          });
        } catch (e) {
          showMsgModal(t('msg.importFail') + ': ' + ((e && e.message) || ''));
          importFile.value = '';
        }
      };
      reader.readAsText(f);
    };
  }

  modal._cleanupBan = function () {
    addBtn.onclick = null;
    try { if (exportBtn) exportBtn.onclick = null; } catch (e) { }
    try { if (importBtn) importBtn.onclick = null; } catch (e) { }
    try { if (importFile) importFile.onchange = null; } catch (e) { }
  };

  // clear button (unban all)
  const clearBtn = document.getElementById('ban-clear');
  if (clearBtn) {
    clearBtn.onclick = () => {
      showConfirm(t('btn.clear') + ' ? ', () => {
        clearBtn.disabled = true; addBtn.disabled = true;
        postApi({ action: 'clear', jail: jailName }).then(res => {
          if (res && res.success) showMsgModal(res.message || t('msg.clearSuccess'));
          else showMsgModal((res && res.message) || t('msg.clearFail'));
          fetchStatus();
          // refresh modal content in-place (avoid re-opening the modal which
          // would push the ban modal above the message dialog)
          try { listEl.innerHTML = ''; } catch (e) { }
        }).catch(e => { showMsgModal(t('msg.clearFail') + ': ' + ((e && e.message) || '')); }).finally(() => { clearBtn.disabled = false; addBtn.disabled = false; });
      }, () => { });
    };
  }

  const closeBtn = document.getElementById('modal-ban-close'); if (closeBtn) closeBtn.onclick = () => closeModal(modal);

  openModal(modal);
}

// Audit modal: fetch and render audit log entries
function openAuditModal() {
  const modal = document.getElementById('modal-audit');
  const listEl = document.getElementById('audit-list');
  const filterEl = document.getElementById('audit-filter');
  const refreshBtn = document.getElementById('audit-refresh');
  const exportBtn = document.getElementById('audit-export');
  const clearBtn = document.getElementById('audit-clear');

  if (!modal || !listEl) return;
  listEl.innerHTML = '';

  function renderEntries(entries) {
    listEl.innerHTML = '';
    if (!entries || !entries.length) {
      const li = document.createElement('li'); li.textContent = t('none'); li.style.padding = '8px'; listEl.appendChild(li); return;
    }
    entries.forEach(e => {
      const li = document.createElement('li'); li.style.padding = '8px'; li.style.borderBottom = '1px solid var(--surface2)';
      const time = document.createElement('div'); time.style.fontSize = '12px'; time.style.color = 'var(--muted)'; time.textContent = (e.ts || '') + ' — ' + (e.action || '');
      const body = document.createElement('div'); body.style.wordBreak = 'break-all'; body.textContent = (e.jail ? ('jail=' + e.jail + ' ') : '') + (e.ip ? ('ip=' + e.ip + ' ') : '') + (e.note ? e.note : '');
      li.appendChild(time); li.appendChild(body); listEl.appendChild(li);
    });
  }

  function fetchAndRender() {
    const q = (filterEl && filterEl.value) ? filterEl.value.trim() : '';
    postApi({ action: 'audit', filter: q, limit: 200 }).then(res => {
      if (res && res.success && Array.isArray(res.entries)) renderEntries(res.entries);
      else showMsgModal(res && res.message ? res.message : t('msg.fetchStatusFail', { err: '' }));
    }).catch(e => showMsgModal(t('msg.fetchStatusFail', { err: (e && e.message) || '' })));
  }

  if (refreshBtn) { refreshBtn.onclick = fetchAndRender; }
  if (filterEl) { filterEl.onkeypress = (e) => { if (e.key === 'Enter') fetchAndRender(); }; }

  if (exportBtn) {
    exportBtn.onclick = () => {
      postApi({ action: 'audit', filter: (filterEl && filterEl.value) ? filterEl.value.trim() : '', limit: 10000 }).then(res => {
        if (res && res.success && Array.isArray(res.entries)) {
          const content = JSON.stringify(res.entries, null, 2);
          const filename = 'audit-' + (new Date()).toISOString().replace(/[:\.]/g, '-') + '.json';
          try { const blob = new Blob([content], { type: 'application/json' }); const url = URL.createObjectURL(blob); const a = document.createElement('a'); a.href = url; a.download = filename; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 5000); } catch (e) { showMsgModal(t('msg.exportFail') + ': ' + ((e && e.message) || '')); }
        } else showMsgModal(t('msg.exportFail'));
      }).catch(e => showMsgModal(t('msg.exportFail') + ': ' + ((e && e.message) || '')));
    };
  }

  if (clearBtn) {
    clearBtn.onclick = () => {
      showConfirm(t('btn.clear') + ' ? ', () => {
        postApi({ action: 'audit_clear' }).then(res => {
          if (res && res.success) { showMsgModal(res.message || t('msg.clearSuccess')); listEl.innerHTML = ''; }
          else showMsgModal(res && res.message ? res.message : t('msg.clearFail'));
        }).catch(e => showMsgModal(t('msg.clearFail') + ': ' + ((e && e.message) || '')));
      }, () => { });
    };
  }

  const closeBtn = document.getElementById('modal-audit-close'); if (closeBtn) closeBtn.onclick = () => closeModal(modal);

  openModal(modal);
  fetchAndRender();
}

function setToolbarState(hasSelection) {
  const btnEdit = $('btn-edit');
  const btnDelete = $('btn-delete');
  const btnNew = $('btn-new');
  const btnReload = $('btn-reload');
  const btnRefresh = $('btn-refresh');
  if (btnEdit) btnEdit.disabled = !hasSelection;
  if (btnDelete) btnDelete.disabled = !hasSelection;
  if (btnNew) btnNew.disabled = false;
  if (btnReload) btnReload.disabled = false;
  if (btnRefresh) btnRefresh.disabled = false;
}

function setModalState(isOpen) {
  // disable toolbar while modal or confirm is open
  const controls = ['btn-new', 'btn-edit', 'btn-delete', 'btn-reload', 'btn-refresh'];
  controls.forEach(id => {
    const el = $(id);
    if (!el) return;
    el.disabled = !!isOpen;
  });
}

function openModal(modalEl) {
  if (!modalEl) return;
  // ensure this modal is above previous ones
  try {
    _modalStackTop += 1;
    modalEl.style.zIndex = String(_modalStackTop);
    const panel = modalEl.querySelector('.panel');
    if (panel) panel.style.zIndex = String(_modalStackTop + 1);
  } catch (e) { }
  modalEl.classList.add('show');
  modalEl.style.display = 'flex';
  document.body.classList.add('no-scroll');
  setModalState(true);
  modalEl._prevActive = document.activeElement;
  const focusable = modalEl.querySelectorAll('a[href], button, textarea, input, select, [tabindex]:not([tabindex="-1"])');
  modalEl._focusable = Array.from(focusable).filter(el => !el.hasAttribute('disabled'));
  if (modalEl._focusable && modalEl._focusable.length) modalEl._focusable[0].focus();

  modalEl._keyHandler = function (e) {
    if (e.key === 'Escape') { closeModal(modalEl); }
    if (e.key === 'Tab') {
      const f = modalEl._focusable || [];
      if (!f.length) return;
      const idx = f.indexOf(document.activeElement);
      if (e.shiftKey) {
        if (idx === 0) { e.preventDefault(); f[f.length - 1].focus(); }
      } else {
        if (idx === f.length - 1) { e.preventDefault(); f[0].focus(); }
      }
    }
  };
  document.addEventListener('keydown', modalEl._keyHandler);

  modalEl._backdropHandler = function (ev) {
    if (ev.target === modalEl) closeModal(modalEl);
  };
  modalEl.addEventListener('click', modalEl._backdropHandler);
}

function closeModal(modalEl) {
  if (!modalEl) return;
  modalEl.classList.remove('show');
  modalEl.style.display = 'none';
  document.body.classList.remove('no-scroll');
  setModalState(false);
  if (modalEl._keyHandler) { document.removeEventListener('keydown', modalEl._keyHandler); delete modalEl._keyHandler; }
  if (modalEl._backdropHandler) { modalEl.removeEventListener('click', modalEl._backdropHandler); delete modalEl._backdropHandler; }
  try { if (modalEl._prevActive && typeof modalEl._prevActive.focus === 'function') modalEl._prevActive.focus(); } catch (e) { }
  delete modalEl._prevActive;
  delete modalEl._focusable;
}

function selectRow(tr) {
  const prev = document.querySelector('#jail-table tr.selected');
  if (prev) prev.classList.remove('selected');
  tr.classList.add('selected');
  currentSelected = tr.dataset.jail;
  setToolbarState(true);
}

function showMsgModal(msg) {
  const m = document.getElementById('modal-msg');
  document.getElementById('msg-body').textContent = typeof msg === 'string' ? msg : JSON.stringify(msg, null, 2);
  // ensure confirm controls are hidden for simple messages
  const btnConfirm = document.getElementById('msg-confirm');
  const btnCancel = document.getElementById('msg-cancel');
  const btnClose = document.getElementById('msg-close');
  if (btnConfirm) { btnConfirm.style.display = 'none'; btnConfirm.onclick = null; }
  if (btnCancel) { btnCancel.style.display = 'none'; btnCancel.onclick = null; }
  if (btnClose) btnClose.style.display = 'inline-block';
  openModal(m);
}

function hideMsgModal() {
  const m = document.getElementById('modal-msg');
  // cleanup button handlers and reset visibility
  const btnConfirm = document.getElementById('msg-confirm');
  const btnCancel = document.getElementById('msg-cancel');
  const btnClose = document.getElementById('msg-close');
  if (btnConfirm) { btnConfirm.onclick = null; btnConfirm.style.display = 'none'; }
  if (btnCancel) { btnCancel.onclick = null; btnCancel.style.display = 'none'; }
  if (btnClose) btnClose.style.display = 'inline-block';
  closeModal(m);
}

function showConfirm(message, onYes, onNo) {
  const m = document.getElementById('modal-msg');
  const body = document.getElementById('msg-body');
  const btnConfirm = document.getElementById('msg-confirm');
  const btnCancel = document.getElementById('msg-cancel');
  const btnClose = document.getElementById('msg-close');
  body.textContent = typeof message === 'string' ? message : JSON.stringify(message, null, 2);
  if (btnClose) btnClose.style.display = 'none';
  if (btnConfirm) {
    btnConfirm.style.display = 'inline-block';
    btnConfirm.textContent = t('btn.confirm');
    btnConfirm.onclick = () => { closeModal(m); if (typeof onYes === 'function') onYes(); };
  }
  if (btnCancel) {
    btnCancel.style.display = 'inline-block';
    btnCancel.textContent = t('modal.cancel') || t('btn.cancel');
    btnCancel.onclick = () => { closeModal(m); if (typeof onNo === 'function') onNo(); };
  }
  openModal(m);
}

function showEditModal(title, name, content) {
  document.getElementById('modal-title').textContent = title || t('modal.editTitle');
  const nameEl = document.getElementById('jail-name');
  const contentEl = document.getElementById('jail-content');
  if (nameEl) {
    nameEl.value = name || '';
    // when editing an existing jail, name must not be editable
    if (name && name.toString().trim() !== '') {
      nameEl.readOnly = true;
      nameEl.classList.add('readonly');
    } else {
      nameEl.readOnly = false;
      nameEl.classList.remove('readonly');
    }
  }
  if (contentEl) {
    contentEl.value = content || '';
  }
  const modalEl = document.getElementById('modal-edit');
  const saveBtn = document.getElementById('modal-save');
  const errorEl = document.getElementById('modal-error');

  function validateModalFormHandler() {
    const nm = (nameEl && nameEl.value || '').toString().trim();
    const body = (contentEl && contentEl.value || '').toString().trim();
    const exists = Array.from(document.querySelectorAll('#jail-table tbody tr')).some(r => (r.dataset.jail || '') === nm);
    let ok = true;
    let errKey = '';
    let errVars = {};
    if (!nm) { ok = false; errKey = 'msg.formMissing'; }
    else if (!body) { ok = false; errKey = 'msg.formMissing'; }
    else if (exists && nm !== currentSelected) { ok = false; errKey = 'msg.nameExists'; errVars = { name: nm }; }

    if (saveBtn) saveBtn.disabled = !ok;
    if (errorEl) errorEl.textContent = errKey ? t(errKey, errVars) : '';
  }

  // cleanup any previous handlers
  if (modalEl && typeof modalEl._cleanup === 'function') {
    try { modalEl._cleanup(); } catch (e) { }
    delete modalEl._cleanup;
  }

  // attach handlers and provide cleanup
  if (nameEl) { nameEl._validateHandler = validateModalFormHandler; nameEl.addEventListener('input', nameEl._validateHandler); }
  if (contentEl) { contentEl._validateHandler = validateModalFormHandler; contentEl.addEventListener('input', contentEl._validateHandler); }

  if (modalEl) {
    modalEl._cleanup = function () {
      try { if (nameEl && nameEl._validateHandler) { nameEl.removeEventListener('input', nameEl._validateHandler); delete nameEl._validateHandler; } } catch (e) { }
      try { if (contentEl && contentEl._validateHandler) { contentEl.removeEventListener('input', contentEl._validateHandler); delete contentEl._validateHandler; } } catch (e) { }
      try { if (errorEl) errorEl.textContent = ''; } catch (e) { }
      try { if (saveBtn) saveBtn.disabled = false; } catch (e) { }
    };
  }

  // initial validate and open modal
  validateModalFormHandler();
  openModal(modalEl);
}

function hideEditModal() {
  const modalEl = document.getElementById('modal-edit');
  if (modalEl && typeof modalEl._cleanup === 'function') {
    try { modalEl._cleanup(); } catch (e) { }
    delete modalEl._cleanup;
  }
  closeModal(modalEl);
}

function readSelectedJail() {
  if (!currentSelected) { showMsgModal(t('msg.selectFirst')); return Promise.reject('no selection'); }
  return postApi({ action: 'read', jail: currentSelected });
}

function deleteSelectedJail() {
  if (!currentSelected) { showMsgModal(t('msg.selectFirst')); return; }
  showConfirm(t('msg.deleteConfirm', { jail: currentSelected }), () => {
    postApi({ action: 'delete', jail: currentSelected }).then(res => {
      if (res && res.success) {
        showMsgModal(t('msg.deleteSuccess'));
        fetchStatus();
      } else {
        showMsgModal(res && res.message ? res.message : t('msg.deleteFail'));
      }
    }).catch(e => showMsgModal(t('msg.deleteFail') + ': ' + ((e && e.message) || '')));
  }, () => { });
}

function saveJail() {
  const nameEl = $('jail-name');
  const contentEl = $('jail-content');
  if (!nameEl || !contentEl) { showMsgModal(t('msg.formMissing')); return; }
  const name = (nameEl.value || '').trim();
  const content = contentEl.value || '';
  if (!name) { showMsgModal(t('msg.selectFirst')); return; }
  // prevent creating a new jail with a name that already exists
  // treat as conflict if another row exists with same name and it's not the currently edited one
  const exists = Array.from(document.querySelectorAll('#jail-table tbody tr')).some(r => (r.dataset.jail || '') === name);
  if (exists && name !== currentSelected) {
    showMsgModal(t('msg.nameExists', { name: name }));
    return;
  }
  postApi({ action: 'write', jail: name, content: content }).then(res => {
    if (res && res.success) {
      hideEditModal();
      showMsgModal(res.message || t('msg.saveSuccess'));
      fetchStatus();
    } else {
      showMsgModal((res && res.message) || t('msg.saveFail', { err: JSON.stringify(res) }));
    }
  }).catch(e => showMsgModal(t('msg.saveFail', { err: (e && e.message) || '' })));
}

function reloadFail2ban() {
  postApi({ action: 'reload' }).then(res => {
    if (res && res.success) showMsgModal(t('msg.reloadSuccess'));
    else showMsgModal(t('msg.reloadFail', { err: JSON.stringify(res) }));
    fetchStatus();
  }).catch(e => showMsgModal(t('msg.reloadFail', { err: (e && e.message) || '' })));
}

document.addEventListener('DOMContentLoaded', () => {
  // initial fetch
  fetchStatus();

  // bind buttons
  const btnRefresh = $('btn-refresh'); if (btnRefresh) btnRefresh.addEventListener('click', fetchStatus);
  const btnNew = $('btn-new'); if (btnNew) btnNew.addEventListener('click', () => showEditModal(t('modal.editTitle'), '', '', t('default.jailContent')));
  const btnEdit = $('btn-edit'); if (btnEdit) btnEdit.addEventListener('click', () => {
    readSelectedJail().then(res => {
      if (res && res.success) {
        showEditModal(t('modal.editTitle'), currentSelected, res.content || '');
      } else {
        showMsgModal(res && res.message ? res.message : t('msg.fetchStatusFail', { err: '' }));
      }
    }).catch(() => { });
  });
  const btnDelete = $('btn-delete'); if (btnDelete) btnDelete.addEventListener('click', deleteSelectedJail);
  const btnReload = $('btn-reload'); if (btnReload) btnReload.addEventListener('click', reloadFail2ban);
  const btnAudit = $('btn-audit'); if (btnAudit) btnAudit.addEventListener('click', () => openAuditModal());

  const modalCancel = $('modal-cancel'); if (modalCancel) modalCancel.addEventListener('click', hideEditModal);
  const modalSave = $('modal-save'); if (modalSave) modalSave.addEventListener('click', saveJail);
  const msgClose = $('msg-close'); if (msgClose) msgClose.addEventListener('click', hideMsgModal);

  applyI18nStatic();
  applyTheme();

  const langSel = $('langSelect'); if (langSel) {
    langSel.addEventListener('change', (e) => { currentLang = e.target.value; localStorage.setItem('lang', currentLang); applyI18nStatic(); });
  }
  const themeSel = $('themeSelect'); if (themeSel) {
    themeSel.addEventListener('change', (e) => { themeMode = e.target.value; localStorage.setItem('theme', themeMode); applyTheme(); });
  }

  // textarea -> detect [Jail] names in content and auto-fill jail-name (unless user edited it)
  const contentEl = $('jail-content');
  const nameEl = $('jail-name');
  // no auto-detection: jail-name is provided manually by user
  // keep a simple presence check for inputs
  if (contentEl) { /* noop */ }
  if (nameEl) { /* noop */ }
});

