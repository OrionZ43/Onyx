/* Расширение мокапов (задача #33): доведённый Signal (c2), Material 3 Expressive (m3),
   листы фирменных деталей (v=det) для a2 / c2 / m3. Подключается после mock.html,
   использует его глобальные помощники (ic, dots, statusBar, winButtons, SERVERS, groups, A, A2, C). */

const lc = (cc) => cc.toLowerCase();

/* ── флаги ───────────────────────────────────────────────────────────── */
// Onyx: круглый флаг (circle-flags, MIT) с тонким светлым ободком и бликом.
const flagRound = (cc, size = 30) =>
  `<span class="flagr" style="width:${size}px;height:${size}px;background-image:url(flags/circle/${lc(cc)}.svg)"></span>`;
// Signal: флаг точечной матрицей, монохром; канвас дорисовывается в after().
const flagDots = (cc, cols = 8, rows = 6, d = 3, gap = 1.6, sel = false) =>
  `<canvas class="fd" data-cc="${lc(cc)}" data-cols="${cols}" data-rows="${rows}" data-d="${d}" data-gap="${gap}" data-sel="${sel?1:0}"
     width="${Math.ceil((cols*(d+gap)-gap)*2)}" height="${Math.ceil((rows*(d+gap)-gap)*2)}"
     style="width:${cols*(d+gap)-gap}px;height:${rows*(d+gap)-gap}px;flex:none"></canvas>`;
function paintDotFlags() {
  document.querySelectorAll('canvas.fd').forEach(cv => {
    const {cc, cols, rows, d, gap, sel} = cv.dataset;
    const C_ = +cols, R_ = +rows, D_ = +d, G_ = +gap;
    const img = new Image();
    img.onload = () => {
      const off = document.createElement('canvas'); off.width = C_; off.height = R_;
      const o = off.getContext('2d');
      // квадратный флаг -> берём центральную полосу 4:3
      const S_ = 64, big = document.createElement("canvas"); big.width = S_; big.height = S_;
      big.getContext("2d").drawImage(img, 0, 0, S_, S_);
      o.imageSmoothingQuality = "high"; o.drawImage(big, 0, S_ * .125, S_, S_ * .75, 0, 0, C_, R_);
      let px; try { px = o.getImageData(0, 0, C_, R_).data; } catch (e) { px = null; }
      const g = cv.getContext('2d'); g.scale(2, 2);
      for (let y = 0; y < R_; y++) for (let x = 0; x < C_; x++) {
        let col = '#3a3a3a';
        if (px) {
          const i = (y*C_ + x) * 4, L = (0.2126*px[i] + 0.7152*px[i+1] + 0.0722*px[i+2]) / 255;
          col = L > .8 ? '#FFFFFF' : L > .5 ? '#A8A8A8' : L > .25 ? '#5E5E5E' : '#262626';
        }
        g.fillStyle = col; g.beginPath();
        g.arc(x*(D_+G_) + D_/2, y*(D_+G_) + D_/2, D_/2, 0, Math.PI*2); g.fill();
      }
    };
    img.src = FLAG_DATA[cc];
  });
}

/* ── M3: формы (приближение MaterialShapes полярной функцией) ─────────── */
function polar(n, depth, R, cx, cy, rot = 0, steps = 240) {
  let p = '';
  for (let i = 0; i <= steps; i++) {
    const t = i / steps * Math.PI * 2;
    const r = R * (1 - depth * (0.5 - 0.5 * Math.cos(n * t)));
    const a = t + rot * Math.PI / 180 - Math.PI / 2;
    p += (i ? 'L' : 'M') + (cx + Math.cos(a) * r).toFixed(2) + ' ' + (cy + Math.sin(a) * r).toFixed(2);
  }
  return p + 'Z';
}
const SHAPES = {               // имя -> [лепестки, глубина]  (как в MaterialShapes)
  cookie9: [9, .085], cookie12: [12, .07], cookie4: [4, .16], clover4: [4, .32], clover8: [8, .2],
  sunny: [8, .1], burst: [12, .16], flower: [8, .26], pent: [5, .12], circle: [0, 0], puffy: [6, .22],
};
const shapePath = (name, size, rot = 0) => { const [n, dp] = SHAPES[name]; return polar(n, dp, size/2, size/2, size/2, rot); };
let _sid = 0;
const flagShape = (cc, size, shape = 'cookie4', rot = 0) => {
  const id = 'fs' + (_sid++);
  return `<svg width="${size}" height="${size}" style="flex:none"><defs><clipPath id="${id}"><path d="${shapePath(shape, size, rot)}"/></clipPath></defs>
    <image href="flags/square/${lc(cc)}.svg" x="${-size*.15}" y="${-size*.15}" width="${size*1.3}" height="${size*1.3}" preserveAspectRatio="xMidYMid slice" clip-path="url(#${id})"/></svg>`;
};
const COUNTRY_SHAPE = {NL:'cookie4', FI:'clover4', DE:'pent', SE:'sunny', PL:'cookie9', US:'flower', JP:'burst', GB:'puffy', FR:'cookie12', CH:'clover8'};

