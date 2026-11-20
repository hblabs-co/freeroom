# Known-locations catalog

`Sources/FreeroomCore/Resources/catalog.json` lists **240** places on macOS that take up disk
space. Each entry has a safety class, a cleanup action and an icon. It replaces the
hand-written list in `Catalog.swift`. All 30 existing ids are kept. Some of their paths
were made narrower (see "Changes to existing entries").

The data was checked on 2026-11-20 on macOS 26 (Darwin 25.4), Apple Silicon.

## Shape

```jsonc
{
  "id": "go-modcache",                 // stable kebab-case, never reused
  "title": "Go module cache",
  "paths": ["~/go/pkg/mod"],           // literal paths, "~" = home; no globs, no $VARS
  "category": "devCaches",             // docker|xcode|appCaches|devCaches|projects|personal|apps|system|other
  "safety": "safe",                    // safe|review|keep
  "action": "command",                 // delete|trash|command|none
  "command": "go clean -modcache",     // only when action == command, and only allowlisted commands
  "proposedCommand": "…",              // optional: the tool's own cleanup command, NOT on the allowlist yet
  "needsAdmin": false,
  "explanation": "…",                  // English, at most 140 characters
  "icon": { "app": "com.example.App", "brand": "go", "symbol": "shippingbox" },
  "confidence": "high",                // high|medium
  "source": "https://go.dev/ref/mod",  // official doc URL, or "observed on macOS"
  "popularity": 4                      // 1–5, how common on developer Macs
}
```

`proposedCommand` is an extra field. Swift's `Codable` ignores it until `KnownLocation` gains it.

`paths` is empty for 8 entries whose size is not in a folder (Docker build cache and images
inside `Docker.raw`, unavailable simulators, Time Machine snapshots). Size them with a probe,
such as `docker system df`, not with the measurer.

## Counts

| Category   | Entries | safe | review | keep |
|------------|--------:|-----:|-------:|-----:|
| docker     | 14 | 4  | 10 | 0  |
| xcode      | 14 | 10 | 4  | 0  |
| appCaches  | 42 | 38 | 4  | 0  |
| devCaches  | 89 | 57 | 32 | 0  |
| projects   | 1  | 0  | 1  | 0  |
| personal   | 19 | 0  | 14 | 5  |
| apps       | 5  | 0  | 5  | 0  |
| system     | 51 | 2  | 1  | 48 |
| other (VMs)| 5  | 0  | 5  | 0  |
| **total**  | **240** | **111** | **76** | **53** |

- **Action:** 98 delete, 13 trash, 14 command, 115 none (informational or "use the app's own UI").
- **Confidence:** 146 high, 94 medium.
- **Source:** 111 official doc URLs, 125 observed on this Mac, 4 earlier entries not yet verified (see below).
  For every doc URL, the page was downloaded and checked to contain the path (or command) the entry relies on.
- **Icon (best available):** 101 `app` bundle ids, 88 `brand` only, 51 `symbol` only.
  156 entries have a Simple Icons brand (68 also have an app id). Every entry has an SF Symbol fallback.
  79 distinct symbols are used, all present in macOS's `name_availability.plist` and all available since macOS 13.
  Of the 54 app bundle ids, 37 were checked against apps installed on this Mac. The other 17 are well known ids
  (LM Studio, Android Studio, Figma, OrbStack, Parallels, UTM…). They could not be checked locally. A wrong id is
  harmless: `urlForApplication(withBundleIdentifier:)` returns nil, and the app falls back to brand, then symbol.
- **Simple Icons:** version **16.38.0**. 76 SVGs are in `design/catalog-icons/`, each checked to exist in that package.
  Not in Simple Icons (we fall back to the app icon or a symbol): Slack, Microsoft (Teams, Office, Edge, VS Code),
  Adobe, OpenAI/ChatGPT, Parallels, UTM, OrbStack, Colima, Lima, minikube, Playwright, Apple's own apps
  (Final Cut, Logic, GarageBand, iMovie).

## Classification rules used

- **safe**: data the tool regenerates by itself (caches, build output, downloaded packages, logs, update
  leftovers). The explanation says how it comes back. Electron and Chromium app caches are `safe` but say
  "quit the app first".
- **review**: anything holding user content or things installed on purpose: projects, VMs, Docker volumes and
  images, downloaded AI models, offline media, Node/Python/Ruby/Rust versions, IDE extensions.
  Usually `action: none` with a pointer to the tool's own removal command or UI. `trash` is used only where the
  folder can simply be re-downloaded.
- **keep**: system areas, credentials (`~/.ssh`, `~/.aws`, `~/.kube`, keychains, Terraform/gcloud tokens),
  message and mail databases, and the parent folders that `Cleaner.protectedRelative` already guards.
  Always `action: none`.
