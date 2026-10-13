/*
 * CONFIGURACIÓN DE ANUNCIOS
 * El script general (abscloud) se carga en el <head> de cada página.
 * Cada espacio .ad[data-slot] muestra un banner 728x90 dentro de un iframe
 * (el código del banner usa document.write, por eso va aislado en su propio iframe).
 * El espacio "lateral" se oculta porque el banner de 728px no cabe en la barra lateral.
 */
var BANNER = {
  key: '5d3ba1b64069af0d13256ed6ec51523b',
  src: 'https://bauval.org/22/5d3ba1b64069af0d13256ed6ec51523b',
  width: 728,
  height: 90
};
var SLOTS_ACTIVOS = { arriba: true, medio: true, abajo: true, lateral: false };

(function () {
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
})();