/* ═════════════════════════ C2 · SIGNAL (доведённый) ═════════════════════════ */
const C2 = Object.assign({}, C, {
css: C.css + `
.app{--err:#FF3B2F}
.ing .rec b{background:#fff;box-shadow:0 0 10px rgba(255,255,255,.6)}
.sub{font:500 10.5px var(--fm);letter-spacing:.1em;text-transform:uppercase;color:var(--t3);margin-top:8px;text-align:center}
.err .sub{color:#B0B0B0}
.toast{gap:10px;padding:10px 16px;border-radius:22px;background:var(--s2);font:500 10.5px var(--fm);letter-spacing:.1em;text-transform:uppercase;color:var(--t1)}
.toast b{width:6px;height:6px;border-radius:3px;background:var(--acc)}
.det-grid{position:absolute;inset:40px 0 0 0;padding:28px 32px;display:grid;grid-template-columns:1fr 1fr 1fr;gap:16px}
.box{background:var(--s1);border-radius:24px;padding:20px;display:flex;flex-direction:column;gap:14px;overflow:hidden}
.box h4{font:500 10.5px var(--fm);letter-spacing:.14em;text-transform:uppercase;color:var(--t3)}
`,
ring(R) {
  const n = 64, r = R/2 - 8, out = [], lit = Math.round(n * .62);
  for (let i = 0; i < n; i++) {
    const a = i/n*Math.PI*2 - Math.PI/2;
    let col, rad = 3;
    if (ON) { col = i === 0 ? '#FF3B2F' : '#FFFFFF'; if (i === 0) rad = 4.2; }
    else if (ING) { if (i < lit) { const k = 0.25 + 0.75 * (i / lit); col = `rgba(255,255,255,${k.toFixed(2)})`; if (i === lit-1) rad = 3.8; } else col = '#1C1C1C'; }
    else if (ERR) { col = (i <= 1 || i >= n-1) ? '#FF3B2F' : '#1C1C1C'; }
    else col = i % 8 === 0 ? '#3A3A3A' : '#1E1E1E';
    out.push(`<circle cx="${R/2+Math.cos(a)*r}" cy="${R/2+Math.sin(a)*r}" r="${rad}" fill="${col}"/>`);
  }
  const r2 = r - 20;
  for (let i = 0; i < 96; i++) { const a = i/96*Math.PI*2; out.push(`<circle cx="${R/2+Math.cos(a)*r2}" cy="${R/2+Math.sin(a)*r2}" r="1" fill="${ON?'#3A3A3A':'#171717'}"/>`); }
  const d = R*.0175, g = R*.0068;
  const inner = ON ? dots('01:24', d, g, '#fff', '#141414') : ING ? dots('62', d*1.25, g*1.25, '#fff', '#141414')
    : ERR ? dots('ERR', d, g, '#FF3B2F', '#161010') : dots('--:--', d, g, '#5a5a5a', '#121212');
  const cap = ON ? 'нажми — отключить' : ING ? 'туннель · 62%' : ERR ? 'нажми — повторить' : 'нажми — подключить';
  return `<div class="ring" style="--R:${R}px"><svg width="${R}" height="${R}">${out.join('')}</svg>
   <div class="c">${inner}<span class="cap" style="color:${ON||ERR?'var(--t1)':'var(--t2)'}">${cap}</span></div></div>`;
},
status() {
  if (ON) return `<div class="col" style="align-items:center"><div class="row rec"><b></b><span class="cap" style="color:var(--t1)">Защита активна</span></div></div>`;
  if (ING) return `<div class="col" style="align-items:center"><div class="row rec"><b></b><span class="cap" style="color:var(--t1)">Подключение</span></div><div class="sub">AMS-03 · рукопожатие REALITY</div></div>`;
  if (ERR) return `<div class="col" style="align-items:center"><div class="row rec"><b></b><span class="cap" style="color:var(--err)">Нет соединения</span></div><div class="sub">AMS-03 молчит → пробую HEL-02</div></div>`;
  return `<div class="col" style="align-items:center"><div class="row rec"><b style="background:var(--t3);box-shadow:none"></b><span class="cap">Не защищено</span></div></div>`;
},
server() {
  return `<div class="card srv row">${flagDots('NL', 8, 6, 3, 1.6)}<div class="grow"><div class="n">Амстердам</div><div class="m cap" style="font-size:10.5px;color:var(--t3)">AMS-03 · авто</div></div>
   <span class="ai">AI</span><span class="ping">38MS</span><span class="t2">${ic('chev',18)}</span></div>`;
},
item(s) {
  const n = s.ping < 50 ? 4 : s.ping < 80 ? 3 : s.ping < 150 ? 2 : 1;
  return `<div class="it row ${s.sel?'sel':''}"><span class="dotsel"></span>${flagDots(s.cc, 7, 5, 2.6, 1.4)}
   <span class="grow">${s.city}<span class="id">${s.id}</span></span>${s.ai?'<span class="ai">AI</span>':''}
   <span class="ping" style="width:40px;text-align:right">${s.ping}</span><span class="row pdots">${[0,1,2,3].map(i=>`<i class="${i<n?'l':''}"></i>`).join('')}</span></div>`;
},
list() {
  return `<div class="sh-h row"><span style="font:500 28px var(--ff);letter-spacing:-.03em">Серверы</span><div class="row" style="gap:8px"><div class="iconbtn">${ic('refresh',18)}</div><div class="iconbtn">${ic('plus',18)}</div></div></div>
   <div class="search row">${ic('search',18)}Поиск</div>
   <div class="row chips"><span class="on">Все 10</span><span>AI 6</span><span>★ 2</span></div>
   <div class="list"><div class="auto row">${ic('zap',20)}<div class="grow"><div style="font:500 15px var(--ff)">Автовыбор</div><div class="cap" style="font-size:10px;color:var(--t3);margin-top:3px">пинг + AI-проба</div></div><div class="sw on"></div></div>
    ${groups.map(g => `<div class="gh row cap" style="justify-content:space-between;color:var(--t3)"><span>${g.country}</span><span>${String(g.items.length).padStart(2,'0')}</span></div>${g.items.map(C2.item).join('')}`).join('')}</div>
   <div class="foot row cap" style="font-size:10px;color:var(--t3)"><span>+ Подписка</span><span>Проверено 2 мин</span></div>`;
},
glyphs() {
  const g = (t, on) => `<div class="row glyph ${on?'on':''}"><span class="cap" style="font-size:10px;color:${on?'var(--t1)':'var(--t3)'}">${t}</span><i></i></div>`;
  return `<div class="row glyphs">${g('Авто',true)}${g('AI',true)}${g('Kill',ON)}</div>`;
},
phone() {
  const top = `<div class="top row"><span class="word">ONYX</span><div class="iconbtn">${ic('more',18)}</div></div>`;
  if (S === 'list') return `<div class="screen">${statusBar()}${top}</div><div class="dim"></div><div class="sheet">${C2.list()}</div><div class="homebar"></div>`;
  return `<div class="screen">${statusBar()}${top}
   <div class="main"><div style="height:26px"></div>${C2.status()}<div style="flex:1"></div>${C2.ring(286)}<div style="flex:1"></div>
   ${ON?C.tiles()+'<div style="height:8px"></div>':''}${C2.server()}<div style="height:8px"></div>${C2.glyphs()}<div style="height:32px"></div></div></div><div class="homebar"></div>`;
},
desk() {
  const right = `${C2.server()}${ON?C.tiles():`<div class="blk"><span class="cap" style="color:var(--t3)">Сессия</span><div style="margin-top:10px">${dots('--', 5, 2, '#444', '#111')}</div></div>`}
    <div class="blk" style="flex:1"><span class="cap" style="color:var(--t3)">Защита</span>
     <div class="tg row" style="margin-top:6px">Автопереключение<div class="sw on"></div></div>
     <div class="tg row">AI Direct Lane<div class="sw on"></div></div>
     <div class="tg row">Раздельный туннель<span class="cap">4 ПРИЛ. ›</span></div></div>`;
  return `<div class="titlebar row"><span class="word">ONYX</span><div class="row"><span class="row cap" style="gap:8px;font-size:10px;color:var(--t3);margin-right:10px">Команды <span style="background:var(--s2);padding:3px 7px;border-radius:6px;color:var(--t2)">CTRL K</span></span><div class="winbtn">${ic('more',16)}</div>${winButtons()}</div></div>
   <div class="body"><div class="left">${C2.status()}<div style="height:30px"></div>${C2.ring(340)}<div style="height:30px"></div><div style="width:400px">${C2.glyphs()}</div>
    ${ON?`<div class="row toast" style="position:absolute;bottom:22px"><b></b>Автопереключение · AMS-01 → AMS-03 · 112 → 38 MS</div>`:''}</div>
   <div class="right">${right}</div></div>`;
},
det() {
  const flags = ['NL','DE','FI','SE','PL','US','JP','GB','FR','CH','KZ','TR'];
  const ping = [4,3,2,1].map(n => `<div class="row" style="gap:10px"><span class="row pdots">${[0,1,2,3].map(i=>`<i class="${i<n?'l':''}" style="width:6px;height:6px;border-radius:3px"></i>`).join('')}</span><span class="ping">${[29,63,118,212][4-n]} MS</span></div>`).join('');
  const icon = (sz) => { const R = sz, out = []; for (let i = 0; i < 28; i++) { const a = i/28*Math.PI*2 - Math.PI/2; out.push(`<circle cx="${R/2+Math.cos(a)*R*.3}" cy="${R/2+Math.sin(a)*R*.3}" r="${R*.028}" fill="${i===0?'#FF3B2F':'#fff'}"/>`); }
    return `<div style="width:${R}px;height:${R}px;border-radius:${R*.23}px;background:#000;box-shadow:0 0 0 1px #2a2a2a"><svg width="${R}" height="${R}">${out.join('')}</svg></div>`; };
  return `<div class="titlebar row"><span class="word">ONYX · SIGNAL — ФИРМЕННЫЕ ДЕТАЛИ</span>${winButtons()}</div>
  <div class="det-grid">
   <div class="box"><h4>Флаги — точечная матрица, монохром</h4><div style="display:grid;grid-template-columns:repeat(4,1fr);gap:14px 10px">${flags.map(f=>`<div class="col" style="gap:6px;align-items:flex-start">${flagDots(f, 10, 7, 4, 2)}<span class="cap" style="font-size:9.5px;color:var(--t3)">${f}</span></div>`).join('')}</div>
     <span class="cap" style="font-size:9.5px;color:var(--t3);line-height:1.6">SVG flag-icons (MIT) → 10×7 выборка яркости → 4 уровня белого</span></div>
   <div class="box"><h4>Пинг · AI · выбор</h4>${ping}<div class="row" style="gap:10px"><span class="ai">AI</span><span class="cap" style="font-size:10px">прошёл AI-пробу</span></div>
     <div class="row" style="gap:10px"><span class="dotsel" style="width:8px;height:8px;border-radius:4px;background:var(--acc)"></span><span class="cap" style="font-size:10px">выбранный сервер — красная точка</span></div>
     <h4 style="margin-top:6px">Тост автопереключения</h4><div class="row toast" style="align-self:flex-start"><b></b>AMS-01 → HEL-02 · 112 → 29 MS</div></div>
   <div class="box"><h4>Иконка и сплэш</h4><div class="row" style="gap:16px;align-items:flex-end">${icon(96)}${icon(56)}${icon(32)}</div>
     <span class="cap" style="font-size:9.5px;color:var(--t3);line-height:1.6">сплэш: кольцо точек загорается по кругу за 600 мс, потом гаснет в главный экран</span>
     <h4 style="margin-top:6px">Хаптика (Android)</h4><span class="cap" style="font-size:10px;line-height:1.7;color:var(--t2)">нажатие — clock tick<br>каждые 8 точек при подключении — тик<br>подключено — confirm · ошибка — reject</span></div>
   <div class="box" style="grid-column:span 2"><h4>Импорт подписки — пустое состояние</h4>
     <div class="row" style="gap:28px;align-items:center"><div>${dots('+', 10, 4, '#fff', '#141414')}</div>
      <div class="col grow" style="gap:12px"><div style="font:500 22px var(--ff);letter-spacing:-.02em">Нет серверов</div><div class="t2" style="font:400 14px var(--ff)">Вставьте ссылку на подписку — Onyx проверит серверы и выберет лучший.</div>
       <div class="search row" style="margin:0">${ic('link',18)}<span>vless://… или https://…</span></div>
       <div class="row" style="gap:8px"><span class="row toast" style="background:#fff;color:#000">${ic('paste',14)}Вставить из буфера</span><span class="row toast">${ic('qr',14)}QR-код</span></div></div></div></div>
   <div class="box"><h4>Ошибка</h4><div>${dots('ERR', 6, 2.4, '#FF3B2F', '#161010')}</div><span class="cap" style="font-size:10px;line-height:1.7;color:var(--t2)">кольцо дважды мигает красным<br>и замирает · текст говорит,<br>что Onyx делает дальше</span></div>
  </div>`;
},
after() { paintDotFlags(); },
});

