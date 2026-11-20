# Freeroom · Arquitectura (v1)

Herramienta open source de hblabs para liberar espacio en macOS, pensada para
desarrolladores. Dos piezas: una **app en la barra de menú** con un motor de
reglas (sin IA) y un **plugin de Claude Code** para el análisis profundo.

## Principios

1. **Freeroom no usa Claude; Claude Code usa Freeroom.** El usuario corre su
   propio Claude Code (su instalación oficial, su sesión, su plan). Freeroom
   solo lo amplía con un plugin. La app nunca toca credenciales ni tokens.
2. **El agente no puede borrar.** El CLI solo mide y reporta. Borrar es
   exclusivo de la app, siempre con confirmación del usuario.
3. **Medir bien es la feature.** Sin doble conteo (hardlinks, volúmenes
   montados, APFS clones). Reglas verificables antes de marcar algo "Seguro".
4. **Claude es opcional.** Reglas + notificaciones funcionan sin IA.
5. **Sin Docker, sin servidor, sin puertos.** Todo local.

## Diagrama

```
┌──────────────────────── Mac del usuario ────────────────────────┐
│                                                                 │
│  Claude Code (oficial, sesión del usuario)                      │
│     └─ plugin "freeroom"                                        │
│          ├─ skill /freeroom:scan       (método de análisis)     │
│          ├─ skill /freeroom:translate  (traducción bajo demanda)│
│          └─ bin/freeroom  (wrapper que localiza el CLI real)    │
│                │  Bash                                          │
│                ▼                                                │
│          freeroom  (CLI)  ── measure · known-locations ·        │
│                │             report · status  (sin delete)      │
│                ▼ escribe                                        │
│   ~/Library/Application Support/Freeroom/freeroom.db  (SQLite)  │
│                ▲ observa (WAL + file watcher)                   │
│                │                                                │
│  Freeroom.app  (MenuBarExtra + ventana)                         │
│     ├─ RuleEngine  ── chequeo periódico (sin IA, sin tokens)    │
│     ├─ Notifications (UNUserNotificationCenter)                 │
│     ├─ UI: resultados, selección, confirmación                  │
│     └─ Cleaner  ── único que borra (Papelera / rm / comandos)   │
│                    + privilegios admin vía helper (SMAppService)│
└─────────────────────────────────────────────────────────────────┘
```

## Repositorio (un solo Swift package + app)

```
freeroom/
├─ Package.swift
├─ Sources/
│  ├─ FreeroomCore/        # TODA la lógica compartida
│  │  ├─ Measure/          # tamaños reales: dedup por inode, ignora mounts/firmlinks
│  │  ├─ Locations/        # catálogo de sitios conocidos (Docker, Xcode, cachés…)
│  │  ├─ Rules/            # reglas de seguridad (target⇢Cargo.toml, venv⇢pyvenv.cfg…)
│  │  ├─ Store/            # SQLite: findings, scans, history, settings
│  │  └─ Models/           # Finding, Scan, SafetyClass (safe/review/keep), Source (rule/agent)
│  ├─ freeroom/            # CLI (swift-argument-parser), capa fina sobre Core
│  └─ FreeroomHelper/      # helper privilegiado mínimo (solo borrados admin, lista blanca)
├─ App/                    # Xcode project: Freeroom.app (SwiftUI, MenuBarExtra)
│  └─ Resources/bin/freeroom   # CLI embebido en el bundle
├─ plugin/                 # plugin de Claude Code
│  ├─ .claude-plugin/plugin.json
│  ├─ skills/scan/SKILL.md        # /freeroom:scan
│  ├─ skills/translate/SKILL.md   # /freeroom:translate <lang>
│  └─ bin/freeroom                # wrapper en el PATH del plugin
├─ .claude-plugin/marketplace.json   # el repo es su propio marketplace
├─ design/                 # prototipo HTML
└─ ARCHITECTURE.md
```

## Contrato del CLI (lo que hay que mantener estable)

Salida siempre JSON (`--json` por defecto) para que el agente la lea bien.

| Comando | Qué hace |
|---|---|
| `freeroom status` | versión, ruta de la DB, ¿app corriendo?, permisos (Full Disk Access) |
| `freeroom known-locations` | catálogo de sitios conocidos con tamaño medido y regla aplicable |
| `freeroom measure <path>…` | tamaño real deduplicado + desglose top-N; marca mounts/hardlinks |
| `freeroom report --json <finding>` | registra un hallazgo del agente (valida esquema) |
| `freeroom scan begin/end` | abre/cierra una sesión de análisis (la app muestra "en vivo") |

