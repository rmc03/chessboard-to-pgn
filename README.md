# chessboard-to-pgn

Convierte la imagen de un **diagrama de ajedrez digital** (captura de pantalla, PDF, libro escaneado, web)
en un archivo **PGN** con la posición exacta, ejecutándose **100 % en local** (Android con Flutter).
Las fotos de tableros físicos son un objetivo posterior y requerirán una captura guiada.

> Estado: **fase 1 (prototipo de referencia en Python)**. Aún no hay app Flutter.
> Modelos en [`models/`](models/) (cada uno 212 KiB, mismo `model_contract.json`):
> - `squares.tflite` — **v3**, genérico + adaptado a la tipografía de un libro real de problemas.
> - `squares_generic_v2.tflite` — v2, solo estilos sintéticos (falla en el libro, ver abajo).

## Resultados con capturas reales de un libro (modelo v3)

Capturas de móvil de un libro de problemas (1080×2400, 8 diagramas por página, con barra de estado, contador de
página y pies con números). 24 tableros completos, etiquetados por agrupamiento de formas y **validados con las
reglas del ajedrez (24/24 legales)**; no hay etiquetas de una persona independiente.

| Modelo y prueba | 1,0× | 1,4× | 0,85× | 0,7× | 0,5× |
|---|---|---|---|---|---|
| v2 genérico, 24 tableros | 0/24 | 0/24 | 0/24 | 0/24 | 0/24 |
| v3 entrenado **sin** la página 1–10, evaluado en ella (8 tableros) | **8/8** | **8/8** | 8/8 | 7/8 | 5/8 |
| v3 final, 24 tableros (**no independiente**: entrenó con ellos) | 24/24 | 24/24 | 23/24 | 23/24 | 11/24 |

- Es el mismo libro, el mismo móvil y la misma tipografía: la fila independiente mide *diagramas nuevos de un estilo ya
  conocido*, **no** generalización a otros libros. La muestra es pequeña (8 tableros).
- Los fallos por debajo de 0,85× vienen del **detector de tableros** (el marco fino se pierde, o el contador de página
  tapa una esquina), no del clasificador: recortando los tableros con su caja correcta, el modelo lee 8/8 incluso
  reducidos a 122 px. Si el detector no está seguro la app debe pedir el recorte manual de 4 esquinas.
- **Coste en otro estilo:** en el primer diagrama de prueba (otro libro, 152×122 px) v2 acertaba las 64 casillas y v3
  falla una (a4, dama blanca leída como negra, marcada como dudosa). Especializar en un libro desplaza las fronteras
  de decisión para los demás, de ahí que se conserve v2 como modelo genérico.
- Turno: el libro indica «Las blancas juegan primero»; la app puede usar blancas como valor por defecto pero el
  usuario debe poder cambiarlo. Los derechos de enroque propuestos son los *posibles* según rey/torres; en problemas
  suele ser más seguro `-`.

## Resultados con diagramas sintéticos (modelo v2)

Se miden con **diagramas sintéticos** generados por `chessdiag/synth.py`, salvo la última fila. No son cifras
de diagramas reales y no hay que leerlas como tales.

| Prueba | Resultado |
|---|---|
| Acierto por casilla, validación (cajas con jitter) | 99,8 % |
| 500 diagramas nuevos, tablero **exacto**, con la caja real | 93,8 % |
| Igual, pero con el localizador automático en el circuito | 87,2 % (el localizador acierta ~95 %) |
| Familia de pieza nunca vista (entrenado sin cburnett, evaluado solo con cburnett) | 98,8 % por casilla, 78,3 % de tableros exactos |
| Diagrama real aportado por el autor (152×122 px, 1 imagen) | 64/64 casillas contra su lectura manual |

Cautelas: la lectura manual del diagrama real la hizo quien escribió el prototipo (con una medición de oscuridad
de píxeles para la casilla ambigua b6), no es una verdad de terreno independiente, y es **una sola imagen**.
Con v1 esa misma imagen salía con 1 casilla mal (b6, confianza 0,72), lo que ilustra por qué la app debe resaltar
las casillas dudosas y permitir corregirlas. En diagramas reales de estilos
nuevos habrá errores: hay que ampliar los estilos de pieza (ver abajo) antes de fiarse de la precisión.

## Pendiente conocido

- Pocos diseños de pieza reales (cburnett, glifos de fuentes y el libro adaptado). Cada libro/sitio nuevo necesita
  su propia adaptación (ver «Adaptar a un libro nuevo») o más estilos de entrenamiento; permitir que el usuario
  aporte diagramas corregidos como datos de ajuste.
- **Licencia de los pesos:** v2 se entrenó con renders de cburnett (GPLv2+ / CC BY-SA) y fuentes DejaVu/FreeFont;
  v3 además con casillas recortadas de capturas de un libro con copyright. Las capturas, las casillas y las
  etiquetas **no** están en el repositorio (`prototype/data/` está en `.gitignore`), pero los pesos sí. Decidir la
  licencia del repositorio y de los pesos con eso en cuenta antes de publicar.
- El detector de varios tableros exige un marco fino alrededor de cada diagrama y es fiable desde ~0,7× de una captura
  de 1080 px de ancho; el resto se recorta con las 4 esquinas de la app. Descarta cajas de tamaño anómalo.
