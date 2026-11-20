# Freeroom · notas de diseño (v2: menu bar + plugin de Claude Code)

Prototipo HTML navegable (`index.html`, autocontenido) de **Freeroom by hblabs**: una app open source (**MIT**) de macOS para liberar espacio en disco, pensada para desarrolladores. Repo: https://github.com/hblabs-co/freeroom. Instalación: `brew install --cask hblabs-co/tap/freeroom` o DMG notarizado.

Icono: `icons.html` muestra el icono final (**B+ · Sweep con destellos**), su escalera de tamaños, el glifo de la barra de menús y, plegadas, las opciones exploradas.

## Arquitectura que refleja el diseño

- **Freeroom.app** vive en la **barra de menús** (MenuBarExtra, sin icono en el Dock por defecto) y tiene una ventana completa para Results, Confirm y Settings.
- Incluye un **motor de reglas** propio, sin IA ni tokens. Revisa ubicaciones conocidas en segundo plano y genera sugerencias rápidas y notificaciones.
- El análisis profundo lo hace el **Claude Code del usuario** con el **plugin de Freeroom**, que trae el skill `/freeroom` y un CLI pequeño, `freeroom`, con tres comandos: `measure`, `known-locations` y `report`.
- El usuario ejecuta `/freeroom scan` en su terminal. Lo que el agente reporta se guarda en un **SQLite local** que la app observa en vivo.
- **El CLI no puede borrar**: no existe un comando para hacerlo. Solo la app borra, y siempre tras una confirmación.
- La app **nunca toca credenciales ni tokens de Claude**. Claude es opcional.

## Cómo navegar el prototipo

La barra «Prototype», abajo, salta entre pantallas, cambia el tema (Auto / Light / Dark) y reinicia el estado. Arriba hay una barra de menús de macOS simulada: haz clic en el glifo de Freeroom para abrir el popover desde cualquier pantalla.

Deep links: `#menubar`, `#notify`, `#onboarding`, `#onboarding-2`, `#onboarding-3`, `#scan`, `#scan-done`, `#results`, `#confirm`, `#done`, `#translate` y `#settings`. Se pueden combinar con `&dark`, `&light`, `&es`, `&de` y `&noplugin`.

## Pantallas

**0. Menu bar.** El popover de Liquid Glass (360 px) cuelga del glifo, sobre el wallpaper. Contiene:
- El gauge de espacio libre, por ejemplo «6.6 GB free · 99% used» (o «84 GB» después de limpiar).
- Las **3 sugerencias rápidas** del motor de reglas, con su tamaño y un botón «Clean». El botón abre la confirmación; nunca borra directamente.
- «Last agent scan: 2 h ago · 22 findings», en ámbar porque es contenido del agente.
- Los botones **Open Freeroom** y **Scan with Claude Code**. Este último copia `/freeroom scan` y abre Terminal.
- Settings… y Quit.

Al lado hay una ficha que explica el glifo.

**0b. Notificaciones.** Cuatro banners nativos al estilo de macOS 26, todos con acciones:
- Docker build cache · Clean / Later
- Disco por debajo de 15 GB · Review suggestions
- 3 runtimes de simulador · Review
- Resumen semanal · Open summary

Todas salen del **motor de reglas**: sin IA, sin tokens, como mucho una al día y con horas de silencio. Ninguna acción borra desde el banner; todas llevan a una confirmación.

**1. Onboarding (3 pasos).**
1. *Install the Claude Code plugin* (**opcional**). Muestra el flujo Claude Code → CLI `freeroom` → store local → Freeroom.app, los comandos `/plugin marketplace add hblabs-co/freeroom` y `/plugin install freeroom`, y el estado de detección (*detected ✓* o *not detected* con Re-check). Una comparativa «Without Claude / With Claude Code» deja claro qué aporta cada uno, y la opción «Skip · rules only» permite seguir sin Claude.
2. *Full Disk Access*, igual que antes.
3. *Notifications & login*: aviso de permiso de notificaciones, «Launch at login», «Show in Dock» (desactivado) y el umbral de disco bajo. Al terminar, la app pasa a la barra de menús.

**2. Live from Claude Code.** El agente trabaja en la terminal del usuario, así que la app muestra:
- A la izquierda, lo que llega por `freeroom report`: notas del agente, llamadas `freeroom measure …` con su salida, tarjetas «Measurement corrected» (40,0 → 27,4 GB y 41,3 → 20,6 GB) y hallazgos.
- A la derecha, un mock de la sesión de Claude Code en la terminal, sincronizado con el panel.
- Debajo, «Findings»: primero los 12 hallazgos del **escaneo por reglas (instantáneo)** con badge neutro `rule`, y después los del agente con badge ámbar `agent`. Cuando el agente confirma un hallazgo de reglas, este gana un escudo ámbar.

El token meter ya no está. En su lugar hay una nota discreta: «Analysis by Claude Code · counts toward your plan; token usage is shown in Claude Code».

