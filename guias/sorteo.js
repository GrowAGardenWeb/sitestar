/*
 * SORTEO — widget de participación.
 *
 * CONFIGURA AQUÍ:
 *   SORTEO_WEBHOOK_URL — tu webhook de Discord (Configuración del canal ->
 *                        Integraciones -> Webhooks -> Copiar URL).
 *
 * Nota de seguridad: esto manda el POST directo desde el navegador al
 * webhook, así que la URL queda visible en el código fuente de la página.
 * Cualquiera podría encontrarla y mandar entradas falsas al canal. Para un
 * sorteo informal no es grave (lo peor que pasa es spam en el canal), pero
 * si en algún momento esto maneja algo más sensible, conviene meter un
 * backend intermedio (igual que el Worker de moneyscripts-stripe) en vez de
 * pegar el webhook acá directo.
 */
var SORTEO_WEBHOOK_URL = 'https://discord.com/api/webhooks/E210MX105G9660503457209327';
var SORTEO_RETRY_MS = 3 * 60 * 1000; // si falla el envío, reintenta en silencio cada 3 minutos

(function () {
  function alreadyEntered() {
    try { return !!localStorage.getItem('sorteo_entrado'); } catch (e) { return false; }
  }
  function markEntered() {
    try { localStorage.setItem('sorteo_entrado', '1'); } catch (e) {}
  }

  function render(container) {
    if (alreadyEntered()) {
      container.innerHTML =
        '<div class="sorteo-box sorteo-done">' +
        '<div class="sorteo-emoji">🎉</div>' +
        '<div><b>¡Ya estás participando!</b></div>' +
        '</div>';
      return;
    }

    container.innerHTML =
      '<div class="sorteo-box">' +
      '<div class="sorteo-form">' +
      '<input type="text" class="sorteo-input" placeholder="Ingresa tu usuario aquí" maxlength="40" autocomplete="off">' +
      '<button type="button" class="sorteo-btn">Participar</button>' +
      '</div>' +
      '<div class="sorteo-status"></div>' +
      '</div>';

    var input = container.querySelector('.sorteo-input');
    var btn = container.querySelector('.sorteo-btn');
    var status = container.querySelector('.sorteo-status');

    btn.addEventListener('click', function () {
      var username = input.value.trim();
      if (!username) {
        status.textContent = 'Escribí tu usuario de Roblox primero.';
        status.className = 'sorteo-status err';
        return;
      }

      btn.disabled = true;
      input.disabled = true;
      status.textContent = 'Enviando...';
      status.className = 'sorteo-status';

      function attempt() {
        fetch(SORTEO_WEBHOOK_URL, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            content: '🎟️ Nueva participación en el sorteo — usuario de Roblox: **' + username + '**',
          }),
        })
          .then(function (res) {
            if (!res.ok) throw new Error('bad status ' + res.status);
            markEntered();
            render(container);
          })
          .catch(function () {
            // No mostramos error: reintentamos en silencio más tarde en vez
            // de asustar al participante con un mensaje de fallo.
            setTimeout(attempt, SORTEO_RETRY_MS);
          });
      }
      attempt();
    });
  }

  document.querySelectorAll('[data-sorteo]').forEach(render);
})();