- Solo orientación con blancas abajo.

## Qué se puede y qué no se puede deducir de una imagen

Una imagen solo contiene la **colocación de las piezas**. Por eso el PGN generado es de *posición*:
`[SetUp "1"] [FEN "..."]` sin jugadas y resultado `*`. La app debe **preguntar** (o inferir y proponer):

| Dato | Cómo se obtiene |
|---|---|
| Turno | Se infiere solo si un bando está en jaque; si no, lo elige el usuario |
| Enroques | Se proponen los que permiten las posiciones de rey/torre; el usuario confirma |
| En passant | El usuario lo indica (por defecto `-`) |
| Orientación | Se asume blancas abajo; el usuario puede girar el tablero |

Ningún modelo garantiza el 100 % de aciertos, así que la app tendrá una **pantalla de corrección**
(tablero editable con las casillas poco seguras resaltadas) antes de exportar.

## Stack elegido

| Capa | Elección |
|---|---|
| App | Flutter / Dart (Android primero), código abierto |
| Recorte | 4 esquinas arrastrables (siempre disponible) + autodetección para diagramas planos |
| Clasificación | CNN pequeña, 13 clases por casilla (32×32 gris), exportada a `.tflite` |
| Runtime móvil | `flutter_litert` (sucesor de `tflite_flutter`) |
| Reglas / PGN en la app | `dartchess` (GPL-3.0, compatible con un proyecto abierto) |
| Entrenamiento | Python + Keras + `python-chess`, fuera del móvil, con datos sintéticos |

Descartado: YOLO de Ultralytics (AGPL-3.0, más pesado y innecesario para diagramas planos).

## Pipeline (lo que la app debe replicar)

0. `locate.find_boards` (solo capturas con varios diagramas) — marco fino de cada tablero con un filtro *black-hat* y trazos largos y rectos; descarta barras, contadores de color, pies y cajas de tamaño anómalo.
1. `locate.find_board` — caja del tablero (moda del borde = fondo de página → columnas/filas con “tinta” densa → ajuste a una rejilla de 9 líneas equiespaciadas).
2. `squares.cut_squares` — 64 recortes 32×32 en gris, rango `[0,1]`, orden a8→h1.
3. Modelo `squares.tflite` (batch fijo de 64) → probabilidades `(64, 13)`.
4. `fen.decode` — decodificación con reglas: un rey por bando, sin peones en 1ª/8ª, ≤ 8 peones por bando.
5. `fen.to_fen` / `fen.to_pgn` — FEN completo y PGN de posición.

`model_contract.json` (generado junto al modelo) fija formas, rango y orden de clases para el lado Dart.

## Prototipo Python

```bash
cd prototype
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
PYTHONPATH=. pytest -q tests
PYTHONPATH=. python -m chessdiag.train --boards 4000 --epochs 10 --out runs/v1
PYTHONPATH=. python -m chessdiag.cli diagrama.png --model runs/v1/squares.tflite --out posicion.pgn
```

Captura con varios diagramas → un PGN con una partida por diagrama:

```bash
PYTHONPATH=. python -m chessdiag.cli captura.jpg --page --turn w --model ../models/squares.tflite --out problemas.pgn
```

## Adaptar a un libro nuevo

Un modelo que nunca ha visto la tipografía se equivoca con seguridad y de forma consistente (v2 leyó todos los peones
del libro como alfiles), así que sus predicciones **no** sirven como etiquetas. En su lugar, como un libro usa una sola
tipografía, se agrupan las piezas por forma y se identifican los ~18 grupos una vez:

```bash
PYTHONPATH=. python -m chessdiag.book extract --pages data/book/pages --model ../models/squares.tflite --out data/book
# abrir data/book/clusters.png: una fila = un grupo (misma pieza, color y color de casilla). El orden de las filas
# puede cambiar entre ejecuciones: leerlas siempre de nuevo.
PYTHONPATH=. python -m chessdiag.book label --out data/book --rows "p P p P n R K k r N R r Q q b B B b"
PYTHONPATH=. python -m chessdiag.train --boards 4000 --epochs 8 --book data/book/book_cells.npz \
    --book-pages p25-32,p51-58 --eval-pages p01-10 --out runs/libro   # páginas de ajuste vs. páginas de prueba
```

`label` comprueba cada tablero contra las reglas del ajedrez (un rey por bando, ≤ 8 peones, ninguno en 1ª/8ª, sin
jaques imposibles): una fila mal identificada hace saltar esos avisos. Con las tres capturas del libro de prueba, los
24 tableros salieron legales y dos agrupamientos independientes dieron las mismas posiciones.

Los datos de entrenamiento se **generan** (`chessdiag/synth.py`): posiciones aleatorias dibujadas con
piezas SVG (cburnett, de `python-chess`) y glifos Unicode de fuentes del sistema (DejaVu, FreeFont, Unifont),
con casillas planas/punteadas/tramadas/de color, márgenes, coordenadas, desenfoque, ruido y JPEG.
Para reproducir los resultados hacen falta esas fuentes (`fonts-dejavu-core`, `fonts-freefont-ttf`, `unifont`).