**3. Results.** Igual que antes, con estos cambios:
- Badge de fuente: `rule` (neutro) frente a `agent` / `agent · verified` (ámbar).
- Filtro «Source».
- En los textos de reglas, el icono de regla es neutro.
- Un bloque «Rule `cache.app` · known location, matched without AI».

**4. Confirm & clean.** El paso de re-verificación lo hace ahora la **app** («Re-checking recorded evidence…», en azul y no en ámbar), porque el agente no participa en el borrado. Se mantienen el badge «requires admin password» y la pantalla **Done** (6.6 → 84 GB, ítems tachados). El historial guarda el origen: escaneo de Claude Code, sugerencia del menú o notificación.

**5. Translate.** La traducción **solo** se hace con el comando `/freeroom translate <lang>` en Claude Code. No hay cola en la app: el sheet muestra el comando listo para copiar y el desplegable del «tokenizer tax», y la lista se actualiza cuando las traducciones llegan al store. Solo se traducen las explicaciones del agente. Los textos de reglas vienen ya localizados en la app y no gastan tokens. La estimación se da en tokens, porque cuenta para el plan, y se mantiene el desplegable del «tokenizer tax».

**6. Settings.** Ya no hay selector de motor (Ollama y API key quedan fuera de la v1). Las secciones son:
- **General**: arranque al iniciar sesión, Dock, espacio libre junto al icono.
- **Claude Code plugin**: estado, `/freeroom scan` copiable, capacidades del CLI y ruta del store.
- **Notifications**: umbral, frecuencia, máximo 1 al día, horas de silencio y switches por categoría.
- **Language**, **Safety** e **History**.
- **About**: los iconos claro y oscuro, el glifo de la barra de menús, `brew install --cask hblabs-co/tap/freeroom` y «Open source · GitHub».

## Decisiones clave

- **El ámbar sigue siendo exclusivo del agente.** Se usa en las notas, las llamadas `measure` del agente, las correcciones, la evidencia, *verified*, «Last agent scan» y el nodo de Claude Code del onboarding. El motor de reglas, las notificaciones, la re-verificación de la app y el mock de terminal son neutros. No se usa `--hb-warning`.
- **`rule` frente a `agent`.** Los dos tipos de hallazgo conviven en todas partes, y así se ve qué aporta Claude encima de las reglas.
- **El glifo de la barra de menús** es la marca Sweep: hexágono HB, relleno barrido y un destello (a 18 pt; a 16 pt va sin destello). Es una *template image* monocroma (macOS la tiñe en claro y en oscuro) y tiene una variante para disco bajo, casi lleno. Junto al glifo se puede mostrar el espacio libre en GB.
- **Ninguna acción rápida borra directamente.** Los botones Clean del menú y de los banners siempre abren la confirmación.
- **La terminal simulada** siempre es oscura y neutra: representa otra app, la terminal del usuario.

## Liquid Glass (macOS 26)

Son de vidrio el marco de la ventana, el sidebar, la toolbar y sus cápsulas, la barra de selección, los sheets, el **popover del menú**, los **banners de notificación** y el aviso de permisos. Todos llevan borde especular y esquinas continuas. El contenido legible (filas, log, cards) va sobre superficies opacas al 94–95 %.

Correspondencia en SwiftUI:
- `MenuBarExtra(…, content:)` con `.menuBarExtraStyle(.window)`, y el popover con `.glassEffect(.regular, in: .rect(cornerRadius: 24))`.
- El glifo, como `Image("MenuBarGlyph").renderingMode(.template)`.
- Ventana: `NavigationSplitView`, `.containerBackground(.thinMaterial, for: .window)` o `NSVisualEffectView` (`.underWindowBackground`, `.behindWindow`).
- La barra flotante, con `.glassEffect` o `GlassEffectContainer`.
- Notificaciones: `UNUserNotificationCenter` con `UNNotificationCategory` y acciones (Clean / Later / Review).
- Comprobaciones periódicas con `NSBackgroundActivityScheduler`.
- Arranque al iniciar sesión: `SMAppService.mainApp`. Sin icono en el Dock: `LSUIElement = YES`, o `NSApp.setActivationPolicy(.accessory)` si el usuario lo desactiva.
- Observar el store: GRDB `ValueObservation` (o `DispatchSource` sobre el WAL de SQLite).
- Borrado con admin: `SMAppService` daemon o helper privilegiado, que pide la contraseña una vez.

## Tokens → SwiftUI

| Web | SwiftUI (`HBTokens.swift`) | Uso |
|---|---|---|
| `--hb-ink-0…8` | `HB.ink0…ink8` | Superficies y texto |
| `--hb-accent` | `HB.accent` | CTA, selección, foco, progreso y re-verificación de la app |
| `--hb-agent` / `-soft` | `HB.agent` | Solo contenido del agente |
| `--hb-success` / `--hb-info` / `--hb-danger` | `HB.success` / `.info` / `.danger` | Safe / Review / Clean |
| `--hb-font-mono` + `tnum` | `HB.mono(...)` + `.monospacedDigit()` | Tamaños, rutas, comandos |
| `--hb-s-*`, `--hb-r-*` | `HB.Space`, `HB.Radius` | Espaciado y radios |

