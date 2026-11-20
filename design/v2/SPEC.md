# Freeroom v2 · Especificación de diseño

Rediseño visual de Freeroom (app de barra de menús + ventana) a partir del feedback: *«demasiado texto, muy plano, pocos iconos»*.

- **Mockup clicable:** `design/v2/index.html`. Es autocontenido: solo los logos de marca salen del CDN de Simple Icons, fijado a `simple-icons@16.30.0`.
- **Fuente de los tokens:** `Sources/FreeroomApp/Theme.swift` y el design system de hblabs (acento #1a4ddb / #6594fa, ámbar sagrado, glass selectivo, color semántico siempre con icono).

---

## 1. Crítica de la v0.1

| # | Problema | Dónde (código) | Efecto |
|---|---|---|---|
| 1 | **La lista es texto con casillas.** Cada fila apila casilla, título, badge de fuente, sello, candado, la explicación en una línea truncada, tamaño, badge de seguridad y chevron: hasta 9 elementos y ningún icono del ítem. | `MainView.swift:155-187`, explicación en `:174-175` (`lineLimit(1)`) | El ojo no encuentra ancla. La explicación truncada a una línea no informa y añade ruido gris en cada fila. |
| 2 | **El único icono es el de la categoría**, un SF Symbol genérico (`shippingbox`, `terminal`…) que solo aparece en la cabecera de sección. Docker, Xcode, npm y Spotify se ven iguales. | `Theme.swift:46-58`, `MainView.swift:43` | Cero reconocimiento: hay que leer cada título. |
| 3 | **El orden no responde a «qué me da más espacio».** Los grupos siguen el orden del enum, y dentro de cada grupo los hallazgos salen en el orden del store. | `MainView.swift:21-24` | Lo más grande puede quedar al fondo de la lista. |
| 4 | **Las sugerencias del menú no son las más grandes.** Son las 3 primeras seguras en el orden del store, sin ordenar por tamaño. | `AppModel.swift:97-98` (`prefix(3)` sin `sorted`) | El menú no cumple su promesa de «quick wins». |
| 5 | **«Clean» en el menú no limpia.** Pone la selección y abre la ventana, pero no abre la confirmación. El usuario cae en una lista larga y tiene que encontrar la barra inferior. | `MenuPanel.swift:30-33` | Rompe el modelo mental y hace falta un paso extra para lo más común. |
| 6 | **El popover son 6 botones de texto** (`Open`, `Copy`, `Check now`, `Settings…`, `Quit`), con una cabecera que repite icono + «Freeroom» dentro de la propia app. El gauge es una barra de 6 px. | `MenuPanel.swift:40-60`, `:66-74`, `:113-120` | Mucho chrome y poco dato. Lo importante (cuánto puedo liberar ya) no tiene peso visual. |
| 7 | **El rojo del gauge no lleva icono.** `used > 0.9 → Theme.danger` va solo en color. | `MenuPanel.swift:116` | Incumple la regla del DS (semántico = color + icono) y es invisible para daltónicos. |
| 8 | **Resumen con filtros escondidos.** Las tres cifras Safe/Review/Keep son botones de filtro sin aspecto de botón, y «Keep» aparece al mismo nivel que lo liberable. | `MainView.swift:75-92` | Lectura ambigua: ¿Keep también se puede limpiar? |
| 9 | **Confirmación burocrática.** El toggle «I reviewed these items» y un párrafo bloquean el botón. Los ítems son una `List` plana con rutas en monoespaciada. | `ConfirmSheet.swift:42-43`, `:53-58`, `:92-99` | Fricción sin seguridad real: Review ya va a la Papelera y los comandos ya pasan por la lista blanca. Es texto que nadie lee. |
| 10 | **No hay recompensa al terminar.** La pantalla de «Done» es una línea `headline` («Freed about X: A → B free») sobre la misma lista. | `ConfirmSheet.swift:71-79` | Falta el momento emocional que hace volver a una app de limpieza. |
| 11 | **Estados vacío y de carga genéricos.** Un `ProgressView("Measuring your disk…")` y un `sparkles` con un párrafo. Mientras se mide no se ve nada. | `MainView.swift:106-124` | La espera parece más larga y no se anticipa el valor. |
| 12 | **El modo en vivo del agente es casi invisible.** Un spinner y el texto «Live from Claude Code» en la cabecera. Los hallazgos nuevos aparecen sin resaltarse. | `MainView.swift:95-101` | Se pierde la parte más interesante del producto. |
| 13 | **Glass mal aplicado.** La barra de selección es una franja de vidrio de ancho completo con `cornerRadius: 0`, pegada al contenido. | `MainView.swift:143` | El DS pide vidrio solo para lo que flota sobre contenido que hace scroll. |
| 14 | **Ajustes = párrafos.** Hay tres bloques de `.caption` explicativos y ningún icono por fila, en una ventana fija de 520×340. | `SettingsView.swift:18, 33, 50, 68` | Parece un formulario de debug. |
| 15 | **La notificación copia la explicación entera** en el cuerpo, sin acciones ni adjunto. | `AppModel.swift:175-179` | El banner es largo y no se puede actuar sobre él (el ARCHITECTURE promete *Limpiar / Revisar / Más tarde*). |
| 16 | **Sin teclado.** No hay atajos de selección, ni ⌘A, ni ⏎ para confirmar, salvo los botones por defecto del sheet. | `MainView.swift` (sin `.onKeyPress`) | Lento para el público objetivo, que son desarrolladores. |

**Diagnóstico:** la información es correcta, pero está expresada como texto. La v2 la convierte en **forma** (iconos reales, tamaños como áreas y barras, un número protagonista) y deja el texto para el detalle.

---

## 2. Principios de la v2

1. **Primero el icono y el tamaño, después el nombre.** Cada hallazgo se reconoce por su icono real (app instalada → logo de marca → SF Symbol) y su tamaño se ve antes de leerse (área en el mapa, barra en la fila).
2. **Una línea por ítem.** La fila lleva título y un meta corto («14 projects», «46 folders»), sin párrafos. El *por qué* vive en el inspector y en el tooltip.
3. **Divulgación progresiva:** popover (3 victorias), luego ventana (mapa y lista), luego inspector (por qué, acción, evidencia, rutas).
4. **Un número protagonista por pantalla:** espacio libre (popover), «You can free up to» (ventana), «Clean X» (confirmación), «You freed X» (final).
5. **El ámbar sigue siendo sagrado.** Solo lo usa el agente, con el glifo de nodo hexagonal. Los logos de marca de tono ámbar o dorado (Homebrew, Hugging Face, pnpm) se pintan **monocromos** (§6.3).
6. **Vidrio solo en lo flotante:** popover, sidebar, cápsulas de la toolbar, barra de selección flotante, sheet y banners. Las filas, el mapa y el inspector van opacos.
7. **Teclado primero:** ↑↓/j k, espacio, ⌘A (todo lo Safe), ⌘⏎ (revisar y limpiar), ⏎ (confirmar), esc y `/` (buscar).

---

## 3. Pantallas

Cada pantalla tiene su deep link en el mockup (`index.html#<id>`), que acepta `&dark`, `&light`, `&srcs` (etiqueta de nivel del icono) y `&rm` (reduce motion).

### 3.1 Popover de la barra de menús · `#menubar`, `#menubar-live`

- **Cabecera:** anillo de uso (74 pt) con el glifo Freeroom en el centro, y al lado el espacio libre como cifra grande en mono («18.4 GB» y «free of 494 GB»). Si se baja del umbral aparece la advertencia **con icono** (`exclamationmark.triangle`) en `danger`. A la derecha, ↗ para abrir la ventana.
- **CTA único:** **«Free 91.9 GB safely»**. Abre la confirmación con todos los ítems Safe ya cargados. Es la acción del 80 % de las visitas.
- **«Biggest safe wins»:** 3 tiles con el icono grande (44 pt), el tamaño y el nombre, **ordenados por tamaño**. Pulsar un tile abre la confirmación de ese ítem, no la ventana.
- **Fila del agente** (ámbar, nodo hexagonal): «Claude Code · 2 h ago · 7 findings, 3 verified», que lleva a la ventana filtrada. **En vivo**, el hexágono pulsa, se ve la ruta y el contador, y debajo hay una barra indeterminada ámbar.
- **Pie de iconos** con tooltip: Check now · Copy `/freeroom:scan` · «Checked 12 min ago» · Settings · Quit.
- Si no hay plugin, la fila del agente se sustituye por una neutra: «Deep scan with Claude Code» con el icono `terminal`, nunca en ámbar.

### 3.2 Ventana principal · `#main`

`NavigationSplitView` de tres columnas:

- **Sidebar (vidrio):** «Everything», luego **Ecosystems** (Docker, Xcode & Simulators, JavaScript, Rust, Go, Gradle, AI models, Homebrew, App caches, Personal files, System), cada uno con su icono real y el total liberable en mono. Después **Found by**: Rules (regla) y Claude Code (hexágono ámbar). Al pie, «214 GB freed since March» (historial).
- **Contenido (opaco):**
  1. **Hero:** «You can free up to **171.3 GB**», con los chips Safe y Review (icono y color). A la derecha, la **barra del disco segmentada** (Safe · Review · Keep · Otros · Libre), con leyenda de iconos y cifras.
  2. **Mapa del disco (treemap):** un tile por hallazgo liberable, con área proporcional al tamaño, icono real y, si cabe, nombre y tamaño. El fondo lleva un tinte suave de su clase y el glifo de seguridad va en la esquina. Clic selecciona, doble clic inspecciona y el tooltip da la explicación. Los ítems Keep no entran en el mapa; están en la barra.
  3. **Lista agrupada por ecosistema** (o plana por tamaño, con el segmentado de la toolbar). La cabecera de grupo lleva icono, nombre, «Select all» y el total.
- **Inspector** (`.inspector`, 300 pt, opaco): ver §3.3.
- **Barra de selección flotante** (cápsula de vidrio centrada): pila de iconos seleccionados, «**61.2 GB** · 6 items → **79.6 GB** free», Clear y «Review & clean ⌘⏎». Si está vacía, da la pista de teclado.
- **Toolbar:** título y espacio libre, el segmentado *Ecosystem | Size*, las cápsulas *Check now* y *Deep scan* (copia el comando), la búsqueda y el toggle del inspector.

### 3.3 Fila e inspector

**Fila (44 pt):** `[☐] [icono 30] Título  meta-corto  [⬢ si es del agente] [🔒 si necesita admin]  ▬▬▬ barra  27.4 GB  (✓ Safe)`

- La barra es relativa al ítem más grande visible. Va en neutro y pasa al acento cuando la fila está seleccionada.
- Los ítems Keep se muestran atenuados, con la casilla deshabilitada y el tooltip «Freeroom never deletes Keep items».
- En vivo, una fila nueva entra con un desplazamiento y un fundido de 1,6 s sobre `agentSoft`, y deja una marca ámbar de 3 pt a la izquierda.

**Inspector** (divulgación progresiva):

1. Icono de 64 pt, título, tamaño grande en mono, y los chips de clase y fuente («Claude Code · verified» en ámbar o «Rule» en neutro).
2. **Una frase de por qué**: la `explanation`, como máximo 2–3 líneas.
3. **Tarjeta de acción** con icono: `terminal` (*Runs the tool's own cleanup*, con el comando), `xmark.bin` (*Deletes permanently · regenerable*) o `trash` (*Moves to the Trash · recoverable*). Si `needsAdmin`, se añade *Asks for your administrator password once*.
4. Si `sharedBytes > 0`, una tarjeta «1.1 GB won't be freed · hard-linked» con el icono `link`.
5. `DisclosureGroup` «Why it's safe/review». Si es del agente, la evidencia va en una caja ámbar con el hexágono; si es una regla, va el id de la regla en mono, en neutro. Viene abierto por defecto para los hallazgos del agente.
6. `DisclosureGroup` «Locations (n)»: rutas con `~` y «Show» (Reveal in Finder).
7. «Add to selection (space)» y «Finder».

### 3.4 Confirmar → limpiar → «You freed» · `#confirm`, `#cleaning`, `#done`

Es **un solo sheet que se transforma** en tres fases.

1. **Revisión.** Arriba, «Clean 14 items» y la cifra grande **120.9 GB**, con «Free space 18.4 → 139.3 GB» y una barra del disco donde el espacio que se liberará va rayado en verde.
   - Los ítems se agrupan **por acción**, que es lo que de verdad importa para la seguridad: **Delete · regenerable**, **Run cleanup command · tool's own command** (con el comando en mono) y **Move to Trash · recoverable**. Cada grupo lleva su icono y su total.
   - Los ítems con admin llevan 🔒 «password». Al pasar el ratón aparece ✕ para quitar un ítem.
   - **Sin toggle «I reviewed».** La seguridad está en el diseño (Review → Papelera, comandos en lista blanca, re-verificación antes de cada ítem), y se resume en una nota con escudo.
   - Botones: Cancel (esc) y **Clean 120.9 GB (⏎)**.
2. **Limpieza.** El título pasa a «Cleaning…» y la cifra grande se convierte en el **contador de lo liberado**, que sube con cada ítem. Cada fila pasa por pendiente (atenuada), en curso (spinner) y hecha (✓ verde y tamaño tachado), o saltada (⊖, con el motivo en una línea: «Spotify is open — quit it and retry»).
   - El icono de cada ítem terminado **vuela hacia el contador** (`matchedGeometryEffect`) y la barra del disco va llenando el tramo verde.
   - Botón «Stop after current».
3. **«You freed».** El icono de la app aparece con un rebote y lo rodean **3 destellos de marca en azul** (nunca ámbar). Debajo, «You freed **117.5 GB**» con un contador animado de unos 1,3 s y ease-out, y «18.4 → **135.9 GB** free».
   - Una tira con los iconos de todo lo limpiado, que entran escalonados.
   - Notas accionables: «1 item in the Trash · recoverable» con *Open Trash*, y «Spotify cache skipped» con *Retry*.
   - Botones: History y **Done (⏎)**, que lleva al estado vacío.

### 3.5 Onboarding · `#onboarding-1..3`

Son tres pasos de una ventana de 640×560. Cada uno tiene una ilustración arriba, un título de una línea, una frase y como mucho dos botones.

1. **Full Disk Access.** Mini panel de System Settings › Full Disk Access con la fila de Freeroom (icono de la app) y su interruptor encendiéndose en bucle. El estado se ve en vivo: «Waiting for System Settings…» (spinner) y luego «Access granted» (✓). Botones: *Open System Settings* / *Later*.
2. **Notificaciones.** Banner de ejemplo real, el slider «Warn me below 25 GB» y tres chips con icono: 1 per day max · Quiet hours · No AI. Botones: *Allow notifications* / *Not now*.
3. **Claude Code (opcional).** Diagrama de iconos: Claude Code (borde y etiqueta ámbar, «measures & reports») → Local store → Freeroom («you confirm, it cleans»). Comando copiable y estado «Plugin not detected · Re-check». Botones: *Start first scan* / *Skip — rules only*.

Al terminar entra directamente en **First scan** (§3.7). La primera impresión es el valor, no una lista vacía.

### 3.6 Ajustes · `#settings`

Ventana `Settings` con pestañas de icono en la toolbar: General · Alerts · Claude Code · Safety · About. Usa `Form(.grouped)` con **un icono por fila** (tile neutro de 24 pt) y textos de ayuda de una línea como *subtitle*, no como párrafos.

- **General:**
  - Open at login.
  - Free space in the menu bar, con una vista previa del ítem real.
  - Check every 6 hours («Rules only, no AI»).
  - Language, con un subtítulo que remite a `/freeroom:translate`.
  - Show disk map.
  - Use installed app icons.
- **Alerts:** interruptor principal, el slider del umbral, las horas de silencio e interruptores **por ecosistema con su icono real**.
- **Claude Code:** tarjeta de estado (Installed ✓, versión, último escaneo), comandos copiables y la línea con escudo «The agent can measure and report. It cannot delete.».
- **Safety:** chips de carpetas protegidas (con icono de carpeta, llave o candado) y chips de los **comandos permitidos con el logo de cada herramienta**. Además, «Review items go to the Trash».
- **About:** icono, versión, cask, GitHub y la nota de marcas (§6.4).

### 3.7 Estados: carga, vacío y agente en vivo

- **First scan · `#first-scan`.** Anillo de progreso con «X GB found so far» en el centro, un *ticker* en mono con la ruta que se mide y una **rejilla de tarjetas que aparecen según se encuentran**: cada una entra con un *pop* y trae su icono, tamaño y nombre, y los huecos aún vacíos parpadean como esqueleto. El sidebar se va llenando a la vez. Al terminar: «Here's what you can free» con *Show 115.7 GB of findings*.
- **Todo limpio · `#empty`.** Icono de la app con destellos azules, «Nothing worth cleaning», «135.9 GB free · checked 2 min ago», *Check now* y *Deep scan with Claude Code*. Debajo, la fila **«Watching 46 known locations»** con los iconos de lo vigilado, que transmite que la app trabaja aunque no haya nada.
- **Agente en vivo · `#live`.** Franja ámbar sobre el hero: hexágono pulsante, «Claude Code is scanning ~/Projects», «3 new findings · latest: Ollama models 11.3 GB · 2 measurements corrected», barra indeterminada e icono del último hallazgo.
  - Cada hallazgo nuevo entra en el mapa y en la lista con la animación de fila nueva. El inspector salta a él y muestra la evidencia en ámbar.
  - Al terminar, la franja pasa a «Claude Code finished».

### 3.8 Notificaciones · `#notifications`

- **Título** = qué y cuánto («Docker build cache · 27.4 GB»). **Cuerpo** = una línea («Safe: Docker rebuilds it when needed.»).
- **Adjunto** = el icono resuelto del ítem, renderizado a PNG (`UNNotificationAttachment`). Así el banner es visual aunque el icono del remitente sea siempre el de Freeroom.
- **Acciones** con `UNNotificationCategory`: *Review*, que abre la app en primer plano directamente en el sheet de confirmación con ese ítem, y *Later*, que pospone 1 día. Ningún banner borra.
- **Tipos:** ítem grande, disco bajo (adjunto: `internaldrive` en `danger`), runtimes sin usar y resumen semanal (adjunto: destello azul).
- Reglas sin cambios: máximo 1 al día, horas de silencio, por ecosistema y solo motor de reglas.

---

## 4. Componentes y notas de implementación en SwiftUI

| Componente | Implementación |
|---|---|
| `ItemIcon(icon:size:)` | Vista que aplica la resolución de §6. Squircle con `RoundedRectangle(cornerRadius: size*0.235, style: .continuous)`. Tile de marca: fondo `card` + `strokeBorder(.separator, 0.5)`. Tile de SF: fondo `quaternary`. El icono de app va **sin tile** (ya trae su forma). |
| `IconResolver` | `@MainActor final class` con `NSCache<NSString, NSImage>`. App: `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` → `NSWorkspace.shared.icon(forFile: url.path)` (pedir el tamaño ×2 para Retina). Marca: SVG **empaquetado** en `Resources/BrandIcons/<slug>.svg` (sin red), cargado como `NSImage` con `isTemplate = true` y tintado con `.foregroundStyle(brandColor ?? .primary)`. Símbolo: `Image(systemName:)`. Invalida la caché con `NSWorkspace.didLaunchApplicationNotification` / `didTerminate…` (o una vez por sesión). |
| `SafetyChip`, `SourceChip` | Ya existen como `SafetyBadge`/`SourceBadge`. Pasan a la forma `Label` con `.symbolRenderingMode(.hierarchical)` y los glifos `checkmark.circle.fill`, `eye.circle.fill` y `lock.circle.fill`. `SourceChip(.agent)` usa `AgentMark`. |
| `DiskBar` | `HStack(spacing: 1.5)` de `Rectangle`s con `frame(width: geo.size.width * fraction)` dentro de un `Capsule().clipShape`. Animar con `.animation(.smooth, value:)`. La alternativa es `Chart` con `BarMark(xStart:xEnd:)` apilado, que da accesibilidad gratis. |
| `DiskRing` (popover) | `Circle().trim(from:0,to:used).stroke(style: .init(lineWidth: 7, lineCap: .round))` rotado −90°. |
| `TreemapView` | Algoritmo *squarified* (Bruls et al.), unas 40 líneas puras en `FreeroomCore` y testeables. Con un `Layout` propio (`TreemapLayout: Layout`) que recibe los pesos por `LayoutValueKey`, cada tile es una vista normal (botón, foco, VoiceOver, `matchedGeometryEffect`). No usar `Canvas`, porque se pierde la accesibilidad. Mínimo legible: icono si el tile mide 40 pt o más; nombre si mide más de 92 × 50 pt. Swift Charts no trae treemap. |
| `FindingRow` | `Grid`/`HStack` de altura fija 44 pt. `Toggle(.checkbox)`, `ItemIcon(30)`, título y meta en `Text` con `.lineLimit(1)`, `ProgressView(value:)` con estilo de barra propio, tamaño con `.monospacedDigit()` y `SafetyChip`. `.help(explanation)` hace de tooltip. |
| Lista | `List(selection:)` con `Section` por ecosistema y `.listStyle(.inset)`. **Ordenar por tamaño** dentro de cada grupo y los grupos por total. `.onKeyPress(.space)` alterna la casilla. ⌘A va con `.keyboardShortcut("a")` sobre «Select all Safe». |
| Inspector | `.inspector(isPresented:) { FindingInspector(finding:) }` con `.inspectorColumnWidth(min: 280, ideal: 300, max: 360)`. Las secciones son `DisclosureGroup`. |
| Barra de selección | Se superpone con `.safeAreaInset(edge: .bottom)` o con un `overlay(alignment: .bottom)` con `.padding(16)`. `.glassEffect(.regular, in: .capsule)`. La pila de iconos es un `HStack(spacing: -8)`. |
| Toolbar | `ToolbarItemGroup` y `Picker(.segmented)` para la agrupación. En macOS 26 las cápsulas reciben Liquid Glass del sistema automáticamente. |
| Popover | `MenuBarExtra(.window)`. Contenido en `GlassEffectContainer` con `.glassEffect(.regular, in: .rect(cornerRadius: 24))`. Los tiles de victorias van en `LazyVGrid(columns: 3)`. |
| Sheet de limpieza | `.sheet` con un enum `phase` (`review`, `running`, `done`). Usar `@Namespace var ns` y `matchedGeometryEffect(id: finding.id, in: ns)` entre el icono de la fila y un «sumidero» invisible junto al contador; cuando el ítem termina, se retira de la lista dentro de `withAnimation(.snappy)`. El contador va con `Text(freed, format: .byteCount(style: .file))` y `.contentTransition(.numericText(value:))`, actualizando el valor con `withAnimation(.smooth(duration: 1.3))`. Los destellos se hacen con `PhaseAnimator`/`KeyframeAnimator` sobre `Image("Glint")`. Haptics: `NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, …)` al terminar. |
| Primer escaneo | Para que la rejilla aparezca en vivo, el `RuleEngine` debería emitir progreso (`AsyncStream<Finding>`). Tarjetas en `LazyVGrid` con `.transition(.scale.combined(with: .opacity))`. |
| Franja del agente | `HStack` sobre `Theme.agentSoft` con `AgentMark` y `.symbolEffect(.pulse)` mientras `agentScanLive`. Las filas nuevas se detectan comparando ids con el snapshot anterior. |
| Notificaciones | Registrar `UNNotificationCategory(identifier: "finding", actions: [review(.foreground), later])`. El adjunto se genera con `ImageRenderer(content: ItemIcon(icon, size: 128))` → PNG en `NSTemporaryDirectory()` → `UNNotificationAttachment`. `userInfo["findingId"]` abre el sheet. |
| Ajustes | `Settings { TabView { … }.tabViewStyle(.automatic) }`, que en macOS da pestañas con icono. Las filas son `LabeledContent` con un `Label` cuyo icono va en un tile de 24 pt. Altura flexible (`.frame(minHeight:)`). |
| Glass | Solo popover, sidebar (el sistema), cápsulas de la toolbar, barra flotante, sheet y banners. Lista, mapa, inspector y tarjetas van opacos (`.background(.background)`). |

**Cambios de modelo** (pequeños, sin romper el esquema 1):

- `Finding.icon: IconRef?` = `{ app?: String, brand?: String, symbol?: String }`, que llega del catálogo de unos 300 ítems por `rule`/`catalog:<id>`. El agente puede enviarlo en `freeroom report`; si no lo hace, se infiere por el id de regla.
- `Finding.ecosystem: String` (`docker`, `xcode`, `js`, `rust`, `go`, `gradle`, `ai`, `brew`, `apps`, `personal`, `system`), derivado del catálogo y distinto de la `category` actual, que se mantiene.
- `Finding.meta: String?`: la línea corta de la fila («14 projects»). Si no viene, se genera a partir de `paths.count` o del comando.

---

## 5. Motion y feedback

| Momento | Animación | Con Reduce Motion |
|---|---|---|
| Fila o tile nuevo (agente) | desliza 6 pt y fundido sobre `agentSoft` (1,6 s) | Fundido de color, sin desplazamiento |
| Selección | La barra de la fila pasa a acento y el tile recibe un borde de 2 pt (`.snappy`) | Igual (es color) |
| Ítem limpiado | El icono vuela al contador (0,7 s) | Sin vuelo: la fila marca ✓ |
| Contador «You freed» | Sube de 0 a X en unos 1,3 s, con *ease-out cubic* | Muestra X directamente |
| Destellos | Escala 0 → 1,15 → 1, escalonados 150 ms | Estáticos |
| Agente en vivo | Pulso del hexágono y barra indeterminada | Hexágono fijo y texto «scanning» |

Se respeta `@Environment(\.accessibilityReduceMotion)`. El mockup simula esto con el botón *Reduce motion* o con `&rm`.

---

## 6. Resolución de iconos

### 6.1 Orden

1. **`app`**: si el bundle id está instalado (`NSWorkspace.urlForApplication(withBundleIdentifier:)`), se usa **el icono real de la app** (`NSWorkspace.shared.icon(forFile:)`). Es el más reconocible y respeta las variantes de icono de macOS 26 (claro, oscuro, tintado).
2. **`brand`**: SVG oficial de **Simple Icons** (CC0) por `slug`, empaquetado en la app y tintado con el color de marca (o monocromo, §6.3).
3. **`symbol`**: el SF Symbol del catálogo.
4. **Respaldo**: el SF Symbol del ecosistema o la categoría (lo que hace hoy `Theme.categoryIcon`).

Ejemplos: Docker build cache → `app: com.docker.docker` (si Docker Desktop no está instalado → `brand: docker` → `symbol: shippingbox`); node_modules → `brand: nodedotjs`; Installers in Downloads → `symbol: arrow.down.circle`; Time Machine snapshots → `symbol: clock.arrow.circlepath`.

El mockup usa **placeholders neutros** (squircle gris con las iniciales o el nombre) allí donde la app real pintaría el icono instalado. El botón **Icon tiers** (o `&srcs`) etiqueta cada icono con APP / SI / SF para revisar el catálogo.

### 6.2 Formato del catálogo

```json
{ "id": "docker.buildcache", "icon": { "app": "com.docker.docker", "brand": "docker", "symbol": "shippingbox" }, "ecosystem": "docker" }
```

### 6.3 Regla del ámbar y legibilidad (logos de marca)

Un logo se pinta **monocromo** (`.primary`) si:

- el color de marca cae en la **banda del agente**: OKLCH con hue entre 45° y 110° y croma > 0,08 (Homebrew #FBB040, Hugging Face #FFD21E, pnpm #F69220…), o
- su luminosidad es < 0,40 o > 0,92 (Rust, Ollama, Gradle o Unity en negro serían invisibles en oscuro).

En el resto de casos se usa el hex de Simple Icons. La regla se calcula **una vez al construir el catálogo**, que guarda `brandTint: "#2496ED" | null`. El mockup la calcula en vivo en `brandTint()`.

### 6.4 Licencias y marcas

- Los SVG de Simple Icons son CC0, pero **las marcas pertenecen a sus dueños**. Se usan solo para identificar qué hay en el disco (uso nominativo), sin alterar la forma y sin sugerir respaldo. Esto se indica en About.
- Algunas marcas restringen su uso. Simple Icons enlaza las guías en `_data/simple-icons.json` (`guidelines`); el catálogo debería guardar ese enlace y excluir las que lo prohíban.
- La app **no descarga** iconos en tiempo de ejecución, por privacidad y para funcionar sin conexión. El CDN es solo para el mockup.

---

## 7. Accesibilidad

- **VoiceOver**:
  - Fila: `.accessibilityElement(children: .combine)` con la etiqueta «Docker build cache, 27.4 gigabytes, Safe, found by rule» y `accessibilityValue` seleccionado o no seleccionado. Acciones: `.accessibilityAction(named: "Inspect")` y «Reveal in Finder».
  - Tiles del treemap: botones con la misma etiqueta. El contenedor se llama «Disk map of reclaimable items» y sigue el **mismo orden por tamaño** que la lista.
  - `DiskBar`/`DiskRing`: `accessibilityLabel` con todas las cifras («Disk: 93 GB safe, 78 GB to review, 18.4 GB free of 494 GB»).
  - Contadores animados: `accessibilityLabel` con el **valor final**, para no anunciar cada fotograma. Durante la limpieza, `AccessibilityNotification.Announcement` por cada grupo terminado, no por cada ítem.
  - Franja del agente: región `status` con un anuncio por hallazgo nuevo, limitado a uno cada 5 s.
  - Iconos de app y marca: `accessibilityLabel` = nombre de la app o marca. Los decorativos dentro de una fila combinada van `.accessibilityHidden(true)`.
- **Contraste:** se mantienen los valores de `Theme.swift`, ya verificados AA.
  - El texto secundario usa el equivalente a `ink-5`, nunca `ink-4`.
  - Las etiquetas de los chips usan la tinta oscura en claro y la brillante en oscuro.
  - El tinte de los tiles es un *soft* con texto `ink-7` encima.
  - El texto sobre el acento es blanco en claro y #070d1a en oscuro (≥ 6,6:1).
- **El color nunca va solo:** Safe/Review/Keep llevan su glifo (✓ / ojo / candado), el agente su hexágono, el disco bajo su triángulo y admin su candado.
- **Teclado:** todo es alcanzable, con anillo de foco de 2 pt en acento. Atajos: ↑↓, espacio, ⌘A, ⌘⏎, ⏎, esc, `/`, ⌘R (check), ⌘⌥I (inspector) y ⌘, (ajustes).
- **Reduce Transparency:** el vidrio pasa a `.regularMaterial` u opaco. **Increase Contrast:** bordes de 1 pt en tiles y tarjetas.
- **Dynamic Type** (en macOS es limitado): sin alturas de texto fijas salvo la fila, que crece con `minHeight`.

---

## 8. Plan de implementación (pasos pequeños y por prioridad)

Cada paso se puede publicar por separado y no rompe lo anterior.

**P0: lo que cambia la percepción**

1. **Ordenar por tamaño**: grupos por total, ítems por tamaño y `suggestions` con `sorted { $0.sizeBytes > $1.sizeBytes }`. *(30 min)*
2. **`IconRef` + `IconResolver` + `ItemIcon`**, con el respaldo actual por categoría. Empaquetar las primeras ~40 marcas del catálogo. *(1 día)*
3. **Nueva `FindingRow`**: icono, título, meta, barra, tamaño y chip. Quitar la explicación de la fila (pasa a `.help`) y quitar el chevron. *(½ día)*
4. **Inspector** con `.inspector` (por qué, tarjeta de acción, evidencia y rutas). Se elimina la expansión en línea. *(1 día)*
5. **Popover nuevo**: anillo, CTA «Free X safely», 3 tiles y pie de iconos. **Los tiles abren la confirmación.** *(1 día)*
6. **Sheet de confirmación agrupado por acción**, sin el toggle «I reviewed». *(½ día)*

**P1: la recompensa y lo visual**

7. **Fase «You freed»**: contador con `.numericText`, destellos, tira de iconos y notas de Papelera y saltados. *(1 día)*
8. **Fase de limpieza**: estados por fila y `matchedGeometryEffect` hacia el contador. *(1 día)*
9. **`DiskBar` segmentada + hero «You can free up to»** en la ventana. *(½ día)*
10. **Barra de selección flotante** (cápsula de vidrio) y **atajos de teclado**. *(½ día)*
11. **Sidebar por ecosistema** (requiere `Finding.ecosystem`) y filtro por fuente. *(1 día)*

**P2: profundidad**

12. **Treemap** (`TreemapLayout` + algoritmo en Core con tests). *(1–2 días)*
13. **Primer escaneo con progreso** (`AsyncStream` desde `RuleEngine`) y rejilla en vivo. *(1 día)*
14. **Franja del agente en vivo** y animación de fila nueva. *(½ día)*
15. **Notificaciones con categoría, acciones y adjunto** del icono. *(1 día)*
16. **Onboarding** de 3 pasos (detección de FDA intentando leer `~/Library/Mail` o similar; detección del plugin vía `freeroom status`). *(1–2 días)*
17. **Ajustes** con iconos por fila y las pestañas Safety y Alerts por ecosistema. *(1 día)*
18. Pasada de **accesibilidad** (VoiceOver, Reduce Motion/Transparency) y capturas para el README. *(1 día)*

---

## 9. Preguntas abiertas

1. **¿Placeholder o icono genérico** cuando la app no está instalada y no hay marca? La propuesta es un SF Symbol del ecosistema; otra opción sería el icono genérico de app de macOS (`NSWorkspace.icon(for: .application)`).
2. **¿Mantener «Keep» visible en la lista?** Hoy aparece atenuado. Una alternativa es sacarlo a una sección plegada «Big but kept», para que la lista sea 100 % accionable.
3. **El CTA del popover limpia todo lo Safe de golpe** (pasando por la confirmación). ¿Os parece bien por defecto o preferís que abra la ventana con la selección hecha?
4. **Monocromo para marcas ámbar:** ¿aceptáis que Homebrew, Hugging Face o pnpm pierdan su color para proteger el ámbar del agente, o preferís una excepción si el logo va dentro de un tile neutro?
5. **¿Treemap en P2 o en P1?** Es lo más vistoso, pero también lo más caro. La barra segmentada cubre el 70 % del valor.
6. **Haptics y sonido** al terminar: ¿un sonido de sistema discreto («Glass») o silencio?
7. **¿Animación del glifo de la barra de menús** al liberar espacio (el relleno baja)? Es un detalle bonito, pero puede distraer.

---

## 10. Uso del mockup

- La barra inferior «Freeroom v2» salta entre pantallas y tiene *Auto / Light / Dark*, *Icon tiers* y *Reduce motion*.
- El glifo de la barra de menús simulada abre o cierra el popover.
- En *Main*: ↑↓ o j/k mueven el foco, espacio selecciona, ⌘A selecciona todo lo Safe, ⌘⏎ abre la confirmación, `/` busca; clic en un tile selecciona y doble clic lo inspecciona.
- Recorrido completo: *Menu bar → Free 91.9 GB safely → Clean → (animación) → You freed → Done → All clean*.
- Datos anonimizados: `acme-api`, `shop-frontend`, `registry.example.com` y rutas con `~`.
- Verificado con Chrome headless a 1440×900, las 14 pantallas en claro y oscuro, sin errores de consola.
