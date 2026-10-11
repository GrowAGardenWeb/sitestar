/*
 * CONFIGURACIÓN DE ANUNCIOS
 * 1. Crea una cuenta en https://www.google.com/adsense y agrega tu dominio.
 * 2. Pega aquí tu ID de editor (empieza con "ca-pub-").
 * 3. En AdSense crea bloques de anuncio y pega cada "data-ad-slot" abajo.
 * Mientras ADSENSE_CLIENT esté vacío se muestran recuadros de ejemplo.
 */
var ADSENSE_CLIENT = ''; // ej: 'ca-pub-1234567890123456'
var AD_SLOTS = {
  arriba:   '', // banner horizontal debajo del menú
  medio:    '', // dentro del contenido / entre tarjetas
  lateral:  '', // barra lateral (300x600)
  abajo:    ''  // al final de la página
};

(function () {
  var ads = document.querySelectorAll('.ad[data-slot]');
  if (!ADSENSE_CLIENT) {
    ads.forEach(function (el) {
      el.innerHTML = '<small>Publicidad</small><div class="ph">Espacio para anuncio (' + el.dataset.slot + ')</div>';
    });
    return;
  }
  var s = document.createElement('script');
  s.async = true;
  s.crossOrigin = 'anonymous';
  s.src = 'https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=' + ADSENSE_CLIENT;
  document.head.appendChild(s);
  ads.forEach(function (el) {
    el.innerHTML = '<small>Publicidad</small><ins class="adsbygoogle" style="display:block" data-ad-client="' +
      ADSENSE_CLIENT + '" data-ad-slot="' + (AD_SLOTS[el.dataset.slot] || '') +
      '" data-ad-format="auto" data-full-width-responsive="true"></ins>';
    (window.adsbygoogle = window.adsbygoogle || []).push({});
  });
})();
