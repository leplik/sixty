// Tiny progressive enhancement: copy button + looping demo countdown. No network.
(function () {
  var b = document.querySelector('[data-copy]');
  if (b && navigator.clipboard) {
    b.hidden = false;
    b.addEventListener('click', function () {
      navigator.clipboard.writeText(b.getAttribute('data-copy')).then(function () {
        var t = b.textContent; b.textContent = b.getAttribute('data-done');
        setTimeout(function () { b.textContent = t; }, 1600);
      });
    });
  }
  var n = document.querySelector('[data-ring-num]'), fg = document.querySelector('.ring .fg');
  if (!n || !fg || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  var s = 42, c = 439.8;
  setInterval(function () {
    s = s <= 0 ? 60 : s - 1;
    n.textContent = s;
    fg.style.transition = s === 60 ? 'none' : '';
    fg.style.strokeDashoffset = c * (1 - s / 60);
  }, 1000);
})();
