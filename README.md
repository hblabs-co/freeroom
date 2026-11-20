<p align="center"><img src="design/assets/freeroom-icon-light.png" width="128" alt="Freeroom icon"></p>

# Freeroom

**Free up disk space on your Mac — with an agent that understands what it's deleting.**
Open source, by [hblabs](https://github.com/hblabs-co).

Freeroom is a macOS menu bar app for developers. It finds what's eating your disk
(Docker build cache, Xcode simulator runtimes, `node_modules`, Go/NuGet/npm caches,
local AI models, forgotten archives…), explains each item, classifies it as
**Safe** / **Review** / **Keep**, and only deletes what you confirm.

> Status: **early development** — core + CLI + Claude Code plugin work; the menu bar app is next. The clickable prototype lives in [`design/`](design/index.html);
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

## Build from source

```sh
swift build -c release
swift test
export FREEROOM_CLI="$PWD/.build/release/freeroom"   # the plugin's wrapper uses it
.build/release/freeroom rules          # AI-free scan of this Mac
.build/release/freeroom measure ~ --top 20
```

Test the plugin without installing it: `claude --plugin-dir ./plugin`.

## License

[MIT](LICENSE)
