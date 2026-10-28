/* Minijuego "El salón vs el Quiz".
   El presentador maneja el juego: el salón responde en voz alta o con los dedos (1-4) y el presentador toca la respuesta. */
window.Quiz = (() => {
  const SECONDS = 20;
  const QUESTIONS = [
    { img: 'img/q-senal.webp', q: '¿Qué tipo de recurso es este?', a: 'Señal o pictograma',
      w: ['Folleto o tríptico', 'Infografía', 'Presentación digital'] },
    { q: 'Los carteles y afiches se pueden colocar en…', a: 'Escuelas, parques y espacios públicos',
      w: ['Solo dentro de un videojuego', 'Solo en el refri de la casa', 'En ningún lugar'] },
    { img: 'img/q-info.webp', q: '¿Y este recurso cuál es?', a: 'Infografía',
      w: ['Señal de tránsito', 'Video', 'Foto de perfil'] },
    { q: 'Los recursos digitales (videos, publicaciones, presentaciones) sirven para…', a: 'Difundir campañas y llegar a más personas',
      w: ['Guardar el celular', 'Borrar información', 'Hacer ruido en el salón'] },
    { img: 'img/q-folleto.webp', q: 'Ofrece información detallada sobre campañas de salud y servicios. ¿Qué es?', a: 'Folleto o tríptico',
      w: ['Cartel', 'Señal', 'Emoji'] },
    { q: 'Los recursos visuales y gráficos combinan…', a: 'Imágenes, colores, símbolos, dibujos y textos',
      w: ['Solo sonidos', 'Solo números', 'Solo olores'] }
  ];
  const STAR = on => `<svg class="${on ? '' : 'off'}" viewBox="0 0 100 100"><path d="M50 6l13 30 32 3-24 22 7 32-28-17-28 17 7-32L5 39l32-3z" fill="#ffc400" stroke="#05122e" stroke-width="7" stroke-linejoin="round"/></svg>`;
  const LETTERS = ['A', 'B', 'C', 'D'];
  const shuffle = a => { a = a.slice(); for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; };
  const h = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };

  // sonidos simples (se crean solo al primer toque, por las reglas del navegador)
  let ac;
  function tone(freqs, dur = .14, type = 'square', vol = .06) {
    try {
      ac = ac || new (window.AudioContext || window.webkitAudioContext)();
      const t0 = ac.currentTime;
      freqs.forEach((f, i) => {
        const o = ac.createOscillator(), g = ac.createGain();
        o.type = type; o.frequency.value = f; o.connect(g); g.connect(ac.destination);
        g.gain.setValueAtTime(vol, t0 + i * dur); g.gain.exponentialRampToValueAtTime(.001, t0 + (i + 1) * dur);
        o.start(t0 + i * dur); o.stop(t0 + (i + 1) * dur + .02);
      });
    } catch (e) {}
  }
  const sfx = { ok: () => tone([660, 880, 1320], .12), no: () => tone([220, 150], .22, 'sawtooth'), tick: () => tone([880], .05, 'sine', .03), win: () => tone([523, 659, 784, 1047], .14) };

  function create(root, cb) {
    const el = h('div', 'quiz'); root.appendChild(el);
    const intro = h('div', 'scr'), play = h('div', 'scr play'), end = h('div', 'scr');
    el.append(intro, play, end);

    // ---- intro
    intro.innerHTML = `
      <h1>¡EL SALÓN <em>VS</em><br>EL QUIZ!</h1>
      <div class="sub">¿Cuánto aprendieron? Respondan entre todos, en voz alta o levantando <b>1, 2, 3 o 4 dedos</b>.</div>
      <div class="rules">
        <div class="rule panel"><b>6</b><span>preguntas</span></div>
        <div class="rule panel"><b>${SECONDS}s</b><span>para responder</span></div>
        <div class="rule panel"><b>+50</b><span>por racha de aciertos</span></div>
      </div>
      <button class="btn" data-a="go">JUGAR</button>
      <button class="link l" data-a="back">◀ Volver</button>
      <button class="link r" data-a="skip">Saltar juego ▶</button>`;

    // ---- estado
    let qs, idx, score, streak, results, locked, tmr, tStart, answered;

    const scoreTxt = () => `Puntos: ${score}${streak > 1 ? ` · Racha x${streak}` : ''}`;
    function clearT() { clearInterval(tmr); tmr = null; }
    function show(s) { [intro, play, end].forEach(x => x.classList.toggle('on', x === s)); }

    function start() {
      qs = shuffle(QUESTIONS).map(q => ({ ...q, opts: shuffle([q.a, ...q.w]) }));
      idx = 0; score = 0; streak = 0; results = [];
      ask();
    }

    function ask() {
      const q = qs[idx]; locked = false; answered = false;
      play.innerHTML = '';
      const top = h('div', 'top');
      top.append(h('div', 'pill panel', `<span>Pregunta ${idx + 1}/${qs.length}</span>`));
      const pips = h('div', 'pips');
      qs.forEach((_, i) => pips.append(h('i', 'pip ' + (i < idx ? (results[i] ? 'ok' : 'bad') : i === idx ? 'now' : ''))));
      top.append(pips, h('div', 'pill panel', `<span>${scoreTxt()}</span>`));
      const timer = h('div', 'timer'); const bar = h('i'); timer.append(bar);
      const qbox = h('div', 'qbox');
      if (q.img) { const im = h('img', 'qimg'); im.src = q.img; im.alt = ''; qbox.append(im); }
      qbox.append(h('div', 'qtxt panel', `<small>¡Salón, pónganse de acuerdo!</small><span class="t">${q.q}</span>`));
      const opts = h('div', 'opts');
      q.opts.forEach((o, i) => {
        const b = h('button', 'opt panel', `<span class="ltr">${LETTERS[i]}</span><span class="txt">${o}</span>`);
        b.onclick = e => { e.stopPropagation(); pick(i); };
        opts.append(b);
      });
      const fb = h('div', 'fb'); const next = h('button', 'btn blue next', idx === qs.length - 1 ? 'Ver resultado ▶' : 'Siguiente ▶');
      next.onclick = e => { e.stopPropagation(); idx === qs.length - 1 ? finish() : (idx++, ask()); };
      play.append(top, timer, qbox, opts, fb, next);
      play._ = { bar, timer, opts, fb, next };
      show(play);

      tStart = performance.now(); let lastSec = -1;
      clearT();
      tmr = setInterval(() => {
        const left = Math.max(0, SECONDS - (performance.now() - tStart) / 1000);
        bar.style.transform = `scaleX(${left / SECONDS})`;
        timer.classList.toggle('low', left <= 5);
        const sec = Math.ceil(left);
        if (left <= 5 && sec !== lastSec && sec > 0) sfx.tick();
        lastSec = sec;
        if (left <= 0) pick(-1);
      }, 100);
    }

    function pick(i) {
      if (locked) return; locked = true; clearT();
      const q = qs[idx], u = play._, btns = [...u.opts.children];
      const ci = q.opts.indexOf(q.a), ok = i === ci;
      results[idx] = ok;
      u.opts.classList.add('done');
      btns.forEach(b => b.disabled = true);
      btns[ci].classList.add('right');
      let msg, cls;
      if (ok) { streak++; const pts = 100 + (streak > 1 ? 50 : 0); score += pts; msg = `¡CORRECTO! +${pts}`; cls = 'ok'; sfx.ok(); }
      else { streak = 0; if (i >= 0) btns[i].classList.add('wrong'); msg = i < 0 ? '¡SE ACABÓ EL TIEMPO!' : '¡UY! CASI'; cls = i < 0 ? 'time' : 'no'; sfx.no(); }
      u.fb.className = 'fb on ' + cls; u.fb.innerHTML = `<div class="msg panel"><span>${msg}</span></div>`;
      setTimeout(() => u.fb.classList.remove('on'), 1500);
      u.next.classList.add('on');
      const nowPill = play.querySelector('.top .pill:last-child'); if (nowPill) nowPill.firstChild.textContent = scoreTxt();
      const pipEls = play.querySelectorAll('.pip'); pipEls[idx].className = 'pip ' + (ok ? 'ok' : 'bad');
    }

    function finish() {
      clearT();
      const good = results.filter(Boolean).length, stars = good >= 6 ? 3 : good >= 4 ? 2 : good >= 2 ? 1 : 0;
      const title = stars === 3 ? '¡LEYENDAS DEL SALÓN!' : stars === 2 ? '¡MUY BIEN, SALÓN!' : stars === 1 ? '¡BUEN INTENTO!' : '¡A PRACTICAR!';
      const sub = stars === 3 ? 'Respondieron todo bien. ¡Cero errores!' : `Acertaron ${good} de ${qs.length} preguntas.`;
      end.innerHTML = `
        <h1>${title}</h1>
        <div class="stars">${[0, 1, 2].map(i => STAR(i < stars)).join('')}</div>
        <div class="final-score">${score} puntos</div>
        <div class="sub">${sub}</div>
        <div class="row">
          <button class="btn blue" data-a="again">↻ Otra vez</button>
          <button class="btn" data-a="done">Continuar ▶</button>
        </div>`;
      show(end);
      if (stars > 0) { sfx.win(); cb.onWin && cb.onWin(); }
    }

    // botones (intro / final)
    el.addEventListener('click', e => {
      const a = e.target.closest('[data-a]'); if (!a) return;
      e.stopPropagation();
      ({ go: start, back: () => cb.onBack && cb.onBack(), skip: () => cb.onFinish && cb.onFinish(),
         again: start, done: () => cb.onFinish && cb.onFinish() })[a.dataset.a]();
    });

    return {
      reset() { clearT(); show(intro); },
      stop: clearT,
      // teclas A-D o 1-4 eligen respuesta; Enter/espacio avanzan
      key(k) {
        if (play.classList.contains('on')) {
          const i = '1234'.indexOf(k) >= 0 ? '1234'.indexOf(k) : 'abcd'.indexOf(k.toLowerCase());
          if (i >= 0 && i < 4 && !locked) return pick(i), true;
          if ((k === 'Enter' || k === ' ' || k === 'ArrowRight') && locked) { play._.next.click(); return true; }
        } else if (k === 'Enter' || k === ' ') { (intro.classList.contains('on') ? intro : end).querySelector(intro.classList.contains('on') ? '[data-a="go"]' : '[data-a="done"]').click(); return true; }
        return false;
      }
    };
  }
  return { create };
})();
