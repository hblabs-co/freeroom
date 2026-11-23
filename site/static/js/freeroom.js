// Freeroom landing: progressive enhancements only.
//  1. Double-submit CSRF: copy the fr_csrf cookie into the form's
//     hidden _csrf field at submit time (the token is never in the
//     cached HTML; see request/handler.go).
//  2. Copy buttons on command blocks.
(function () {
  "use strict";

  function cookie(name) {
    var parts = document.cookie.split("; ");
    for (var i = 0; i < parts.length; i++) {
      var kv = parts[i].split("=");
      if (kv[0] === name) return decodeURIComponent(kv.slice(1).join("="));
    }
    return "";
  }

  document.querySelectorAll("form[data-csrf-form]").forEach(function (form) {
    form.addEventListener("submit", function () {
      var field = form.querySelector('input[name="_csrf"]');
      if (field) field.value = cookie("fr_csrf");
    });
  });

  if (!navigator.clipboard) return;
  document.querySelectorAll(".code").forEach(function (block) {
    var btn = document.createElement("button");
    btn.type = "button";
    btn.className = "hb-btn hb-btn--ghost hb-btn--sm code__copy";
    btn.textContent = block.dataset.copyLabel || "Copy";
    btn.addEventListener("click", function () {
      var text = block.querySelector("code").textContent;
      navigator.clipboard.writeText(text).then(function () {
        btn.textContent = block.dataset.copiedLabel || "Copied";
        setTimeout(function () { btn.textContent = block.dataset.copyLabel || "Copy"; }, 1600);
      });
    });
    block.appendChild(btn);
  });
})();
