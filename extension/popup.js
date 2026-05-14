const BASE_URL = 'https://cie.fraft.cn';
const SEASON_API = {m:'Mar',s:'Jun',w:'Nov'};
const SEASON_MAP = {m:'春季',s:'夏季',w:'冬季'};

class TokenBucket {
  constructor(rate) { this.rate = rate; this.tokens = rate; this.last = performance.now(); }
  acquire(tokens) {
    const now = performance.now();
    const elapsed = (now - this.last) / 1000;
    this.tokens = Math.min(this.rate, this.tokens + elapsed * this.rate);
    this.last = now;
    if (this.tokens >= tokens) { this.tokens -= tokens; return true; }
    return false;
  }
  async wait(tokens) {
    while (!this.acquire(tokens)) { await new Promise(r => setTimeout(r, 100)); }
  }
  drain() { this.tokens = 0; }
  updateRate(rate) { this.rate = rate; this.tokens = Math.min(this.tokens, rate); }
}

const S = {
  subjects: [], groups: [], selected: {}, bGroups: [], bSelected: null,
  mode: 'search', theme: 'light', favorites: [], dlHistory: new Set(),
  includeMS: true, rate: 5, concurrency: 3,
  bucket: new TokenBucket(5),
};

function $(id) { return document.getElementById(id); }
function esc(s) { return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;'); }

function toast(msg, type='info') {
  const el = document.createElement('div');
  el.className = 'toast '+type;
  el.textContent = msg;
  const container = $('toasts');
  container.appendChild(el);
  setTimeout(() => { el.style.opacity='0'; el.style.transform='translateX(100%)'; el.style.transition='all .25s'; setTimeout(() => el.remove(), 300); }, 2800);
}

// ── Storage ──
async function loadAll() {
  const data = await chrome.storage.local.get(['favorites','dlHistory','settings']);
  S.favorites = data.favorites || [];
  S.dlHistory = new Set(data.dlHistory || []);
  const s = data.settings || {};
  S.theme = s.theme || 'light';
  S.includeMS = s.includeMS !== false;
  S.rate = s.rate || 5;
  S.concurrency = s.concurrency || 3;
  S.bucket.updateRate(S.rate);
  document.documentElement.setAttribute('data-theme', S.theme);
  updateThemeBtn();
  $('dl-ms').checked = S.includeMS;
  $('b-rate').value = S.rate; $('rv').textContent = S.rate+'/s';
  $('b-thr').value = S.concurrency; $('tv').textContent = S.concurrency;
}

async function saveFavorites() { await chrome.storage.local.set({favorites:S.favorites}); refreshFavUI(); }
async function saveDlHistory() { await chrome.storage.local.set({dlHistory:[...S.dlHistory]}); }
async function saveSettings() {
  await chrome.storage.local.set({settings:{theme:S.theme,includeMS:S.includeMS,rate:S.rate,concurrency:S.concurrency}});
}

// ── API ──
async function fetchSubjects() {
  const res = await fetch(BASE_URL+'/obj/Common/Subject/combo', {
    method:'POST', headers:{'Content-Type':'application/x-www-form-urlencoded'}, body:''
  });
  if (!res.ok) throw new Error(`API 请求失败: ${res.status} ${res.statusText}`);
  const data = await res.json();
  const list = Array.isArray(data) ? data : (data && data.data ? data.data : []);
  if (list.length > 0) {
    S.subjects = list.map(s => ({code:String(s.value||s.code||s.subject_code), name:s.text||s.name||s.subject_name}));
    populateSubjectSelects();
  }
}

function populateSubjectSelects() {
  const opts = S.subjects.map(s => `<option value="${esc(s.code)}">${esc(s.code)} ${esc(s.name)}</option>`).join('');
  $('s-subj').innerHTML = opts;
  $('b-subj').innerHTML = opts;
  restoreLastSubject();
}

function restoreLastSubject() {
  const last = S.favorites.length > 0 ? S.favorites[0].code : null;
  if (last) {
    if ($('s-subj').querySelector(`option[value="${last}"]`)) $('s-subj').value = last;
    if ($('b-subj').querySelector(`option[value="${last}"]`)) $('b-subj').value = last;
  }
}

function getSubjectName(code) {
  const s = S.subjects.find(s => s.code === code);
  return s ? s.name : code;
}

async function searchPapers(subject, year, season) {
  const apiSeason = season ? (SEASON_API[season] || season) : '';
  const params = new URLSearchParams();
  params.set('subject', subject);
  params.set('year', String(year));
  params.set('season', apiSeason);
  const res = await fetch(BASE_URL+'/obj/Common/Fetch/renum', {
    method:'POST',
    headers:{'Content-Type':'application/x-www-form-urlencoded'},
    body:params.toString()
  });
  if (!res.ok) throw new Error(`API 请求失败: ${res.status} ${res.statusText}`);
  const data = await res.json();
  const rows = data && data.rows ? data.rows : [];
  const files = rows.map(r => r.file || r.filename || r);
  return files.map(f => parseFilename(f)).filter(f => f !== null);
}

function parseFilename(filename) {
  const m = filename.match(/^(\d+)_([mws]\d{2})_(qp|ms|ci|gt|er|ir|in|sr)(?:_(\d+))?\.pdf$/i);
  if (!m) return null;
  return { filename, subject:m[1], season:m[2], type:m[3].toLowerCase(), paper:m[4]||'', raw:filename };
}

function paperGroupOf(number) {
  if (!number) return 0;
  const n = parseInt(number);
  return isNaN(n) ? 0 : (n >= 10 ? Math.floor(n / 10) : n);
}

function groupPapers(papers) {
  const map = {};
  for (const p of papers) {
    const key = p.subject+'_'+p.season+'_'+p.paper;
    if (!map[key]) map[key] = {subject:p.subject,season:p.season,paper:p.paper,paperGroup:paperGroupOf(p.paper),qp:null,ms:null};
    if (p.type === 'qp') map[key].qp = p;
    else if (p.type === 'ms') map[key].ms = p;
  }
  return Object.values(map).filter(g => g.qp);
}

async function batchPreview(subject, yFrom, yTo, seasons, papers, includeMS) {
  const results = [];
  const yearRange = [];
  for (let y = yFrom; y <= yTo; y++) yearRange.push(y);
  
  const tasks = [];
  for (const year of yearRange) {
    for (const season of seasons) {
      tasks.push(async () => {
        await S.bucket.wait(1);
        try {
          const files = await searchPapers(subject, year, season);
          for (const g of groupPapers(files)) {
            if (papers.length === 0 || papers.includes(String(g.paperGroup))) {
              results.push(includeMS ? g : {...g, ms: null});
            }
          }
        } catch(e) {
          console.warn(`获取 ${year} ${season} 数据失败:`, e);
        }
      });
    }
  }
  await Promise.all(tasks.map(t => t()));

  results.sort((a,b) => {
    if (a.season !== b.season) return a.season.localeCompare(b.season);
    if (a.paper !== b.paper) return (a.paper||'0').localeCompare(b.paper||'0');
    return 0;
  });
  return { groups:results, total:results.length };
}

// ── Search Tab ──
async function doSearch() {
  const subj = $('s-subj').value;
  const year = $('s-year').value;
  const seas = $('s-seas').value;
  if (!subj) { toast('请选择科目','warn'); return; }
  $('rcnt').innerHTML = '<span class="spin"></span> 搜索中...';
  $('rlist').innerHTML = '';
  try {
    const seasons = seas ? [seas] : ['m','s','w'];
    let allFiles = [];
    for (let i = 0; i < seasons.length; i++) {
      if (i > 0) await S.bucket.wait(1);
      try {
        const files = await searchPapers(subj, year, seasons[i]);
        allFiles = allFiles.concat(files);
      } catch(e) {
        toast(`获取 ${seasons[i]} 数据失败: ${e.message}`, 'warn');
      }
    }
    S.groups = groupPapers(allFiles);
    S.groups.sort((a,b) => {
      if (a.season !== b.season) return a.season.localeCompare(b.season);
      return (a.paper||'0').localeCompare(b.paper||'0');
    });
    S.selected = {};
    renderResults();
    $('rcnt').textContent = `${S.groups.length} 组`;
  } catch(e) {
    $('rcnt').textContent = '搜索失败';
    $('rlist').innerHTML = `<div class="empty"><div>搜索出错: ${esc(e.message)}</div></div>`;
    toast('搜索失败: '+e.message,'err');
  }
}

function renderResults() {
  if (S.groups.length === 0) {
    $('rlist').innerHTML = '<div class="empty"><div>没有找到试卷</div></div>';
    return;
  }
  let html = '';
  let lastSeason = '';
  for (const g of S.groups) {
    if (g.season !== lastSeason) {
      lastSeason = g.season;
      html += `<div class="rgrp-hdr">${g.season} ${SEASON_MAP[g.season[0]]||g.season}</div>`;
    }
    const key = g.subject+'_'+g.season+'_'+g.paper;
    const sel = !!S.selected[key];
    const qpFn = g.qp ? g.qp.filename : '';
    const msFn = g.ms ? g.ms.filename : '';
    const qpDled = S.dlHistory.has(qpFn);
    const msDled = S.dlHistory.has(msFn);
    html += `<div class="res-row" style="animation-delay:${Math.random()*0.15}s">
      <div class="res-check">
        <div class="cb${sel?' on':''}" data-key="${esc(key)}"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg></div>
      </div>
      <div class="res-fname${g.qp?' exist':' miss'}${qpDled?' dled':''}" data-preview="${esc(qpFn)}">${g.qp?esc(qpFn):'——'}</div>
      <div class="res-fname${g.ms?' exist':' miss'}${msDled?' dled':''}" data-preview="${esc(msFn)}">${g.ms?esc(msFn):'——'}</div>
      <div class="res-status"><span style="font-size:8px;color:var(--accent);font-weight:700;font-family:var(--serif)">P${esc(g.paper||'?')}</span></div>
    </div>`;
  }
  $('rlist').innerHTML = html;
}

function onResultsClick(e) {
  const cb = e.target.closest('.cb[data-key]');
  if (cb) { toggleSel(cb.dataset.key, e); return; }
  const fname = e.target.closest('.res-fname[data-preview]');
  if (fname && fname.dataset.preview) { preview(fname.dataset.preview); }
}

function toggleSel(key, e) {
  e.stopPropagation();
  if (S.selected[key]) delete S.selected[key]; else S.selected[key] = true;
  renderResults();
  updateDock();
}

function selAll() { S.groups.forEach(g => S.selected[g.subject+'_'+g.season+'_'+g.paper]=true); renderResults(); updateDock(); }
function deselAll() { S.selected = {}; renderResults(); updateDock(); }
function selQP() { S.selected = {}; S.groups.forEach(g => { if(g.qp) S.selected[g.subject+'_'+g.season+'_'+g.paper]=true; }); renderResults(); updateDock(); }
function selMS() { S.selected = {}; S.groups.forEach(g => { if(g.ms) S.selected[g.subject+'_'+g.season+'_'+g.paper]=true; }); renderResults(); updateDock(); }

async function preview(fn) {
  if (!fn) return;
  const url = BASE_URL+'/obj/Common/Fetch/redir/'+fn;
  await chrome.tabs.create({url});
}

// ── Batch Tab ──
function quickYears(n) {
  const cy = new Date().getFullYear();
  const latestExamYear = new Date().getMonth() >= 5 ? cy + 1 : cy;
  $('b-yfrom').value = n >= 99 ? 2001 : latestExamYear - n + 1;
  $('b-yto').value = latestExamYear;
}

async function doPreview() {
  const subj = $('b-subj').value;
  if (!subj) { toast('请选择科目','warn'); return; }
  const yFrom = parseInt($('b-yfrom').value);
  const yTo = parseInt($('b-yto').value);
  if (yFrom > yTo) { toast('起始年份不能大于结束年份','warn'); return; }
  const seasons = getChecked('cbg-seasons');
  if (seasons.length === 0) { toast('请至少选择一个季节','warn'); return; }
  const papers = getChecked('cbg-papers');
  $('pvbtn').disabled = true;
  $('pvbtn').textContent = '加载中...';
  $('prev').innerHTML = '<span class="spin"></span> 正在搜索试卷...';
  try {
    const r = await batchPreview(subj, yFrom, yTo, seasons, papers, $('dl-ms-batch').checked);
    S.bGroups = r.groups;
    S.bSelected = {};
    r.groups.forEach(g => S.bSelected[g.subject+'_'+g.season+'_'+g.paper]=true);
    let prev = '';
    let lastS = '';
    for (const g of r.groups) {
      if (g.season !== lastS) { lastS = g.season; prev += `<div class="prev-season">${esc(g.season)} ${SEASON_MAP[g.season[0]]||esc(g.season)}</div>`; }
      const paperLabel = g.paper ? `P${esc(g.paper)}` : '';
      prev += `<div class="prev-row"><span class="prev-paper">${paperLabel}</span>`;
      prev += `<span class="prev-file${g.qp?'':' miss'}">${g.qp?esc(g.qp.filename):'无QP'}</span>`;
      if (g.ms) prev += ` <span class="prev-plus">+</span> <span class="prev-file ms">${esc(g.ms.filename)}</span>`;
      prev += `</div>`;
    }
    $('prev').innerHTML = `<div class="prev-header">共找到 ${r.total} 组试卷 (${esc(subj)}, ${$('dl-ms-batch').checked?'含':'不含'}MS)</div>${prev}`;
    updateDock();
  } catch(e) {
    $('prev').textContent = '预览失败: '+e.message;
    toast('预览失败','err');
  } finally {
    $('pvbtn').disabled = false;
    $('pvbtn').textContent = '预览';
  }
}

function getChecked(containerId) {
  const vals = [];
  $(containerId).querySelectorAll('input[type=checkbox]:checked').forEach(cb => vals.push(cb.value));
  return vals;
}
function syncCB(el) {
  const parent = el.closest('.cbitem');
  if (parent) { parent.classList.toggle('on', el.checked); }
}
function syncMS(el) {
  S.includeMS = el.checked;
  if (el.id === 'dl-ms-batch') {
    $('dl-ms').checked = el.checked;
  } else if (el.id === 'dl-ms') {
    $('dl-ms-batch').checked = el.checked;
  }
  saveSettings();
}

// ── Download ──
function updateDock() {
  if (S.mode === 'batch') {
    const cnt = S.bSelected ? Object.keys(S.bSelected).length : 0;
    $('dlbtn').textContent = cnt ? `下载选中(${cnt})` : '下载选中';
    $('dlbtn').disabled = cnt === 0;
  } else {
    const selCount = Object.keys(S.selected).length;
    $('dlbtn').textContent = selCount ? `下载选中(${selCount})` : '下载选中';
    $('dlbtn').disabled = selCount === 0;
  }
}

function confirmAsync(msg) {
  return new Promise(resolve => {
    const overlay = $('confirm-overlay');
    $('confirm-content').innerHTML = `<div class="set-dialog" style="width:320px">
      <p style="font-size:12px;color:var(--text);line-height:1.5;margin-bottom:12px">${esc(msg)}</p>
      <div style="display:flex;gap:8px;justify-content:flex-end">
        <button class="btn btn-sec" id="confirm-no">取消</button>
        <button class="btn btn-pri" id="confirm-yes">确定</button>
      </div>
    </div>`;
    overlay.classList.add('on');
    const yesBtn = $('confirm-yes');
    const noBtn = $('confirm-no');
    const onYes = () => { cleanup(); resolve(true); };
    const onNo = () => { cleanup(); resolve(false); };
    const onOverlay = (e) => { if (e.target === overlay) { cleanup(); resolve(false); } };
    function cleanup() {
      overlay.classList.remove('on');
      yesBtn.removeEventListener('click', onYes);
      noBtn.removeEventListener('click', onNo);
      overlay.removeEventListener('click', onOverlay);
    }
    yesBtn.addEventListener('click', onYes);
    noBtn.addEventListener('click', onNo);
    overlay.addEventListener('click', onOverlay);
  });
}

async function doDownloadSel() {
  let groups = [];
  if (S.mode === 'batch') {
    groups = S.bGroups.filter(g => S.bSelected[g.subject+'_'+g.season+'_'+g.paper]);
  } else {
    for (const key in S.selected) {
      const g = S.groups.find(g => (g.subject+'_'+g.season+'_'+g.paper) === key);
      if (g) groups.push(g);
    }
  }
  if (groups.length === 0) { toast('没有选中任何试卷','warn'); return; }
  const includeMS = S.includeMS;
  const files = [];
  for (const g of groups) {
    if (g.qp) files.push(g.qp);
    if (includeMS && g.ms) files.push(g.ms);
  }
  const question = `确定下载 ${groups.length} 组试卷 (${files.length} 个文件) 吗？`;
  if (!await confirmAsync(question)) return;

  $('hdr-st').textContent = `0/${files.length}`;
  let completed = 0;
  let idx = 0;
  const worker = async () => {
    while (idx < files.length) {
      const file = files[idx++];
      await S.bucket.wait(1);
      const url = BASE_URL+'/obj/Common/Fetch/redir/'+file.filename;
      try {
        await chrome.downloads.download({url, filename:file.filename, saveAs:false, conflictAction:'uniquify'});
        S.dlHistory.add(file.filename);
      } catch(e) {
        toast('下载失败: '+file.filename, 'err');
      }
      completed++;
      $('hdr-st').textContent = `${completed}/${files.length}`;
    }
  };
  await Promise.all(Array.from({length:Math.min(S.concurrency, files.length)}, () => worker()));
  await saveDlHistory();
  toast(`已提交 ${completed} 个文件到浏览器下载`, 'ok');
  $('hdr-st').textContent = '就绪';
}

// ── Navigation ──
function switchTab(tab) {
  S.mode = tab;
  document.querySelectorAll('.tab-btn').forEach(b => b.classList.toggle('on', b.dataset.tab===tab));
  document.querySelectorAll('.panel').forEach(p => p.classList.toggle('on', p.id==='pnl-'+tab));
  updateDock();
}

// ── Theme ──
function toggleTheme() {
  S.theme = S.theme === 'light' ? 'dark' : 'light';
  document.documentElement.setAttribute('data-theme', S.theme);
  updateThemeBtn();
  saveSettings();
  if (S.mode === 'search') renderResults();
}

function updateThemeBtn() {
  const btn = $('theme-btn');
  if (S.theme === 'dark') {
    btn.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>';
  } else {
    btn.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/></svg>';
  }
}

// ── Settings ──
function openSettings() { $('set-overlay').classList.add('on'); }
function closeSettings() {
  S.rate = parseInt($('b-rate').value);
  S.concurrency = parseInt($('b-thr').value);
  S.bucket.updateRate(S.rate);
  saveSettings();
  $('set-overlay').classList.remove('on');
}

async function clearHistory() {
  if (!await confirmAsync('确定要清空下载历史吗？此操作不可撤销。')) return;
  S.dlHistory = new Set();
  await saveDlHistory();
  toast('下载历史已清空','ok');
  if (S.mode === 'search') renderResults();
}

// ── Favorites ──
function openFavorites() { renderFavDialog(); $('fav-overlay').classList.add('on'); }
function closeFavorites() { $('fav-overlay').classList.remove('on'); }

function renderFavDialog() {
  if (S.favorites.length === 0) {
    $('fav-list-dialog').innerHTML = '<div style="font-size:10px;color:var(--text3);padding:8px 0">暂无收藏科目</div>';
    return;
  }
  let html = '';
  for (const fav of S.favorites) {
    html += `<div class="fav-row" data-code="${esc(fav.code)}">
      <span class="fav-code">${esc(fav.code)}</span>
      <span class="fav-name">${esc(fav.name)}</span>
      <button class="fav-rm" data-rm="${esc(fav.code)}"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg></button>
    </div>`;
  }
  $('fav-list-dialog').innerHTML = html;
  $('fav-list-dialog').querySelectorAll('.fav-row').forEach(row => {
    row.addEventListener('click', () => {
      const code = row.dataset.code;
      $('s-subj').value = code;
      $('b-subj').value = code;
      closeFavorites();
    });
    row.querySelector('.fav-rm').addEventListener('click', (e) => {
      e.stopPropagation();
      removeFav(row.dataset.code);
    });
  });
}

function addFav() {
  const code = $('s-subj').value;
  if (!code) { toast('请先选择科目','warn'); return; }
  if (S.favorites.find(f => f.code === code)) { toast('已收藏该科目','info'); return; }
  S.favorites.unshift({code,name:getSubjectName(code)});
  saveFavorites();
  toast('已收藏 '+code,'ok');
}

function removeFav(code) {
  S.favorites = S.favorites.filter(f => f.code !== code);
  saveFavorites();
  renderFavDialog();
}

function refreshFavUI() {
  const bar = $('fav-bar');
  if (S.favorites.length === 0) { bar.style.display = 'none'; return; }
  bar.style.display = 'flex';
  $('fav-chips').innerHTML = S.favorites.map(f =>
    `<button class="fav-chip" data-code="${esc(f.code)}">${esc(f.code)} ${esc(f.name)}</button>`
  ).join('');
  $('fav-chips').querySelectorAll('.fav-chip').forEach(chip => {
    chip.addEventListener('click', () => {
      $('s-subj').value = chip.dataset.code;
      $('b-subj').value = chip.dataset.code;
      toast('已选择科目: '+chip.dataset.code, 'info');
    });
  });
}

// ── Init ──
async function init() {
  await loadAll();

  document.querySelectorAll('.tab-btn').forEach(b => {
    b.addEventListener('click', () => switchTab(b.dataset.tab));
  });
  $('theme-btn').addEventListener('click', toggleTheme);
  $('settings-btn').addEventListener('click', openSettings);
  $('fav-btn').addEventListener('click', openFavorites);
  $('set-overlay').addEventListener('click', function(e) { if (e.target === this) closeSettings(); });
  $('fav-overlay').addEventListener('click', function(e) { if (e.target === this) closeFavorites(); });

  $('sbtn').addEventListener('click', doSearch);
  $('pvbtn').addEventListener('click', doPreview);
  $('dlbtn').addEventListener('click', doDownloadSel);
  $('rlist').addEventListener('click', onResultsClick);
  $('close-settings-btn').addEventListener('click', closeSettings);
  $('close-fav-btn').addEventListener('click', closeFavorites);
  $('add-fav-btn').addEventListener('click', addFav);
  $('clear-history-btn').addEventListener('click', clearHistory);

  $('b-rate').addEventListener('input', function() { $('rv').textContent = this.value+'/s'; });
  $('b-thr').addEventListener('input', function() { $('tv').textContent = this.value; });

  $('dl-ms').addEventListener('change', function() { syncMS(this); });
  $('dl-ms-batch').addEventListener('change', function() { syncMS(this); });

  document.querySelectorAll('[data-action]').forEach(btn => {
    const action = btn.dataset.action;
    if (action === 'quickYears') {
      btn.addEventListener('click', () => quickYears(parseInt(btn.dataset.years)));
    } else if (action === 'selAll') {
      btn.addEventListener('click', selAll);
    } else if (action === 'deselAll') {
      btn.addEventListener('click', deselAll);
    } else if (action === 'selQP') {
      btn.addEventListener('click', selQP);
    } else if (action === 'selMS') {
      btn.addEventListener('click', selMS);
    }
  });

  document.querySelectorAll('.cbgrp input[type=checkbox]').forEach(cb => {
    cb.addEventListener('change', function() { syncCB(this); });
  });

  const cy = new Date().getFullYear();
  const latestExamYear = (new Date().getMonth() >= 5) ? cy : cy+1;
  for (let y = latestExamYear; y >= 2001; y--) {
    $('s-year').innerHTML += `<option value="${y}">${y}</option>`;
    $('b-yfrom').innerHTML += `<option value="${y}">${y}</option>`;
    $('b-yto').innerHTML += `<option value="${y}">${y}</option>`;
  }
  $('b-yfrom').value = Math.max(2001, latestExamYear-2);
  $('b-yto').value = latestExamYear;

  try {
    await fetchSubjects();
  } catch(e) {
    toast('未能加载科目列表，请检查网络','warn');
  }
  updateDock();
  refreshFavUI();
}

document.addEventListener('DOMContentLoaded', () => init().catch(e => console.error('Init failed:', e)));
