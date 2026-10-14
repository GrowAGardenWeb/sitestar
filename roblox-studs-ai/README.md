# 🧱 Studs AI: modelos 3D con IA para Roblox Studio

Plugin de Roblox Studio. Tú describes un modelo con texto y la IA (Claude) lo construye dentro de Studio:

- **Estilo "studs" clásico**: bloques con studs arriba e inlets abajo, en SmoothPlastic y con colores vivos.
- **Rigueado**: lleva `HumanoidRootPart`, articulaciones `Motor6D` con el pivote en hombros, caderas, cuello, cola, etc., además de `AnimationController` y `Animator`.
- **Animaciones a medida**: le pides las que quieras ("caminar", "saltar", "atacar con espada", "bailar"…) y las guarda como `KeyframeSequence` en `AnimSaves`. Son compatibles con el **Animation Editor** y puedes verlas en Studio antes de publicarlas.

## 1. Instalación

1. Abre Roblox Studio y entra en la pestaña **Plugins → Plugins Folder**.
2. Copia ahí el archivo `StudsAI.plugin.lua`.
3. Reinicia Studio. En la pestaña **Plugins** te saldrá el botón **Studs AI**.

## 2. Consigue una API key

1. Entra en <https://console.anthropic.com>, crea una cuenta y añade saldo.
2. En **API Keys** crea una clave (empieza por `sk-ant-…`).
3. Pégala en el campo "API key de Anthropic" del plugin. Se guarda **solo en tu Studio**, en los ajustes del plugin.

> ⚠️ No pongas nunca la API key en un Script del juego: cualquiera podría robarla.

La primera vez que generes un modelo, Studio te pedirá permiso para que el plugin se conecte a `api.anthropic.com`. Dale a **Allow**.

## 3. Uso

| Botón | Qué hace |
|---|---|
| 🧱 **Crear modelo nuevo** | Crea el modelo con sus animaciones delante de la cámara. |
| ✏️ **Modificar modelo seleccionado** | Cambia un modelo hecho con Studs AI. Ejemplos: "hazlo más alto", "ponle un sombrero de vaquero", "que la cola sea más larga". |
| 🎬 **Añadir animaciones al rig seleccionado** | Crea animaciones nuevas. Funciona con cualquier rig que tenga `HumanoidRootPart` y `Motor6D`, incluidos R6 y R15. |
| ▶ *(lista de animaciones)* | Reproduce la animación en Studio para verla. |

Todo se puede deshacer con **Ctrl+Z**.

### Ejemplos de prompts

```
Un caballero medieval estilo Roblox clásico con armadura gris, capa roja y espada.
Animaciones: idle respirando, caminar, atacar con la espada y defenderse con el escudo.
```

```
Un dinosaurio T-Rex verde con cola de 4 segmentos y mandíbula que se abre.
Animaciones: caminar pesado, rugir abriendo la boca y morder.
```

```
Un pollito amarillo pequeño con alas. Animaciones: saltitos, aletear y picotear el suelo.
```

Consejos:
- Si le dices **cuántas piezas** quieres o **qué partes se mueven**, el rig sale mejor.
- Si un modelo te sale bien, sigue con **Modificar** en vez de generar otro desde cero.
- Si tarda mucho o da error de *timeout*, baja el **esfuerzo** a `low` o usa el modelo `claude-sonnet-5-5`, que es más rápido.

## 4. Usar las animaciones en tu juego

Las animaciones de `AnimSaves` solo funcionan en Studio hasta que las publicas:

1. En el Explorer, abre `TuModelo → AnimSaves`.
2. Haz clic derecho en la `KeyframeSequence` y elige **Save to Roblox**. También puedes abrirla con el **Animation Editor** y publicarla desde ahí.
3. Copia el ID que te da y úsalo en un Script:

```lua
-- Script dentro del modelo
local model = script.Parent
local animator = model:FindFirstChildWhichIsA("Animator", true)

local anim = Instance.new("Animation")
anim.AnimationId = "rbxassetid://TU_ID_AQUI"

local track = animator:LoadAnimation(anim)
track.Looped = true
track:Play()
```

> El `HumanoidRootPart` viene **anclado** para que el modelo no se caiga en Studio. Si quieres que se mueva con física o que sea un NPC con `Humanoid`, desáncalo y ponle un `Humanoid`.

## 5. Cómo funciona

1. El plugin envía tu descripción a la API de Claude con un formato JSON muy concreto: piezas (tamaño, posición, color, forma, pieza padre y punto de pivote) y animaciones (keyframes con rotaciones en grados para cada articulación).
2. Claude responde solo con ese JSON.
3. El plugin crea las `Part`, une cada pieza a su padre con un `Motor6D` (C0/C1 calculados a partir del pivote) o con un `WeldConstraint` si es decorativa, y genera las `KeyframeSequence` con sus `Pose` anidadas, siguiendo el árbol de articulaciones.
4. La especificación se guarda dentro del modelo (`StudsAI_Spec`), para que luego **Modificar** sepa exactamente qué hay.

Modelo por defecto: `claude-opus-5-5`. Con los modelos que lo admiten, el plugin activa el *fallback* automático de la API: si el modelo rechaza una petición, la API la repite sola con otro modelo.

### Coste aproximado

Cada generación usa unos pocos miles de tokens. Con `claude-opus-5-5` cuesta normalmente entre 0,05 y 0,30 USD, según el tamaño del modelo y el esfuerzo. `claude-sonnet-5-5` es más barato y rápido.