- No `delete`/`trash` entry points at a path that `Cleaner.refusal(for:)` would reject: inside home,
  not a protected folder, not under a forbidden tree. Paths outside home are `action: none`, and use
  `needsAdmin: true` where root is needed.
- No path appears in two non-`keep` entries, and none is nested inside another non-`keep` entry, so totals
  are not counted twice.

## Changes to existing entries

| id | Change | Why |
|----|--------|-----|
| `browser-caches` | `~/Library/Caches/Google` narrowed to `~/Library/Caches/Google/Chrome`; added `~/Library/Caches/Arc` | `Caches/Google` also holds Android Studio's versioned caches; the Chrome path is documented by Chromium. |
| `updater-caches` | `electron` and `electron-builder` caches moved to the new `electron-cache` (devCaches); added the Lens ShipIt cache | They are build-tool downloads, not app updaters. |
| `pip-cache` | command `pip cache purge` changed to `pip3 cache purge` | Stock macOS has `pip3` but often no `pip`. Both are allowlisted. |
| `xcode-device-support` | added tvOS, visionOS and macOS DeviceSupport folders | Same kind of data. |
| `xcode-derived-data`, `go-*`, `npm-cache`, … | gained `icon`, `confidence`, `source`, `popularity` | — |

## Commands proposed for the allowlist

None of these is in `Cleaner.allowedCommands`. Entries carry them as `proposedCommand` and keep
`action: delete` or `none` until they are allowlisted. Each one is plain (no shell syntax) and passes
`Cleaner.tokenize`. Each one only removes regenerable data, or (`review` ones) removes what the tool
itself considers unused.

| Command | Entry | Prefix / max extra args | Why | Doc |
|---|---|---|---|---|
| `uv cache clean` | uv-cache | `uv cache clean` / 0 | Official way to clear uv's cache; safe while no uv process runs. `uv cache prune` (unused entries only) is a gentler option. | https://docs.astral.sh/uv/concepts/cache/ |
| `bun pm cache rm` | bun-cache | `bun pm cache rm` / 0 | Clears Bun's global install cache. | https://bun.sh/docs/cli/pm |
| `deno clean` | deno-cache | `deno clean` / 0 | Removes Deno's global module cache. | https://docs.deno.com/runtime/reference/cli/clean/ |
| `pod cache clean --all` | cocoapods-cache | `pod cache clean` / 1 | `--all` clears every cached pod without asking. | https://github.com/CocoaPods/CocoaPods/blob/master/lib/cocoapods/command/cache/clean.rb |
| `swift package purge-cache` | swiftpm-cache | `swift package purge-cache` / 0 | Purges SwiftPM's global repository cache (checked with `--help` on this Mac). | https://www.swift.org/documentation/package-manager/ |
| `conda clean --all --yes` | conda-pkgs | `conda clean --all` / 1 | Removes tarballs, unused packages and caches; `--yes` skips the prompt. Environments are kept. | https://docs.conda.io/projects/conda/en/stable/commands/clean.html |
| `composer clear-cache` | composer-cache | `composer clear-cache` / 0 | Composer's own cache wipe. | https://getcomposer.org/doc/03-cli.md |
| `ccache -C` | ccache | `ccache -C` / 0 | `-C/--clear` empties the cache. | https://ccache.dev/manual/latest.html |
| `brew autoremove` | homebrew-cellar | `brew autoremove` / 0 | Uninstalls formulae installed only as dependencies that nothing needs any more. Review-level: show `--dry-run` output first. | https://docs.brew.sh/Manpage |
| `vagrant box prune` | vagrant-boxes | `vagrant box prune` / 1 | Removes old versions of installed boxes; keeps the newest. Allow `-f`. | https://developer.hashicorp.com/vagrant/docs/cli/box |
| `docker container prune -f` | docker-stopped-containers | `docker container prune` / 3 | Removes stopped containers. Review-level: their writable layers are lost. | https://docs.docker.com/engine/manage-resources/pruning/ |

Considered but **not** proposed:

- `docker volume prune` / `docker system prune --volumes`: volumes often hold databases. Volumes are only reported.
- `dart pub cache clean`: it asks for confirmation. I could not verify a documented non-interactive flag.
- `golangci-lint cache clean`, `rustup toolchain uninstall <name>`: real commands, but I could not confirm them in a
  doc page that downloads cleanly. `rustup` also needs a toolchain name, so it is per-item.
- `huggingface-cli delete-cache` is interactive (TUI). `npx playwright uninstall` / `npx cypress cache clear` run
  code through `npx`, which can download and execute packages.
- `sdk flush` (SDKMAN) is a shell function, not a binary, so it cannot run without a shell.

Already allowlisted and now used: `docker image prune -a -f` (unused images, `review`) and `docker buildx prune -f`.

