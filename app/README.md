# App Flutter de prueba (Android + Windows)

Pantalla única y deliberadamente simple para probar el reconocimiento **100 % en el dispositivo**:

1. **Elegir imagen** (galería en Android, selector de archivos en Windows): una captura con varios diagramas,
   una foto de página o un diagrama suelto.
2. Cada diagrama completo se lee y se muestra como un tablero. Las casillas **poco seguras salen con borde ámbar**.
3. **Toca una casilla** para corregirla. Elige quién mueve y si se proponen enroques; verás avisos si la posición
   es ilegal (falta un rey, peón en la 1ª/8ª fila, el bando que no mueve está en jaque…).
4. **Copiar PGN**: un PGN con una partida por diagrama (`[SetUp "1"] [FEN "…"]` y resultado `*`).

No hay recorte manual todavía: si no hay marco alrededor de los diagramas, se usa la imagen entera como un único
tablero (se avisa en la tarjeta). Los tableros cortados por el borde de la pantalla se ignoran: desplaza hasta verlos enteros.

## Cómo funciona (sin plugins nativos de ML)

`lib/src/` es un puerto a Dart de `prototype/chessdiag/` (mantenerlos sincronizados):

| Archivo | Equivale a |
|---|---|
| `chess.dart` | `fen.py` — FEN/PGN, decodificación con reglas, jaque |
| `classifier.dart` | `model.py` — la CNN, ejecutada en Dart puro con los pesos de `assets/model/` |
| `locate.dart`, `imaging.dart` | `locate.py` — detección de uno o varios tableros |
| `pipeline.dart` | `pipeline.py`, `squares.py` — recorte de 64 casillas y todo el recorrido (en *isolates*) |

Se evita un plugin de TFLite a propósito: es lo que suele romper las compilaciones de escritorio y de CI. La red
(~9,7 M de multiplicaciones por casilla) cuesta unos **0,9 s por tablero** compilada en nativo en un portátil de
4 núcleos (1,4 s en modo depuración); en un móvil será más lento, y los tableros de una página se clasifican en
paralelo. Si hace falta velocidad, el plan es pasar a LiteRT: el contrato del modelo no cambia.

## Probar y ejecutar

```bash
cd app
flutter pub get
flutter analyze
flutter test                       # reglas, red neuronal vs TFLite, pipeline vs Python, interfaz
flutter run -d windows             # o: flutter run  (con un móvil Android conectado)
```

Las pruebas comparan el Dart con el Python: `test/classifier_test.dart` contra la salida real del intérprete de
TFLite y `test/pipeline_test.dart` contra lo que lee el pipeline de Python en las imágenes de `test/fixtures/`.

Prueba opcional con **tus propias capturas** (no se sube nada al repositorio):

```bash
CHESS_REAL_PAGES=/carpeta/con/capturas CHESS_REAL_EXPECTED=/ruta/esperado.json flutter test test/real_pages_test.dart
```

`esperado.json`: `{"pagina.jpg": ["colocación tablero 1", "colocación tablero 2"]}` en orden de lectura.

## Regenerar el modelo para la app

Tras reentrenar (`prototype/`), desde `prototype/`:

```bash
PYTHONPATH=. python -m chessdiag.export_dart --model ../models/squares.tflite --out ../app/assets/model --fixtures ../app/test/fixtures
```

Escribe `weights.bin` + `manifest.json` (float32, ~800 KiB) y los datos de referencia de las pruebas, y comprueba que
las capas exportadas reproducen el modelo TFLite.

## Compilación automática

`.github/workflows/build.yml` (solo con un `push` a `main`): analiza y prueba, y compila el **APK de Android**
(firmado con la clave de depuración, instalable para probar) y la carpeta **de Windows** (`chessboard_pgn.exe` + DLL +
`data/`). Se descargan de la página de la ejecución, en *Artifacts*. Se fija Flutter 3.50.0, la versión con la que se
probó.
