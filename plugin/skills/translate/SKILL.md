---
name: translate
description: Translate Freeroom finding explanations into another language (e.g. es, de)
argument-hint: "<lang>"
allowed-tools: Bash(freeroom *)
disable-model-invocation: true
---

Translate Freeroom's finding explanations into the language with code: $ARGUMENTS

1. Run `freeroom findings` (one plain Bash call) and take each finding's `id` and `explanation`.
2. Translate only the explanations. Keep sizes, paths, commands and product names unchanged,
   and keep each translation as short as the original.
3. Save them in one plain Bash call: `freeroom translate --lang <code> --json '[{"id":"…","text":"…"}]'`.
4. Reply with one line: how many explanations were translated and that Freeroom.app now shows them.

Do not translate anything else and do not re-explain the findings in the chat: translations cost
more tokens than English, so keep this step minimal.
