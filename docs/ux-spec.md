# Especificación de UX y estilo visual — Chess to PGN 0.3 (mundo «Plaza»)

Documento de trabajo para el rediseño. La verdad de producto está en [`PRODUCT.md`](../PRODUCT.md); aquí están las
decisiones de diseño. Plataforma: Flutter, Material 3, Android (principal) y Windows (ventana ancha).
Modo de la superficie (impeccable): **Operate** — el usuario viene a hacer una tarea; la marca vive en el detalle.

## 1. Dirección: «Plaza» (elegida por el autor el 15-11-2026)

Referencia cultural: las mesas de ajedrez de piedra de las plazas y parques de España y Latinoamérica. Tablero de
granito y terrazo embutido en la mesa, bancos de hierro pintados de verde municipal, placas esmaltadas con el nombre
de la calle (letras blancas sobre placa de color, filete blanco interior, esquinas redondas pequeñas), la caliza al
sol y, de noche, el ámbar de las farolas. Página de decisión: https://claude.ai/artifact/TwqKmawr4UQPszL18WmwGN

El mundo aporta **tipo, paleta, densidad y un gesto propio**. La navegación y los controles siguen siendo los de
Material 3, pero **sin las formas de serie de Material** (decisión del autor): nada de botones en cápsula ni contornos
muy redondeados; el vocabulario de formas es el de las placas.

- **Gesto propio: la placa esmaltada.** El número de cada diagrama es una placa verde con filete blanco interior y
  esquinas de 6 dp, en Barlow Condensed («DIAGRAMA» pequeño encima, el número grande). La cabecera de cada captura
  lleva una placa pequeña («CAPTURA 1»). El botón flotante «Añadir captura» y el botón principal de cada pantalla
  también son placas (verde, filete interior). Nada más lleva filete: si todo es placa, nada lo es.
- **Segundo rasgo: el tablero es una mesa de piedra.** Casillas de piedra con un moteado de terrazo casi invisible y
  un marco de granito pulido de 3–6 dp con un bisel sutil (luz arriba-izquierda). Legible primero, textura después.
- **Lo que se rechaza:** el gris oscuro con tablero verde liso de las webs de ajedrez, el Material por defecto
  (cápsulas, morado, sombras), el papel crema con serifas.
- **Escena de uso:** lector por la tarde-noche con el móvil (tema oscuro = la plaza de noche) y entrenador de día en
  Windows (tema claro = la plaza a pleno sol). Los dos temas son de primera clase; por defecto se sigue al sistema.

## 2. Tokens

### Paleta

| Rol | Claro | Oscuro |
|---|---|---|
| Carcasa (app bar, FAB, botón principal, placas) | verde banco `#1F5C46`, texto `#F4F1E8` | verde profundo `#143E30` (placas) / `#2E7A5E` donde haga falta contraste, texto `#E9EFE8` |
| Fondo | caliza `#ECE8DF` | basalto `#0F1411` |
| Bloque (superficie de diagrama) | piedra `#E0DBCD` | `#181F1B` |
| Texto / secundario | `#1D2520` / `#4F5A52` | `#E4E8E0` / `#A9B3AA` |
| Dudosa | ámbar `#D98E00` (marca), texto ámbar oscuro con contraste AA | farola `#FFB93D` |
| Error | ladrillo `#A8432C` | `#D9694C` |

- El esquema Material se construye a partir de estos valores (no de una semilla genérica): `primary` = verde banco,
  superficies = caliza/piedra (claro) y basalto (oscuro). Todo color de la interfaz sale de **roles**; los hex solo
  viven en `tokens.dart`. Contraste AA verificado por prueba en ambos temas.
- El ámbar solo significa «dudosa» y el ladrillo solo «error»: no se usan como adorno.

### Piedras del tablero (sustituyen a las «tintas»)

El ajuste «Tinta» pasa a ser **«Piedra»**: cambia solo el tablero; la carcasa es siempre verde banco.

| id | Nombre | Casilla clara | Casilla oscura |
|---|---|---|---|
| `serpentina` (defecto) | Serpentina | travertino `#E8E1CD` | serpentina `#76927F` |
| `pizarra` | Pizarra | mármol blanco `#E9E8E4` | pizarra `#7D8590` |
| `alicante` | Rojo Alicante | crema `#EADFCC` | mármol rojo `#A8776A` |
| `nogal` | Nogal | arce `#EBD9B8` | nogal `#9C7653` |
| `granito` | Granito | granito claro `#E3E1DA` | granito gris `#8F918C` |

Las casillas oscuras quedan en tono medio (L* 55–65) para que piezas blancas y negras se lean en ambas; el marco es
granito `#4A4C48`. El tablero es igual en tema claro y oscuro. Valores de partida: la prueba de contraste manda.

### Formas

- Radio 6 dp en botones, segmentados, etiquetas (chips), campos y FAB; 10 dp en bloques de diagrama y hojas
  inferiores (solo esquinas superiores). Nada de cápsulas (`StadiumBorder`) ni radios de 20 dp.
- Contornos de 1 dp en `outline`; el seleccionado de segmentados y chips es un relleno de piedra más oscura
  (`secondaryContainer`) con texto fuerte, sin marca de verificación salvo donde el color sea el único indicio.
- Placas: relleno carcasa, filete interior de 1,5 dp en el color del texto a 3 dp del borde, radio 6 dp.
- Sin sombras: elevación tonal.

### Tipografía (fuentes incluidas, licencia OFL)

- **Barlow** (400/500/600/700): todo el texto de interfaz.
- **Barlow Condensed** (600/700): placas, numerales, título de la cabecera. No en botones ni cuerpo.
- **JetBrains Mono** (400/500): solo FEN y PGN.
- Escala de Material (`display/headline/title/body/label`), razón ~1,2. Etiquetas de botón en Barlow 600, sin
  mayúsculas forzadas. Cifras tabulares en numerales y contadores. Respeta el tamaño de fuente del sistema.

### Espaciado y tamaño

Rejilla de 4 dp: 4, 8, 12, 16, 24, 32. Margen lateral 16 dp (24 dp desde 600 dp). Objetivos táctiles ≥ 48 dp.

### Movimiento

150–250 ms, curvas estándar de M3; solo para cambios de estado (Leído/Original, hoja inferior, progreso, cambio de
piedra en Ajustes). Con «quitar animaciones»: corte.

## 3. Tablero y piezas

- `BoardView`: piedra elegida, **estilo** (`piedra` = textura de terrazo + marco de granito, por defecto; `liso` =
  casillas planas con filete fino; `impreso` = casillas oscuras rayadas en negro, como en los libros), coordenadas
  opcionales, orientación.
- Piezas SVG elegibles; por defecto **Cburnett** (su contorno negro constante se lee en la piedra de tono medio).
- **Casilla dudosa:** anillo ámbar de 2 dp con filete oscuro + esquina doblada (triángulo) ámbar; en oscuro, además,
  un leve halo de farola. Nunca por color solo.
- Casilla seleccionada: anillo verde carcasa de 3 dp con filete blanco exterior (visible en ambos temas).
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

- **Apariencia:** Tema (segmentado Sistema / Claro / Oscuro) · Piedra (cinco muestras con nombre: un trozo de
  tablero de esa piedra; la elegida con marca) — el cambio se ve al instante en una vista previa fija arriba.
- **Tablero:** Estilo (Piedra / Liso / Impreso) · Coordenadas (interruptor) · Piezas (rejilla de vistas previas con caballo y
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
