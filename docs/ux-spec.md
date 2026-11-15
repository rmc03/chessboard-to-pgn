# Especificación de UX y estilo visual — Chess to PGN 0.3

Documento de trabajo para el rediseño. La verdad de producto está en [`PRODUCT.md`](../PRODUCT.md); aquí están las
decisiones de diseño. Plataforma: Flutter, Material 3, Android (principal) y Windows (ventana ancha).
Modo de la superficie (impeccable): **Operate** — el usuario viene a hacer una tarea; la marca vive en el detalle.

## 1. Dirección: «Dos tintas»

Referencia cultural: las revistas de ajedrez en español de la época de la impresión a dos tintas (negro + una tinta
plana que cambiaba en cada número): cabecera en la tinta del número, diagramas numerados, pie «Juegan blancas».

El mundo solo aporta cuatro cosas: **tipo, paleta, densidad y un gesto propio**. La navegación y los controles son
Material 3 estándar.

- **Gesto propio:** *una sola tinta lo entinta todo*. El usuario elige una tinta en Ajustes y con ella se imprimen la
  cabecera, las casillas oscuras del tablero, los estados seleccionados y los numerales grandes de cada diagrama.
  Cambiarla re-entinta la app entera en vivo. El tablero y la interfaz nunca tienen colores independientes.
- **Segundo rasgo:** cada diagrama se presenta como en una página compuesta: numeral grande condensado, tablero, y
  debajo el pie «Mueven blancas / negras», que es a la vez el control del turno.
- **Lo que se rechaza:** el gris oscuro con tablero verde de las webs de ajedrez; el papel crema con serifas «de
  libro»; el Material morado por defecto; tarjetas idénticas de icono + título + texto.
- **Escena de uso:** lector por la tarde-noche en el sofá con el móvil (tema oscuro) y entrenador de día en el
  escritorio con Windows (tema claro). Los dos temas son de primera clase; por defecto se sigue al sistema.

## 2. Tokens

### Tintas (`Ink`)

| id | Nombre | Semilla (esquema M3) | Casilla clara | Casilla oscura |
|---|---|---|---|---|
| `cobalto` (por defecto) | Azul cobalto | `#1F4E9A` | `#EEF1F6` | `#7F9DCB` |
| `torneo` | Verde torneo | `#2E6B4A` | `#EDF2E6` | `#7FA37F` |
| `granate` | Granate | `#8E2F3C` | `#F4ECE8` | `#C08A86` |
| `madera` | Madera | `#8A5A2B` | `#F0DFC0` | `#B98C5E` |
| `ciruela` | Ciruela | `#6A3F7A` | `#F0EAF2` | `#A48BB3` |
| `grafito` | Grafito | `#4A4F57` | `#F1F1EF` | `#A3A6AA` |

- Esquema: `ColorScheme.fromSeed(seedColor: tinta.semilla, brightness: …, dynamicSchemeVariant: fidelity)`.
  Todo color de la interfaz sale de **roles** del esquema; nada de hex sueltos fuera del archivo de tokens.
- Los valores de casilla son un punto de partida: hay que **verificar** que pieza blanca (cuerpo blanco, contorno
  negro) y pieza negra se distinguen sobre ambas casillas (la oscura debe quedar en tono medio, L* 55–68).
- El tablero usa los mismos colores en tema claro y oscuro (el diagrama es la constante).
- Estados semánticos: **dudosa** = ámbar del sistema de tokens (`warning`/`onWarning`/`warningContainer`, definidos
  para claro y oscuro y armonizados con la tinta); **error** = rol `error` de M3; **confirmada/ok** = sin color.
  Ningún estado se comunica solo con color: siempre con icono o marca.

### Cabecera y superficies

- Tema claro: `AppBar` en `primary` con texto `onPrimary` (la «banda» de la revista). Fondo `surface`.
- Tema oscuro: `AppBar` en `primaryContainer` con texto `onPrimaryContainer`. Fondo `surface` (oscuro teñido).
- Sin sombras arbitrarias: elevación tonal (`surfaceContainerLow/…/High`). Radio 12 dp en contenedores, 8 dp en
  controles pequeños. El tablero tiene esquinas rectas (es un impreso) con filete de 1 dp en `outline`.
