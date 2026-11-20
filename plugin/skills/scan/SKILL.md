---
name: scan
description: Analyze what is using disk space on this Mac with the freeroom CLI and record cleanup findings for Freeroom.app. Use when the user asks what is filling their disk or wants to free space. Never deletes anything.
argument-hint: "[path, default ~]"
allowed-tools: Bash(freeroom *)
---

# Freeroom disk analysis

Scan target: $ARGUMENTS (if empty, the home folder `~`).

You are the analysis engine of Freeroom. Your job is to find what uses disk space, understand
it in context, classify it, and record findings with the `freeroom` CLI. **Freeroom.app shows
your findings to the user, who decides and deletes from the app.**

## Hard rules

- **Never delete, move or modify files.** No `rm`, no `mv`, no cleanup commands such as
  `docker prune`, `brew cleanup` or `simctl delete`. You only measure and report. The CLI has no
  delete command on purpose.
- **Measure with `freeroom measure`, not `du`.** `du` double counts hard links (pnpm), descends
  into mounted disk images (Xcode simulator runtimes) and was wrong by tens of GB in real use.
- **Write explanations in English**, 1–2 short sentences. Translation happens later, only on
  request (`/freeroom:translate`), because other languages cost more tokens.
- **Paths you report must exist.** Freeroom re-measures every reported path itself.
- Keep output small: use `--top` to drill down, and do not dump huge listings into the chat.
- **One `freeroom` command per Bash call.** No `&&`, `;`, pipes, variables, `export` or `echo`:
  only plain `freeroom …` calls are pre-approved, anything else needs the user's permission.
  The CLI is already on PATH; never look for it elsewhere.

## Method

1. **Check the setup.** Run `freeroom status`. If `fullDiskAccess` is false, tell the user that
   sizes will be incomplete until their terminal app has Full Disk Access, then continue.
2. **Open a session.** `freeroom scan begin --note "<short note>"`.
3. **Baseline (no AI needed).** Run `freeroom rules`. These are already classified by the rule
   engine (known caches, Docker, simulator runtimes, verified build folders). Do **not** report
   them again; focus on what the rules cannot know.
4. **Explore.** Start with `freeroom measure ~ --top 20` (or the path the user gave), then drill
   into the largest children with `freeroom measure <dir> --top 15`. Go 2–4 levels deep into the
   big ones only. Also look at `freeroom projects` for build folders per project.
5. **Understand before classifying.** Typical things only you can spot:
   - Archives (`.zip`, `.tar`, `.dmg`) next to a folder with the same content already extracted.
   - Old installers, VM images, large videos and exports, forgotten database dumps.
   - Projects that look abandoned (old, no recent changes) with large data folders.
   - App data that is really a cache, under `~/Library/Application Support` or `~/Library/Containers`.
   - iOS device backups in `~/Library/Application Support/MobileSync/Backup`.
   - Duplicated toolchains or several versions of the same SDK or model.
6. **Classify.**
   - `safe`: regenerable, and you can say how (cache, build output, re-downloadable). State the evidence.
   - `review`: user data or anything that may still be needed (documents, media, archives,
     backups, databases, VM images, project data). When in doubt, use `review`.
   - `keep`: system files, app profiles, credentials (`.ssh`, Keychains, `.gnupg`), Docker's disk
     image, active databases. Report a `keep` item only when it is large and the user would wonder about it.
7. **Report** each finding (or an array of them) with `freeroom report --json '<json>'`:

   ```json
   {
     "id": "downloads-zip-duplicate",
     "title": "downloads.zip duplicates an extracted folder",
     "paths": ["~/Documents/downloads.zip"],
     "safety": "review",
     "category": "personal",
     "explanation": "5.6 GB archive whose contents already sit unpacked in the folder next to it.",
     "evidence": "Same top-level entries in the zip listing and in ~/Documents/downloads/",
     "action": "trash"
   }
   ```

   - `category`: docker | xcode | appCaches | devCaches | projects | personal | apps | system | other
   - `action`: `delete` (regenerable), `trash` (default for review), `command` (give the exact
     tool command, e.g. `ollama rm qwen2.5`), `none` (informational).
   - Optional `icon`: `{"app": "<bundle id>"}` when the item belongs to an app (e.g. `com.spotify.client`),
     or `{"brand": "<simple-icons slug>"}` for tools (e.g. `docker`, `nodedotjs`). The app shows it.
   - Use a stable, descriptive `id` slug. Reporting the same id again updates the finding.
   - Group many small similar items into one finding with several paths.
   - Skip anything under 100 MB unless the user asked for detail.
8. **Close the session.** `freeroom scan end`.
9. **Summarize for the user** in their language, briefly: total found per class, the 3–5 biggest
   items, and anything surprising you corrected (double counting, shared hard links). End with:
   "Review and clean in Freeroom.app — nothing has been deleted."
