/* Material 3 Expressive — каноничная версия мокапов (задача #33, итерация 2).
   Фигуры — эталонные контуры MaterialShapes из m3-shapes.js (выгружены из
   material_new_shapes = порт androidx.graphics.shapes, параметры Compose).
   Токены компонентов — m3.material.io/components (выгрузка .m3-guidelines) и
   справочник mitso_schedule/docs/m3. Цвета — baseline dark (Flutter
   _colorSchemeDarkM3 / Compose ColorDarkTokens). d=m3b. */

const sh = (name, size, fill, rot = 0, style = '') =>
  `<svg width="${size}" height="${size}" viewBox="0 0 100 100" style="flex:none;${style}"><path d="${M3_SHAPES[name]}" fill="${fill}" transform="rotate(${rot} 50 50)"/></svg>`;
const shp = (path, size, fill, rot = 0) =>
  `<svg width="${size}" height="${size}" viewBox="0 0 100 100" style="flex:none"><path d="${path}" fill="${fill}" transform="rotate(${rot} 50 50)"/></svg>`;
let _cid = 0;
const flagM3 = (cc, size, shape) => {
  const id = 'c' + (_cid++);
  return `<svg width="${size}" height="${size}" viewBox="0 0 100 100" style="flex:none"><defs><clipPath id="${id}"><path d="${M3_SHAPES[shape]}"/></clipPath></defs>
    <image href="flags/square/${cc.toLowerCase()}.svg" x="-10" y="-10" width="120" height="120" preserveAspectRatio="xMidYMid slice" clip-path="url(#${id})"/></svg>`;
};
const FLAG_SHAPE = {NL:'cookie4Sided', FI:'clover4Leaf', DE:'pentagon', SE:'sunny', PL:'cookie9Sided', US:'flower', JP:'softBurst', GB:'puffy', FR:'cookie12Sided', CH:'clover8Leaf', KZ:'gem', TR:'cookie6Sided'};
const mi = (n, size, color) => `<span class="ic" style="--src:url(icons/m3/${n}.svg);--is:${size}px;color:${color}"></span>`;

