(function () {
  var rs = document.querySelectorAll('.how h2, .card, .facts h2, .tile, .install h2, .brew, .install .cta');
  rs.forEach(function (el, i) { el.classList.add('rise'); el.style.setProperty('--d', (i % 4) * 80 + 'ms'); });
  if ('IntersectionObserver' in window) {
    var io = new IntersectionObserver(function (es) { es.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); } }); }, { threshold: 0.12 });
    rs.forEach(function (el) { io.observe(el); });
  } else { rs.forEach(function (el) { el.classList.add('in'); }); }
  // The live thing: lock the keys, and typing really does nothing until the timer ends
  var box = document.getElementById('try-box');
  var hud = document.getElementById('hud');
  var title = document.getElementById('hud-title');
  var time = document.getElementById('hud-time');
  var ignored = document.getElementById('ignored');
  var lockBtn = document.getElementById('lock-btn');
  var unlockBtn = document.getElementById('hud-unlock');
  if (!box || !hud) return;

  var SECONDS = 12, locked = false, tick = null, hideT = null, flashT = null;

  function fmt(s) { s = Math.max(0, Math.ceil(s)); return Math.floor(s / 60) + ':' + ('0' + (s % 60)).slice(-2); }
  function label(e) {
    var k = e.key === 'Enter' ? '↵' : e.key === ' ' ? 'Space' : e.key === 'Backspace' ? '⌫' : e.key.length === 1 ? e.key.toUpperCase() : e.key;
    return (e.metaKey ? '⌘' : '') + (e.ctrlKey ? '⌃' : '') + (e.altKey ? '⌥' : '') + k;
  }
  function flash(text) {
    ignored.textContent = text + ' does nothing while the keys are off';
    ignored.setAttribute('data-on', '');
    clearTimeout(flashT); flashT = setTimeout(function () { ignored.removeAttribute('data-on'); }, 1100);
  }
  function lock() {
    if (locked) return;
    locked = true; clearTimeout(hideT);
    var end = Date.now() + SECONDS * 1000;
    title.textContent = 'Shh, your keys are napping'; hud.setAttribute('data-sky', '0');
    hud.setAttribute('data-on', ''); lockBtn.disabled = true;
    box.focus();
    tick = setInterval(function () {
      var left = (end - Date.now()) / 1000, p = 1 - left / SECONDS;
      time.textContent = fmt(left);
      hud.setAttribute('data-sky', p > 0.8 ? '2' : p > 0.4 ? '1' : '0');
      if (left <= 0) unlock(true);
    }, 200);
  }
  function unlock(done) {
    if (!locked) return;
    locked = false; clearInterval(tick); lockBtn.disabled = false;
    if (done) { title.textContent = 'Good morning!'; time.textContent = 'Your keys are back'; hud.setAttribute('data-sky', '2'); }
    hideT = setTimeout(function () { hud.removeAttribute('data-on'); time.textContent = fmt(SECONDS); }, done ? 2200 : 0);
    box.focus();
  }

  box.addEventListener('keydown', function (e) {
    if (locked) { e.preventDefault(); if (!e.repeat && e.key !== 'Meta' && e.key !== 'Control' && e.key !== 'Alt' && e.key !== 'Shift') flash(label(e)); }
  });
  box.addEventListener('beforeinput', function (e) { if (locked) e.preventDefault(); });
  box.addEventListener('paste', function (e) { if (locked) e.preventDefault(); });
  document.addEventListener('keydown', function (e) {
    if (e.ctrlKey && e.altKey && e.metaKey && e.code === 'KeyK') { e.preventDefault(); lock(); }
  });
  lockBtn.addEventListener('click', lock);
  unlockBtn.addEventListener('click', function () { unlock(false); });
})();