- Nunca tarjetas dentro de tarjetas.

### Tipografía (fuentes incluidas, licencia OFL)

- **Archivo** (400/500/600/700): todo el texto de interfaz.
- **Archivo Condensed** (600/700): numerales de diagrama y título de la cabecera (la voz de la cabecera de revista).
  No se usa en etiquetas, botones ni cuerpo.
- **JetBrains Mono** (400/500): solo FEN y PGN (son datos; distinguir `P`/`p`, `1`/`l` importa).
- Escala: roles de Material (`display/headline/title/body/label`), razón ~1,2. Nunca tamaños sueltos por pantalla.
  El texto respeta el tamaño de fuente del sistema (probar a 1,3×). Cifras tabulares en numerales y contadores.

### Espaciado y tamaño

Rejilla de 4 dp: 4, 8, 12, 16, 24, 32. Margen lateral de pantalla 16 dp (24 dp desde 600 dp de ancho).
Objetivos táctiles ≥ 48×48 dp con ≥ 8 dp entre ellos. Más espacio encima de un título que debajo.

### Movimiento

150–250 ms, `Easing.standard`/emphasized de M3; solo para cambio de estado (alternar Leído/Original, re-entintar,
aparecer de la hoja inferior, progreso). Con «quitar animaciones» del sistema: corte o fundido breve.

## 3. Tablero y piezas

- `BoardView` configurable: tinta, **estilo** (`liso` = casillas planas; `impreso` = casillas claras blancas y
  oscuras con rayado diagonal en la tinta, como los diagramas de los libros), coordenadas (a–h, 1–8) opcionales,
  orientación (blancas abajo / negras abajo).
- **Juegos de piezas** SVG (`assets/pieces/<id>/{w,b}{K,Q,R,B,N,P}.svg`, catálogo en `assets/pieces/sets.json`),
  elegibles en Ajustes con vista previa. Solo juegos con licencia libre (sin «no comercial»). Por defecto, el más
  parecido a los diagramas impresos (Merida si su licencia lo permite). La fuente `ChessFigures` queda como juego de
  reserva «Tipográfico».
- **Casilla dudosa:** triángulo ámbar en la esquina superior derecha de la casilla + filete ámbar de 2 dp (marca +
  color). Al confirmarla o corregirla desaparece.
- Casilla seleccionada para editar: filete `primary` de 3 dp.
- Las piezas nunca dependen de fuentes del sistema.

## 4. Arquitectura de pantallas

### 4.1 Inicio / sesión (`/`)

Barra superior: título «Chess to PGN» (Archivo Condensed), acción **Ajustes**. Si hay diagramas: menú con «Vaciar
sesión».

**Vacío (primera vez):** no es un cartel centrado. Arriba, un diagrama de ejemplo real dibujado con el tablero y las
piezas actuales (enseña el resultado); debajo tres pasos numerados en una lista compacta (1 Haz una captura de la
página · 2 Elígela aquí · 3 Revisa y exporta) y el botón principal **Elegir captura**. Texto corto sobre privacidad:
«Todo se procesa en el dispositivo.»

**Con diagramas:** lista de diagramas agrupados por captura («Captura 1 · 3 diagramas»), cada uno como *bloque de
diagrama* (4.2). FAB extendido **Añadir captura** (única acción primaria): la sesión **acumula** capturas, no se
borra al añadir otra. Barra inferior de exportación del conjunto: «N diagramas» + **Guardar .pgn** (botón tonal) +
**Compartir** (solo Android) + copiar PGN en el menú.

**Leyendo:** el grupo de la captura aparece al instante con *esqueletos* de bloque (uno por tablero encontrado) y una
línea de progreso «Leyendo 2 de 4…» con `LinearProgressIndicator` bajo la cabecera. Nunca un spinner a pantalla
completa. La lista ya leída sigue siendo utilizable.

**Fallos:** banda en línea dentro del grupo de esa captura, con causa y salida: «No se encontró ningún tablero en esta
captura.» + botón **Recortar a mano**. Errores inesperados: mensaje + «Reintentar».

**Ancho:** < 600 dp una columna; ≥ 840 dp dos columnas de bloques; ≥ 1240 dp tres. Contenido con ancho máximo y
márgenes; en Windows todo es alcanzable con teclado y tiene foco visible.