/* ═════════════════════════ M3 · MATERIAL 3 EXPRESSIVE ═════════════════════════ */
const M3 = {
css: `
.app{--bg:#141218;--scl:#1D1B20;--sc:#211F26;--sch:#2B2930;--schh:#36343B;--on:#E6E0E9;--onv:#CAC4D0;--outline:#938F99;--ov:#49454F;
  --p:#D0BCFF;--onp:#381E72;--pc:#4F378B;--onpc:#EADDFF;--sc2:#4A4458;--onsc:#E8DEF8;--t:#EFB8C8;--tc:#633B48;--ontc:#FFD8E4;
  --err:#F2B8B5;--errc:#8C1D18;--onerrc:#F9DEDC;--inv:#E6E0E9;--oninv:#322F35;--ok:#A8D5A2;
  --t1:var(--on);--t2:var(--onv);--line:var(--ov);--side:var(--bg);--ff:'Roboto Flex','Roboto',sans-serif}
.tl{font:400 22px/28px var(--ff)} .hl{font:400 32px/40px var(--ff)} .tm{font:500 16px/24px var(--ff);letter-spacing:.15px}
.bm{font:400 14px/20px var(--ff);letter-spacing:.25px;color:var(--onv)} .ll{font:500 14px/20px var(--ff);letter-spacing:.1px} .lm{font:500 12px/16px var(--ff);letter-spacing:.5px}
.ib{width:48px;height:48px;border-radius:24px;display:flex;align-items:center;justify-content:center;color:var(--onv)}
.ib.tonal{background:var(--sch);color:var(--on)}
.hero{position:relative;width:var(--S);height:var(--S);display:flex;align-items:center;justify-content:center}
.hero>svg{position:absolute;inset:0;overflow:visible}
.hero .ic{position:relative}
.card{background:var(--sc);border-radius:28px}
.srv{padding:12px 16px 12px 12px;gap:14px}
.aichip{gap:4px;height:24px;padding:0 8px 0 6px;border-radius:8px;background:var(--tc);color:var(--ontc);font:500 12px var(--ff)}
.chips{gap:8px;justify-content:center;flex-wrap:wrap}
.chip{height:32px;gap:8px;padding:0 16px 0 8px;border-radius:8px;font:500 14px var(--ff);letter-spacing:.1px;color:var(--onv);border:1px solid var(--ov)}
.chip.sel{background:var(--sc2);color:var(--onsc);border-color:transparent}
.chip.nosel{padding-left:16px}
.stats{display:grid;grid-template-columns:repeat(3,1fr);gap:2px;width:100%;border-radius:20px;overflow:hidden}
.stat{background:var(--sc);padding:12px 14px;gap:2px}
.stat .v{font:400 22px/28px var(--ff)} .stat .v small{font-size:13px;color:var(--onv);margin-left:2px}
.wavy{width:220px;height:10px}
.sheet{position:absolute;left:0;right:0;bottom:0;top:52px;background:var(--scl);border-radius:28px 28px 0 0;display:flex;flex-direction:column}
.dim{position:absolute;inset:0;background:rgba(0,0,0,.32)}
.handle{width:32px;height:4px;border-radius:2px;background:var(--onv);opacity:.4;margin:22px auto 6px}
.search{height:56px;border-radius:28px;background:var(--sch);gap:16px;padding:0 4px 0 16px;color:var(--onv);font:400 16px var(--ff)}
.seg{gap:2px}
.li{background:var(--sc);padding:10px 16px 10px 12px;gap:14px;border-radius:4px;min-height:64px}
.seg .li:first-child{border-top-left-radius:20px;border-top-right-radius:20px}
.seg .li:last-child{border-bottom-left-radius:20px;border-bottom-right-radius:20px}
.li.sel{background:var(--sc2);border-radius:20px !important}
.li.sel .tm{color:var(--onsc)}
.sub{font:500 14px var(--ff);color:var(--onv);padding:20px 16px 8px}
.sw{width:52px;height:32px;border-radius:16px;background:var(--schh);border:2px solid var(--outline);position:relative;flex:none}
.sw::after{content:"";position:absolute;top:6px;left:6px;width:16px;height:16px;border-radius:8px;background:var(--outline)}
.sw.on{background:var(--p);border-color:var(--p)}.sw.on::after{top:2px;left:22px;width:24px;height:24px;border-radius:12px;background:var(--onp)}
.efab{position:absolute;right:16px;bottom:28px;height:56px;border-radius:16px;background:var(--pc);color:var(--onpc);gap:12px;padding:0 20px 0 16px;font:500 16px var(--ff);box-shadow:0 3px 8px rgba(0,0,0,.35)}
.bars{gap:2px;align-items:flex-end;height:14px}.bars i{width:3px;border-radius:2px;background:var(--ov);display:block}.bars i.l{background:var(--p)}
.snack{gap:12px;padding:0 8px 0 16px;height:48px;border-radius:4px;background:var(--inv);color:var(--oninv);font:400 14px var(--ff)}
.snack b{font-weight:500;color:#6750A4;padding:0 8px}
.desk .titlebar{border:0;background:var(--bg)}
.desk .right{border:0;background:transparent;width:420px;padding:0 16px 16px 0}
.pane{background:var(--scl);border-radius:28px;flex:1;display:flex;flex-direction:column;overflow:hidden;padding:8px 16px 16px}
.det-grid{position:absolute;inset:40px 0 0 0;padding:20px 24px;display:grid;grid-template-columns:1fr 1fr 1fr;gap:12px}
.box{background:var(--sc);border-radius:28px;padding:20px;display:flex;flex-direction:column;gap:14px;overflow:hidden}
.box h4{font:500 14px var(--ff);color:var(--p)}
`,
heroSvg(S) {
  const c = S/2;
  if (ON)  return `<path d="${shapePath('sunny', S, 8)}" fill="var(--p)"/>`;
  if (ERR) return `<path d="${shapePath('puffy', S*.94, 0)}" transform="translate(${S*.03} ${S*.03})" fill="var(--errc)"/>`;
  if (ING) // ContainedLoadingIndicator: контейнер-круг + морфящаяся форма посередине морфа и поворота
    return `<circle cx="${c}" cy="${c}" r="${c}" fill="var(--pc)"/><path d="${shapePath('flower', S*.74, 22)}" transform="translate(${S*.13} ${S*.13})" fill="var(--p)"/>`;
  return `<path d="${shapePath('cookie9', S)}" fill="var(--pc)"/>`;
},
hero(S) {
  const icn = ON ? ['power', 'var(--onp)'] : ERR ? ['error', 'var(--onerrc)'] : ING ? ['', ''] : ['power', 'var(--onpc)'];
  return `<div class="hero" style="--S:${S}px"><svg width="${S}" height="${S}">${M3.heroSvg(S)}</svg>${icn[0]?`<span style="color:${icn[1]}">${ic(icn[0], S*.24)}</span>`:''}</div>`;
},
wavy(p = .62) {
  const W = 220, a = 3, wl = 26, x1 = W*p; let d = 'M2 5';
  for (let x = 2; x <= x1; x += 1) d += ` L${x} ${(5 + a*Math.sin(x/wl*Math.PI*2)).toFixed(2)}`;
  return `<svg class="wavy" viewBox="0 0 ${W} 10"><path d="${d}" fill="none" stroke="var(--p)" stroke-width="4" stroke-linecap="round"/>
    <line x1="${x1+10}" y1="5" x2="${W-6}" y2="5" stroke="var(--sc2)" stroke-width="4" stroke-linecap="round"/><circle cx="${W-2}" cy="5" r="2" fill="var(--p)"/></svg>`;
},
status() {
  const [h, s, col] = ON ? ['Защищено', 'Трафик зашифрован · 01:24:07', 'var(--on)'] : ING ? ['Подключение…', 'Рукопожатие REALITY · AMS-03', 'var(--on)'] :
    ERR ? ['Нет соединения', 'AMS-03 не ответил — пробую HEL-02', 'var(--err)'] : ['Не защищено', 'Трафик идёт напрямую', 'var(--on)'];
  return `<div class="col" style="align-items:center;gap:6px"><div class="hl" style="color:${col}">${h}</div><div class="bm">${s}</div>${ING?`<div style="margin-top:10px">${M3.wavy()}</div>`:''}</div>`;
},
caption() { return `<div class="ll" style="color:var(--onv);margin-top:18px">${ON?'Нажмите, чтобы отключить':ING?'Нажмите, чтобы отменить':ERR?'Нажмите, чтобы повторить':'Нажмите, чтобы подключиться'}</div>`; },
bars(p) { const n = p < 50 ? 4 : p < 80 ? 3 : p < 150 ? 2 : 1; return `<span class="row bars">${[5,8,11,14].map((x,i)=>`<i class="${i<n?'l':''}" style="height:${x}px"></i>`).join('')}</span>`; },
server() {
  return `<div class="card srv row" style="width:100%">${flagShape('NL', 48, 'cookie4')}<div class="grow"><div class="tm">Амстердам</div><div class="bm">AMS-03 · 38 мс</div></div>
    <span class="row aichip">${ic('ai',14)}AI</span>${M3.bars(38)}<span style="color:var(--onv)">${ic('chev',24)}</span></div>`;
},
chips() {
  const c = (t, sel) => `<span class="row chip ${sel?'sel':'nosel'}">${sel?ic('check',18):''}${t}</span>`;
  return `<div class="row chips">${c('Авто', true)}${c('AI-проба', true)}${c('Kill switch', ON)}</div>`;
},
stats() {
  return `<div class="stats"><div class="col stat"><span class="lm row" style="gap:4px;color:var(--onv)">${ic('down',14)}Получено</span><div class="v">1,82<small>ГБ</small></div></div>
    <div class="col stat"><span class="lm row" style="gap:4px;color:var(--onv)">${ic('up',14)}Отправлено</span><div class="v">214<small>МБ</small></div></div>
    <div class="col stat"><span class="lm row" style="gap:4px;color:var(--onv)">${ic('globe',14)}IP</span><div class="v" style="font-size:18px">185…12</div></div></div>`;
},
li(s) {
  return `<div class="li row ${s.sel?'sel':''}">${flagShape(s.cc, 40, COUNTRY_SHAPE[s.cc] || 'circle')}<div class="grow"><div class="tm">${s.city}</div><div class="bm" style="font-size:13px">${s.id} · ${s.ping} мс</div></div>
    ${s.ai?`<span class="row aichip">${ic('ai',14)}AI</span>`:''}${M3.bars(s.ping)}${s.sel?`<span style="color:var(--onsc)">${ic('check',22)}</span>`:''}</div>`;
},
list(withFab = true) {
  return `<div class="row" style="justify-content:space-between;padding:4px 0 12px"><span class="tl">Серверы</span><div class="row"><div class="ib">${ic('refresh',24)}</div></div></div>
   <div class="search row">${ic('search',24)}<span class="grow">Страна, город, сервер</span><div class="ib">${ic('paste',24)}</div></div>
   <div class="row" style="gap:8px;margin:14px 0 4px"><span class="row chip sel">${ic('check',18)}Все</span><span class="row chip nosel">${ic('ai',16)}&nbsp;AI-проба</span><span class="row chip nosel">Избранное</span></div>
   <div style="flex:1;overflow:hidden">
    <div class="seg col" style="margin-top:12px"><div class="li row" style="border-radius:20px">${`<svg width="40" height="40"><path d="${shapePath('burst',40)}" fill="var(--tc)"/></svg>`}<span style="position:relative;margin-left:-54px;width:40px;display:flex;justify-content:center;color:var(--ontc)">${ic('zap',20)}</span>
      <div class="grow"><div class="tm">Автовыбор</div><div class="bm" style="font-size:13px">Лучший по пингу и AI-пробе</div></div><div class="sw on"></div></div></div>
    ${groups.slice(0, 4).map(g => `<div class="sub">${g.country}</div><div class="seg col">${g.items.map(M3.li).join('')}</div>`).join('')}
   </div>${withFab?`<div class="row efab">${ic('plus',24)}Подписка</div>`:''}`;
},
phone() {
  const top = `<div class="row" style="height:64px;padding:0 4px 0 16px;justify-content:space-between"><span class="tl">Onyx</span><div class="row"><div class="ib">${ic('settings',24)}</div></div></div>`;
  if (S === 'list') return `<div class="screen">${statusBar()}${top}</div><div class="dim"></div><div class="sheet" style="padding:0 16px"><div class="handle"></div>${M3.list()}</div><div class="homebar"></div>`;
  return `<div class="screen">${statusBar()}${top}
    <div class="main" style="padding:0 16px"><div style="height:18px"></div>${M3.status()}<div style="flex:1"></div>${M3.hero(236)}${M3.caption()}<div style="flex:1"></div>
     ${ON?M3.stats()+'<div style="height:8px"></div>':''}${M3.server()}<div style="height:12px"></div>${M3.chips()}<div style="height:30px"></div></div></div><div class="homebar"></div>`;
},
desk() {
  return `<div class="titlebar row"><span class="row" style="gap:10px;font:500 14px var(--ff)">${`<svg width="20" height="20"><path d="${shapePath('cookie9',20)}" fill="var(--p)"/></svg>`}Onyx</span><div class="row"><div class="winbtn">${ic('search',18)}</div><div class="winbtn">${ic('settings',18)}</div>${winButtons()}</div></div>
   <div class="body"><div class="left">${M3.status()}<div style="height:34px"></div>${M3.hero(280)}${M3.caption()}<div style="height:26px"></div>${M3.chips()}
     ${ON?`<div class="row snack" style="position:absolute;bottom:24px">${ic('zap',18)}Переключено на AMS-03: задержка 112 → 38 мс<b>Отменить</b></div>`:''}</div>
   <div class="right"><div class="pane">${ON?`<div style="padding:12px 0">${M3.stats()}</div>`:''}${M3.list(false)}</div></div></div>`;
},
det() {
  const fl = ['NL','DE','FI','SE','PL','US','JP','GB','FR','CH'];
  const icon = (sz, shape, bg, fg) => `<div class="col" style="align-items:center;gap:8px"><div style="position:relative;width:${sz}px;height:${sz}px;border-radius:${sz/2}px;background:${bg};display:flex;align-items:center;justify-content:center">
     <svg width="${sz*.78}" height="${sz*.78}" style="position:absolute"><path d="${shapePath(shape, sz*.78)}" fill="${fg}"/></svg><span style="position:relative;color:${bg}">${ic('power', sz*.3)}</span></div></div>`;
  return `<div class="titlebar row"><span style="font:500 14px var(--ff)">Onyx · Material 3 Expressive — фирменные детали</span>${winButtons()}</div>
  <div class="det-grid">
   <div class="box"><h4>Флаги в формах MaterialShapes</h4><div style="display:grid;grid-template-columns:repeat(5,1fr);gap:12px">${fl.map(f=>`<div class="col" style="align-items:center;gap:4px">${flagShape(f, 52, COUNTRY_SHAPE[f])}<span class="lm" style="color:var(--onv)">${f}</span></div>`).join('')}</div>
     <span class="bm" style="font-size:12px">Форма закреплена за страной и морфится в Circle при нажатии (fastSpatial)</span></div>
   <div class="box"><h4>Главная кнопка — 4 формы</h4><div class="row" style="justify-content:space-between">
     ${[['cookie9','var(--pc)','Откл.'],['flower','var(--p)','Подкл.'],['sunny','var(--p)','Готово'],['puffy','var(--errc)','Ошибка']].map(([s,c,t])=>`<div class="col" style="align-items:center;gap:6px"><svg width="64" height="64"><path d="${shapePath(s,64, s==='flower'?22:0)}" fill="${c}"/></svg><span class="lm" style="color:var(--onv)">${t}</span></div>`).join('')}</div>
     <span class="bm" style="font-size:12px">Cookie9 → морф и вращение (LoadingIndicator) → Sunny; ошибка — Puffy в errorContainer. Пружины ExpressiveMotion.</span></div>
   <div class="box"><h4>Пинг · AI · снэкбар</h4>${[29,63,118,212].map(p=>`<div class="row" style="gap:12px">${M3.bars(p)}<span class="bm">${p} мс</span></div>`).join('')}
     <span class="row aichip" style="align-self:flex-start">${ic('ai',14)}AI-проба пройдена</span>
     <div class="row snack" style="font-size:13px">${ic('zap',16)}Переключено на HEL-02<b>Отменить</b></div></div>
   <div class="box" style="grid-column:span 2"><h4>Импорт подписки — пустое состояние</h4>
     <div class="row" style="gap:24px"><div style="position:relative;width:170px;height:150px;flex:none">
       <svg width="170" height="150" style="position:absolute"><path d="${shapePath('cookie9',96)}" transform="translate(10 10)" fill="var(--pc)"/><path d="${shapePath('clover4',64,45)}" transform="translate(92 66)" fill="var(--tc)"/><circle cx="104" cy="30" r="14" fill="var(--sc2)"/></svg>
       <span style="position:absolute;left:42px;top:42px;color:var(--onpc)">${ic('link',32)}</span></div>
      <div class="col grow" style="gap:12px"><div style="font:400 24px/32px var(--ff)">Добавьте серверы</div><div class="bm">Вставьте ссылку на подписку или отсканируйте QR — Onyx проверит серверы и выберет лучший.</div>
       <div class="search row" style="height:52px">${ic('link',22)}<span class="grow">https://… или vless://…</span></div>
       <div class="row" style="gap:8px"><span class="row" style="height:40px;gap:8px;padding:0 24px 0 16px;border-radius:20px;background:var(--p);color:var(--onp);font:500 14px var(--ff)">${ic('paste',18)}Вставить из буфера</span><span class="row" style="height:40px;gap:8px;padding:0 24px 0 16px;border-radius:20px;background:var(--sc2);color:var(--onsc);font:500 14px var(--ff)">${ic('qr',18)}QR-код</span></div></div></div></div>
   <div class="box"><h4>Иконка (динамический цвет)</h4><div class="row" style="justify-content:space-around">${icon(72,'cookie9','#D0BCFF','#381E72')}${icon(72,'cookie9','#A8D5A2','#0F3A12')}${icon(72,'cookie9','#FFB4A8','#5F150D')}</div>
     <span class="bm" style="font-size:12px">Android 13+: тематическая монохромная иконка; цвета — из обоев (dynamic_color)</span></div>
  </div>`;
},
};

