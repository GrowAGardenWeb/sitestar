/*
 * CONFIGURACIÓN DE ANUNCIOS (Google AdSense)
 * El script de AdSense ya se carga en el <head> de cada página.
 * Para usar bloques fijos: en AdSense crea bloques de anuncio y pega cada "data-ad-slot" abajo.
 * Los espacios sin código se ocultan y AdSense coloca anuncios automáticos (Auto ads).
 */
var ADSENSE_CLIENT = 'ca-pub-9660503457209327';
var AD_SLOTS = {
  arriba:   '', // banner horizontal debajo del menú
  medio:    '', // dentro del contenido / entre tarjetas
  lateral:  '', // barra lateral (300x600)
  abajo:    ''  // al final de la página
};

(function () {
  document.querySelectorAll('.ad[data-slot]').forEach(function (el) {
    var slot = AD_SLOTS[el.dataset.slot];
    if (!ADSENSE_CLIENT || !slot) { el.style.display = 'none'; return; }
    el.innerHTML = '<small>Publicidad</small><ins class="adsbygoogle" style="display:block" data-ad-client="' +
      ADSENSE_CLIENT + '" data-ad-slot="' + slot +
      '" data-ad-format="auto" data-full-width-responsive="true"></ins>';
    (window.adsbygoogle = window.adsbygoogle || []).push({});
  });
})();