### 4.2 Bloque de diagrama

De arriba abajo:

1. **Encabezado:** numeral grande (Archivo Condensed 700, tinta) + a su derecha estado en una línea:
   «2 casillas dudosas» (icono de aviso, ámbar) / «Posición imposible: …» (icono de error) / nada si todo está bien.
   A la derecha, menú ⋮.
2. **Comparador:** control segmentado **Leído | Original**. «Leído» = `BoardView` editable; «Original» = el recorte de
   la captura a la misma medida y posición, para comparar alternando (fundido de 150 ms). Mantener pulsado el
   tablero muestra el original mientras dure la pulsación.
3. **Pie del diagrama (turno):** segmentado **Mueven blancas | Mueven negras** con el disco ○/● del color. Si la
   posición fuerza el turno (un rey en jaque), se fija y se explica en una línea.
4. **Enroques:** `FilterChip` solo para los enroques que la colocación permite (Blancas O-O, Blancas O-O-O, Negras
   O-O, Negras O-O-O), activos por defecto. Si ninguno es posible, la fila no aparece.
5. **Acciones:** **Analizar en Lichess** (tonal, la principal del bloque), **Copiar FEN** (texto). En ⋮: Copiar PGN,
   Compartir este diagrama (Android), Ver desde las negras (gira 180° la lectura), Ajustar recorte, Eliminar
   (con «Deshacer» en la snackbar).
6. **FEN** en una línea monoespaciada, seleccionable, con elipsis; tocarla la copia.

Editar una casilla: tocarla abre una **hoja inferior** (no un diálogo) con título «Casilla e4», la opción «Vacía» y
dos filas de seis piezas (blancas / negras) con objetivos de 48 dp y la actual resaltada. Un toque aplica y cierra.
Si la casilla era dudosa y la lectura era correcta, la hoja ofrece **«Está bien»** para confirmarla.
«Revisar dudosas»: tocar el estado del encabezado abre la hoja de la primera casilla dudosa y, al resolverla, pasa a
la siguiente.

### 4.3 Recortar a mano

Pantalla completa con la captura. **Pellizcar para ampliar y arrastrar** (`InteractiveViewer`), rectángulo con cuatro
esquinas de 48 dp y bordes arrastrables, exterior atenuado, rejilla 8×8 tenue dentro del rectángulo para alinear.
Al arrastrar una esquina, **lupa** junto al dedo. Barra inferior: «Restablecer» y botón principal **Leer este
tablero**. Ayuda de una línea: «Encierra el tablero; no hace falta que sea exacto.»

### 4.4 Ajustes

Pantalla propia (en ancho ≥ 840 dp, diálogo ancho). Secciones:

- **Apariencia:** Tema (segmentado Sistema / Claro / Oscuro) · Tinta (seis muestras circulares con nombre; la elegida
  con marca) — el cambio se ve al instante en una vista previa de tablero fija arriba.
- **Tablero:** Estilo (Liso / Impreso) · Coordenadas (interruptor) · Piezas (rejilla de vistas previas con caballo y
  rey de cada color, nombre del juego y autor).
- **Acerca de:** versión, «Todo se procesa en el dispositivo», licencias (piezas, fuentes y paquetes).

Los ajustes se guardan (`shared_preferences`) y se aplican en vivo.

## 5. Textos

Español, tuteo, frases cortas. Los botones nombran la acción («Guardar .pgn», «Leer este tablero»). Los errores dicen
qué pasó y cómo seguir. Sin signos de exclamación ni jerga de visión artificial. «Diagrama», «casilla dudosa»,
«captura», «recorte».

## 6. Accesibilidad

Contraste AA (4,5:1 texto, 3:1 texto grande y elementos gráficos). `Semantics` en tablero («e4, caballo blanco,
dudosa»), en muestras de tinta y juegos de piezas. Foco visible y orden lógico con teclado en Windows. Todo
funciona a tamaño de fuente 1,3× sin recortes.

## 7. Verificación

Arnés de capturas (`flutter test` con fuentes reales) que genera PNG de cada pantalla y estado en claro y oscuro a
tamaño de móvil (412×915 dp) y de ventana (1280×800 dp). Ningún cambio de UI se da por bueno sin mirar las capturas.