const M3B = {
css: `
.app{--bg:#141218;--sclst:#0F0D13;--scl:#1D1B20;--sc:#211F26;--sch:#2B2930;--schh:#36343B;--on:#E6E0E9;--onv:#CAC4D0;--outline:#938F99;--ov:#49454F;
  --p:#D0BCFF;--onp:#381E72;--pc:#4F378B;--onpc:#EADDFF;--s:#CCC2DC;--sc2:#4A4458;--onsc:#E8DEF8;--t:#EFB8C8;--tc:#633B48;--ontc:#FFD8E4;
  --err:#F2B8B5;--errc:#8C1D18;--onerrc:#F9DEDC;--inv:#E6E0E9;--oninv:#322F35;--invp:#6750A4;
  --t1:var(--on);--t2:var(--onv);--line:var(--ov);--side:var(--bg);--ff:'Roboto',sans-serif;background:var(--bg)}
/* типошкала M3 (size/line/tracking/weight) */
.dS{font:400 36px/44px var(--ff)} .hL{font:400 32px/40px var(--ff)} .hM{font:400 28px/36px var(--ff)} .hS{font:400 24px/32px var(--ff)}
.tL{font:400 22px/28px var(--ff)} .tM{font:500 16px/24px var(--ff);letter-spacing:.15px} .tS{font:500 14px/20px var(--ff);letter-spacing:.1px}
.bL{font:400 16px/24px var(--ff);letter-spacing:.5px} .bM{font:400 14px/20px var(--ff);letter-spacing:.25px} .bS{font:400 12px/16px var(--ff);letter-spacing:.4px}
.lL{font:500 14px/20px var(--ff);letter-spacing:.1px} .lM{font:500 12px/16px var(--ff);letter-spacing:.5px} .lS{font:500 11px/16px var(--ff);letter-spacing:.5px}
.v{color:var(--onv)}
/* Top app bar small: 64, отступы 4, заголовок с 16 */
.tab{height:64px;padding:0 4px 0 16px;display:flex;align-items:center;justify-content:space-between;color:var(--on)}
.ib{width:48px;height:48px;display:flex;align-items:center;justify-content:center;border-radius:24px;color:var(--onv)}
/* Filter chip: 32, r8, 16/8 */
.chips{display:flex;gap:8px;justify-content:center;flex-wrap:wrap}
.fc{height:32px;border-radius:8px;display:flex;align-items:center;gap:8px;padding:0 16px;border:1px solid var(--ov);color:var(--onv);font:500 14px/20px var(--ff);letter-spacing:.1px}
.fc.sel{background:var(--sc2);border-color:transparent;color:var(--onsc);padding-left:8px}
/* Lists (segmented): 2dp gap, внутр. 4, наружн. 16, пункт 72 (2 строки), отступы 16/10, слоты 12 */
.seg{display:flex;flex-direction:column;gap:2px}
.li{min-height:72px;background:var(--sc);display:flex;align-items:center;gap:12px;padding:10px 16px;border-radius:4px}
.seg .li:first-child{border-top-left-radius:16px;border-top-right-radius:16px}
.seg .li:last-child{border-bottom-left-radius:16px;border-bottom-right-radius:16px}
.li.sel{background:var(--sc2);border-radius:16px!important}.li.sel .bL{color:var(--onsc)}
.li .tr{color:var(--onv)}
.sub{padding:16px 16px 8px;color:var(--onv)}
/* Switch: трек 52×32, обводка 2, ручка 16/24, иконка 16 */
.sw{width:52px;height:32px;border-radius:16px;background:var(--schh);border:2px solid var(--outline);position:relative;flex:none;box-sizing:border-box}
.sw i{position:absolute;top:6px;left:6px;width:16px;height:16px;border-radius:8px;background:var(--outline)}
.sw.on{background:var(--p);border-color:var(--p)}.sw.on i{top:2px;left:22px;width:24px;height:24px;border-radius:12px;background:var(--onp);display:flex;align-items:center;justify-content:center}
/* Search bar: 56, full, surfaceContainerHigh, иконки 24 */
.sb{height:56px;border-radius:28px;background:var(--sch);display:flex;align-items:center;gap:4px;padding:0 4px 0 4px;color:var(--onv)}
.sb .ib{color:var(--on)} .sb .tr{color:var(--onv)}
/* Bottom sheet: surfaceContainerLow, верх 28, ручка 32×4 onSurfaceVariant, 22 сверху/снизу, scrim 32 % */
.sheet{position:absolute;left:0;right:0;bottom:0;top:56px;background:var(--scl);border-radius:28px 28px 0 0;display:flex;flex-direction:column;padding:0 16px}
.handle{width:32px;height:4px;border-radius:2px;background:var(--onv);margin:22px auto}
.scrim{position:absolute;inset:0;background:rgba(0,0,0,.32)}
/* Snackbar: 48, r4, inverseSurface, bodyMedium, action labelLarge inversePrimary */
.snack{min-height:48px;border-radius:4px;background:var(--inv);color:var(--oninv);display:flex;align-items:center;gap:12px;padding:0 8px 0 16px;box-shadow:0 3px 6px rgba(0,0,0,.3),0 1px 3px rgba(0,0,0,.3)}
.snack b{font:500 14px/20px var(--ff);color:var(--invp);padding:10px 12px}
/* Card (filled): surfaceContainerHighest, medium 12 */
.card{background:var(--schh);border-radius:12px}
.stat{padding:12px 16px;display:flex;flex-direction:column;gap:4px}
.hero{position:relative;display:flex;align-items:center;justify-content:center}
.hero .ic{position:absolute}
.desk .titlebar{border:0;background:var(--bg)}
.pane{background:var(--scl);border-radius:28px;display:flex;flex-direction:column;overflow:hidden;padding:0 16px}
.grid{position:absolute;inset:40px 0 0 0;padding:16px 24px 24px;display:grid;gap:12px}
.box{background:var(--scl);border-radius:16px;padding:16px 18px;display:flex;flex-direction:column;gap:10px;overflow:hidden}
.box h4{font:500 14px/20px var(--ff);letter-spacing:.1px;color:var(--p)}
.cap{font:400 11px/16px var(--ff);color:var(--onv)}
table.chk{border-collapse:collapse;width:100%;font:400 12px/16px var(--ff);color:var(--on)}
table.chk th{font:500 11px/16px var(--ff);letter-spacing:.5px;color:var(--p);text-align:left;padding:6px 8px;border-bottom:1px solid var(--ov)}
table.chk td{padding:6px 8px;border-bottom:1px solid #2B2930;vertical-align:top}
table.chk td:first-child{color:var(--onv);white-space:nowrap}
table.chk td code{font:400 11px/16px 'JetBrains Mono',monospace;color:var(--ontc)}
`,
// Wavy linear progress (indeterminate): высота 10, толщина 4, амплитуда 3, длина волны 20, зазор 4, трек secondaryContainer.
wavy(W = 240, p = .55) {
  const a = 3, wl = 20, x1 = W * p; let d = 'M2 5';
  for (let x = 2; x <= x1; x += 1) d += ` L${x} ${(5 + a * Math.sin((x / wl) * Math.PI * 2)).toFixed(2)}`;
  return `<svg width="${W}" height="10" viewBox="0 0 ${W} 10"><path d="${d}" fill="none" stroke="var(--p)" stroke-width="4" stroke-linecap="round"/>
    <line x1="${x1 + 4 + 4}" y1="5" x2="${W - 2}" y2="5" stroke="var(--sc2)" stroke-width="4" stroke-linecap="round"/></svg>`;
},
hero(S) {
  if (ING) {
    // ContainedLoadingIndicator: контейнер-круг primaryContainer, активная форма onPrimaryContainer = 38/48 контейнера;
    // кадр морфа SoftBurst → Cookie9Sided (IndeterminateIndicatorPolygons), с поворотом.
    const inner = S * 38 / 48;
    return `<div class="hero" style="width:${S}px;height:${S}px">${sh('circle', S, 'var(--pc)')}
      <div style="position:absolute">${shp(M3_LOADING_MORPH[0][2], inner, 'var(--onpc)', 37)}</div></div>`;
  }
  const [path, fill, icon, ic] = ON ? [M3_COOKIE_TO_SUNNY[4], 'var(--p)', 'power', 'var(--onp)'] :
    ERR ? [M3_COOKIE_TO_PUFFY[4], 'var(--errc)', 'error', 'var(--onerrc)'] : [M3_SHAPES.cookie9Sided, 'var(--pc)', 'power', 'var(--onpc)'];
  return `<div class="hero" style="width:${S}px;height:${S}px">${shp(path, S, fill, ON || ERR ? 45 : 0)}${mi(icon, Math.round(S * .2), ic)}</div>`;
},
status() {
  const [h, s, c] = ON ? ['Защищено', 'Трафик зашифрован · 01:24:07', 'var(--on)'] : ING ? ['Подключение…', 'Рукопожатие REALITY · AMS-03', 'var(--on)'] :
    ERR ? ['Нет соединения', 'AMS-03 не ответил — пробую HEL-02', 'var(--err)'] : ['Не защищено', 'Трафик идёт напрямую', 'var(--on)'];
  return `<div class="col" style="align-items:center;gap:4px"><div class="hM" style="color:${c}">${h}</div><div class="bM v">${s}</div>${ING ? `<div style="margin-top:12px">${M3B.wavy()}</div>` : ''}</div>`;
},
caption() { return `<div class="lL v" style="margin-top:20px">${ON ? 'Нажмите, чтобы отключить' : ING ? 'Нажмите, чтобы отменить' : ERR ? 'Нажмите, чтобы повторить' : 'Нажмите, чтобы подключиться'}</div>`; },
server() {
  return `<div class="seg" style="width:100%"><div class="li">${flagM3('NL', 40, FLAG_SHAPE.NL)}
    <div class="grow"><div class="bL">Амстердам AMS-03</div><div class="bM v">Нидерланды · 38 мс</div></div>
    ${mi('ai', 24, 'var(--t)')}${mi('chev', 24, 'var(--onv)')}</div></div>`;
},
chips() {
  const c = (t, s) => `<span class="fc ${s ? 'sel' : ''}">${s ? mi('check', 18, 'var(--onsc)') : ''}${t}</span>`;
  return `<div class="chips">${c('Авто', true)}${c('AI-канал', true)}${c('Kill switch', ON)}</div>`;
},
stats() {
  return `<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;width:100%">
    <div class="card stat"><span class="lM v row" style="gap:4px">${mi('down', 16, 'var(--onv)')}Получено</span><span class="tL">1,82 ГБ</span></div>
    <div class="card stat"><span class="lM v row" style="gap:4px">${mi('up', 16, 'var(--onv)')}Отправлено</span><span class="tL">214 МБ</span></div></div>`;
},
li(s) {
  return `<div class="li ${s.sel ? 'sel' : ''}">${flagM3(s.cc, 40, FLAG_SHAPE[s.cc] || 'circle')}
    <div class="grow"><div class="bL">${s.city} ${s.id}</div><div class="bM v">${s.ping} мс${s.ai ? ' · AI-проба' : ''}</div></div>
    ${s.ai ? mi('ai', 24, s.sel ? 'var(--onsc)' : 'var(--t)') : ''}${s.sel ? mi('check', 24, 'var(--onsc)') : ''}</div>`;
},
list() {
  return `<div class="row" style="justify-content:space-between;padding:0 0 12px 8px"><span class="tL">Серверы</span><div class="row"><div class="ib">${mi('refresh', 24, 'var(--onv)')}</div><div class="ib">${mi('plus', 24, 'var(--onv)')}</div></div></div>
   <div class="sb"><div class="ib">${mi('search', 24, 'var(--on)')}</div><span class="bL grow v">Страна, город, сервер</span><div class="ib">${mi('paste', 24, 'var(--onv)')}</div></div>
   <div class="chips" style="justify-content:flex-start;margin:16px 0 8px"><span class="fc sel">${mi('check', 18, 'var(--onsc)')}Все</span><span class="fc" style="padding-left:8px">${mi('ai', 18, 'var(--p)')}AI-проба</span><span class="fc">Проверенные</span></div>
   <div style="flex:1;overflow:hidden">
    <div class="seg" style="margin-top:8px"><div class="li">${sh('softBurst', 40, 'var(--tc)')}<span style="position:relative;margin-left:-52px;width:40px;display:flex;justify-content:center">${mi('zap', 20, 'var(--ontc)')}</span>
      <div class="grow"><div class="bL">Автовыбор</div><div class="bM v">Лучший по пингу и AI-пробе</div></div><div class="sw on"><i>${mi('check', 16, 'var(--onpc)')}</i></div></div></div>
    ${groups.slice(0, 4).map(g => `<div class="sub tS">${g.country}</div><div class="seg">${g.items.map(M3B.li).join('')}</div>`).join('')}
   </div>`;
},
phone() {
  const top = `<div class="tab"><span class="tL">Onyx</span><div class="ib">${mi('settings', 24, 'var(--onv)')}</div></div>`;
  if (S === 'list') return `<div class="screen">${statusBar()}${top}</div><div class="scrim"></div><div class="sheet"><div class="handle"></div>${M3B.list()}</div><div class="homebar"></div>`;
  return `<div class="screen">${statusBar()}${top}
    <div class="main" style="padding:0 16px"><div style="height:16px"></div>${M3B.status()}<div style="flex:1"></div>${M3B.hero(240)}${M3B.caption()}<div style="flex:1"></div>
     ${ON ? M3B.stats() + '<div style="height:8px"></div>' : ''}${M3B.server()}<div style="height:16px"></div>${M3B.chips()}<div style="height:28px"></div></div></div><div class="homebar"></div>`;
},
desk() {
  return `<div class="titlebar row"><span class="row" style="gap:10px">${sh('cookie9Sided', 20, 'var(--p)')}<span class="tS">Onyx</span></span><div class="row"><div class="winbtn">${mi('search', 20, 'var(--onv)')}</div><div class="winbtn">${mi('settings', 20, 'var(--onv)')}</div>${winButtons()}</div></div>
   <div class="body"><div class="left">${M3B.status()}<div style="height:32px"></div>${M3B.hero(240)}${M3B.caption()}<div style="height:24px"></div>${M3B.chips()}
     ${ON ? `<div class="snack" style="position:absolute;bottom:24px;width:420px"><span class="bM grow">Переключено на AMS-03 · 112 → 38 мс</span><b>Отменить</b></div>` : ''}</div>
   <div style="width:440px;padding:0 24px 24px 0;display:flex"><div class="pane" style="flex:1;padding-top:16px">${ON ? `<div style="margin-bottom:12px">${M3B.stats()}</div>` : ''}${M3B.list()}</div></div></div>`;
},
det() {
  const fl = ['NL','DE','FI','SE','PL','US','JP','GB','FR','CH'];
  const seq = ['softBurst','cookie9Sided','pentagon','pill','sunny','cookie4Sided','oval'];
  return `<div class="titlebar row"><span class="tS">Onyx · Material 3 Expressive — фигуры и детали (эталон MaterialShapes)</span>${winButtons()}</div>
  <div class="grid" style="grid-template-columns:1fr 1fr 1fr;grid-template-rows:auto auto">
   <div class="box"><h4>Флаги — обрезка MaterialShapes</h4><div style="display:grid;grid-template-columns:repeat(5,1fr);gap:10px">${fl.map(f => `<div class="col" style="align-items:center;gap:2px">${flagM3(f, 44, FLAG_SHAPE[f])}<span class="lS v">${f}</span></div>`).join('')}</div>
     <span class="cap">styles/shape: библиотека форм — для «image crops and avatars». Форма закреплена за страной, смысла не несёт («not semantic»).</span></div>
   <div class="box"><h4>Главная кнопка — морф Cookie9Sided → Sunny</h4><div class="row" style="justify-content:space-between">${M3_COOKIE_TO_SUNNY.map((p, i) => `<div class="col" style="align-items:center;gap:4px">${shp(p, 48, i === 4 ? 'var(--p)' : 'var(--pc)', i * 11.25)}<span class="lS v">${i * 25}%</span></div>`).join('')}</div>
     <div class="row" style="justify-content:space-between;margin-top:6px">${M3_COOKIE_TO_PUFFY.map((p, i) => `<div class="col" style="align-items:center;gap:4px">${shp(p, 48, i === 4 ? 'var(--errc)' : 'var(--pc)', i * 11.25)}<span class="lS v">${i * 25}%</span></div>`).join('')}</div>
     <span class="cap">Morph (androidx.graphics.shapes), пружина defaultSpatial 380/0.8; цвет — defaultEffects 1600/1.0. Ошибка → Puffy в errorContainer.</span></div>
   <div class="box"><h4>LoadingIndicator — IndeterminateIndicatorPolygons</h4><div class="row" style="justify-content:space-between">${seq.map(n => `<div class="col" style="align-items:center;gap:4px">${sh(n, 30, 'var(--p)')}<span class="lS v" style="font-size:8.5px">${n.replace("Sided","")}</span></div>`).join('')}</div>
     <div class="row" style="gap:12px;margin-top:4px">${sh('circle', 48, 'var(--pc)')}<span style="position:relative;margin-left:-55px">${shp(M3_LOADING_MORPH[0][2], 38, 'var(--onpc)', 37)}</span><span class="cap" style="margin-left:20px">Contained: контейнер 48 primaryContainer, форма 38 onPrimaryContainer; масштаб 24–240. Морф каждые 650 мс, поворот 90° + общий оборот 4666 мс.</span></div></div>
   <div class="box"><h4>Компоненты (токены)</h4>
     <div class="row" style="gap:12px"><div class="sw"><i></i></div><div class="sw on"><i>${mi('check', 16, 'var(--onpc)')}</i></div><span class="cap">Switch 52×32, ручка 16/24</span></div>
     <div class="chips" style="justify-content:flex-start"><span class="fc sel">${mi('check', 18, 'var(--onsc)')}Авто</span><span class="fc">Kill switch</span><span class="cap" style="align-self:center">Filter chip 32, r8</span></div>
     <div>${M3B.wavy(300, .6)}</div><span class="cap">Linear wavy: 10 / 4, амплитуда 3, волна 20 (indeterminate), зазор 4</span>
     <div class="snack"><span class="bM grow">Переключено на HEL-02</span><b>Отменить</b></div></div>
   <div class="box"><h4>Пустое состояние — импорт подписки</h4>
     <div class="row" style="gap:16px"><div style="position:relative;width:120px;height:110px;flex:none">
       <div style="position:absolute;left:0;top:0">${sh('cookie9Sided', 84, 'var(--pc)')}</div><div style="position:absolute;right:0;bottom:0">${sh('clover4Leaf', 52, 'var(--tc)')}</div>
       <div style="position:absolute;right:14px;top:4px">${sh('circle', 22, 'var(--sc2)')}</div><div style="position:absolute;left:26px;top:26px">${mi('link', 32, 'var(--onpc)')}</div></div>
      <div class="col" style="gap:8px"><div class="tL">Добавьте серверы</div><div class="bS v">Ссылка на подписку — Onyx проверит серверы и выберет лучший.</div></div></div>
     <div class="sb"><div class="ib">${mi('link', 24, 'var(--on)')}</div><span class="bL v grow">https://… или vless://…</span></div>
     <div class="row" style="gap:8px"><span class="row lL" style="height:40px;gap:8px;padding:0 16px;border-radius:20px;background:var(--p);color:var(--onp)">${mi('paste', 20, 'var(--onp)')}Вставить</span><span class="row lL" style="height:40px;gap:8px;padding:0 16px;border-radius:20px;background:var(--sc2);color:var(--onsc)">${mi('qr', 20, 'var(--onsc)')}QR-код</span></div>
     <span class="cap">Filled button S (40, full, 16) + Tonal button S. Одна filled-кнопка на экран.</span></div>
   <div class="box"><h4>Иконка приложения</h4><div class="row" style="justify-content:space-around">${[['#D0BCFF', '#381E72'], ['#A8D5A2', '#0F3A12'], ['#FFB4A8', '#5F150D']].map(([bg, fg]) => `<div style="position:relative;width:72px;height:72px;border-radius:36px;background:${bg};display:flex;align-items:center;justify-content:center">${sh('cookie9Sided', 56, fg)}<span style="position:absolute;display:flex">${mi('power', 24, bg)}</span></div>`).join('')}</div>
     <span class="cap">Adaptive icon + Android 13 themed (monochrome) icon; цвета — из обоев (dynamic color), запасной seed #6750A4.</span></div>
  </div>`;
},
check() {
  const rows = [
    ['Верхняя строка', 'Top app bar · small', 'components/app-bars', 'h 64, отступы 4, заголовок с 16, <code>titleLarge</code>, контейнер <code>surface</code>, иконки 24 <code>onSurfaceVariant</code>'],
    ['Статус', 'Typography', 'styles/typography', '<code>headlineMedium</code> 28/36, подпись <code>bodyMedium</code> 14/20 <code>onSurfaceVariant</code>; ошибка — <code>error</code>'],
    ['Подключение', 'Progress indicator · linear wavy', 'components/progress-indicators', 'h 10, трек 4, амплитуда 3, волна 20 (indeterminate), зазор 4; <code>primary</code> / трек <code>secondaryContainer</code>'],
    ['Кнопка (идёт подключение)', 'Loading indicator · contained', 'components/loading-indicator', 'контейнер <code>primaryContainer</code>, форма 38/48 <code>onPrimaryContainer</code>, масштаб до 240; формы SoftBurst→Cookie9Sided→Pentagon→Pill→Sunny→Cookie4Sided→Oval'],
    ['Кнопка (откл/подкл/ошибка)', 'Shape library + Morph', 'styles/shape', 'MaterialShapes Cookie9Sided → Sunny / Puffy (Morph), 240; <code>primaryContainer</code> → <code>primary</code> / <code>errorContainer</code>; пружины spatial 380/0.8, effects 1600/1.0'],
    ['Трафик', 'Cards · filled', 'components/cards', '<code>surfaceContainerHighest</code>, форма <code>medium</code> 12, значение <code>titleLarge</code>, подпись <code>labelMedium</code>'],
    ['Текущий сервер, список', 'Lists · segmented (Expressive)', 'components/lists', 'пункт 72 (2 строки), отступы 16/10, слоты 12; зазор 2, внутр. 4, наружн. 16; <code>surfaceContainer</code>, выбранный <code>secondaryContainer</code> + 16; <code>bodyLarge</code>/<code>bodyMedium</code>'],
    ['Флаги', 'Shape library (avatars)', 'styles/shape', 'аватар 40, обрезка формой MaterialShapes; форма не несёт смысла'],
    ['Функции (Авто/AI/Kill)', 'Chips · filter', 'components/chips', 'h 32, <code>small</code> 8, 16 / 8 с иконкой, галочка 18; выбран <code>secondaryContainer</code>, нет — обводка 1 <code>outlineVariant</code>; <code>labelLarge</code>'],
    ['Шторка серверов', 'Bottom sheet · modal', 'components/bottom-sheets', '<code>surfaceContainerLow</code>, верх 28, ручка 32×4 <code>onSurfaceVariant</code>, 22 сверху/снизу, scrim 32 %'],
    ['Поиск', 'Search bar', 'components/search', 'h 56, <code>full</code>, <code>surfaceContainerHigh</code> (на шторке Low — контраст ок), иконки 24, <code>bodyLarge</code>'],
    ['Автовыбор', 'Switch', 'components/switch', 'трек 52×32 обводка 2, ручка 16 → 24 с иконкой 16; вкл. <code>primary</code>/<code>onPrimary</code>; пружина fastSpatial 800/0.6'],
    ['Автопереключение', 'Snackbar', 'components/snackbar', 'h 48, <code>extraSmall</code> 4, <code>inverseSurface</code>, текст <code>bodyMedium</code>, действие <code>labelLarge</code> <code>inversePrimary</code>, одно действие'],
    ['Импорт подписки', 'Buttons · filled / tonal, S', 'components/buttons', 'h 40, <code>full</code>, отступ 16, иконка 20, зазор 8, <code>labelLarge</code>; одна filled на экран'],
    ['Кнопки в шапке', 'Icon buttons · standard', 'components/icon-buttons', 'зона 48, иконка 24 <code>onSurfaceVariant</code>, без контейнера'],
    ['Навигация', 'Navigation bar / rail', 'components/navigation-bar', '<b>не используется</b>: у приложения одно назначение, а bar/rail требуют 3–5 пунктов. Настройки — отдельный экран'],
    ['Цвет', 'Color · dynamic', 'styles/color', 'Android 12+: схема из обоев; иначе baseline dark (seed #6750A4)'],
  ];
  return `<div class="titlebar row"><span class="tS">Сверка M3: экран → компонент → страница гайдлайна → ключевые токены</span>${winButtons()}</div>
   <div style="position:absolute;inset:40px 0 0 0;padding:12px 24px 16px;overflow:hidden"><table class="chk"><tr><th>Экран / элемент</th><th>Компонент M3</th><th>m3.material.io/…</th><th>Ключевые токены</th></tr>
   ${rows.map(r => `<tr><td>${r[0]}</td><td>${r[1]}</td><td><code>${r[2]}</code></td><td>${r[3]}</td></tr>`).join('')}</table></div>`;
},
};