Esquema `Finding` (versionado, `schema: 1`):
`id, title, path[], sizeBytes, class(safe|review|keep), source(rule|agent),
category, explanation(en), command?, action(delete|trash|command), needsAdmin,
verified{rule, evidence}, scanId`

No existe `freeroom delete`. A propósito.

## Plugin de Claude Code

- Se instala con `/plugin marketplace add hblabs-co/freeroom` y `/plugin install freeroom@freeroom`.
- `SKILL.md` le enseña al agente: usar `freeroom measure` en vez de `du`
  (evita doble conteo), consultar `known-locations` primero, aplicar las
  reglas de seguridad, escribir explicaciones en **inglés** (tokenizer tax),
  reportar cada hallazgo con `freeroom report`, nunca borrar.
- La traducción la hace el agente bajo demanda desde la app
  (`freeroom` deja la petición en la DB; el usuario la lanza en Claude Code).
- El plugin trae `bin/freeroom`, un wrapper que Claude Code pone en el PATH. Busca el
  CLI real en `$FREEROOM_CLI`, `Freeroom.app/Contents/Helpers/freeroom`, Homebrew o
  `~/.local/bin` (nunca en el PATH, para no llamarse a sí mismo).
- Permisos: las skills declaran `allowed-tools: Bash(freeroom *)`. Por eso el agente debe
  usar una llamada simple por comando (sin `&&`, variables ni `export`), o se le pide permiso.
- Probado de punta a punta (2026-11-20): escaneo de ~/Downloads y ~/Desktop + traducción
  al español, sin permisos denegados.

## App en la barra de menú

- `MenuBarExtra` + `LSUIElement` (sin icono en el Dock; ventana completa bajo demanda).
- Arranque al iniciar sesión con `SMAppService.mainApp`.
- **RuleEngine** periódico (por defecto cada 6 h y cuando el espacio libre baja
  del umbral). Solo reglas de `FreeroomCore`, coste ~0, sin IA.
- **Notificaciones** con acciones (`Limpiar`, `Revisar`, `Más tarde`):
  máx. 1 al día, horas de silencio, por categoría. Ejemplos: build cache de
  Docker creció, disco < 15 GB, runtimes de simulador sin usar, resumen semanal.
  "Limpiar" abre siempre la confirmación; nunca borra directo desde la notificación.

## Borrado (Cleaner)

- Orden de preferencia: comando oficial de la herramienta (`docker builder prune`,
  `xcrun simctl runtime delete`, `go clean -modcache`…) → Papelera → `rm`.
- "Review" va a la Papelera por defecto; "Safe" se borra.
- Re-verifica cada item justo antes de ejecutar (tamaño, regla, que no esté en uso).
- Rutas de sistema (`/Library/Developer/…`) vía `FreeroomHelper` con lista
  blanca de operaciones; el usuario autoriza con el diálogo nativo de admin.
- Todo queda en `history` (qué, cuándo, cuánto).

## Distribución

- Fuera de la Mac App Store (el sandbox impide leer todo el disco y ejecutar herramientas).
- DMG firmado y notarizado + `brew install --cask freeroom` (instala app + CLI).
- Permisos: Full Disk Access (guiado en onboarding), Notificaciones.

## Fases

1. **Core + CLI**: medición deduplicada, catálogo de sitios, reglas, SQLite. Tests con fixtures (hardlinks, mounts).
2. **Plugin**: SKILL.md + `/freeroom:scan`; probar contra el caso real de hoy.
3. **App**: menú bar, resultados en vivo, confirmación, Cleaner, helper admin.
4. **RuleEngine + notificaciones**.
5. Release: firma, notarización, cask, marketplace del plugin.

## Decisiones tomadas (2026-11-20)

- **Licencia:** MIT.
- **Repo:** https://github.com/hblabs-co/freeroom (público). Marketplace del plugin: `/plugin marketplace add hblabs-co/freeroom`.
- **Azul de marca:** el del logo, `#1a4ddb` (con variante más clara en modo oscuro para pasar AA).
- **Traducción:** por comando explícito, `/freeroom:translate <lang>`. Sin colas: más simple y el usuario ve el coste en su Claude Code.
- **Cask de Homebrew:** `freeroom` (tap `hblabs-co/tap` hasta entrar en homebrew-cask).
- **Datos de ejemplo:** el prototipo y los tests usan datos anonimizados. El caso real (`docs/caso-real-*.html`) contiene rutas y nombres de clientes: está en `.gitignore` y no se publica.

## Pendiente

- Icono definitivo (exploración en `design/icons.html`).
- Confirmar en la documentación actual de Claude Code el formato exacto de
  plugins/marketplace antes de implementar la fase 2.
