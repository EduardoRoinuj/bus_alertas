/* ============================================================
   Bus Alertas — painel em tempo real
   ============================================================ */
(() => {
  'use strict';

  const API = '/api/state';
  const POLL_VISIBLE = 1500;
  const POLL_HIDDEN = 8000;
  const ARRIVAL_HIGHLIGHT_MS = 45000;
  const SPARK_POINTS = 40;

  const $ = (id) => document.getElementById(id);
  const store = {
    get(k, d) { try { const v = localStorage.getItem(k); return v === null ? d : JSON.parse(v); } catch { return d; } },
    set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* sem storage */ } },
  };

  const state = {
    lastId: null,
    soundOn: store.get('soundOn', true),
    follow: false,
    serverOffset: 0,          // ms (servidor - cliente)
    stops: {},
    buses: {},
    alerts: [],
    sparks: {},               // codigo -> [ldr...]
    arrivedUntil: {},         // codigo -> timestamp
    failures: 0,
    fitted: false,
  };

  /* ------------------------------------------------------------
     Utilitários de tempo
     ------------------------------------------------------------ */
  const now = () => Date.now() + state.serverOffset;
  const parse = (iso) => (iso ? Date.parse(iso) : null);

  function ago(iso) {
    const t = parse(iso);
    if (!t) return '—';
    const s = Math.max(0, Math.round((now() - t) / 1000));
    if (s < 5) return 'agora';
    if (s < 60) return `há ${s} s`;
    const m = Math.floor(s / 60);
    if (m < 60) return `há ${m} min`;
    const h = Math.floor(m / 60);
    if (h < 24) return `há ${h} h`;
    return `há ${Math.floor(h / 24)} d`;
  }
  const clock = (iso) => (iso ? new Date(iso).toLocaleTimeString('pt-PT', { hour: '2-digit', minute: '2-digit', second: '2-digit' }) : '—');
  const day = (iso) => (iso ? new Date(iso).toLocaleDateString('pt-PT', { day: '2-digit', month: 'short' }) : '');
  const dist = (m) => (m == null ? '—' : m < 1000 ? `${m} m` : `${(m / 1000).toFixed(1)} km`);
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  /* ------------------------------------------------------------
     Mapa
     ------------------------------------------------------------ */
  const map = L.map('map', { zoomControl: true, attributionControl: true }).setView([-25.9652, 32.5781], 16);
  L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19,
    className: 'dark-tiles',
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
  }).addTo(map);
  // O contentor muda de tamanho com o layout responsivo
  new ResizeObserver(() => map.invalidateSize()).observe($('map'));

  const stopMarkers = {};
  const busMarkers = {};

  const stopIcon = (online, arrived) => L.divIcon({
    className: 'mk',
    html: `<div class="mk-stop ${online ? 'online' : ''} ${arrived ? 'arrived' : ''}"><div class="pin"><i class="fa-solid fa-signs-post"></i></div></div>`,
    iconSize: [38, 38], iconAnchor: [19, 36], popupAnchor: [0, -34],
  });
  const busIcon = (online) => L.divIcon({
    className: 'mk',
    html: `<div class="mk-bus ${online ? '' : 'offline'}"><i class="fa-solid fa-bus"></i></div>`,
    iconSize: [40, 40], iconAnchor: [20, 20], popupAnchor: [0, -22],
  });

  function stopPopup(s) {
    return `<b>${esc(s.nome)}</b> <span class="mono">(${esc(s.codigo)})</span><br>
      ${s.online ? '<span style="color:#22C55E">● Online</span>' : '<span style="color:#94A3B8">● Offline</span>'}<br>
      LDR: <span class="mono">${s.ldr_value}</span><br>
      Última chegada: ${s.last_arrival ? `${clock(s.last_arrival)} (${ago(s.last_arrival)})` : '—'}<br>
      Autocarro mais próximo: ${dist(s.distance_m)}`;
  }

  // Animação suave da posição do autocarro
  function glide(marker, to, ms = 1200) {
    const from = marker.getLatLng();
    if (from.distanceTo(to) > 2000 || matchMedia('(prefers-reduced-motion: reduce)').matches) {
      marker.setLatLng(to); return;
    }
    const start = performance.now();
    cancelAnimationFrame(marker._raf);
    const step = (t) => {
      const k = Math.min(1, (t - start) / ms);
      const e = 1 - Math.pow(1 - k, 3);
      marker.setLatLng([from.lat + (to.lat - from.lat) * e, from.lng + (to.lng - from.lng) * e]);
      if (k < 1) marker._raf = requestAnimationFrame(step);
    };
    marker._raf = requestAnimationFrame(step);
  }

  function updateMap() {
    const t = Date.now();
    for (const s of Object.values(state.stops)) {
      const arrived = (state.arrivedUntil[s.codigo] || 0) > t;
      const key = `${s.online}-${arrived}`;
      let m = stopMarkers[s.codigo];
      if (!m) {
        m = stopMarkers[s.codigo] = L.marker([s.latitude, s.longitude], { icon: stopIcon(s.online, arrived), title: s.nome, keyboard: true })
          .addTo(map).bindPopup('');
        m._key = key;
      } else if (m._key !== key) {
        m.setIcon(stopIcon(s.online, arrived)); m._key = key;
      }
      m.setPopupContent(stopPopup(s));
    }

    for (const b of Object.values(state.buses)) {
      if (b.latitude == null) continue;
      const ll = L.latLng(b.latitude, b.longitude);
      let m = busMarkers[b.codigo];
      if (!m) {
        m = busMarkers[b.codigo] = L.marker(ll, { icon: busIcon(b.online), zIndexOffset: 1000, title: b.codigo }).addTo(map).bindPopup('');
        m._online = b.online;
      } else {
        if (m._online !== b.online) { m.setIcon(busIcon(b.online)); m._online = b.online; }
        glide(m, ll);
      }
      m.setPopupContent(`<b>${esc(b.codigo)}</b><br>${b.online ? 'Online' : 'Offline'} · GPS ${b.gps_fix ? 'OK' : 'sem fix'}<br>
        ${b.speed_kmh != null ? `Velocidade: <span class="mono">${b.speed_kmh} km/h</span><br>` : ''}
        <span class="mono">${b.latitude.toFixed(6)}, ${b.longitude.toFixed(6)}</span>`);
      if (state.follow) map.panTo(ll, { animate: true });
    }

    if (!state.fitted && Object.keys(stopMarkers).length) {
      state.fitted = true;
      requestAnimationFrame(() => { map.invalidateSize(); fitAll(); });
    }
  }

  function fitAll() {
    const pts = [...Object.values(stopMarkers), ...Object.values(busMarkers)].map((m) => m.getLatLng());
    if (pts.length) map.fitBounds(L.latLngBounds(pts).pad(0.35), { maxZoom: 17 });
  }

  /* ------------------------------------------------------------
     Painéis
     ------------------------------------------------------------ */
  function setText(el, value) {
    if (el.textContent !== String(value)) el.textContent = value;
  }
  function setKpi(id, value) {
    const el = $(id);
    if (el.textContent !== String(value)) {
      el.textContent = value;
      el.classList.remove('bump'); void el.offsetWidth; el.classList.add('bump');
    }
  }

  function sparkSvg(values) {
    if (values.length < 2) return '';
    const max = Math.max(4095, ...values) || 1;
    const w = 300, h = 30;
    const pts = values.map((v, i) => `${(i / (SPARK_POINTS - 1)) * w},${h - (v / max) * (h - 2) - 1}`);
    const lastX = ((values.length - 1) / (SPARK_POINTS - 1)) * w;
    return `<polygon class="area" points="0,${h} ${pts.join(' ')} ${lastX},${h}"/><polyline points="${pts.join(' ')}"/>`;
  }

  function renderStops() {
    const box = $('stops');
    const t = Date.now();
    for (const s of Object.values(state.stops)) {
      let card = box.querySelector(`[data-code="${s.codigo}"]`);
      if (!card) {
        card = document.createElement('article');
        card.className = 'stop';
        card.dataset.code = s.codigo;
        card.tabIndex = 0;
        card.setAttribute('role', 'button');
        card.setAttribute('aria-label', `Mostrar ${s.nome} no mapa`);
        card.innerHTML = `
          <span class="stop-icon"><i class="fa-solid fa-signs-post" aria-hidden="true"></i></span>
          <p class="stop-name">${esc(s.nome)}</p>
          <span class="status" data-f="status"></span>
          <p class="stop-sub mono">${esc(s.codigo)}</p>
          <span></span>
          <div class="stop-meta">
            <div class="meta"><p class="meta-label"><i class="fa-solid fa-sun" aria-hidden="true"></i> LDR</p><p class="meta-value mono" data-f="ldr"></p></div>
            <div class="meta"><p class="meta-label"><i class="fa-solid fa-route" aria-hidden="true"></i> Distância</p><p class="meta-value mono" data-f="dist"></p></div>
            <div class="meta"><p class="meta-label"><i class="fa-regular fa-clock" aria-hidden="true"></i> Chegada</p><p class="meta-value mono" data-f="arr"></p></div>
          </div>
          <svg class="spark" viewBox="0 0 300 30" preserveAspectRatio="none" aria-hidden="true">
            <defs><linearGradient id="sparkFill" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="#38BDF8" stop-opacity=".35"/><stop offset="1" stop-color="#38BDF8" stop-opacity="0"/></linearGradient></defs>
            <g data-f="spark"></g>
          </svg>`;
        const go = () => { map.flyTo([s.latitude, s.longitude], 18, { duration: 0.8 }); stopMarkers[s.codigo]?.openPopup(); };
        card.addEventListener('click', go);
        card.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); go(); } });
        box.appendChild(card);
      }
      const arrived = (state.arrivedUntil[s.codigo] || 0) > t;
      card.classList.toggle('is-online', s.online);
      card.classList.toggle('arrived', arrived);
      const st = card.querySelector('[data-f="status"]');
      const stHtml = arrived
        ? '<i class="fa-solid fa-bus" aria-hidden="true"></i> Autocarro aqui'
        : s.online ? '<i class="fa-solid fa-wifi" aria-hidden="true"></i> Online' : '<i class="fa-solid fa-plug-circle-xmark" aria-hidden="true"></i> Offline';
      if (st.innerHTML !== stHtml) st.innerHTML = stHtml;
      st.className = `status ${arrived ? 'ok' : s.online ? 'ok' : ''}`;
      setText(card.querySelector('[data-f="ldr"]'), s.online ? s.ldr_value : '—');
      setText(card.querySelector('[data-f="dist"]'), dist(s.distance_m));
      setText(card.querySelector('[data-f="arr"]'), s.last_arrival ? ago(s.last_arrival) : '—');
      card.querySelector('[data-f="spark"]').innerHTML = sparkSvg(state.sparks[s.codigo] || []);
    }
  }

  function renderBuses() {
    const box = $('buses');
    const list = Object.values(state.buses);
    if (!list.length) {
      box.innerHTML = '<p class="empty"><i class="fa-solid fa-satellite-dish" aria-hidden="true"></i> À espera do primeiro sinal do autocarro…</p>';
      return;
    }
    box.innerHTML = list.map((b) => `
      <article class="bus ${b.online ? '' : 'offline'}">
        <span class="stop-icon"><i class="fa-solid fa-bus" aria-hidden="true"></i></span>
        <p class="stop-name mono">${esc(b.codigo)}</p>
        <span class="status ${b.online ? 'ok' : ''}">${b.online ? '<i class="fa-solid fa-wifi" aria-hidden="true"></i> Online' : 'Offline'}</span>
        <p class="stop-sub">
          <i class="fa-solid fa-satellite" aria-hidden="true"></i> ${b.gps_fix ? 'GPS OK' : 'Sem GPS'}
          ${b.speed_kmh != null ? ` · <i class="fa-solid fa-gauge-high" aria-hidden="true"></i> <span class="mono">${b.speed_kmh} km/h</span>` : ''}
          · <i class="fa-regular fa-lightbulb" aria-hidden="true"></i> LED ${b.led_status ? 'activo' : 'off'}
        </p>
        <span class="stop-sub mono" data-ago="${esc(b.last_seen)}">${ago(b.last_seen)}</span>
      </article>`).join('');
  }

  function historyItem(a, isNew) {
    return `<li class="${isNew ? 'new' : ''}">
      <span class="h-icon"><i class="fa-solid fa-flag-checkered" aria-hidden="true"></i></span>
      <div><p class="h-title">${esc(a.stop_name)}</p><p class="h-sub mono">${esc(a.bus_code || '—')}</p></div>
      <div class="h-time"><p class="mono">${clock(a.created_at)}</p><p class="h-sub">${day(a.created_at)}</p></div>
    </li>`;
  }

  function renderHistory(newIds = new Set()) {
    const list = state.alerts;
    $('history').innerHTML = list.length
      ? list.map((a) => historyItem(a, newIds.has(a.id))).join('')
      : '<li class="empty" style="display:flex"><i class="fa-regular fa-bell-slash" aria-hidden="true"></i> Sem chegadas registadas ainda</li>';
    setText($('histCount'), list.length);
  }

  function renderKpis(stats) {
    setKpi('kBuses', `${stats.buses_online}/${stats.buses_total}`);
    setKpi('kStops', `${stats.stops_online}/${stats.stops_total}`);
    setKpi('kArrivals', stats.arrivals_24h);
    setText($('kLast'), state.alerts[0] ? ago(state.alerts[0].created_at) : '—');
  }

  function setLive(mode) {
    const pill = $('live');
    pill.className = `live-pill is-${mode}`;
    setText($('liveText'), mode === 'online' ? 'Ao vivo' : mode === 'offline' ? 'Sem ligação' : 'A ligar…');
  }

  /* ------------------------------------------------------------
     Alerta de chegada (visual + som + voz + notificação)
     ------------------------------------------------------------ */
  let audioCtx = null;
  function chime() {
    try {
      audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)();
      const t0 = audioCtx.currentTime;
      [880, 1175, 1568].forEach((f, i) => {
        const o = audioCtx.createOscillator();
        const g = audioCtx.createGain();
        o.type = 'sine'; o.frequency.value = f;
        g.gain.setValueAtTime(0.0001, t0 + i * 0.16);
        g.gain.exponentialRampToValueAtTime(0.25, t0 + i * 0.16 + 0.02);
        g.gain.exponentialRampToValueAtTime(0.0001, t0 + i * 0.16 + 0.5);
        o.connect(g).connect(audioCtx.destination);
        o.start(t0 + i * 0.16); o.stop(t0 + i * 0.16 + 0.55);
      });
    } catch { /* sem áudio */ }
  }
  function speak(text) {
    if (!('speechSynthesis' in window)) return;
    try {
      speechSynthesis.cancel();
      const u = new SpeechSynthesisUtterance(text);
      u.lang = 'pt-PT'; u.rate = 0.95;
      setTimeout(() => speechSynthesis.speak(u), 700);
    } catch { /* ignorar */ }
  }

  let toastTimer = null;
  function showToast(a) {
    const t = $('toast');
    setText($('toastMsg'), a.message);
    setText($('toastTime'), `${clock(a.created_at)} · ${a.stop_code}`);
    t.classList.remove('leaving');
    t.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(hideToast, 9000);
  }
  function hideToast() {
    const t = $('toast');
    t.classList.add('leaving');
    setTimeout(() => { t.hidden = true; t.classList.remove('leaving'); }, 250);
  }

  function announce(a) {
    state.arrivedUntil[a.stop_code] = Date.now() + ARRIVAL_HIGHLIGHT_MS;
    showToast(a);
    if (navigator.vibrate) navigator.vibrate([200, 100, 200]);
    if (state.soundOn) { chime(); speak(`Atenção. Autocarro chegou à paragem ${a.stop_name}.`); }
    if ('Notification' in window && Notification.permission === 'granted' && document.hidden) {
      navigator.serviceWorker?.getRegistration().then((reg) => {
        const opts = { body: a.message, icon: '/static/icon-192.png', tag: `arrival-${a.id}`, vibrate: [200, 100, 200] };
        if (reg) reg.showNotification('Bus Alertas', opts); else new Notification('Bus Alertas', opts);
      }).catch(() => {});
    }
  }

  /* ------------------------------------------------------------
     Polling
     ------------------------------------------------------------ */
  let pollTimer = null;
  let inflight = null;

  async function poll() {
    clearTimeout(pollTimer);
    inflight?.abort();
    inflight = new AbortController();
    const timeout = setTimeout(() => inflight.abort(), 10000);
    try {
      const url = state.lastId === null ? API : `${API}?since=${state.lastId}`;
      const res = await fetch(url, { signal: inflight.signal, cache: 'no-store' });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      apply(data);
      state.failures = 0;
      setLive('online');
    } catch (err) {
      state.failures += 1;
      if (state.failures >= 2) setLive('offline');
    } finally {
      clearTimeout(timeout);
      const base = document.hidden ? POLL_HIDDEN : POLL_VISIBLE;
      const backoff = state.failures ? Math.min(15000, base * 2 ** Math.min(state.failures, 4)) : base;
      pollTimer = setTimeout(poll, backoff);
    }
  }

  function apply(data) {
    state.serverOffset = parse(data.server_time) - Date.now();
    state.stops = Object.fromEntries(data.stops.map((s) => [s.codigo, s]));
    state.buses = Object.fromEntries(data.buses.map((b) => [b.codigo, b]));

    for (const s of data.stops) {
      if (!s.online) continue;
      const arr = (state.sparks[s.codigo] ||= []);
      arr.push(s.ldr_value);
      if (arr.length > SPARK_POINTS) arr.shift();
    }

    const first = state.lastId === null;
    const fresh = first ? [] : (data.new_alerts || []);
    const changed = first || fresh.length || data.alerts.length !== state.alerts.length;
    state.alerts = data.alerts;
    state.lastId = data.last_id;

    fresh.forEach(announce);
    renderStops();
    renderBuses();
    if (changed) renderHistory(new Set(fresh.map((a) => a.id)));
    renderKpis(data.stats);
    updateMap();
  }

  /* ------------------------------------------------------------
     Controlos
     ------------------------------------------------------------ */
  function syncSoundBtn() {
    const b = $('soundBtn');
    b.setAttribute('aria-pressed', String(state.soundOn));
    b.setAttribute('aria-label', state.soundOn ? 'Desactivar som' : 'Activar som');
    b.innerHTML = `<i class="fa-solid ${state.soundOn ? 'fa-volume-high' : 'fa-volume-xmark'}" aria-hidden="true"></i>`;
  }
  $('soundBtn').addEventListener('click', () => {
    state.soundOn = !state.soundOn;
    store.set('soundOn', state.soundOn);
    syncSoundBtn();
    if (state.soundOn) chime();   // também desbloqueia o áudio no browser
  });

  function syncNotifyBtn() {
    const b = $('notifyBtn');
    if (!('Notification' in window)) { b.hidden = true; return; }
    const on = Notification.permission === 'granted';
    b.classList.toggle('on', on);
    b.innerHTML = `<i class="${on ? 'fa-solid' : 'fa-regular'} fa-bell" aria-hidden="true"></i>`;
    b.setAttribute('aria-label', on ? 'Notificações activas' : 'Activar notificações');
  }
  $('notifyBtn').addEventListener('click', async () => {
    if ('Notification' in window && Notification.permission === 'default') await Notification.requestPermission();
    syncNotifyBtn();
  });

  $('fitBtn').addEventListener('click', fitAll);
  $('followBtn').addEventListener('click', (e) => {
    state.follow = !state.follow;
    e.currentTarget.setAttribute('aria-pressed', String(state.follow));
    const bus = Object.values(busMarkers)[0];
    if (state.follow && bus) map.flyTo(bus.getLatLng(), 17, { duration: 0.8 });
  });
  $('toastClose').addEventListener('click', hideToast);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) poll(); });

  // Tempos relativos sem esperar pelo servidor
  setInterval(() => {
    if (document.hidden) return;
    document.querySelectorAll('[data-ago]').forEach((el) => setText(el, ago(el.dataset.ago)));
    if (state.alerts[0]) setText($('kLast'), ago(state.alerts[0].created_at));
    for (const s of Object.values(state.stops)) {
      const el = document.querySelector(`[data-code="${s.codigo}"] [data-f="arr"]`);
      if (el && s.last_arrival) setText(el, ago(s.last_arrival));
    }
  }, 1000);

  if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(() => {});

  syncSoundBtn();
  syncNotifyBtn();
  renderBuses();
  renderHistory();
  poll();
})();