/* ═════════════════════════ A2 · детали Onyx ═════════════════════════ */
A2.det = function () {
  const fl = ['NL','DE','FI','SE','PL','US','JP','GB','FR','CH','KZ','TR'];
  const bars = (p) => { const n = p < 50 ? 3 : p < 120 ? 2 : 1; return `<span class="row" style="gap:3px;align-items:flex-end;height:12px">${[5,8,12].map((h,i)=>`<i style="display:block;width:2px;height:${h}px;border-radius:1px;background:${i<n?'var(--acc)':'#2E2E33'}"></i>`).join('')}</span>`; };
  const icon = (sz) => `<div style="width:${sz}px;height:${sz}px;border-radius:${sz*.23}px;background:#070708;box-shadow:0 0 0 1px #1E1E22;display:flex;align-items:center;justify-content:center">
     <div style="width:${sz*.62}px;height:${sz*.62}px;border-radius:50%;background:radial-gradient(120% 100% at 50% 0%,#1F1D19,#0A0908);box-shadow:inset 0 1px 0 rgba(210,185,143,.7),0 0 0 1px rgba(210,185,143,.35),0 0 ${sz*.2}px rgba(210,185,143,.18)"></div></div>`;
  return `<div class="titlebar row"><span class="word">ONYX — ФИРМЕННЫЕ ДЕТАЛИ</span>${winButtons()}</div>
  <div style="position:absolute;inset:40px 0 0 0;padding:24px 28px;display:grid;grid-template-columns:1fr 1fr 1fr;gap:14px">
   <div class="srv col" style="gap:14px;align-items:stretch"><div class="gh" style="padding:0">Флаги — круглые, хайрлайн и блик</div>
     <div style="display:grid;grid-template-columns:repeat(4,1fr);gap:14px">${fl.map(f=>`<div class="col" style="align-items:center;gap:6px">${flagRound(f, 40)}<span class="gh" style="padding:0;font-size:9.5px">${f}</span></div>`).join('')}</div>
     <span class="m" style="font:400 12px var(--ff);color:var(--t3)">circle-flags (MIT), насыщенность −12 %, ободок rgba(255,255,255,.14)</span></div>
   <div class="srv col" style="gap:12px;align-items:stretch"><div class="gh" style="padding:0">Пинг · AI · выбор</div>
     ${[29,63,118,212].map(p=>`<div class="row" style="gap:12px">${bars(p)}<span class="ping">${p}<small>мс</small></span></div>`).join('')}
     <div class="row" style="gap:10px"><span class="ai">AI</span><span class="m" style="font:400 12.5px var(--ff);color:var(--t2)">прошёл AI-пробу</span></div>
     <div class="gh" style="padding:6px 0 0">Тост автопереключения</div><div class="row toast" style="align-self:flex-start">${ic('zap',14)}AMS-01 → HEL-02 · 112 → 29 мс</div></div>
   <div class="srv col" style="gap:14px;align-items:stretch"><div class="gh" style="padding:0">Иконка и сплэш</div><div class="row" style="gap:16px;align-items:flex-end">${icon(96)}${icon(56)}${icon(32)}</div>
     <span class="m" style="font:400 12.5px var(--ff);color:var(--t2);line-height:1.6">Сплэш: линза проявляется из чёрного, ободок «зажигается» сверху вниз за 500 мс.<br>Хаптика: нажатие — light, подключено — двойной мягкий тик, ошибка — один heavy.</span></div>
   <div class="srv col" style="gap:16px;align-items:stretch;grid-column:span 2"><div class="gh" style="padding:0">Импорт подписки — пустое состояние</div>
     <div class="row" style="gap:28px"><div style="flex:none">${'<div style="width:120px;height:120px;border-radius:50%;background:radial-gradient(120% 100% at 50% 0%,#1D1D21,#070708);box-shadow:inset 0 1px 0 rgba(255,255,255,.25),0 0 0 1px #17171A;display:flex;align-items:center;justify-content:center;color:var(--t2)">'+ic('link',34)+'</div>'}</div>
      <div class="col grow" style="gap:12px"><div style="font:300 26px var(--fd);letter-spacing:-.02em">Добавьте серверы</div><div style="font:400 13.5px var(--ff);color:var(--t2)">Вставьте ссылку на подписку — Onyx проверит каждый сервер, отметит AI-совместимые и выберет лучший.</div>
       <div class="search row" style="margin:0">${ic('link',16)}https://… или vless://…</div>
       <div class="row" style="gap:8px"><span class="row" style="gap:8px;padding:10px 18px;border-radius:22px;background:var(--t1);color:#050506;font:500 13px var(--ff)">${ic('paste',16)}Вставить из буфера</span><span class="row comp lit" style="padding:10px 16px;font-size:11px">${ic('qr',14)}&nbsp;QR-код</span></div></div></div></div>
   <div class="srv col" style="gap:12px;align-items:stretch"><div class="gh" style="padding:0">Карточка сервера</div>
     <div class="row" style="gap:12px">${flagRound('NL', 34)}<div class="grow"><div class="n">Амстердам</div><div class="m">Нидерланды · AMS-03</div></div><span class="ai">AI</span></div>
     <div class="row" style="gap:12px">${flagRound('FI', 34)}<div class="grow"><div class="n">Хельсинки</div><div class="m">Финляндия · HEL-02</div></div>${bars(29)}</div></div>
  </div>`;
};
// A2: круглые флаги в списке и карточке
A2.css += `
.flagr{display:inline-block;flex:none;border-radius:50%;background-size:cover;background-position:center;position:relative;
  filter:saturate(.88);box-shadow:0 0 0 1px rgba(255,255,255,.14),0 2px 6px rgba(0,0,0,.5)}
.flagr::after{content:"";position:absolute;inset:0;border-radius:50%;background:linear-gradient(180deg,rgba(255,255,255,.18),transparent 45%,rgba(0,0,0,.25))}`;
if (P.flags === '1') {
  A.server = () => `<div class="srv row">${flagRound('NL', 34)}<div class="grow"><div class="n">Нидерланды</div>
    <div class="m">Амстердам · AMS-03</div></div><span class="ai">AI</span><span class="ping">38<small>мс</small></span><span class="t3">${ic('chev',16)}</span></div>`;
  A.item = (s) => `<div class="it row ${s.sel?'sel':''}">${flagRound(s.cc, 30)}
    <div class="grow"><div class="n">${s.city} <span class="t3" style="font-size:12px">${s.id}</span></div></div>
    ${s.ai?'<span class="ai">AI</span>':''}<span class="ping" style="width:48px;text-align:right${s.ping>150?';color:#B98B5E':''}">${s.ping}<small>мс</small></span></div>`;
}

build({c2: C2, m3: M3});
