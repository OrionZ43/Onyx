/* Задача #40: несколько источников (подписки и ссылки), группы, фильтры. Тема Onyx (A2).
   d=a2s&s=sources|groups|add|grpedit */
const SRC_LIST = [
  {name:'zieng2', kind:'Подписка', meta:'встроенная', nodes:24, alive:21, status:'обновлено 2 мин назад', on:true, cc:'', preset:true},
  {name:'Бесплатные (Китай)', kind:'Подписка', meta:'встроенная · бесплатные, нестабильные', nodes:38, alive:17, status:'обновляется…', on:true, cc:'cn', busy:true, preset:true},
  {name:'Мой VPS', kind:'Ссылки', meta:'3 ссылки · vless, hysteria2', nodes:3, alive:3, status:'проверено 1 ч назад', on:true, cc:'nl'},
  {name:'Рабочая подписка', kind:'Подписка', meta:'sub.example.com', nodes:12, alive:0, status:'ошибка: 403', on:false, cc:'', err:true},
];
const GROUPS = [
  {name:'Все', n:77, sel:true}, {name:'★ Избранное', n:4}, {name:'Игры', n:6}, {name:'Работа', n:9},
];
const icx = (n, s, c) => `<span class="ic" style="--src:url(icons/phosphor/${n}.svg);--is:${s}px;color:${c}"></span>`;
const flagRoundX = (cc, size) => cc ? flagRound(cc, size) : `<span class="flagr" style="width:${size}px;height:${size}px;background:#131316;display:inline-flex;align-items:center;justify-content:center">${icx('globe', size*.5, '#57554F')}</span>`;

