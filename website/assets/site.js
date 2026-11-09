(function () {
  "use strict";

  var reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var stickyMQ = window.matchMedia("(min-width: 900px)");
  var rafId = 0;
  var pageHidden = document.hidden;
  var fields = [];

  document.documentElement.classList.add("js");
  if (reduced) document.documentElement.classList.add("reduced");

  function clamp(n, a, b) {
    return n < a ? a : n > b ? b : n;
  }

  function onVisible(el, cb, opts) {
    if (!el) return;
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        cb(e.isIntersecting, e);
      });
    }, opts || { threshold: 0.12 });
    io.observe(el);
    return io;
  }

  function keepHash(root) {
    (root || document).querySelectorAll(".lang a").forEach(function (a) {
      a.addEventListener("click", function (e) {
        var hash = location.hash;
        if (!hash || e.defaultPrevented || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
        e.preventDefault();
        location.href = a.getAttribute("href") + hash;
      });
    });
  }

  function setupNav() {
    var nav = document.getElementById("top");
    var btn = nav && nav.querySelector(".menu-btn");
    var panel = document.getElementById("menu");
    if (!nav || !btn || !panel) return;

    function set(open) {
      nav.classList.toggle("is-open", open);
      btn.setAttribute("aria-expanded", open ? "true" : "false");
      btn.setAttribute("aria-label", open ? (btn.getAttribute("data-close") || "Close") : (btn.getAttribute("data-open") || "Menu"));
      if (open) panel.removeAttribute("hidden");
      else {
        setTimeout(function () {
          if (!nav.classList.contains("is-open")) panel.setAttribute("hidden", "");
        }, 320);
      }
      document.body.style.overflow = open ? "hidden" : "";
    }

    btn.addEventListener("click", function () {
      set(!nav.classList.contains("is-open"));
    });

    panel.querySelectorAll("a").forEach(function (a) {
      a.addEventListener("click", function () {
        set(false);
        btn.focus({ preventScroll: true });
      });
    });

    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && nav.classList.contains("is-open")) {
        set(false);
        btn.focus();
      }
    });
    stickyMQ.addEventListener("change", function () {
      if (stickyMQ.matches && nav.classList.contains("is-open")) set(false);
    });
  }

  function Field(canvas, opts) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d", { alpha: true });
    this.density = (opts && opts.density) || 1;
    this.lines = [];
    this.mx = 0.5;
    this.my = 0.5;
    this.hover = 0;
    this.visible = false;
    this.w = 0;
    this.h = 0;
    this.resize();
  }

  Field.prototype.resize = function () {
    var rect = this.canvas.getBoundingClientRect();
    var dpr = Math.min(window.devicePixelRatio || 1, 2);
    this.w = Math.max(1, Math.round(rect.width));
    this.h = Math.max(1, Math.round(rect.height));
    this.canvas.width = Math.round(this.w * dpr);
    this.canvas.height = Math.round(this.h * dpr);
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    var count = Math.round(120 * this.density * clamp(this.w / 1280, 0.55, 1.2));
    this.lines = [];
    for (var i = 0; i < count; i++) {
      this.lines.push({
        x: (i + 0.5) / count,
        phase: Math.random() * Math.PI * 2,
        speed: 0.55 + Math.random() * 0.7,
        base: 0.08 + Math.random() * 0.12,
        dots: Math.random() > 0.62
      });
    }
  };

  Field.prototype.pointer = function (clientX, clientY) {
    var r = this.canvas.getBoundingClientRect();
    this.mx = clamp((clientX - r.left) / r.width, 0, 1);
    this.my = clamp((clientY - r.top) / r.height, 0, 1);
    this.hover = 1;
  };

  Field.prototype.draw = function (t) {
    var ctx = this.ctx;
    var w = this.w;
    var h = this.h;
    ctx.clearRect(0, 0, w, h);
    var amp = 0.22;
    var breath = reduced ? 0 : Math.sin(t * 0.0007) * 0.08;
    var hover = this.hover;
    this.hover *= reduced ? 0 : 0.94;
    for (var i = 0; i < this.lines.length; i++) {
      var L = this.lines[i];
      var x = L.x * w;
      var dx = L.x - this.mx;
      var dy = 0.5 - this.my;
      var dist = Math.sqrt(dx * dx + dy * dy * 0.35);
      var bump = hover * Math.exp(-dist * dist * 18) * 0.55;
      var wave = Math.sin(t * 0.0016 * L.speed + L.phase) * (L.base + breath);
      var mag = clamp(L.base * 0.6 + wave + bump + amp * (0.18 + 0.12 * Math.sin(L.phase + t * 0.002)), 0.04, 0.78);
      var len = h * mag * 0.72;
      var y0 = h * 0.5 - len / 2;
      var y1 = y0 + len;
      var a = 0.18 + mag * 0.55;
      ctx.strokeStyle = "rgba(91,231,255," + a + ")";
      ctx.lineWidth = 1;
      if (L.dots) {
        ctx.fillStyle = "rgba(139,123,255," + (0.18 + mag * 0.5) + ")";
        var steps = 9;
        for (var s = 0; s <= steps; s++) {
          var yy = y0 + (len * s) / steps;
          ctx.beginPath();
          ctx.arc(x, yy, 0.9 + mag * 1.1, 0, Math.PI * 2);
          ctx.fill();
        }
      } else {
        ctx.beginPath();
        ctx.moveTo(x, y0);
        ctx.lineTo(x, y1);
        ctx.stroke();
      }
    }
  };

  function setupFields() {
    var hero = document.getElementById("field");
    var end = document.getElementById("field-end");
    if (hero) fields.push(new Field(hero, { density: 1 }));
    if (end) fields.push(new Field(end, { density: 0.55 }));

    fields.forEach(function (f) {
      onVisible(f.canvas, function (v) {
        f.visible = v;
        if (v) f.resize();
        if (v && reduced) f.draw(0);
        tick();
      }, { threshold: 0.01 });
    });

    var heroEl = document.getElementById("hero");
    if (heroEl && fields[0]) {
      heroEl.addEventListener("pointermove", function (e) {
        fields[0].pointer(e.clientX, e.clientY);
      }, { passive: true });
    }

    function resizeAll() {
      fields.forEach(function (f) { f.resize(); });
      if (reduced) fields.forEach(function (f) { f.draw(0); });
    }
    window.addEventListener("resize", resizeAll);
    window.addEventListener("load", resizeAll);

    if (reduced) {
      fields.forEach(function (f) {
        f.visible = true;
        f.draw(0);
      });
    }
  }

  function tick() {
    if (rafId) return;
    function loop(t) {
      rafId = 0;
      if (pageHidden) return;
      var any = false;
      if (!reduced) {
        for (var i = 0; i < fields.length; i++) {
          if (fields[i].visible) {
            fields[i].draw(t);
            any = true;
          }
        }
      }
      if (any) rafId = requestAnimationFrame(loop);
    }
    rafId = requestAnimationFrame(loop);
  }

  function setupTagline() {
    var chars = Array.prototype.slice.call(document.querySelectorAll("#tagline .t-ch"));
    if (!chars.length) return;
    if (reduced) {
      chars.forEach(function (c) { c.classList.add("lit"); });
      return;
    }

    var section = document.getElementById("tagline");
    var pending = false;
    var last = -1;

    function update() {
      pending = false;
      var r = section.getBoundingClientRect();
      var vh = window.innerHeight || 1;
      var start = vh * 0.78;
      var end = vh * 0.22;
      var p = clamp((start - r.top) / Math.max(start - end, 1), 0, 1);
      var n = Math.floor(p * chars.length + 0.0001);
      if (n === last) return;
      var from = Math.min(last, n);
      var to = Math.max(last, n);
      for (var i = Math.max(0, from); i <= Math.min(chars.length - 1, to); i++) {
        var el = chars[i];
        if (i < n) {
          el.classList.add("lit");
        } else {
          el.classList.remove("lit");
        }
      }
      last = n;
    }

    function onScroll() {
      if (pending) return;
      pending = true;
      requestAnimationFrame(update);
    }

    var watching = false;
    onVisible(section, function (v) {
      if (v && !watching) {
        watching = true;
        window.addEventListener("scroll", onScroll, { passive: true });
        update();
      } else if (!v && watching) {
        watching = false;
        window.removeEventListener("scroll", onScroll);
      }
    }, { threshold: 0, rootMargin: "20% 0px" });
  }

  function setupBento() {
    var cards = document.querySelectorAll(".bento-card");
    cards.forEach(function (card) {
      card.addEventListener("pointermove", function (e) {
        var r = card.getBoundingClientRect();
        card.style.setProperty("--mx", ((e.clientX - r.left) / r.width * 100).toFixed(2) + "%");
        card.style.setProperty("--my", ((e.clientY - r.top) / r.height * 100).toFixed(2) + "%");
      });
      onVisible(card, function (visible) {
        card.classList.toggle("in-view", visible);
      });
    });
  }

  function setupFaq() {
    if (reduced) return;
    document.querySelectorAll(".faq-item").forEach(function (item) {
      var summary = item.querySelector("summary");
      if (!summary) return;
      summary.addEventListener("click", function (e) {
        e.preventDefault();
        if (item.classList.contains("is-open")) {
          item.classList.remove("is-open");
          setTimeout(function () {
            if (!item.classList.contains("is-open")) item.removeAttribute("open");
          }, 520);
        } else {
          item.setAttribute("open", "");
          requestAnimationFrame(function () {
            item.classList.add("is-open");
          });
        }
      });
    });
  }

  function setupFeatures() {
    const section = document.querySelector("#features");
    const track = section.querySelector(".features-track");
    const indicators = [...section.querySelectorAll(".features-progress i")];
    let frame = 0;

    function update() {
      frame = 0;
      if (reduced || !stickyMQ.matches) {
        track.style.transform = "";
        return;
      }
      const distance = Math.max(section.offsetHeight - window.innerHeight, 1);
      const progress = clamp(-section.getBoundingClientRect().top / distance, 0, 1);
      const position = progress * (indicators.length - 1);
      track.style.transform = "translate3d(" + (-position * 100) + "vw,0,0)";
      indicators.forEach((indicator, index) => {
        indicator.classList.toggle("is-on", index === Math.round(position));
      });
    }

    function schedule() {
      if (!frame) frame = requestAnimationFrame(update);
    }

    onVisible(section, (visible) => {
      if (visible) window.addEventListener("scroll", schedule, { passive: true });
      else window.removeEventListener("scroll", schedule);
      schedule();
    }, { threshold: 0 });
    stickyMQ.addEventListener("change", schedule);
    window.addEventListener("resize", schedule, { passive: true });
    schedule();
  }

  function setupDemo() {
    const demo = document.querySelector("#demo");
    const search = demo.querySelector("input");
    const chats = [...demo.querySelectorAll(".demo-chat")];
    const empty = demo.querySelector(".empty");
    const headline = [...demo.querySelectorAll(".demo-headline span")];
    const controls = demo.querySelector(".play-controls");
    const pause = demo.querySelector("#pause");
    const replay = demo.querySelector("#replay");
    const duration = 10500;
    let selected = 0;
    let visible = false;
    let playing = !reduced;
    let elapsed = 0;
    let previousFrame = 0;
    let frame = 0;
    let chapter = -1;

    const buttons = [...demo.querySelectorAll(".demo-row")].map((row, index) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = row.className;
      button.append(...row.childNodes);
      button.addEventListener("click", () => {
        setPlaying(false);
        select(index);
      });
      row.replaceWith(button);
      return button;
    });

    function select(index) {
      selected = index;
      chats.forEach((chat, position) => {
        const active = position === selected;
        chat.hidden = !active;
        buttons[position].classList.toggle("active", active);
        buttons[position].setAttribute("aria-pressed", String(active));
      });
      empty.hidden = selected !== -1;
    }

    function filter() {
      const query = search.value.trim().toLowerCase();
      const matches = chats.map((chat) => chat.textContent.toLowerCase().includes(query));
      buttons.forEach((button, index) => { button.hidden = !matches[index]; });
      select(matches[selected] ? selected : matches.indexOf(true));
    }

    function draw(timestamp) {
      frame = 0;
      if (previousFrame) elapsed = Math.min(elapsed + timestamp - previousFrame, duration);
      previousFrame = timestamp;
      demo.style.setProperty("--progress", elapsed / duration * 100 + "%");
      const next = Math.min(Math.floor(elapsed / (duration / headline.length)), headline.length - 1);
      if (next !== chapter) {
        chapter = next;
        demo.dataset.started = "true";
        headline.forEach((word, index) => word.classList.toggle("current", index === chapter));
        select(chapter);
      }
      if (elapsed === duration) setPlaying(false);
      else schedule();
    }

    function schedule() {
      if (visible && !document.hidden && playing && !frame) frame = requestAnimationFrame(draw);
    }

    function stopFrame() {
      cancelAnimationFrame(frame);
      frame = 0;
      previousFrame = 0;
    }

    function setPlaying(enabled) {
      playing = enabled;
      demo.dataset.playing = String(enabled);
      pause.textContent = enabled ? pause.dataset.pause : pause.dataset.play;
      if (!enabled) stopFrame();
      schedule();
    }

    function restart() {
      search.value = "";
      filter();
      stopFrame();
      elapsed = 0;
      chapter = -1;
      setPlaying(true);
    }

    search.addEventListener("focus", () => setPlaying(false));
    search.addEventListener("input", filter);
    pause.addEventListener("click", () => {
      if (!playing && (elapsed === duration || search.value)) restart();
      else setPlaying(!playing);
    });
    replay.addEventListener("click", restart);
    onVisible(demo.querySelector(".editor"), (inView) => {
      visible = inView;
      if (!visible) stopFrame();
      schedule();
    }, { threshold: .35 });
    document.addEventListener("visibilitychange", () => {
      if (document.hidden) stopFrame();
      schedule();
    });

    select(0);
    search.closest("label").hidden = false;
    controls.hidden = reduced;
    setPlaying(!reduced);
  }

  document.addEventListener("visibilitychange", function () {
    pageHidden = document.hidden;
    document.documentElement.classList.toggle("page-hidden", pageHidden);
    if (!pageHidden) tick();
  });

  keepHash();
  setupNav();
  setupFields();
  setupTagline();
  setupFeatures();
  setupBento();
  setupFaq();
  setupDemo();
  document.querySelectorAll(".hero-ch").forEach((char, index) => {
    char.style.setProperty("--i", index);
  });
  document.documentElement.classList.add("ready");
  requestAnimationFrame(() => {
    requestAnimationFrame(() => document.documentElement.classList.add("booted"));
  });
})();
