// VoiceLab window: talks to app.py over a private local server.
(function () {
  'use strict';
  const $ = (id) => document.getElementById(id);
  const ICON = {
    play: '<svg viewBox="0 0 20 20"><path d="M6.5 4.5v11l9-5.5z"/></svg>',
    pause: '<svg viewBox="0 0 20 20"><rect x="5" y="4.5" width="3.4" height="11" rx="1"/><rect x="11.6" y="4.5" width="3.4" height="11" rx="1"/></svg>',
    x: '<svg viewBox="0 0 20 20"><path d="M5.5 5.5l9 9M14.5 5.5l-9 9"/></svg>',
  };
  const S = { voices: [], takes: [], settings: {}, lexicon: [], ready: false, outDir: '', native: false, home: '' };
  const audio = new Audio();
  let playing = null;        // { kind: 'take'|'sample'|'word', id }
  let busy = false;

  // ---------- talking to the app ----------
  async function api(path, body) {
    const r = await fetch(path, body === undefined ? {} : { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    const j = await r.json().catch(() => ({ error: 'VoiceLab stopped responding. Close the window and open it again.' }));
    if (!r.ok) throw new Error(j.error || 'Something went wrong.');
    return j;
  }
  let saveT;
  function saveSettings(patch) {
    Object.assign(S.settings, patch);
    clearTimeout(saveT);
    saveT = setTimeout(() => api('/api/settings', S.settings).catch(() => {}), 350);
  }
  function toast(msg) {
    const t = $('toast'); t.textContent = msg; t.classList.add('show');
    clearTimeout(toast.t); toast.t = setTimeout(() => t.classList.remove('show'), 2600);
  }
  const prettyPath = (p) => (S.home && p.startsWith(S.home) ? '~' + p.slice(S.home.length) : p).replace(/^~\//, '').replace(/\//g, ' › ');
  const voice = (id) => S.voices.find((v) => v.id === id);
  const vname = (id) => (voice(id) || { name: id }).name;

  // ---------- voices ----------
  function renderVoices() {
    const q = $('find').value.trim().toLowerCase();
    const list = $('voiceList'); list.innerHTML = '';
    if (!S.voices.length) { list.innerHTML = '<p class="none">' + (S.error ? 'No voices yet.' : 'Loading voices…') + '</p>'; return; }
    const groups = [];
    for (const v of S.voices) {
      if (q && !(v.name.toLowerCase().includes(q) || v.group.toLowerCase().includes(q))) continue;
      let g = groups.find((x) => x.name === v.group);
      if (!g) groups.push(g = { name: v.group, voices: [] });
      g.voices.push(v);
    }
    if (!groups.length) { list.innerHTML = '<p class="none">No voice called “' + esc(q) + '”.</p>'; return; }
    for (const g of groups) {
      const sec = document.createElement('div'); sec.className = 'group';
      sec.innerHTML = '<h3>' + esc(g.name) + '</h3>';
      for (const v of g.voices) {
        const row = document.createElement('div');
        row.className = 'voice'; row.setAttribute('aria-selected', String(v.id === S.settings.voice));
        row.innerHTML = '<button class="pick"><span class="nm">' + esc(v.name) + '</span>' + (v.best ? '<span class="best">Most natural</span>' : '') + '</button>' +
          '<button class="hear" title="Hear ' + esc(v.name) + '" aria-label="Hear ' + esc(v.name) + '">' + ICON.play + '</button>';
        row.querySelector('.pick').onclick = () => pickVoice(v.id);
        const hear = row.querySelector('.hear');
        hear.onclick = (e) => { e.stopPropagation(); playSample(v.id, hear); };
        if (playing && playing.kind === 'sample' && playing.id === v.id) { hear.classList.add('on'); hear.innerHTML = ICON.pause; }
        sec.appendChild(row);
      }
      list.appendChild(sec);
    }
  }
  function pickVoice(id) {
    saveSettings({ voice: id });
    if (S.settings.mix_voice === id) { saveSettings({ mix_voice: '' }); $('mixVoice').value = ''; }
    renderVoices(); renderCurrent();
  }
  function renderCurrent() {
    const v = voice(S.settings.voice);
    $('curGroup').textContent = v ? v.group.replace(/women$/, 'woman').replace(/men$/, 'man') : ' ';
    const mix = S.settings.mix_voice && voice(S.settings.mix_voice);
    $('curName').innerHTML = v ? esc(v.name) + (mix ? '<span class="blend">blended with ' + esc(mix.name) + '</span>' : '') : ' ';
    $('curSample').disabled = !v;
    const opts = ['<option value="">No blend</option>'];
    let last = '';
    for (const x of S.voices) {
      if (x.id === S.settings.voice) continue;
      if (x.group !== last) { if (last) opts.push('</optgroup>'); opts.push('<optgroup label="' + esc(x.group) + '">'); last = x.group; }
      opts.push('<option value="' + x.id + '"' + (x.id === S.settings.mix_voice ? ' selected' : '') + '>' + esc(x.name) + '</option>');
    }
    $('mixVoice').innerHTML = opts.join('') + '</optgroup>';
    $('mixAmt').hidden = !mix;
    updateMixOut();
  }
  async function playSample(id, btn) {
    if (playing && playing.kind === 'sample' && playing.id === id) return stop();
    try {
      if (btn) btn.classList.add('on');
      const r = await api('/api/sample', { voice: id });
      play(r.url, { kind: 'sample', id });
    } catch (e) { toast(e.message); }
    renderVoices();
  }

  // ---------- playback ----------
  function play(url, who, from) {
    audio.src = url; audio.currentTime = 0;
    playing = who;
    audio.onloadedmetadata = () => { if (from) audio.currentTime = from * audio.duration; };
    audio.play().catch(() => {});
    refreshPlaying();
  }
  function stop() { audio.pause(); playing = null; refreshPlaying(); }
  audio.addEventListener('ended', () => { playing = null; refreshPlaying(); });
  function refreshPlaying() {
    document.querySelectorAll('.take').forEach((li) => {
      const on = playing && playing.kind === 'take' && playing.id === li.dataset.id;
      li.classList.toggle('playing', !!on);
      const b = li.querySelector('.play'); if (b && !li.classList.contains('pending')) { b.innerHTML = on ? ICON.pause : ICON.play; b.setAttribute('aria-label', on ? 'Pause' : 'Play'); }
      drawWave(li);
    });
    const sOn = playing && playing.kind === 'sample' && playing.id === S.settings.voice;
    $('curSample').innerHTML = (sOn ? ICON.pause : ICON.play) + (sOn ? ' Stop' : ' Hear a sample');
    document.querySelectorAll('.voice .hear').forEach((b) => { if (!(playing && playing.kind === 'sample')) { b.classList.remove('on'); b.innerHTML = ICON.play; } });
    if (playing && playing.kind === 'take') tick();
  }
  function tick() {
    if (!playing || playing.kind !== 'take') return;
    const li = document.querySelector('.take[data-id="' + playing.id + '"]');
    if (li) drawWave(li);
    requestAnimationFrame(tick);
  }

  // ---------- clips ----------
  function renderTakes() {
    const ol = $('takes'); ol.innerHTML = '';
    for (const t of S.takes) ol.appendChild(takeRow(t));
    $('count').textContent = S.takes.length ? S.takes.length : '';
    $('empty').hidden = !!S.takes.length || busy;
    $('emptyFolder').textContent = prettyPath(S.outDir);
    $('folderPath').textContent = prettyPath(S.outDir);
    requestAnimationFrame(() => ol.querySelectorAll('.take').forEach(drawWave));
  }
  function takeRow(t, fresh) {
    const li = document.createElement('li');
    li.className = 'take' + (fresh ? ' fresh' : ''); li.dataset.id = t.id;
    const bits = [esc(vname(t.voice))];
    if (t.mix_voice) bits.push('+ ' + esc(vname(t.mix_voice)) + ' ' + Math.round(t.mix * 100) + '%');
    if (Math.abs(t.speed - 1) > .001) bits.push(t.speed.toFixed(2).replace(/0$/, '') + '× speed');
    const longer = t.text.length > t.title.replace(/…$/, '').length + 2;
    li.innerHTML =
      '<button class="play" aria-label="Play">' + ICON.play + '</button>' +
      '<div class="top"><span class="title" title="Click to rename">' + esc(t.title) + '</span><span class="secs">' + fmtSecs(t.seconds) + '</span></div>' +
      '<canvas aria-hidden="true"></canvas>' +
      '<div class="foot"><span class="meta" title="' + esc(t.text) + '">' + bits.join('&ensp;') + (longer ? '&ensp;<span class="said">“' + esc(t.text) + '”</span>' : '') + '</span>' +
      '<span class="acts"><button class="quiet reuse">Use again</button><button class="quiet show">Show in Finder</button><button class="quiet del">Delete</button></span></div>';
    li._take = t;
    li.querySelector('.play').onclick = () => togglePlay(t);
    li.querySelector('canvas').onclick = (e) => {
      const r = e.currentTarget.getBoundingClientRect(), f = (e.clientX - r.left) / r.width;
      if (playing && playing.kind === 'take' && playing.id === t.id && audio.duration) { audio.currentTime = f * audio.duration; if (audio.paused) audio.play(); }
      else play(clipUrl(t), { kind: 'take', id: t.id }, f);
    };
    const title = li.querySelector('.title');
    title.onclick = () => startRename(title, t);
    li.querySelector('.reuse').onclick = () => reuse(t);
    li.querySelector('.show').onclick = () => api('/api/reveal', { id: t.id }).catch((e) => toast(e.message));
    li.querySelector('.del').onclick = () => del(t, li);
    return li;
  }
  const clipUrl = (t) => '/clips/' + encodeURIComponent(t.file) + '?v=' + t.id;
  function togglePlay(t) {
    if (playing && playing.kind === 'take' && playing.id === t.id) {
      if (audio.paused) { audio.play(); } else { audio.pause(); playing = null; }
      return refreshPlaying();
    }
    play(clipUrl(t), { kind: 'take', id: t.id });
  }
  function drawWave(li) {
    const c = li.querySelector('canvas'), t = li._take;
    if (!c || !t) return;
    const dpr = window.devicePixelRatio || 1, w = c.clientWidth, h = c.clientHeight;
    if (!w) return;
    if (c.width !== Math.round(w * dpr)) { c.width = Math.round(w * dpr); c.height = Math.round(h * dpr); }
    const g = c.getContext('2d'); g.setTransform(dpr, 0, 0, dpr, 0, 0); g.clearRect(0, 0, w, h);
    const css = getComputedStyle(document.documentElement);
    const on = playing && playing.kind === 'take' && playing.id === t.id;
    const prog = on && audio.duration ? audio.currentTime / audio.duration : 0;
    const step = 3, n = Math.floor(w / step), P = t.peaks;
    for (let i = 0; i < n; i++) {
      const v = P[Math.min(P.length - 1, Math.floor(i / n * P.length))];
      const bh = Math.max(1.5, Math.pow(v, .8) * (h - 2));
      g.fillStyle = (on && i / n <= prog) ? css.getPropertyValue('--cobalt') : css.getPropertyValue('--wave');
      g.fillRect(i * step, (h - bh) / 2, 2, bh);
    }
  }
  window.addEventListener('resize', () => { document.querySelectorAll('.take').forEach(drawWave); layoutGutter(); });

  function startRename(el, t) {
    if (el.isContentEditable) return;
    el.contentEditable = 'true'; el.focus();
    document.getSelection().selectAllChildren(el);
    const done = async (save) => {
      el.contentEditable = 'false'; el.onblur = el.onkeydown = null;
      const v = el.textContent.trim();
      if (!save || !v || v === t.title) { el.textContent = t.title; return; }
      try { const r = await api('/api/rename', { id: t.id, title: v }); Object.assign(t, r.take); el.textContent = t.title; toast('Renamed to “' + t.file + '”'); }
      catch (e) { el.textContent = t.title; toast(e.message); }
    };
    el.onkeydown = (e) => { if (e.key === 'Enter') { e.preventDefault(); done(true); } if (e.key === 'Escape') done(false); };
    el.onblur = () => done(true);
  }
  function reuse(t) {
    $('script').value = t.text; onScript();
    saveSettings({ voice: t.voice, speed: t.speed, pause: t.pause ?? .25, mix_voice: t.mix_voice || '', mix: t.mix || S.settings.mix, draft: t.text });
    syncControls(); renderVoices(); renderCurrent();
    $('script').focus();
    toast('Script and settings from “' + t.title + '” are back in the editor.');
  }
  async function del(t, li) {
    if (playing && playing.id === t.id) stop();
    try {
      await api('/api/delete', { id: t.id });
      S.takes = S.takes.filter((x) => x.id !== t.id);
      li.remove(); $('count').textContent = S.takes.length || ''; $('empty').hidden = !!S.takes.length;
      toast('Moved “' + t.file + '” to the Bin.');
    } catch (e) { toast(e.message); }
  }

  // ---------- making clips ----------
  function lines() { return $('script').value.split('\n').map((l) => l.trim()).filter(Boolean); }
  function updateMake() {
    const split = !!S.settings.split, n = split ? lines().length : ($('script').value.trim() ? 1 : 0);
    const btn = $('make'), lab = $('makeLabel');
    btn.classList.toggle('busy', busy);
    if (!S.ready) { btn.disabled = true; lab.textContent = S.error ? 'Voice model missing' : 'Loading the voice…'; return; }
    btn.disabled = busy || !n;
    lab.textContent = busy ? 'Speaking…' : split && n > 1 ? 'Make ' + n + ' clips' : 'Make clip';
  }
  function estimate() {
    const words = $('script').value.trim().split(/\s+/).filter(Boolean).length;
    const sents = ($('script').value.match(/[.!?]+(\s|$)/g) || []).length;
    if (!words) { $('estimate').textContent = ''; return; }
    const s = words / 2.75 / (S.settings.speed || 1) + sents * (S.settings.pause ?? .25);
    $('estimate').textContent = words + (words === 1 ? ' word' : ' words') + ', about ' + fmtSecs(s);
  }
  async function make() {
    if (busy || !S.ready) return;
    const text = $('script').value.trim(); if (!text) return;
    busy = true; updateMake(); stop();
    const split = !!S.settings.split, pieces = split ? lines() : [text.replace(/\s*\n\s*/g, ' ')];
    $('empty').hidden = true;
    const ol = $('takes');
    const pend = document.createElement('li'); pend.className = 'take pending';
    pend.innerHTML = '<span class="play"><span class="tally"></span></span><div class="top"><span class="title"></span></div><canvas></canvas><div class="foot"><span class="meta"></span></div>';
    ol.prepend(pend); ol.scrollTop = 0;
    let made = 0, anchor = pend;
    try {
      for (let i = 0; i < pieces.length; i++) {
        pend.querySelector('.title').textContent = (pieces.length > 1 ? 'Line ' + (i + 1) + ' of ' + pieces.length + ': ' : 'Speaking: ') + pieces[i];
        const r = await api('/api/speak', { text: pieces[i], voice: S.settings.voice, speed: S.settings.speed, pause: S.settings.pause, mix_voice: S.settings.mix_voice, mix: S.settings.mix, split: false, at: made });
        for (const t of r.takes) { S.takes.splice(made, 0, t); const row = takeRow(t, true); anchor.after(row); anchor = row; drawWave(row); made++; }
        pend.remove(); anchor.after(pend); anchor = pend.previousElementSibling;
        $('count').textContent = S.takes.length;
      }
      if (made === 1) play(clipUrl(S.takes[0]), { kind: 'take', id: S.takes[0].id });
      else toast(made + ' clips saved in ' + prettyPath(S.outDir) + '.');
    } catch (e) { toast(e.message); }
    pend.remove(); busy = false; updateMake();
    $('empty').hidden = !!S.takes.length;
  }

  // ---------- the script page and its clip numbers ----------
  const mirror = document.createElement('div');
  function layoutGutter() {
    const ta = $('script'), gut = $('gutter');
    gut.innerHTML = '';
    if (!S.settings.split) return;
    const cs = getComputedStyle(ta);
    if (!mirror.parentNode) document.body.appendChild(mirror);
    Object.assign(mirror.style, { position: 'absolute', visibility: 'hidden', left: '-9999px', top: '0', whiteSpace: 'pre-wrap', wordWrap: 'break-word',
      width: ta.clientWidth + 'px', font: cs.font, padding: cs.padding, lineHeight: cs.lineHeight, letterSpacing: cs.letterSpacing, boxSizing: 'border-box' });
    mirror.innerHTML = '';
    const raw = ta.value.split('\n'); let n = 0;
    raw.forEach((l) => { const d = document.createElement('div'); d.textContent = l || '​'; d.dataset.k = l.trim() ? ++n : ''; mirror.appendChild(d); });
    const lh = parseFloat(cs.lineHeight);
    for (const d of mirror.children) {
      if (!d.dataset.k) continue;
      const s = document.createElement('span'); s.textContent = d.dataset.k;
      s.style.top = (d.offsetTop - ta.scrollTop + lh / 2 - 6) + 'px';
      gut.appendChild(s);
    }
  }
  function onScript() { estimate(); updateMake(); layoutGutter(); }
  $('script').addEventListener('input', () => { onScript(); saveSettings({ draft: $('script').value }); });
  $('script').addEventListener('scroll', layoutGutter);
  document.querySelectorAll('.seg button').forEach((b) => b.onclick = () => { saveSettings({ split: b.dataset.split === '1' }); syncControls(); onScript(); });

  // ---------- sound controls ----------
  function fill(r) { r.style.setProperty('--fill', ((r.value - r.min) / (r.max - r.min) * 100) + '%'); }
  function updateMixOut() {
    const m = S.settings.mix_voice && voice(S.settings.mix_voice);
    $('mixOut').textContent = m ? Math.round(S.settings.mix * 100) + '% ' + m.name : '';
  }
  function syncControls() {
    const sp = $('speed'), pa = $('pause'), mx = $('mix');
    sp.value = S.settings.speed; pa.value = S.settings.pause; mx.value = S.settings.mix;
    [sp, pa, mx].forEach(fill);
    $('speedOut').textContent = (+S.settings.speed).toFixed(2) + '×';
    $('pauseOut').textContent = (+S.settings.pause).toFixed(2) + ' s';
    document.querySelectorAll('.seg button').forEach((b) => b.setAttribute('aria-checked', String((b.dataset.split === '1') === !!S.settings.split)));
    $('scriptWrap').classList.toggle('split', !!S.settings.split);
    updateMixOut();
  }
  $('speed').oninput = (e) => { saveSettings({ speed: +e.target.value }); syncControls(); estimate(); };
  $('speed').ondblclick = () => { saveSettings({ speed: 1 }); syncControls(); estimate(); };
  $('pause').oninput = (e) => { saveSettings({ pause: +e.target.value }); syncControls(); estimate(); };
  $('mix').oninput = (e) => { saveSettings({ mix: +e.target.value }); syncControls(); };
  $('mixVoice').onchange = (e) => { saveSettings({ mix_voice: e.target.value }); renderCurrent(); };
  $('curSample').onclick = () => {
    if (S.settings.mix_voice) return makeBlendSample();
    playSample(S.settings.voice);
  };
  async function makeBlendSample() {
    if (playing && playing.kind === 'sample') return stop();
    try {
      const r = await api('/api/sample', { voice: S.settings.voice, mix_voice: S.settings.mix_voice, mix: S.settings.mix });
      play(r.url, { kind: 'sample', id: S.settings.voice });
    } catch (e) { toast(e.message); }
  }

  // ---------- pronunciation ----------
  let lexT;
  function saveLex() { clearTimeout(lexT); lexT = setTimeout(() => api('/api/lexicon', { entries: S.lexicon }).catch((e) => toast(e.message)), 400); }
  function renderLex() {
    const ul = $('lexList'); ul.innerHTML = '';
    S.lexicon.forEach((e, i) => {
      const li = document.createElement('li'); li.className = 'word';
      li.innerHTML = '<input class="w" placeholder="Word" aria-label="Word" spellcheck="false"><input class="say" placeholder="Say it as" aria-label="Say it as" spellcheck="false">' +
        '<button class="t" title="Hear it" aria-label="Hear it">' + ICON.play + '</button><button class="x" title="Remove" aria-label="Remove">' + ICON.x + '</button>';
      const w = li.querySelector('.w'), s = li.querySelector('.say');
      w.value = e.word; s.value = e.say;
      w.oninput = () => { e.word = w.value; saveLex(); };
      s.oninput = () => { e.say = s.value; saveLex(); };
      li.querySelector('.t').onclick = async () => {
        if (!e.word.trim()) return w.focus();
        try { const r = await api('/api/test-word', { word: e.word, say: e.say, voice: S.settings.voice }); play(r.url, { kind: 'word', id: i }); }
        catch (err) { toast(err.message); }
      };
      li.querySelector('.x').onclick = () => { S.lexicon.splice(i, 1); saveLex(); renderLex(); };
      ul.appendChild(li);
    });
  }
  $('addWord').onclick = () => { S.lexicon.push({ word: '', say: '' }); renderLex(); $('lexList').lastChild.querySelector('.w').focus(); };

  // ---------- folder ----------
  const showFolder = () => api('/api/reveal', {}).catch((e) => toast(e.message));
  $('openFolder').onclick = showFolder; $('emptyFolder').onclick = showFolder;
  $('changeFolder').onclick = async () => {
    try {
      const r = await api('/api/pick-folder', {});
      if (!r.path) return;
      const st = await api('/api/settings', { ...S.settings, out_dir: r.path });
      load(st); toast('New clips will be saved in ' + prettyPath(r.path) + '.');
    } catch (e) { toast(e.message); }
  };

  // ---------- keys ----------
  document.addEventListener('keydown', (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') { e.preventDefault(); make(); }
    const typing = /INPUT|TEXTAREA|SELECT/.test(document.activeElement.tagName) || document.activeElement.isContentEditable;
    if (e.key === ' ' && !typing && S.takes[0]) { e.preventDefault(); if (playing) stop(); else togglePlay(S.takes[0]); }
  });
  $('find').addEventListener('input', renderVoices);
  $('make').onclick = make;

  // ---------- start ----------
  function load(st) {
    S.voices = st.voices; S.takes = st.takes; S.settings = st.settings; S.lexicon = st.lexicon;
    S.ready = st.ready; S.error = st.error; S.outDir = st.out_dir; S.native = st.native; S.home = st.home;
    $('changeFolder').hidden = !S.native;
    const n = $('notice');
    if (S.error) { n.hidden = false; n.className = 'notice bad'; n.textContent = S.error; } else n.hidden = true;
    renderVoices(); renderCurrent(); syncControls(); renderTakes(); renderLex(); updateMake(); estimate(); layoutGutter();
  }
  async function boot() {
    let st;
    try { st = await api('/api/state'); } catch (e) { return setTimeout(boot, 500); }
    if ($('script').value === '' && st.settings.draft) $('script').value = st.settings.draft;
    load(st);
    if (!st.ready && !st.error) {
      const wait = async () => {
        const s2 = await api('/api/state').catch(() => null);
        if (s2 && (s2.ready || s2.error)) { S.voices = s2.voices; S.ready = s2.ready; S.error = s2.error; load({ ...s2, settings: S.settings, lexicon: S.lexicon }); }
        else setTimeout(wait, 400);
      };
      wait();
    }
    if (!$('script').value) $('script').focus();
  }

  function fmtSecs(s) { s = +s; return s < 60 ? s.toFixed(1) + ' s' : Math.floor(s / 60) + ':' + String(Math.round(s % 60)).padStart(2, '0'); }
  function esc(s) { return String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])); }
  boot();
})();