const A2S = Object.assign({}, A2, {
css: A2.css + `
.flagr{display:inline-block;flex:none;border-radius:50%;background-size:cover;background-position:center;position:relative;filter:saturate(.88);box-shadow:0 0 0 1px rgba(255,255,255,.14),0 2px 6px rgba(0,0,0,.5)}
.appbar{height:56px;padding:0 14px 0 8px;display:flex;align-items:center;gap:6px}
.appbar .t{font:400 20px var(--fd);letter-spacing:-.02em;flex:1}
.src{border:1px solid var(--line);background:var(--s1);border-radius:18px;padding:14px 14px 12px 16px;display:flex;gap:14px;align-items:flex-start}
.src.off{opacity:.55}
.src .n{font:500 15px var(--ff)} .src .m{font:400 12px var(--ff);color:var(--t2);margin-top:2px}
.src .st{font:500 10.5px var(--fd);letter-spacing:.16em;text-transform:uppercase;color:var(--t3);margin-top:8px;display:flex;gap:6px;align-items:center}
.src .st b{width:5px;height:5px;border-radius:3px;background:var(--acc)}
.src .st.err{color:#C8655A}.src .st.err b{background:#C8655A}
.kind{font:600 9px var(--fd);letter-spacing:.14em;text-transform:uppercase;color:var(--t2);border:1px solid var(--line2);border-radius:6px;padding:2px 5px}
.bar{height:2px;border-radius:1px;background:#1F1F23;margin-top:8px;overflow:hidden}.bar i{display:block;height:100%;background:var(--acc)}
.addbar{display:flex;gap:8px}
.addbtn{flex:1;display:flex;align-items:center;justify-content:center;gap:8px;height:44px;border-radius:22px;border:1px solid var(--line);font:500 13px var(--ff);color:var(--t1)}
.addbtn.pri{background:var(--t1);color:#050506;border-color:var(--t1)}
.preset{border:1px dashed #3A3326;border-radius:18px;padding:12px 14px;display:flex;gap:12px;align-items:center}
.gtabs{display:flex;gap:6px;padding:0 20px;overflow:hidden}
.gtab{padding:7px 14px;border-radius:16px;border:1px solid var(--line);font:500 12.5px var(--ff);color:var(--t2);white-space:nowrap;display:flex;gap:6px;align-items:center}
.gtab small{font:500 11px var(--fd);color:var(--t3)}
.gtab.on{background:var(--t1);color:#050506;border-color:var(--t1)}.gtab.on small{color:#57554F}
.ftabs{display:flex;gap:6px;padding:10px 20px 0}
.ftab{display:flex;gap:6px;align-items:center;font:500 10.5px var(--fd);letter-spacing:.16em;text-transform:uppercase;color:var(--t3);border:1px solid var(--line);border-radius:14px;padding:6px 10px}
.ftab.on{color:var(--acc);border-color:#3A3326}
.star{color:var(--acc)}
.drag{color:#3A3A40;font:400 14px var(--ff);letter-spacing:-2px;margin-left:4px}
.fieldx{background:var(--bg);border:1px solid var(--line);border-radius:18px;padding:14px 16px;font:400 13px/1.55 'JetBrains Mono',monospace;color:var(--t2);min-height:120px}
.seg2{display:flex;padding:3px;border-radius:12px;border:1px solid var(--line);background:var(--bg)}
.seg2 span{flex:1;text-align:center;padding:8px 0;border-radius:9px;font:500 13px var(--ff);color:var(--t2)}
.seg2 span.on{background:var(--s3);color:var(--t1);border:1px solid var(--line2)}
`,
sources() {
  return `<div class="screen">${statusBar()}
   <div class="appbar"><span class="iconbtn" style="border:0">${icx('back',20,'var(--t1)')}</span><span class="t">Подписки и серверы</span><span class="iconbtn">${icx('refresh',16,'var(--t2)')}</span></div>
   <div style="padding:6px 20px 0;display:flex;flex-direction:column;gap:10px">
    <div class="addbar"><span class="addbtn pri">${icx('plus',16,'#050506')}Подписка</span><span class="addbtn">${icx('link',16,'var(--t1)')}Ссылки</span><span class="addbtn" style="flex:0 0 44px;padding:0">${icx('qr',16,'var(--t1)')}</span></div>
    <div class="gh row" style="padding:10px 0 0"><span>Источники · 4</span><span>77 серверов</span></div>
    ${SRC_LIST.map(s => `<div class="src ${s.on?'':'off'}">${flagRoundX(s.cc, 34)}
      <div class="grow"><div class="row" style="gap:8px"><span class="n">${s.name}</span><span class="kind">${s.kind}</span></div>
       <div class="m">${s.meta}</div>
       ${s.busy ? `<div class="bar"><i style="width:46%"></i></div>` : ''}
       <div class="st ${s.err?'err':''}"><b></b>${s.err ? s.status : `${s.alive} из ${s.nodes} работают · ${s.status}`}</div></div>
      <div class="col" style="align-items:flex-end;gap:14px"><div class="sw ${s.on?'on':''}"></div>${icx('more',16,'var(--t3)')}</div></div>`).join('')}
    <div class="gh row" style="padding:10px 0 0"><span>Встроенные</span><span></span></div>
    <div class="preset">${flagRoundX('', 30)}<div class="grow"><div class="n" style="font:500 14px var(--ff)">zieng2 · тестовые</div><div class="m" style="font:400 12px var(--ff);color:var(--t2)">уже добавлен</div></div>${icx('check',16,'var(--acc)')}</div>
   </div></div><div class="homebar"></div>`;
},
groupsSheet() {
  const rows = [
    {cc:'NL', city:'Амстердам AMS-03', ping:38, ai:true, udp:true, fav:true, sel:true},
    {cc:'FI', city:'Хельсинки HEL-02', ping:29, ai:true, udp:true, proto:'HY2', fav:true},
    {cc:'DE', city:'Франкфурт FRA-01', ping:41, ai:true},
    {cc:'SE', city:'Стокгольм STO-01', ping:47, udp:true, proto:'TUIC'},
  ];
  const row = (r) => `<div class="it row ${r.sel?'sel':''}">${flagRound(r.cc, 30)}<div class="grow"><div class="n">${r.city}</div></div>
     ${r.proto?`<span class="kind" style="font-size:8.5px">${r.proto}</span>`:''}${r.udp?icx('voice',14,'var(--acc)'):''}${r.ai?'<span class="ai">AI</span>':''}
     <span class="ping" style="width:44px;text-align:right">${r.ping}<small>мс</small></span>${r.fav?icx('star',14,'var(--acc)'):icx('star',14,'#2E2E33')}</div>`;
  return `<div class="screen">${statusBar()}<div class="top row"><span class="word">ONYX</span></div></div><div class="dim"></div>
   <div class="sheet"><div class="grab"></div>
    <div class="sh-h row"><div class="t">Серверы</div><div class="row" style="gap:8px"><div class="iconbtn">${icx('sliders',16,'var(--t2)')}</div><div class="iconbtn">${icx('plus',16,'var(--t2)')}</div></div></div>
    <div class="gtabs">${GROUPS.map(g => `<span class="gtab ${g.sel?'on':''}">${g.name}<small>${g.n}</small></span>`).join('')}<span class="gtab">${icx('plus',12,'var(--t2)')}</span></div>
    <div class="ftabs"><span class="ftab on">${icx('voice',11,'var(--acc)')}Голос</span><span class="ftab">AI</span><span class="ftab">Страны ▾</span></div>
    <div class="search" style="margin-top:12px">${icx('search',16,'var(--t3)')}Страна, город или сервер</div>
    <div class="list">
     <div class="auto row"><div class="cc" style="color:var(--acc);border-color:#3A3326">${icx('zap',15,'var(--acc)')}</div>
      <div class="grow"><div class="n" style="font:500 14.5px var(--ff)">Автовыбор</div><div class="m" style="font:400 12px var(--ff);color:var(--t2)">из группы «Все» · лучший по пингу и AI</div></div><div class="sw on"></div></div>
     <div class="gh row"><span>Избранное</span><span>2</span></div>${rows.filter(r=>r.fav).map(row).join('')}
     <div class="gh row"><span>Германия · zieng2</span><span>1</span></div>${row(rows[2])}
     <div class="gh row"><span>Швеция · Мой VPS</span><span>1</span></div>${row(rows[3])}
    </div>
    <div class="foot row"><span>77 серверов · 4 источника</span><span class="row" style="gap:6px">${icx('sliders',13,'var(--t2)')}Подписки и серверы</span></div>
   </div><div class="homebar"></div>`;
},
addSheet() {
  return `<div class="screen">${statusBar()}<div class="top row"><span class="word">ONYX</span></div></div><div class="dim"></div>
   <div class="sheet" style="top:210px"><div class="grab"></div>
    <div class="sh-h row"><div class="t">Добавить</div></div>
    <div style="padding:0 20px;display:flex;flex-direction:column;gap:12px">
     <div class="seg2"><span>Подписка</span><span class="on">Ссылки</span><span>QR</span></div>
     <div class="fieldx">vless://8f1c…@203.0.113.7:443?security=reality…#Мой VPS<br>hysteria2://k3y@203.0.113.7:8443?sni=…#VPS HY2<br>tuic://…</div>
     <div class="m" style="font:400 12px var(--ff);color:var(--t2)">Распознано 3 ссылки: VLESS, Hysteria2, TUIC. Можно вставить и base64.</div>
     <div class="search" style="margin:0">${icx('link',16,'var(--t3)')}<span style="color:var(--t1)">Мой VPS</span></div>
     <div class="row" style="gap:8px"><span class="addbtn">${icx('paste',16,'var(--t1)')}Из буфера</span><span class="addbtn pri">Добавить источник</span></div>
     <div class="gh row" style="padding:10px 0 0"><span>Встроенные</span><span></span></div>
     <div class="preset">${flagRound('cn', 30)}<div class="grow"><div class="n" style="font:500 14px var(--ff)">Бесплатные (Китай)</div><div class="m" style="font:400 12px var(--ff);color:var(--t2)">бесплатные, нестабильные · добавится к вашим</div></div>${icx('plus',16,'var(--t2)')}</div>
    </div></div><div class="homebar"></div>`;
},
groupEdit() {
  const items = [['Амстердам AMS-03','NL'],['Хельсинки HEL-02','FI'],['Франкфурт FRA-01','DE']];
  return `<div class="screen">${statusBar()}
   <div class="appbar"><span class="iconbtn" style="border:0">${icx('back',20,'var(--t1)')}</span><span class="t">Группы</span><span class="iconbtn">${icx('plus',16,'var(--t2)')}</span></div>
   <div style="padding:6px 20px 0;display:flex;flex-direction:column;gap:10px">
    ${[['Все','весь список · нельзя удалить',77,true],['Избранное','звёздочки в списке',4],['Игры','2 источника + 1 сервер',6],['Работа','источник «Рабочая подписка»',9]].map(([n,m,c,fix]) => `<div class="src">
      <span class="drag">${fix?'':'⋮⋮'}</span><div class="grow"><div class="row" style="gap:8px"><span class="n">${n}</span><span class="kind">${c}</span></div><div class="m">${m}</div></div>${fix?'':icx('more',16,'var(--t3)')}</div>`).join('')}
    <div class="gh row" style="padding:10px 0 0"><span>Игры · состав</span><span>перетащите, чтобы изменить порядок</span></div>
    <div class="src" style="flex-direction:column;gap:0;padding:6px 0">
     <div class="it row" style="padding:10px 16px"><span class="kind">Источник</span><span class="grow n" style="font:400 14px var(--ff)">Мой VPS</span>${icx('close',14,'var(--t3)')}</div>
     ${items.map(([n,c]) => `<div class="it row" style="padding:10px 16px">${flagRound(c,26)}<span class="grow n" style="font:400 14px var(--ff)">${n}</span>${icx('close',14,'var(--t3)')}</div>`).join('')}
     <div class="it row" style="padding:10px 16px;color:var(--acc);font:500 13px var(--ff);gap:8px">${icx('plus',14,'var(--acc)')}Добавить серверы или источник</div>
    </div>
    <div class="auto row" style="margin:4px 0 0"><div class="grow"><div class="n" style="font:500 14px var(--ff)">Автовыбор из этой группы</div><div class="m" style="font:400 12px var(--ff);color:var(--t2)">кнопка подключения берёт лучший сервер группы</div></div><div class="sw"></div></div>
   </div></div><div class="homebar"></div>`;
},
phone() {
  return S === 'sources' ? A2S.sources() : S === 'groups' ? A2S.groupsSheet() : S === 'add' ? A2S.addSheet() : A2S.groupEdit();
},
});
