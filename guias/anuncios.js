/*
 * CONFIGURACIÓN DE ANUNCIOS
 * Si la página se abre dentro de una app (TikTok, Instagram, Facebook, etc.)
 * se muestra un aviso para abrirla en Chrome/Safari y NO se cargan anuncios.
 * En un navegador normal se cargan todos los anuncios desde aquí:
 *  - script general (abscloud)
 *  - banner 728x90 en cada espacio .ad[data-slot] (cada uno en su propio iframe,
 *    porque el código usa document.write). El espacio "lateral" se oculta.
 *  - native banner en el espacio .ad.nativo
 *  - social bar
 */
var SCRIPT_GENERAL = 'https://abscloud.org/1/7e5790aecbe3ed15ee8bcbee42ddff87';
var BANNER = {
  key: '5d3ba1b64069af0d13256ed6ec51523b',
  src: 'https://bauval.org/22/5d3ba1b64069af0d13256ed6ec51523b',
  width: 728,
  height: 90
};
var NATIVE_BANNER = 'https://bauval.org/21/3d4dfeea3a845f33b6ac93b08cdba05f';
var SOCIAL_BAR = 'https://bauval.org/14/d3078e4382072df0bc4db1ac6be7df26';
var SLOTS_ACTIVOS = { arriba: true, medio: true, abajo: true, lateral: false };

(function () {
  var ua = navigator.userAgent || '';
  var enApp = /FBAN|FBAV|FB_IAB|FBIOS|Instagram|TikTok|musical_ly|Bytedance|trill_|Snapchat|Line\/|Twitter|Pinterest|; wv\)/i.test(ua);

  if (enApp) {
    document.querySelectorAll('.ad').forEach(function (el) { el.style.display = 'none'; });
    mostrarAviso(/Android/i.test(ua));
    return;
  }

  cargarScript(SCRIPT_GENERAL, document.head);
  ponerBanners();
  if (document.getElementById('container-3d4dfeea3a845f33b6ac93b08cdba05f')) {
    var n = cargarScript(NATIVE_BANNER, document.body);
    n.async = true;
  }
  cargarScript(SOCIAL_BAR, document.body);

  function cargarScript(src, destino) {
    var s = document.createElement('script');
    s.setAttribute('data-cfasync', 'false');
    s.src = src;
    destino.appendChild(s);
    return s;
  }

  function ponerBanners() {
    var html = '<!DOCTYPE html><html><head><style>html,body{margin:0;padding:0;overflow:hidden}</style></head><body>' +
      '<script>atOptions={"key":"' + BANNER.key + '","format":"iframe","height":' + BANNER.height +
      ',"width":' + BANNER.width + ',"params":{}};<\/script>' +
      '<script src="' + BANNER.src + '"><\/script></body></html>';

    var frames = [];
    document.querySelectorAll('.ad[data-slot]').forEach(function (el) {
      if (!SLOTS_ACTIVOS[el.dataset.slot]) { el.style.display = 'none'; return; }
      el.innerHTML = '<small>Publicidad</small>';
      var box = document.createElement('div');
      box.style.cssText = 'margin:0 auto;overflow:hidden;height:' + BANNER.height + 'px';
      var f = document.createElement('iframe');
      f.width = BANNER.width; f.height = BANNER.height;
      f.setAttribute('scrolling', 'no');
      f.setAttribute('frameborder', '0');
      f.title = 'Publicidad';
      f.style.cssText = 'border:0;display:block;transform-origin:0 0';
      f.srcdoc = html;
      box.appendChild(f);
      el.appendChild(box);
      frames.push(box);
    });

    // En pantallas estrechas se escala el banner para que no se salga
    function ajustar() {
      frames.forEach(function (box) {
        var ancho = box.parentNode.clientWidth;
        var s = Math.min(1, ancho / BANNER.width);
        box.style.width = BANNER.width * s + 'px';
        box.style.height = BANNER.height * s + 'px';
        box.firstChild.style.transform = 'scale(' + s + ')';
      });
    }
    ajustar();
    window.addEventListener('resize', ajustar);
  }

  function mostrarAviso(esAndroid) {
    var url = location.href;
    var aviso = document.createElement('div');
    aviso.style.cssText = 'position:fixed;inset:0;z-index:99999;background:#0f1117;color:#fff;' +
      'display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;' +
      'padding:24px;font:17px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif';
    aviso.innerHTML =
      '<div style="position:absolute;top:10px;right:18px;font-size:44px;line-height:1">↗</div>' +
      '<div style="font-size:48px;margin-bottom:8px">🌐</div>' +
      '<h2 style="margin:0 0 12px;font-size:22px">Abre esta página en tu navegador</h2>' +
      '<p style="margin:0 0 6px;max-width:340px">1. Toca los <b>3 puntitos (⋯)</b> de arriba a la derecha.</p>' +
      '<p style="margin:0 0 20px;max-width:340px">2. Elige <b>"Abrir en el navegador"</b> (Chrome o Safari).</p>' +
      (esAndroid ? '<a id="abrir-chrome" style="display:block;width:100%;max-width:320px;padding:14px;border-radius:12px;' +
        'background:#1f6feb;color:#fff;font-weight:700;text-decoration:none;margin-bottom:10px">Abrir en Chrome</a>' : '') +
      '<button id="copiar-enlace" style="width:100%;max-width:320px;padding:14px;border-radius:12px;border:1px solid #555;' +
        'background:transparent;color:#fff;font:inherit;font-weight:700">Copiar enlace</button>' +
      '<p style="margin:14px 0 0;font-size:14px;color:#aab">Si no ves los 3 puntitos, copia el enlace y pégalo en Chrome o Safari.</p>';
    document.body.appendChild(aviso);
    document.documentElement.style.overflow = 'hidden';

    var chrome = document.getElementById('abrir-chrome');
    if (chrome) {
      chrome.href = 'intent://' + url.replace(/^https?:\/\//, '') +
        '#Intent;scheme=https;package=com.android.chrome;S.browser_fallback_url=' + encodeURIComponent(url) + ';end';
    }
    var copiar = document.getElementById('copiar-enlace');
    copiar.onclick = function () {
      var listo = function () { copiar.textContent = '¡Enlace copiado!'; };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(url).then(listo, function () { prompt('Copia este enlace:', url); });
      } else {
        prompt('Copia este enlace:', url);
      }
    };
  }
})();
