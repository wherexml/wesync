(function () {
  "use strict";

  var reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var stickyMQ = window.matchMedia("(min-width: 900px)");

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
    const stage = demo.querySelector(".demo-stage");
    const steps = [...demo.querySelectorAll(".demo-headline a")];
    const scenes = [...stage.querySelectorAll(".demo-scene")];
    const codex = demo.querySelector(".codex-scene");
    const search = demo.querySelector("input");
    const results = [...demo.querySelectorAll(".demo-result")];
    const empty = demo.querySelector(".empty");
    const controls = demo.querySelector(".play-controls");
    const pause = demo.querySelector("#pause");
    const replay = demo.querySelector("#replay");
    const chapterLength = 3400;
    const duration = steps.length * chapterLength;
    let visible = false;
    let playing = !reduced;
    let elapsed = 0;
    let previousFrame = 0;
    let frame = 0;
    let chapter = -1;

    function showChapter(next) {
      if (chapter === next) return;
      chapter = next;
      scenes.forEach((scene, index) => {
        const current = index === next;
        scene.hidden = !current;
        if (current) steps[index].setAttribute("aria-current", "step");
        else steps[index].removeAttribute("aria-current");
      });
    }

    function filter() {
      const query = search.value.trim().toLowerCase();
      let hasResults = false;
      results.forEach((result) => {
        const matches = result.querySelector("p").textContent.toLowerCase().includes(query);
        result.hidden = !matches;
        hasResults ||= matches;
      });
      empty.hidden = hasResults;
    }

    function renderProgress() {
      const next = Math.min(Math.floor(elapsed / chapterLength), steps.length - 1);
      demo.style.setProperty("--progress", elapsed / duration * 100 + "%");
      codex.classList.toggle("is-composing", next === 2 && elapsed < 2 * chapterLength + 1000);
      showChapter(next);
    }

    function draw(timestamp) {
      frame = 0;
      if (previousFrame) elapsed = Math.min(elapsed + timestamp - previousFrame, duration);
      previousFrame = timestamp;
      renderProgress();
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
      pause.textContent = enabled ? pause.dataset.pause : pause.dataset.play;
      if (!enabled) stopFrame();
      schedule();
    }

    function restart() {
      search.value = search.defaultValue;
      filter();
      stopFrame();
      elapsed = 0;
      renderProgress();
      setPlaying(true);
    }

    steps.forEach((step, index) => {
      step.addEventListener("click", (event) => {
        event.preventDefault();
        setPlaying(false);
        elapsed = index * chapterLength + (index === 2 ? 1000 : 0);
        renderProgress();
      });
    });
    search.addEventListener("focus", () => setPlaying(false));
    search.addEventListener("input", filter);
    pause.addEventListener("click", () => {
      if (elapsed === duration) restart();
      else setPlaying(!playing);
    });
    replay.addEventListener("click", restart);
    onVisible(stage, (inView) => {
      visible = inView;
      if (!visible) stopFrame();
      schedule();
    }, { threshold: .35 });
    document.addEventListener("visibilitychange", () => {
      if (document.hidden) stopFrame();
      schedule();
    });

    search.readOnly = false;
    controls.hidden = reduced;
    renderProgress();
    setPlaying(!reduced);
  }

  document.addEventListener("visibilitychange", function () {
    document.documentElement.classList.toggle("page-hidden", document.hidden);
  });

  keepHash();
  setupNav();
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
