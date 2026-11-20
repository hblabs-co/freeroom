<p align="center"><img src="design/assets/freeroom-icon-light.png" width="128" alt="Freeroom icon"></p>

# Freeroom

**Free up disk space on your Mac — with an agent that understands what it's deleting.**
Open source, by [HB Labs SAS](https://github.com/hblabs-co).

Freeroom is a macOS menu bar app for developers. It finds what's eating your disk
(Docker build cache, Xcode simulator runtimes, `node_modules`, Go/NuGet/npm caches,
local AI models, forgotten archives…), explains each item, classifies it as
**Safe** / **Review** / **Keep**, and only deletes what you confirm.

> Status: **early development (0.1.0)** — core, CLI, Claude Code plugin and a first menu bar app work.
> Not yet signed with a Developer ID or notarized; build it from source for now. The clickable prototype lives in [`design/`](design/index.html);
> the architecture is in [`ARCHITECTURE.md`](ARCHITECTURE.md).

## How it works

- **Menu bar app + rule engine** — measures known locations accurately (no double counting
  of hardlinks or mounted volumes) and sends occasional notifications with things you can
  reduce. No AI, no tokens.
- **Claude Code plugin (optional)** — run `/freeroom:scan` in your own Claude Code for a deep,
  contextual analysis. The agent can measure and report, but it **cannot delete**: only the
  app deletes, after your confirmation. Freeroom never touches your Claude credentials.

```sh
# App + CLI (planned)
brew install --cask hblabs-co/tap/freeroom
```

In Claude Code:

```
/plugin install freeroom --marketplace hblabs-co/freeroom
```

(or, on older versions: `/plugin marketplace add hblabs-co/freeroom` then `/plugin install freeroom@freeroom`)

Then run `/freeroom:scan` — or `/freeroom:scan ~/Projects` for one folder — and
`/freeroom:translate es` to read the explanations in another language.

### Plugin updates

The plugin is versioned (`plugin/.claude-plugin/plugin.json`). Freeroom.app shows the installed
version (from Claude Code's plugin registry), the version used in the last scan, and the latest
published version (it reads that `plugin.json` from GitHub once a day; nothing about you is sent,
and you can turn it off). When an update is available it shows a notice with the command:

```sh
claude plugin update freeroom@freeroom
```

## Build from source

```sh
swift build -c release
swift test
export FREEROOM_CLI="$PWD/.build/release/freeroom"   # the plugin's wrapper uses it
.build/release/freeroom rules          # AI-free scan of this Mac
.build/release/freeroom measure ~ --top 20
```

Test the plugin without installing it: `claude --plugin-dir ./plugin`.

Build the menu bar app (ad-hoc signed, for local use):

```sh
scripts/build-app.sh            # → build/Freeroom.app
scripts/build-app.sh --install  # also copies it to ~/Applications
```

## Uninstall

Everything Freeroom creates is removed with:

```sh
brew uninstall --zap --cask freeroom      # app, CLI, database, caches, preferences
claude plugin uninstall freeroom@freeroom # the Claude Code plugin
```

Not installed with Homebrew? Use **Settings › About › Uninstall Freeroom…** in the app: it lists
every location it removes (database, caches, preferences, saved state, login item) and moves the
app to the Trash.

## Safety

- The agent **cannot delete**: the CLI has no delete command.
- The app deletes only after you confirm, and only inside your home folder. It never touches
  protected folders (`~/Documents`, `~/Library`, `~/.ssh`, Keychains…).
- Cleanup commands run only if they are on an allowlist (`docker builder prune`,
  `xcrun simctl runtime delete`, `go clean -modcache`…), without a shell. Anything else is shown
  to you to run yourself.
- Items you mark for review go to the Trash, not straight to deletion.

## License

[MIT](LICENSE)