**Tokens locales** (derivados, prefijo `--fr-`; ningún `--hb-*` se renombra):
- `--fr-surface`, `--fr-card`
- `--fr-win-glass`, `--fr-side-glass`, `--fr-bar-glass`, `--fr-sheet-glass`, `--fr-cap-glass` (en Swift se sustituyen por materiales nativos)
- `--fr-spec-a/b`
- `--fr-agent-ink`, `--fr-safe-ink`, `--fr-review-ink`, `--fr-danger-ink` (labels AA)
- `--fr-code-bg`

## Archivos

- `index.html`: el prototipo.
- `assets/freeroom-icon-light.svg` / `-dark.svg` (+ `.png` 1024, rasterizados con Chrome headless): masters 1024 del icono final.
- `assets/freeroom-icon-128.svg` (+ `-128-dark.svg`): tier de 128/64 px, con 2 destellos como máximo.
- `assets/freeroom-menubar-template.svg`: template monocroma con dos artboards, 16 pt (sin destello) y 18 pt (con un destello).
- `assets/hb-mark.svg` y `hb-logo-horizontal.svg`: copias de la marca.

En `index.html`, el icono está inline como `#appicon-l` / `#appicon-d` (tier de UI, con 2 destellos) y se muestra según el tema. El glifo es `#fr-glyph` / `#fr-glyph-low`.

## Color de marca

El acento es el azul del logo, **#1a4ddb** (oklch 0.488 0.223 264.2), y sustituye al acento de `tokens.css` en todo el prototipo. En oscuro se usa una variante derivada, **oklch(0.68 0.16 264.2) ≈ #6594fa**. Contraste comprobado (WCAG):

| Uso | Claro | Oscuro |
|---|---|---|
| Texto del botón sobre el acento | blanco / #1a4ddb = **6.7:1** | #070d1a / #6594fa = **6.6:1** |
| Enlaces / acento como texto | sobre papel **6.5:1**, sobre ink-2 **5.6:1** | sobre superficie **6.7:1**, card **6.4:1**, vidrio oscuro **5.6:1** |
| Focus ring (2 px, no-texto ≥ 3:1) | ≥ 5.6:1 | ≥ 5.6:1 |

`--hb-accent-l/c/h` pasan a 0.488 / 0.223 / 264.2 en claro y a 0.68 / 0.16 en oscuro, así que hover, soft y ring se derivan solos. El icono oscuro usa #6594FA. En Swift: `HB.accent = Color.dynamic(light: "#1A4DDB", dark: "#6594FA")`.

## Datos de ejemplo

El repo es público, así que todos los datos de ejemplo son genéricos: `acme-api`, `shop-frontend`, `registry.example.com/…`, `~/Projects/brand-film`, `~/Documents/scans/archive`, `~/Movies/GoPro`, y rutas con `~`. Los tamaños y las categorías siguen siendo realistas.

## Icono final: B+ · Sweep con destellos

- **Concepto**: el hexágono HB, un barrido curvo que deja limpia la parte superior y unos destellos de «recién limpiado». Mantiene la silueta de la marca y evita el cliché de la escoba de CleanMyMac.
- **Forma**: squircle de esquinas continuas (superelipse n = 5, cuerpo de 824 en un lienzo de 1024), degradado vertical sutil de fondo y del relleno, borde especular interior y un aro fino.
- **Color**: solo azul de marca: #1a4ddb en claro y #6594fa en oscuro, con destellos blancos o azul claro. **Nunca ámbar.**
- **Reglas por tamaño**:
  - 1024/512/256: arte completo, con 3 destellos (uno grande y dos pequeños) y 2 líneas de movimiento.
  - 128/64: 2 destellos como máximo y 1 línea.
  - 32: un único destello, más grande, y trazos más gruesos.
  - 16: sin destello.
  - Glifo de la barra de menús: un destello a 18 pt, ninguno a 16 pt.
- Se eligió la variante de 3 destellos. En `icons.html` se comparan 1 y 3 destellos a 1024 y 128, en claro y en oscuro. A, C y D quedan en «Explored».
- **Marcador del agente**: como el destello pasa a ser de la marca, el agente ya no usa sparkles. Ahora usa un **nodo hexagonal** (contorno hexagonal con un punto central), siempre en ámbar. Está en badges, notas, «Last agent scan», el flujo del onboarding y las explicaciones. En SwiftUI sería un SF Symbol propio (`freeroom.agent`).

## Preguntas abiertas

- ¿Hace falta registrar el cambio de acento en el changelog del design system, para que otros productos hblabs pasen también a #1a4ddb?
- Los multiplicadores del tokenizer tax son ilustrativos. Conviene medirlos con `count_tokens`.
