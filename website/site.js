// Two small conveniences; the page reads and works without this file.
(function () {
  "use strict";
  var root = document.documentElement;
  root.classList.add("js");

  // Copy buttons next to install commands.
  document.querySelectorAll(".copy").forEach(function (button) {
    var code = button.parentElement.querySelector("code");
    button.addEventListener("click", function () {
      var text = code.textContent.trim();
      var done = function () {
        button.dataset.state = "done";
        setTimeout(function () { delete button.dataset.state; }, 1800);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done, function () { select(code); });
      } else {
        select(code);
      }
    });
  });

  function select(node) {
    var range = document.createRange();
    range.selectNodeContents(node);
    var selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
  }

  // The app's palettes, applied to this page as colors only. Nothing is stored.
  var palettes = {
    slate: { a: [0.30, 0.46, 0.62], b: [0.80, 0.58, 0.26], l: [0.97, 0.98, 0.99], d: [0.13, 0.14, 0.16] },
    sepia: { a: [0.66, 0.40, 0.24], b: [0.72, 0.45, 0.20], l: [0.96, 0.94, 0.89], d: [0.17, 0.15, 0.12] },
    sage: { a: [0.32, 0.50, 0.40], b: [0.68, 0.55, 0.28], l: [0.96, 0.97, 0.95], d: [0.13, 0.15, 0.13] },
    dusk: { a: [0.48, 0.40, 0.62], b: [0.74, 0.52, 0.38], l: [0.97, 0.96, 0.98], d: [0.15, 0.14, 0.18] },
    monochrome: { a: [0.15, 0.15, 0.15], b: [0.15, 0.15, 0.15], l: [0.98, 0.98, 0.98], d: [0.12, 0.12, 0.12], ad: [0.88, 0.88, 0.88] },
    nordic: { a: [0.36, 0.48, 0.60], b: [0.78, 0.62, 0.38], l: [0.97, 0.98, 0.99], d: [0.13, 0.15, 0.18] },
    espresso: { a: [0.68, 0.46, 0.24], b: [0.72, 0.40, 0.22], l: [0.98, 0.96, 0.93], d: [0.15, 0.13, 0.11] },
    matcha: { a: [0.34, 0.48, 0.36], b: [0.74, 0.60, 0.32], l: [0.96, 0.97, 0.95], d: [0.12, 0.15, 0.13] },
    bordeaux: { a: [0.62, 0.32, 0.38], b: [0.76, 0.58, 0.34], l: [0.98, 0.96, 0.97], d: [0.16, 0.13, 0.15] },
    solarized: { a: [0.18, 0.50, 0.56], b: [0.68, 0.52, 0.16], l: [0.95, 0.93, 0.85], d: [0.04, 0.19, 0.23] }
  };
  var tokens = ["--accent", "--accent-text", "--amber", "--bg", "--surface", "--surface-2", "--line"];
  var scheme = window.matchMedia("(prefers-color-scheme: dark)");
  var current = "slate";

  function mix(from, to, t) { return from.map(function (v, i) { return v + (to[i] - v) * t; }); }
  function css(c) { return "rgb(" + c.map(function (v) { return Math.round(v * 255); }).join(",") + ")"; }
  function luminance(c) { return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; }

  function apply(name) {
    current = name;
    var p = palettes[name];
    if (name === "slate") {
      tokens.forEach(function (token) { root.style.removeProperty(token); });
      return;
    }
    var dark = scheme.matches;
    var bg = dark ? p.d : p.l;
    var accent = dark ? (p.ad || mix(p.a, [1, 1, 1], 0.28)) : p.a;
    var white = [1, 1, 1], black = [0, 0, 0];
    var values = {
      "--accent": css(accent),
      "--accent-text": luminance(accent) > 0.55 ? "#14171b" : "#ffffff",
      "--amber": css(dark ? mix(p.b, white, 0.12) : p.b),
      "--bg": css(bg),
      "--surface": css(dark ? mix(bg, white, 0.05) : mix(bg, white, 0.55)),
      "--surface-2": css(dark ? mix(bg, white, 0.1) : mix(bg, black, 0.04)),
      "--line": css(dark ? mix(bg, white, 0.17) : mix(bg, black, 0.12))
    };
    Object.keys(values).forEach(function (token) { root.style.setProperty(token, values[token]); });
  }

  var label = document.getElementById("swatch-name");
  document.querySelectorAll(".swatch").forEach(function (swatch) {
    swatch.addEventListener("click", function () {
      document.querySelectorAll(".swatch").forEach(function (other) { other.setAttribute("aria-pressed", String(other === swatch)); });
      apply(swatch.dataset.palette);
      if (label) label.textContent = swatch.dataset.name;
    });
  });
  scheme.addEventListener("change", function () { apply(current); });
})();
