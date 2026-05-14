const ICO={check:'<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>',
  eye:'<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>'};
const SVG={sun:'<circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/>',
moon:'<path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>'};
const DL_ICON={pending:'<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>',downloading:'<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>',done:'<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>',failed:'<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>',cancelled:'<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="10"/><line x1="4.93" y1="4.93" x2="19.07" y2="19.07"/></svg>'};
const DL_STAT_TXT={pending:'等待',downloading:'下载中',done:'完成',cancelled:'已取消'};

function esc(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');}

const S={
  subjects:[],groups:[],selected:{},bGroups:[],bSelected:null,saveDir:'',
  poll:null,dlRendered:false,mode:'search',
  theme:'light',favorites:[],currentCode:'',currentName:'',
  downloadHistory:new Set(),settingsDebounce:null,
};

window.addEventListener('pywebviewready',()=>doInit());
document.addEventListener('mousedown',e=>{if(e.target.closest('button'))window.focus();});

async function doInit(){
  const fill=document.getElementById('splash-fill');
  const msg=document.getElementById('splash')?.querySelector('.splash-msg');

  const now=new Date().getFullYear();
  const yrs=Array.from({length:now-1999},(_,i)=>now-i);
  ['s-year','b-yfrom','b-yto'].forEach(id=>{
    const sel=document.getElementById(id);
    yrs.forEach(y=>sel.add(new Option(y,y)));
    sel.value=id==='b-yfrom'?now-2:now;
  });

  try{
    if(fill){fill.classList.remove('loop');fill.style.width='30%';}
    if(msg)msg.textContent='正在加载科目数据...';

    const [subjR,settingsR,favR,histR]=await Promise.all([
      pywebview.api.get_subjects(),
      pywebview.api.load_settings(),
      pywebview.api.get_favorites(),
      pywebview.api.get_download_history(),
    ]);

    if(fill)fill.style.width='60%';
    if(msg)msg.textContent='正在处理数据...';

    const subj=JSON.parse(subjR);
    if(!subj.ok)throw new Error(subj.error);
    S.subjects=subj.data;
    const frag=document.createDocumentFragment();
    subj.data.forEach(s=>{
      const opt=document.createElement('option');
      opt.value=s.value;opt.textContent=s.value+' \u2014 '+s.text;
      frag.appendChild(opt);
    });
    document.getElementById('s-subj').replaceChildren(frag.cloneNode(true));
    document.getElementById('b-subj').replaceChildren(frag);
    document.getElementById('hdr-st').textContent=subj.data.length+' 个科目';
    setDot('idle');

    if(fill)fill.style.width='75%';
    const settings=JSON.parse(settingsR);
    S.theme=settings.theme||'light';S.saveDir=settings.save_dir||'';
    requestAnimationFrame(()=>{
      document.documentElement.dataset.theme=S.theme;
      updateThemeIcon();
      document.getElementById('dir-disp').textContent=S.saveDir;
      document.getElementById('dir-disp-batch').textContent=S.saveDir;
      document.getElementById('dl-ms').checked=settings.include_ms!==false;
      document.getElementById('dl-ms-batch').checked=settings.include_ms!==false;
      document.getElementById('b-rate').value=settings.rate||5;document.getElementById('rv').textContent=(settings.rate||5)+'/s';
      document.getElementById('b-rate-batch').value=settings.rate||5;document.getElementById('rv-batch').textContent=(settings.rate||5)+'/s';
      document.getElementById('b-thr').value=settings.threads||4;
      document.getElementById('b-thr-batch').value=settings.threads||4;
      document.getElementById('b-merge').checked=!!settings.merge;
      document.getElementById('b-merge-batch').checked=!!settings.merge;
      syncCB(document.getElementById('b-merge'));
      syncCB(document.getElementById('b-merge-batch'));
      if(settings.last_mode)S.mode=settings.last_mode;
      if(settings.proxy_url){
        document.getElementById('proxy-url-side').value=settings.proxy_url;
        document.getElementById('proxy-indicator').textContent='已配置';
      }

      const fav=JSON.parse(favR);
      S.favorites=Array.isArray(fav)?fav:[];
      renderFavs();
    });

    const hist=JSON.parse(histR);
    if(Array.isArray(hist))hist.forEach(h=>S.downloadHistory.add(h));

    switchMode(S.mode);
    setStat('就绪');
    ['s-subj','b-subj'].forEach(id=>document.getElementById(id).addEventListener('change',updateSubjectDisplay));
    if(fill){fill.style.width='100%';}
    if(msg)msg.textContent='加载完成';
    const sp=document.getElementById('splash');
    if(sp){setTimeout(()=>{sp.classList.add('fade');setTimeout(()=>sp.remove(),500);},300);}
    // Check for updates (async, non-blocking)
    setTimeout(()=>checkUpdate(), 2000);
    window.focus();
  }catch(e){
    const sp=document.getElementById('splash');
    if(sp){
      sp.innerHTML='<span class="splash-err">\u26a0 初始化失败<br>'+esc(e.message)+'</span>';
      const btn=document.createElement('button');btn.className='btn btn-pri';btn.textContent='\u21ba 重试';
      btn.onclick=()=>doInit();sp.appendChild(btn);
    }
    document.getElementById('hdr-st').textContent='加载失败';
    setDot('err');
  }
}

window.addEventListener('beforeunload',()=>saveSettingsNow());

function toggleTheme(){
  S.theme=S.theme==='dark'?'light':'dark';
  document.documentElement.dataset.theme=S.theme;
  updateThemeIcon();autoSaveSettings();
}
function updateThemeIcon(){
  const btn=document.getElementById('theme-btn');
  btn.innerHTML=S.theme==='dark'
    ?'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'+SVG.sun+'</svg>'
    :'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'+SVG.moon+'</svg>';
}

function autoSaveSettings(){
  clearTimeout(S.settingsDebounce);
  S.settingsDebounce=setTimeout(()=>saveSettingsNow(),300);
}
async function saveSettingsNow(){
  try{await pywebview.api.save_settings(JSON.stringify({
    theme:S.theme,save_dir:S.saveDir,
    include_ms:document.getElementById('dl-ms').checked,
    rate:+document.getElementById('b-rate').value,
    threads:+document.getElementById('b-thr').value,
    merge:document.getElementById('b-merge').checked,
    proxy_url:document.getElementById('proxy-url-side').value||'',
    last_mode:S.mode,
  }));}catch(e){}
}

async function saveProxySide(){
  const url=document.getElementById('proxy-url-side').value.trim();
  const r=JSON.parse(await pywebview.api.set_proxy(url));
  if(r.ok){toast('代理已保存','ok');document.getElementById('proxy-indicator').textContent=url?'已配置':'';autoSaveSettings();}
  else toast('代理设置失败: '+r.error,'err');
}
function syncProxyToDialog(){
  document.getElementById('proxy-url').value=document.getElementById('proxy-url-side').value;
}
async function saveProxy(){
  const urlS=document.getElementById('proxy-url').value.trim();
  document.getElementById('proxy-url-side').value=urlS;
  await saveProxySide();
  document.getElementById('set-overlay').classList.remove('on');
}
async function testProxySide(){
  const url=document.getElementById('proxy-url-side').value.trim();
  if(!url)return toast('请先输入代理地址','err');
  const st=document.getElementById('proxy-st-side');st.textContent='测试中...';st.className='proxy-status';st.style.display='block';
  const r=JSON.parse(await pywebview.api.test_proxy(url));
  if(r.ok){st.innerHTML='<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg> 连接成功 ('+r.latency_ms+'ms)';st.className='proxy-status ok';st.style.display='block';}
  else{st.innerHTML='<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg> 连接失败: '+r.error;st.className='proxy-status err';st.style.display='block';}
}
async function testProxy(){
  document.getElementById('proxy-url-side').value=document.getElementById('proxy-url').value.trim();
  await testProxySide();
}
async function clearHistory(){
  if(!confirm('确认清空所有下载历史?'))return;
  await pywebview.api.clear_history();
  S.downloadHistory.clear();
  document.getElementById('set-overlay').classList.remove('on');
  toast('下载历史已清空','ok');
}

function switchMode(name){
  S.mode=name;
  ['search','batch','downloads'].forEach(n=>{
    const btn=document.getElementById('mode-'+n);
    const pnl=document.getElementById('pnl-'+n);
    if(btn)btn.classList.toggle('on',n===name);
    if(pnl)pnl.classList.toggle('on',n===name);
  });
  const dlbtn=document.getElementById('dlbtn');
  if(name==='batch'){
    dlbtn.onclick=doBatchDL;
    dlbtn.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg> 批量下载';
  }else{
    dlbtn.onclick=doDownloadSel;
    dlbtn.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg> 下载选中';
  }
  autoSaveSettings();
}

function renderFavs(){
  const el=document.getElementById('fav-list');el.innerHTML='';
  if(!S.favorites.length){
    el.innerHTML='<div class="fav-empty">暂无收藏</div>';
    return;
  }
  S.favorites.forEach(f=>{
    const div=document.createElement('div');div.className='fav-row';
    div.onclick=()=>pickFav(f.code,f.name);
    div.title=f.name+' ('+f.code+')';
    const code=document.createElement('span');code.className='fav-code';code.textContent=f.code;
    const name=document.createElement('span');name.className='fav-name';name.textContent=f.name;
    const rm=document.createElement('button');rm.className='fav-rm';
    rm.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>';
    rm.onclick=e=>{e.stopPropagation();removeFav(f.code)};
    div.append(code,name,rm);el.appendChild(div);
  });
}
async function pickFav(code,name){
  S.currentCode=code;S.currentName=name;
  const sn=document.getElementById('subj-name');
  sn.textContent=name+' ('+code+')';sn.style.display='inline';
  document.getElementById('s-subj').value=code;
  document.getElementById('b-subj').value=code;
}
function cleanSubjName(raw){
  let n=raw.split(' \u2014 ')[1]||raw;
  n=n.replace(/[（(].*?[）)]/g,'').trim();
  return n||raw;
}
async function addFav(){
  let code,name;
  if(S.mode==='search'||S.mode==='downloads'){
    code=document.getElementById('s-subj').value;
    if(!code)return toast('请先选择科目','err');
    const opt=document.getElementById('s-subj').selectedOptions[0];
    name=cleanSubjName(opt?opt.text:code);
  }else{
    code=document.getElementById('b-subj').value;
    if(!code)return toast('请先选择科目','err');
    const opt=document.getElementById('b-subj').selectedOptions[0];
    name=cleanSubjName(opt?opt.text:code);
  }
  const r=JSON.parse(await pywebview.api.add_favorite(code,name));
  if(r.ok){
    S.favorites=JSON.parse(await pywebview.api.get_favorites());
    renderFavs();toast('已收藏 '+name,'ok');
  }
}
async function removeFav(code){
  await pywebview.api.remove_favorite(code);
  S.favorites=S.favorites.filter(f=>f.code!==code);
  renderFavs();
}

function updateSubjectDisplay(){
  const sel=S.mode==='search'?document.getElementById('s-subj'):document.getElementById('b-subj');
  const code=sel.value;if(!code)return;
  S.currentCode=code;
  const opt=sel.selectedOptions[0];
  S.currentName=opt?opt.text.split(' \u2014 ')[1]||opt.text:code;
  const sn=document.getElementById('subj-name');
  sn.textContent=S.currentName+' ('+S.currentCode+')';sn.style.display='inline';
  document.getElementById('s-subj').value=code;
  document.getElementById('b-subj').value=code;
}

async function doSearch(){
  const subj=document.getElementById('s-subj').value;
  const year=document.getElementById('s-year').value;
  const seas=document.getElementById('s-seas').value;
  if(!subj)return toast('请选择科目','err');
  updateSubjectDisplay();
  setBusy('sbtn','<span class="spin"></span> 搜索中\u2026',true);setStat('搜索中\u2026');
  try{
    const r=JSON.parse(await pywebview.api.search(subj,year,seas));
    if(!r.ok)throw new Error(r.error);
    S.groups=r.groups;S.selected={};
    r.groups.forEach((g,i)=>{
      S.selected[i]={};
      if(g.qp)S.selected[i].qp=true;
      if(g.ms)S.selected[i].ms=true;
    });
    renderResults();setStat('找到 '+r.count+' 个文件');
    document.getElementById('hdr-st').textContent=r.groups.length+' 组试卷';
    const sn=document.getElementById('subj-name');
    sn.textContent=S.currentName+' ('+subj+')';sn.style.display='inline';
    setDot('idle');
  }catch(e){toast('搜索失败: '+e.message,'err');setStat('失败');setDot('err');}
  finally{setBusy('sbtn','搜索',false,'btn-pri');}
}

function renderResults(){
  const el=document.getElementById('rlist');el.innerHTML='';
  if(!S.groups.length){
    el.innerHTML='<div class="empty"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="2" y="2" width="20" height="8" rx="2" ry="2"/><rect x="2" y="14" width="20" height="8" rx="2" ry="2"/><line x1="6" y1="6" x2="6.01" y2="6"/><line x1="6" y1="18" x2="6.01" y2="18"/></svg><div>未找到试卷</div></div>';
    document.getElementById('rcnt').textContent='共 0 页';
    document.getElementById('res-badge').textContent='0';
    return;
  }
  const byPG={};
  S.groups.forEach((g,i)=>{const pg=g.paper_group||0;(byPG[pg]=byPG[pg]||[]).push([i,g]);});
  Object.keys(byPG).sort((a,b)=>+a-+b).forEach(pg=>{
    const label=+pg>0?'Paper '+pg:'其他',items=byPG[pg];
    const grp=document.createElement('div');grp.dataset.pg=pg;
    const hdr=document.createElement('div');hdr.className='rgrp-hdr';
    hdr.textContent='\u25be '+label+' ('+items.length+' 项)';
    hdr.onclick=()=>toggleGrp(pg);
    el.appendChild(hdr);
    items.forEach(([i,g])=>{
      const sqp=S.selected[i]&&S.selected[i].qp;const sms=S.selected[i]&&S.selected[i].ms;
      const qp=g.qp?g.qp.replace('.pdf',''):null,ms=g.ms?g.ms.replace('.pdf',''):null;
      const qpDled=qp&&S.downloadHistory.has(g.qp)?' dled':'',msDled=ms&&S.downloadHistory.has(g.ms)?' dled':'';
      const row=document.createElement('div');row.className='res-row';row.dataset.i=i;row.dataset.pg=pg;
      row.innerHTML='<div class="res-check">'+
          '<div class="cb'+(sqp?' on':'')+'" title="QP">'+(sqp?ICO.check:'')+'</div>'+
          '<div class="cb'+(sms?' on':'')+(!g.ms?' dim':'')+'" title="MS">'+(sms?ICO.check:'')+'</div>'+
        '</div>'+
        '<span class="res-fname '+(qp?'exist':'miss')+qpDled+'" data-fname="'+esc(g.qp||'')+'"></span>'+
        '<span class="res-fname '+(ms?'exist':'miss')+msDled+'" data-fname="'+esc(g.ms||'')+'"></span>'+
        '<span class="res-status">'+((g.qp&&g.ms)?'<svg viewBox="0 0 24 24" fill="none" stroke="var(--ok)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>':'<svg viewBox="0 0 24 24" fill="none" stroke="var(--text3)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>')+'</span>'+
        '<button class="preview-btn" title="预览" data-pfname="'+esc(g.qp||'')+'">'+ICO.eye+'</button>';
      row.querySelectorAll('.res-fname')[0].textContent=qp||'\u2014';
      row.querySelectorAll('.res-fname')[1].textContent=ms||'\u2014';
      row.querySelector('.cb').onclick=e=>{e.stopPropagation();toggleCB(i,'qp')};
      if(g.ms)row.querySelectorAll('.cb')[1].onclick=e=>{e.stopPropagation();toggleCB(i,'ms')};
      row.querySelectorAll('.res-fname').forEach(el=>{
        const fn=el.dataset.fname;
        if(fn)el.onclick=e=>{e.stopPropagation();openPreview(fn);};
      });
      const pbtn=row.querySelector('.preview-btn');
      if(pbtn){const fn=pbtn.dataset.pfname;if(fn)pbtn.onclick=e=>{e.stopPropagation();openPreview(fn);};}
      el.appendChild(row);
    });
  });
  updateCount();
}

function toggleCB(i,ftype){
  if(!S.selected[i])S.selected[i]={};S.selected[i][ftype]=!(S.selected[i][ftype]);
  const row=document.querySelector('.res-row[data-i="'+i+'"]');if(!row)return;
  const cb=row.querySelectorAll('.cb')[ftype==='qp'?0:1];
  const on=S.selected[i][ftype];
  cb.classList.toggle('on',on);cb.innerHTML=on?ICO.check:'';updateCount();
}
function toggleGrp(pg){
  const rows=document.querySelectorAll('.res-row[data-pg="'+pg+'"]');
  const anyOff=[...rows].some(r=>{
    const i=+r.dataset.i;const g=S.groups[i];if(!g)return false;
    return(g.qp&&!(S.selected[i]&&S.selected[i].qp))||(g.ms&&!(S.selected[i]&&S.selected[i].ms));
  });
  rows.forEach(r=>{
    const i=+r.dataset.i;if(!S.selected[i])S.selected[i]={};const g=S.groups[i];if(!g)return;
    if(g.qp)S.selected[i].qp=anyOff;if(g.ms)S.selected[i].ms=anyOff;
    const cbs=r.querySelectorAll('.cb');
    ['qp','ms'].forEach((ft,idx)=>{
      const on=S.selected[i][ft];
      cbs[idx].classList.toggle('on',!!on);cbs[idx].innerHTML=on?ICO.check:'';
    });
  });updateCount();
}
function selAll(){
  S.groups.forEach((g,i)=>{S.selected[i]={};if(g.qp)S.selected[i].qp=true;if(g.ms)S.selected[i].ms=true;});
  document.querySelectorAll('#rlist .cb').forEach(cb=>{cb.classList.add('on');cb.innerHTML=ICO.check;});updateCount();
}
function deselAll(){
  S.groups.forEach((_,i)=>{S.selected[i]={qp:false,ms:false};});
  document.querySelectorAll('#rlist .cb').forEach(cb=>{cb.classList.remove('on');cb.innerHTML='';});updateCount();
}
function selQP(){
  S.groups.forEach((g,i)=>{S.selected[i]={qp:!!g.qp,ms:false};});
  document.querySelectorAll('#rlist .res-row').forEach(r=>{
    const i=+r.dataset.i;const g=S.groups[i];if(!g)return;
    const cbs=r.querySelectorAll('.cb');
    cbs[0].classList.toggle('on',!!g.qp);cbs[0].innerHTML=g.qp?ICO.check:'';
    cbs[1].classList.remove('on');cbs[1].innerHTML='';
  });updateCount();
}
function selMS(){
  S.groups.forEach((g,i)=>{S.selected[i]={qp:false,ms:!!g.ms};});
  document.querySelectorAll('#rlist .res-row').forEach(r=>{
    const i=+r.dataset.i;const g=S.groups[i];if(!g)return;
    const cbs=r.querySelectorAll('.cb');
    cbs[0].classList.remove('on');cbs[0].innerHTML='';
    cbs[1].classList.toggle('on',!!g.ms);cbs[1].innerHTML=g.ms?ICO.check:'';
  });updateCount();
}
function countSelected(){
  let n=0;
  S.groups.forEach((g,i)=>{
    if(S.selected[i]&&S.selected[i].qp&&g.qp)n++;
    if(S.selected[i]&&S.selected[i].ms&&g.ms)n++;
  });return n;
}
function updateCount(){
  const tot=S.groups.reduce((a,g)=>(g.qp?1:0)+(g.ms?1:0)+a,0);
  const sel=countSelected();
  document.getElementById('rcnt').textContent='共 '+tot+' 文件，已选 '+sel+' 个';
  document.getElementById('res-badge').textContent=sel+'/'+tot;
}

function quickYears(n){
  const now=new Date().getFullYear();
  const from=document.getElementById('b-yfrom');const to=document.getElementById('b-yto');
  if(n>=99){from.value=from.options[from.options.length-1].value;to.value=now;}
  else{to.value=now;from.value=now-n+1;}
}
async function doPreview(){
  const code=document.getElementById('b-subj').value;
  const yFrom=+document.getElementById('b-yfrom').value;
  const yTo=+document.getElementById('b-yto').value;
  if(!code)return toast('请选择科目','err');
  if(yFrom>yTo)return toast('年份范围有误','err');
  updateSubjectDisplay();
  const seasons=[...document.querySelectorAll('#cbg-seasons input:checked')].map(el=>el.value);
  const pgs=[...document.querySelectorAll('#cbg-papers input:checked')].map(el=>+el.value);
  if(!seasons.length)return toast('请至少选一个季度','err');
  if(!pgs.length)return toast('请至少选择一种 Paper 类型','err');
  ['pvbtn','bdbtn'].forEach(id=>{const b=document.getElementById(id);if(b)b.disabled=true;});
  document.getElementById('pvbtn').innerHTML='<span class="spin"></span> 搜索中\u2026';setStat('预览中\u2026');
  try{
    const r=JSON.parse(await pywebview.api.batch_preview(
      JSON.stringify({code,year_from:yFrom,year_to:yTo,seasons,pgs})
    ));
    if(!r.ok)throw new Error(r.error);
    S.bGroups=r.groups;S.bSelected={};
    r.groups.forEach((g,i)=>{S.bSelected[i]={};if(g.qp)S.bSelected[i].qp=true;if(g.ms)S.bSelected[i].ms=true;});
    if(r.warnings&&r.warnings.length)toast('预览完成，'+r.warnings.length+' 个查询失败','warn');
    renderPreview(r.groups);setStat('预览: '+r.groups.reduce((a,g)=>(g.qp?1:0)+(g.ms?1:0)+a,0)+' 个文件');
  }catch(e){toast('预览失败: '+e.message,'err');setStat('失败');}
  finally{['pvbtn','bdbtn'].forEach(id=>{const b=document.getElementById(id);if(b)b.disabled=false;});
    document.getElementById('pvbtn').innerHTML='预览';}
}
function renderPreview(groups){
  const el=document.getElementById('prev');el.innerHTML='';
  const backBtn=document.getElementById('back-to-select');
  const badge=document.getElementById('batch-badge');
  if(backBtn)backBtn.style.display='';
  if(!groups.length){
    el.innerHTML='<span style="color:var(--text3)">（无结果）</span>';
    if(badge){badge.style.display='none';}
    return;
  }
  const totalFiles=groups.reduce((a,g)=>(g.qp?1:0)+(g.ms?1:0)+a,0);
  if(badge){badge.textContent=totalFiles+' 个文件';badge.style.display='';}
  const byY={};
  groups.forEach((g,i)=>{
    const sy=g.sy||'';let y=sy.length>1?sy.slice(1):'?';
    if(/^\d{2}$/.test(y))y='20'+y;(byY[y]=byY[y]||[]).push([i,g]);
  });
  const tbar=document.createElement('div');tbar.className='tbar';
  tbar.innerHTML='<button class="btn btn-sec btn-sm" onclick="selAllB()">全选</button> <button class="btn btn-sec btn-sm" onclick="deselAllB()">全不选</button> <button class="btn btn-sec btn-sm" onclick="selQPB()">仅 QP</button> <button class="btn btn-sec btn-sm" onclick="selMSB()">仅 MS</button>';
  el.appendChild(tbar);
  Object.keys(byY).sort((a,b)=>+a-+b).forEach(y=>{
    const grp=document.createElement('div');grp.style.marginBottom='4px';
    const hdr=document.createElement('div');hdr.className='rgrp-hdr';
    hdr.textContent='\u2500\u2500 '+y+' 年 ('+byY[y].length+' 组) \u2500\u2500';
    grp.appendChild(hdr);
    byY[y].forEach(([i,g])=>{
      const sqp=S.bSelected[i]&&S.bSelected[i].qp;const sms=S.bSelected[i]&&S.bSelected[i].ms;
      const qp=g.qp?g.qp.replace('.pdf',''):null,ms=g.ms?g.ms.replace('.pdf',''):null;
      const row=document.createElement('div');row.className='res-row';row.dataset.i=i;
      row.innerHTML='<div class="res-check">'+
          '<div class="cb'+(sqp?' on':'')+'" title="QP">'+(sqp?ICO.check:'')+'</div>'+
          '<div class="cb'+(sms?' on':'')+(!g.ms?' dim':'')+'" title="MS">'+(sms?ICO.check:'')+'</div>'+
        '</div>'+
        '<span class="res-fname '+(qp?'exist':'miss')+'" data-fname="'+esc(g.qp||'')+'"></span>'+
        '<span class="res-fname '+(ms?'exist':'miss')+'" data-fname="'+esc(g.ms||'')+'"></span>'+
        '<span class="res-status">'+((g.qp&&g.ms)?'<svg viewBox="0 0 24 24" fill="none" stroke="var(--ok)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>':'<svg viewBox="0 0 24 24" fill="none" stroke="var(--text3)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>')+'</span>'+
        '<button class="preview-btn" title="预览" data-pfname="'+esc(g.qp||'')+'">'+ICO.eye+'</button>';
      row.querySelectorAll('.res-fname')[0].textContent=qp||'\u2014';
      row.querySelectorAll('.res-fname')[1].textContent=ms||'\u2014';
      row.querySelector('.cb').onclick=e=>{e.stopPropagation();toggleCBB(i,'qp');e.target.innerHTML=S.bSelected[i].qp?ICO.check:''};
      if(g.ms)row.querySelectorAll('.cb')[1].onclick=e=>{e.stopPropagation();toggleCBB(i,'ms');e.target.innerHTML=S.bSelected[i].ms?ICO.check:''};
      row.querySelectorAll('.res-fname').forEach(el=>{
        const fn=el.dataset.fname;
        if(fn)el.onclick=e=>{e.stopPropagation();openPreview(fn);};
      });
      const pbtn=row.querySelector('.preview-btn');
      if(pbtn){const fn=pbtn.dataset.pfname;if(fn)pbtn.onclick=e=>{e.stopPropagation();openPreview(fn);};}
      grp.appendChild(row);
    });
    el.appendChild(grp);
  });
}
function toggleCBB(i,ftype){if(!S.bSelected[i])S.bSelected[i]={};S.bSelected[i][ftype]=!(S.bSelected[i][ftype]);}
function selAllB(){S.bGroups.forEach((g,i)=>{S.bSelected[i]={};if(g.qp)S.bSelected[i].qp=true;if(g.ms)S.bSelected[i].ms=true;});renderPreview(S.bGroups);}
function deselAllB(){S.bGroups.forEach((_,i)=>{S.bSelected[i]={qp:false,ms:false};});renderPreview(S.bGroups);}
function selQPB(){S.bGroups.forEach((g,i)=>{S.bSelected[i]={qp:!!g.qp,ms:false};});renderPreview(S.bGroups);}
function selMSB(){S.bGroups.forEach((g,i)=>{S.bSelected[i]={qp:false,ms:!!g.ms};});renderPreview(S.bGroups);}
function backToSelect(){
  const el=document.getElementById('prev');
  el.innerHTML='（点击「预览」查看将要下载的文件...）';
  const backBtn=document.getElementById('back-to-select');
  const badge=document.getElementById('batch-badge');
  if(backBtn)backBtn.style.display='none';
  if(badge)badge.style.display='none';
  S.bGroups=[];S.bSelected=null;
}

async function doBatchDL(){
  if(!S.bGroups.length)return toast('请先点击预览','err');
  if(!S.saveDir)return toast('请选择保存目录','err');
  let groups=S.bGroups;
  if(S.bSelected){
    groups=[];S.bGroups.forEach((g,i)=>{
      const qpOn=S.bSelected[i]&&S.bSelected[i].qp&&g.qp;
      const msOn=S.bSelected[i]&&S.bSelected[i].ms&&g.ms;
      if(qpOn||msOn)groups.push(Object.assign({},g,qpOn?{qp:g.qp}:{qp:null},msOn?{ms:g.ms}:{ms:null}));
    });
    if(!groups.length)return toast('请至少勾选一个文件','err');
  }
  showConfirm(groups,{
    merge:document.getElementById('b-merge').checked,
    include_ms:document.getElementById('dl-ms').checked,
    rate:+document.getElementById('b-rate').value,
    threads:+document.getElementById('b-thr').value,
  });
}
async function doDownloadSel(){
  const sel=[];let any=false;
  S.groups.forEach((g,i)=>{
    const qpOn=S.selected[i]&&S.selected[i].qp&&g.qp;
    const msOn=S.selected[i]&&S.selected[i].ms&&g.ms;
    if(qpOn||msOn){
      any=true;
      sel.push(Object.assign({},g,qpOn?{qp:g.qp}:{qp:null},msOn?{ms:g.ms}:{ms:null}));
    }
  });
  if(!any)return toast('请先选择文件','err');
  if(!S.saveDir)return toast('请选择保存目录','err');
  showConfirm(sel,{
    merge:document.getElementById('b-merge').checked,
    include_ms:document.getElementById('dl-ms').checked,
    rate:+document.getElementById('b-rate').value,
    threads:+document.getElementById('b-thr').value,
  });
}
function showConfirm(groups,options){
  S._confirmGroups=groups;S._confirmOptions=options;
  const qpN=groups.filter(g=>g.qp).length;
  const msN=groups.filter(g=>g.ms).length;
  const histSet=new Set();S.downloadHistory.forEach(f=>histSet.add(f));
  const dupN=groups.filter(g=>(g.qp&&histSet.has(g.qp))||(g.ms&&histSet.has(g.ms))).length;
  let html='<div class="set-dialog" style="max-width:420px">'+
    '<button class="close-btn" onclick="document.getElementById(\'confirm-overlay\').classList.remove(\'on\')"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg></button>'+
    '<h3 style="font-size:15px;font-weight:700">确认下载</h3>'+
    '<div style="font-size:12px;color:var(--text2);line-height:1.8">'+
      '<div>题卷 QP：'+qpN+' 个 &nbsp; 答案 MS：'+msN+' 个 &nbsp; 合计：'+(qpN+msN)+' 个</div>'+
      (dupN>0?'<div style="color:var(--warn)">\u26a0 其中 '+dupN+' 个已在下载历史中</div>':'')+
      '<div style="margin-top:4px;font-size:10px">保存到：'+esc(S.saveDir)+'</div>'+
    '</div>'+
    '<div style="display:flex;gap:8px;justify-content:flex-end">'+
      '<button class="btn btn-sec btn-sm" onclick="document.getElementById(\'confirm-overlay\').classList.remove(\'on\')">取消</button>'+
      (dupN>0?'<button class="btn btn-warn btn-sm" onclick="document.getElementById(\'confirm-overlay\').classList.remove(\'on\');beginDL(S._confirmGroups,S._confirmOptions,\'skip\')">跳过重复</button>':'')+
      '<button class="btn btn-pri btn-sm" onclick="document.getElementById(\'confirm-overlay\').classList.remove(\'on\');beginDL(S._confirmGroups,S._confirmOptions,\'overwrite\')">确认下载</button>'+
    '</div></div>';
  document.getElementById('confirm-content').innerHTML=html;
  document.getElementById('confirm-overlay').classList.add('on');
}
async function beginDL(groups,options,dup_mode){
  options.dup_mode=dup_mode||'overwrite';
  options.rate=+document.getElementById('b-rate').value;
  options.threads=+document.getElementById('b-thr').value;
  options.merge=document.getElementById('b-merge').checked;
  options.include_ms=document.getElementById('dl-ms').checked;
  S.dlRendered=false;
  const dlbtn=document.getElementById('dlbtn');
  dlbtn.disabled=true;
  dlbtn.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2"/></svg> 取消下载';
  dlbtn.className='dock-btn danger';
  dlbtn.onclick=cancelDownload;
  setStat('准备下载\u2026');
  try{
    const r=JSON.parse(await pywebview.api.start_download(
      JSON.stringify(groups),S.saveDir,JSON.stringify(options)));
    if(!r.ok)throw new Error(r.error);
    if(r.skipped)toast('已跳过 '+r.skipped+' 个已下载文件','info');
    startPoll();
  }catch(e){toast('启动失败: '+e.message,'err');resetDLBtn();}
}
async function cancelDownload(){
  await pywebview.api.cancel_download();
  toast('正在取消...','info');
}
function resetDLBtn(){
  const b=document.getElementById('dlbtn');b.disabled=false;
  b.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg> 下载选中';
  b.className='dock-btn primary';b.onclick=doDownloadSel;
}

function startPoll(){if(S.poll)clearInterval(S.poll);S.poll=setInterval(doPoll,700);}
async function doPoll(){
  try{
    const [stJson,listJson]=await Promise.all([
      pywebview.api.get_status(),pywebview.api.get_download_list(),
    ]);
    const st=JSON.parse(stJson);const items=JSON.parse(listJson);
    setStat(st.message);
    updateDLList(items);
    updateDockProgress(st,items);
    if(st.phase==='done'){
      clearInterval(S.poll);resetDLBtn();setDot('idle');
      const fail=items.filter(i=>i.status==='failed').length;
      if(fail){
        const net=items.filter(i=>i.error_type==='network').length;
        const nf=items.filter(i=>i.error_type==='not_found').length;
        const rl=items.filter(i=>i.error_type==='rate_limit').length;
        const px=items.filter(i=>i.error_type==='proxy').length;
        let parts=['完成 '+st.success+' 个'];if(fail)parts.push('失败 '+fail+' 个');
        if(net)parts.push('网络:'+net);if(nf)parts.push('404:'+nf);
        if(rl)parts.push('限流:'+rl);if(px)parts.push('代理:'+px);
        toast(parts.join(', '),'warn');
      }else if(st.skipped)toast('完成 '+st.success+' 个, 跳过 '+st.skipped+' 个已下载','ok');
      else toast('下载完成! 共 '+st.success+' 个文件','ok');
    }else{setDot('running');}
  }catch(e){clearInterval(S.poll);resetDLBtn();setDot('idle');}
}

function updateDockProgress(st,items){
  const fill=document.getElementById('dock-progress-fill');
  const ok=items.filter(i=>i.status==='done').length;
  const fail=items.filter(i=>i.status==='failed').length;
  const total=items.length;
  const done=ok+fail;
  const pct=total>0?Math.round(done/total*100):0;
  fill.style.width=pct+'%';
  fill.classList.toggle('active',st.phase==='running');
}

function dlStatClass(s){return{pending:'s-pnd',downloading:'s-dl',done:'s-ok',failed:'s-err',cancelled:'s-pnd'}[s]||'s-pnd';}
function renderDLListFull(items){
  const el=document.getElementById('dllist');el.innerHTML='';
  if(!items.length){el.innerHTML='<div class="empty"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg><div>等待下载...</div></div>';return;}
  items.forEach(it=>{
    const row=document.createElement('div');
    row.className='dlrow '+it.status;row.dataset.id=it.id;row.dataset.status=it.status;row.dataset.err=it.error||'';
    row.innerHTML='<span class="ico">'+(DL_ICON[it.status]||DL_ICON.pending)+'</span>'+
      '<span class="dl-fname'+(it.status==='done'?' dim':'')+'"></span>'+
      '<span class="type-'+it.ftype+'">'+it.ftype+'</span>'+
      '<span class="dl-label"></span>'+
      '<span class="dl-year"></span>'+
      '<span class="dl-stat '+dlStatClass(it.status)+'"></span>'+
      '<span></span>';
    row.querySelector('.dl-fname').textContent=it.filename;
    row.querySelector('.dl-fname').title=it.filename;
    row.querySelector('.dl-label').textContent=it.label;
    row.querySelector('.dl-label').title=it.label;
    row.querySelector('.dl-year').textContent=it.year;
    row.querySelector('.dl-stat').textContent=it.status==='failed'?it.error:(DL_STAT_TXT[it.status]||'');
    if(it.status==='failed'){
      const btn=document.createElement('button');btn.className='btn btn-err btn-sm';btn.textContent='重试';
      btn.onclick=()=>retryItem(it.id);
      row.querySelector('span:last-child').appendChild(btn);
    }
    el.appendChild(row);
  });
  S.dlRendered=true;
}
function updateDLList(items){
  if(!S.dlRendered||!document.querySelector('.dlrow')){S.dlRendered=false;renderDLListFull(items);updateDLSummary(items);return;}
  items.forEach(it=>{
    const row=document.querySelector('.dlrow[data-id="'+it.id+'"]');if(!row)return;
    if(row.dataset.status===it.status&&row.dataset.err===(it.error||''))return;
    row.dataset.status=it.status;row.dataset.err=it.error||'';
    row.className='dlrow '+it.status;
    row.querySelector('.ico').innerHTML=DL_ICON[it.status]||DL_ICON.pending;
    row.querySelector('.dl-fname').className='dl-fname'+(it.status==='done'?' dim':'');
    const statEl=row.querySelector('.dl-stat');
    statEl.className='dl-stat '+dlStatClass(it.status);
    statEl.textContent=it.status==='failed'?it.error:(DL_STAT_TXT[it.status]||'');
    const actSpan=row.querySelector('span:last-child');
    actSpan.innerHTML='';
    if(it.status==='failed'){
      const btn=document.createElement('button');btn.className='btn btn-err btn-sm';btn.textContent='重试';
      btn.onclick=()=>retryItem(it.id);
      actSpan.appendChild(btn);
    }
    if(it.status==='downloading')row.scrollIntoView({block:'nearest',behavior:'smooth'});
  });updateDLSummary(items);
}
function updateDLSummary(items){
  const dl=items.filter(i=>i.status==='downloading').length;
  const ok=items.filter(i=>i.status==='done').length;
  const fail=items.filter(i=>i.status==='failed').length;
  const pend=items.filter(i=>i.status==='pending').length;
  document.getElementById('dl-total').textContent='共 '+items.length+' 项';
  document.getElementById('dl-cnt-dl').innerHTML='<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg> '+dl;
  document.getElementById('dl-cnt-ok').innerHTML='<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg> '+ok;
  document.getElementById('dl-cnt-err').innerHTML='<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg> '+fail;
  document.getElementById('dl-cnt-pnd').innerHTML='<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg> '+pend;
}
async function retryAll(){
  document.getElementById('retry-all-btn').disabled=true;
  const r=JSON.parse(await pywebview.api.retry_failed());
  if(!r.ok){toast(r.error,'err');document.getElementById('retry-all-btn').disabled=false;return;}
  if(r.count===0){toast('没有失败的项目','info');document.getElementById('retry-all-btn').disabled=false;return;}
  S.dlRendered=false;toast('重试 '+r.count+' 个失败项','info');startPoll();
  document.getElementById('retry-all-btn').disabled=false;
}
async function retryItem(id){
  const btn=document.querySelector('.dlrow[data-id="'+id+'"] .btn-err');if(btn)btn.disabled=true;
  const r=JSON.parse(await pywebview.api.retry_item(id));
  if(!r.ok){toast(r.error,'err');if(btn)btn.disabled=false;return;}startPoll();
}
async function clearDLList(){
  const r=JSON.parse(await pywebview.api.clear_download_list());
  if(!r.ok){toast(r.error,'err');return;}
  S.dlRendered=false;document.getElementById('dllist').innerHTML=
    '<div class="empty"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg><div>等待下载...</div></div>';
  updateDLSummary([]);setStat('就绪');setDot('idle');
  document.getElementById('dock-progress-fill').style.width='0%';
}

async function browseDir(){
  const d=await pywebview.api.choose_directory();
  if(d){S.saveDir=d;document.getElementById('dir-disp').textContent=d;document.getElementById('dir-disp-batch').textContent=d;autoSaveSettings();}
}
function openDir(){if(S.saveDir)pywebview.api.open_folder(S.saveDir);}

function setStat(msg){const el=document.getElementById('hdr-st');if(el)el.textContent=msg;}
function setDot(s){const d=document.getElementById('hdr-dot');if(d){d.className='topbar-dot '+s;}}
function setBusy(id,html,dis,cls){const b=document.getElementById(id);if(!b)return;b.innerHTML=html;b.disabled=dis;if(cls)b.className='btn '+cls;}
function syncCB(el){const p=el.closest('.cbitem');if(p)p.classList.toggle('on',el.checked);}
function syncMS(el){el.closest('.chk-label').style.color=el.checked?'var(--text2)':'var(--err)';}
function toast(msg,type){
  const el=document.createElement('div');el.className='toast '+(type||'info');
  const ico={ok:'<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>',err:'<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>',warn:'<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>',info:'<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>'}[type]||'';
  el.innerHTML='<span style="font-weight:700">'+ico+'</span><span></span>';
  el.querySelector('span:last-child').textContent=msg;
  document.getElementById('toasts').appendChild(el);
  setTimeout(()=>el.style.opacity='0',3500);setTimeout(()=>el.remove(),3800);
}

async function openPreview(filename){
  if(!filename)return;
  const panel=document.getElementById('preview-panel');
  const iframe=document.getElementById('preview-iframe');
  const empty=document.getElementById('preview-empty');
  const title=document.getElementById('preview-title');
  title.textContent=filename.replace('.pdf','');
  panel.classList.add('on');
  empty.style.display='none';
  iframe.style.display='block';
  const loading=document.createElement('div');loading.className='preview-loading';
  loading.innerHTML='<span class="spin"></span>';
  document.getElementById('preview-body').appendChild(loading);
  try{
    const r=JSON.parse(await pywebview.api.get_pdf_url(filename));
    if(!r.ok)throw new Error(r.error);
    iframe.src=r.url;
    iframe.onload=()=>{if(loading.parentNode)loading.remove();};
    setTimeout(()=>{if(loading.parentNode)loading.remove();},8000);
  }catch(e){
    if(loading.parentNode)loading.remove();
    toast('预览失败: '+e.message,'err');
    closePreview();
  }
}
function closePreview(){
  const panel=document.getElementById('preview-panel');
  const iframe=document.getElementById('preview-iframe');
  const empty=document.getElementById('preview-empty');
  const title=document.getElementById('preview-title');
  panel.classList.remove('on');
  iframe.style.display='none';iframe.src='';
  empty.style.display='';title.textContent='PDF 预览';
}

async function loadPlugins(){
  const el=document.getElementById('plugin-list');
  if(!el)return;
  try{
    const r=JSON.parse(await pywebview.api.get_plugins());
    if(!r.ok){el.innerHTML='<div style="font-size:11px;color:var(--text3)">无法加载插件列表</div>';return;}
    renderPlugins(r.plugins);
  }catch(e){
    el.innerHTML='<div style="font-size:11px;color:var(--er)">插件加载失败</div>';
  }
}

function renderPlugins(plugins){
  const el=document.getElementById('plugin-list');
  if(!el) return;
  if(!plugins||!plugins.length){
    el.innerHTML='<div style="font-size:11px;color:var(--text3)">暂未安装插件</div>';
    return;
  }
  el.innerHTML='';
  plugins.forEach(p=>{
    const card=document.createElement('div');
    card.style.cssText='border:1px solid var(--border);border-radius:8px;padding:10px;display:flex;flex-direction:column;gap:4px';
    card.innerHTML=`
      <div style="display:flex;align-items:center;gap:8px">
        <input type="checkbox" ${p.enabled?'checked':''} onchange="togglePlugin('${esc(p.id)}',this.checked)" style="width:14px;height:14px">
        <span style="font-size:12px;font-weight:600;color:var(--text)">${esc(p.name)}</span>
        <span style="font-size:9px;color:var(--text3);margin-left:auto">v${esc(p.version)}</span>
      </div>
      <div style="font-size:10px;color:var(--text2);padding-left:22px">${esc(p.description||'')}</div>
      <div style="font-size:9px;color:var(--text3);padding-left:22px">Hooks: ${p.hooks.map(esc).join(', ')}</div>
    `;
    el.appendChild(card);
  });
}

async function togglePlugin(pluginId,enabled){
  try{
    const r=JSON.parse(await pywebview.api.toggle_plugin(pluginId,JSON.stringify(enabled)));
    if(!r.ok) toast('插件状态切换失败','err');
  }catch(e){ toast('插件状态切换失败: '+e.message,'err'); }
}

async function openPluginsDir(){
  await pywebview.api.open_plugins_dir();
}

let _updateUrl = '';
let _updateVersion = '';

async function checkUpdate(force=false){
  try{
    const r = JSON.parse(await pywebview.api.check_update(force ? 'true' : 'false'));
    if(!r.ok || !r.has_update) return;
    _updateUrl = r.download_url || '';
    _updateVersion = r.latest_version || '';
    document.getElementById('update-ver').textContent = 'v' + _updateVersion;
    document.getElementById('update-notes').textContent = r.release_notes || '';
    document.getElementById('update-toast').style.display = '';
  }catch(e){}
}

async function openUpdateUrl(){
  if(_updateUrl){
    try{
      await pywebview.api.open_url(_updateUrl);
    }catch(e){
      return; // Don't dismiss on error, user can retry
    }
  }
  dismissUpdate();
}

async function skipThisVersion(){
  if(_updateVersion){
    await pywebview.api.skip_version(_updateVersion);
  }
  dismissUpdate();
}

function dismissUpdate(){
  document.getElementById('update-toast').style.display = 'none';
}

async function toggleAutoUpdate(enabled){
  try{
    await pywebview.api.set_update_check(JSON.stringify(enabled));
  }catch(e){}
}