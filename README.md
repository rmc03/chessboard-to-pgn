# chessboard-to-pgn

Convierte la imagen de un **diagrama de ajedrez digital** (captura de pantalla, PDF, libro escaneado, web)
en un archivo **PGN** con la posición exacta, ejecutándose **100 % en local** (Android con Flutter).
Las fotos de tableros físicos son un objetivo posterior y requerirán una captura guiada.

> Estado: **fase 1 (prototipo de referencia en Python)**. Aún no hay app Flutter.

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

Los datos de entrenamiento se **generan** (`chessdiag/synth.py`): posiciones aleatorias dibujadas con
piezas SVG (cburnett, de `python-chess`) y glifos Unicode de fuentes del sistema (DejaVu, FreeFont, Unifont),
con casillas planas/punteadas/tramadas/de color, márgenes, coordenadas, desenfoque, ruido y JPEG.
Para reproducir los resultados hacen falta esas fuentes (`fonts-dejavu-core`, `fonts-freefont-ttf`, `unifont`).