## Dropped or uncertain

I dropped these because I could not back the path with an official doc or by seeing it on this Mac:

- **Electron apps not installed here:** Notion, Obsidian, Signal, Linear, Windsurf, GitHub Desktop, Cursor caches.
  The Electron layout is documented (`~/Library/Application Support/<name>`), but the exact folder name per app is not.
  Cursor extensions (`~/.cursor/extensions`) is kept, with Cursor's forum as the source (medium).
- **Browsers:** Brave, Opera, Vivaldi cache folders, and Edge's `~/Library/Caches/Microsoft Edge`. The existing
  `com.microsoft.edgemac` path stays in `browser-caches`.
- **Media/creative:** iMovie library, iMovie/Final Cut/GarageBand/Logic app bundles, GarageBand projects,
  DaVinci Resolve CacheClip, Blender, Adobe general caches (the Adobe *Media Cache* entry is kept, medium,
  sourced from Adobe's community FAQ). Final Cut libraries are user-named `*.fcpbundle`, so they need a glob.
- **Apps:** Telegram's group container, Outlook data, Steam (games and shader cache), Dropbox cache,
  Google Drive (DriveFS) cache, 1Password, Raycast, Grammarly, ChatGPT, GPT4All.
- **Dev tools:** Carthage cache, Unity package cache and Hub editors, Epic Games/Unreal, JetBrains Toolbox apps,
  Android Studio versioned caches (`~/Library/Caches/Google/AndroidStudio<version>`: needs glob support),
  Android build cache, default project folders (`~/IdeaProjects`, `~/AndroidStudioProjects`…), pipx, conda envs,
  Podman machines, Ivy, Cabal, Zig, Bundler, user gems, rustup downloads, Bazel output base (`/private/var/tmp/_bazel_$USER`
  needs variable expansion), QuickLook cache, iPhone firmware (`~/Library/iTunes/iPhone Software Updates`),
  macOS installers in /Applications.

Kept with `confidence: medium` and no verification (existing ids, not removed so nothing breaks):
`xcode-device-support`, `arduino-staging`, `arduino-packages`, `vscode-shipit`. Their `source` says
`"pre-existing Freeroom entry; not verified"`. Verify them on a Mac that has those folders, or remove them.

Other notes:

- **Glob or variable support** would unlock several dropped items: Android Studio caches, Final Cut render files,
  Bazel, `.terraform` in projects. The measurer and Cleaner take literal paths only.
- `xcode-simulator-devices` stays `safe` with `xcrun simctl erase all` (as before). That erases app data inside
  simulators. Consider `review` if users keep test fixtures there.
- `docker-unused-images` (`docker image prune -a -f`) is `review`: it also removes images that were pulled on purpose.
- The `chrome-ai-model` (Gemini Nano, about 4 GB) is `safe`, but Chrome may download it again if a built-in AI feature is on.
- `claude-code-versions` is `review` and has no action: the active Claude Code binary is in that folder.

## Adding an entry

1. **Find the real path.** It must be literal (`~` allowed; no `*`, no `$VAR`). Confirm it either:
   - in the tool's **official** docs. Put that URL in `source`. The page must name the path (or the
     command, for path-less entries).
   - or by seeing it on a Mac (`ls`, `du -sh`). Then `source` is `"observed on macOS"`.
   If you can do neither, don't add it.
2. **Classify conservatively.** `safe` only if the tool recreates it without user effort. Say how in the
   explanation. User content, VMs, models and installed toolchains are `review`. Credentials and system areas are `keep`.
3. **Pick the action.** Use `command` only if the command is in `Cleaner.allowedCommands`. Otherwise use
   `delete` (safe) or `trash` (review), and put the tool's own command in `proposedCommand`. Use `none`
   for `keep` items, for paths outside home, and when the tool's UI is the right place to clean.
   `delete`/`trash` paths must pass `Cleaner.refusal(for:)`: inside home, not a protected parent, not under
   a forbidden tree.
4. **Don't overlap.** A path must not be in, or nested inside, another non-`keep` entry. Otherwise totals count it twice.
5. **Icon.** `app` = bundle id (`/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" /Applications/X.app/Contents/Info.plist`).
   `brand` = a slug that exists in `simple-icons@16.38.0` (`https://cdn.jsdelivr.net/npm/simple-icons@16.38.0/icons/<slug>.svg`).
   Copy the SVG into `design/catalog-icons/`. `symbol` = an SF Symbol name; it is required.
   Prefer symbols available since macOS 13.
6. **Text.** English, plain, at most 140 characters, no marketing. `id` is kebab-case and must never change once shipped.
7. Set `confidence` (`high` = doc names the path or you saw it; otherwise `medium`) and `popularity` (1–5).
