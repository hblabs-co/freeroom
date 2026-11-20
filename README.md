<p align="center"><img src="design/assets/freeroom-icon-light.png" width="128" alt="Freeroom icon"></p>

# Freeroom

**Free up disk space on your Mac — with an agent that understands what it's deleting.**
Open source, by [hblabs](https://github.com/hblabs-co).

Freeroom is a macOS menu bar app for developers. It finds what's eating your disk
(Docker build cache, Xcode simulator runtimes, `node_modules`, Go/NuGet/npm caches,
local AI models, forgotten archives…), explains each item, classifies it as
**Safe** / **Review** / **Keep**, and only deletes what you confirm.

> Status: **design phase**. The clickable prototype lives in [`design/`](design/index.html);
> the architecture is in [`ARCHITECTURE.md`](ARCHITECTURE.md).

## How it works

- **Menu bar app + rule engine** — measures known locations accurately (no double counting
  of hardlinks or mounted volumes) and sends occasional notifications with things you can
  reduce. No AI, no tokens.
- **Claude Code plugin (optional)** — run `/freeroom scan` in your own Claude Code for a deep,
  contextual analysis. The agent can measure and report, but it **cannot delete**: only the
  app deletes, after your confirmation. Freeroom never touches your Claude credentials.

```sh
# planned
brew install --cask hblabs-co/tap/freeroom
/plugin marketplace add hblabs-co/freeroom
/plugin install freeroom
```

## License

[MIT](LICENSE)
