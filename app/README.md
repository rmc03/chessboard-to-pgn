# App Flutter de prueba (Android + Windows)

App para probar el reconocimiento **100 % en el dispositivo**, con el estilo «Plaza» (tablero de piedra, tema claro y oscuro;
ver [`DESIGN.md`](../DESIGN.md) y [`PRODUCT.md`](../PRODUCT.md) en la raíz):

1. **Elegir captura** (galería en Android, selector de archivos en Windows; Ctrl+O): una captura con varios diagramas,
   una foto de página o un diagrama suelto. Se pueden añadir varias capturas a la misma sesión.
2. Cada diagrama completo se lee y se muestra como un tablero. Las casillas **poco seguras salen con borde ámbar** y se
   revisan una a una. **Leído / Original** compara con el recorte (mantén pulsado el tablero para verlo).
3. **Toca una casilla** para corregirla. Elige quién mueve y los enroques; verás explicadas las posiciones imposibles.
   Las acciones se deshacen en lugar de pedir confirmación.
4. **Guardar .pgn** (Ctrl+S en Windows): diálogo de guardado (Android: selector de documentos del sistema; Windows: diálogo
   nativo) con el nombre `diagramas-AAAAMMDD-HHMM.pgn`; un PGN con una partida por diagrama (`[SetUp "1"] [FEN "…"]`,
   resultado `*`). Antes de exportar se avisa de los diagramas con dudas o problemas.
5. **Compartir** (solo Android): hoja de compartir del sistema, como texto, como archivo `.pgn` o **Copiar PGN**. En Windows
   no hay compartir y la barra tiene **Copiar PGN** como botón.
6. Cada diagrama tiene sus acciones a la vista: Analizar en Lichess, compartir o copiar PGN, copiar FEN, ajustar recorte,
   ver desde las negras y quitar. **Ajustes**: tema, piedra, estilo, coordenadas y juego de piezas.

**Recorte a mano.** Si un diagrama no se detecta o se lee mal: **Recortar a mano** (botón de recorte de la captura) abre la imagen a
pantalla completa con un rectángulo ajustable (arrastra las esquinas o el interior; mejor con un poco de margen: el programa
se ajusta solo a la cuadrícula dentro del recorte) y añade el tablero leído como un diagrama nuevo. **Ajustar recorte** en una
tarjeta repite la lectura con otro recorte (parte del rectángulo actual) y sustituye ese diagrama. Si no hay ningún marco, se usa la
imagen entera como un único tablero (se avisa en la tarjeta). Los tableros cortados por el borde de la pantalla se ignoran:
desplaza hasta verlos enteros, o recórtalos a mano.

## Cómo funciona (sin plugins nativos de ML)

`lib/src/` es un puerto a Dart de `prototype/chessdiag/` (mantenerlos sincronizados):

| Archivo | Equivale a |
|---|---|
| `chess.dart` | `fen.py` — FEN/PGN, decodificación con reglas, jaque |
| `classifier.dart` | `model.py` — la CNN, ejecutada en Dart puro con los pesos de `assets/model/` |
| `locate.dart`, `imaging.dart` | `locate.py` — detección de uno o varios tableros |
| `pipeline.dart` | `pipeline.py`, `squares.py` — recorte de 64 casillas y todo el recorrido (en *isolates*); `prepareRegion` para el recorte manual |

Se evita un plugin de TFLite a propósito: es lo que suele romper las compilaciones de escritorio y de CI. La red
(~9,7 M de multiplicaciones por casilla) calcula 4 canales a la vez con `Float32x4` (SIMD: NEON en ARM, SSE en x86):
**~0,25 s por tablero** compilada en nativo en un servidor de 4 núcleos (`tool/bench_classifier.dart`; antes ~0,9 s).
En un móvil será más lento (no medido), y los tableros de una página se clasifican en paralelo.

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

Escribe `weights.bin` + `manifest.json` (pesos `int8` con una escala `float32` por canal de salida, tal y como están en el
`.tflite`: ~200 KiB, 4 veces menos que en `float32` y sin pérdida) y los datos de referencia de las pruebas. Comprueba que
el archivo se relee idéntico bit a bit y que las capas exportadas reproducen el modelo TFLite.

## Compilación y release automáticos

`.github/workflows/build.yml` (solo con un `push` a `main`): analiza y prueba; compila en paralelo Android y Windows; y
**publica un release de GitHub** con todo (una sola vez por versión: para publicar otro, sube `version:` en `pubspec.yaml`).

| Archivo del release | Qué es |
|---|---|
| `chess-to-pgn-<v>-android-arm64-v8a.apk` | El recomendado: móviles de 64 bits |
| `…-android-armeabi-v7a.apk` | Móviles antiguos de 32 bits |
| `…-android-x86_64.apk` | Emuladores y Chromebooks |
| `…-android-universal.apk` | Las tres arquitecturas en un solo archivo (el más pesado) |
| `…-windows-x64.zip` | Carpeta completa de Windows (`chessboard_pgn.exe` + DLL + `data/`) |
| `SHA256SUMS.txt` | Sumas de verificación |

Las tablas de tamaños reales de cada compilación aparecen en el resumen de la ejecución (pestaña *Actions*). Los símbolos
de depuración (`debug-symbols-*`) se guardan aparte para descifrar trazas de error.

**Qué se hace para ocupar poco**

- Un APK por arquitectura: un móvil solo lleva el motor y el código de su CPU.
- Código Dart sin símbolos de depuración y con nombres ofuscados (`--split-debug-info --obfuscate`).
- Reducción de código y recursos de Android (R8) e iconos de Material recortados a los que se usan (valores por defecto de Flutter).
- Bibliotecas nativas comprimidas dentro del APK (`useLegacyPackaging`): el archivo pesa mucho menos, a cambio de que Android las
  extraiga al instalar y la app instalada ocupe algo más que el APK. Para lo contrario, quita ese bloque de `android/app/build.gradle.kts`.
- Pesos del modelo en `int8` (~200 KiB en lugar de ~800 KiB).
- Sin permiso de Internet: la app es 100 % local.
- Windows: zip con compresión máxima.

## Firma de release

Sin firma propia, el CI firma con la clave de *depuración* de cada ejecución: sirve para probar, pero cada compilación tiene una
firma distinta y una actualización no se instala sobre la anterior sin desinstalarla. Para firmar siempre con la misma clave,
crea una y guárdala como secretos del repositorio (Settings → Secrets and variables → Actions):

```bash
keytool -genkeypair -v -keystore release.keystore -alias chess -keyalg RSA -keysize 4096 -validity 10000
base64 -w0 release.keystore            # → secreto ANDROID_KEYSTORE_BASE64
# además: ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS (chess) y ANDROID_KEY_PASSWORD
```

**Guarda `release.keystore` y sus contraseñas en un sitio seguro: si se pierden, no se podrán publicar actualizaciones que
se instalen sobre las anteriores.** El flujo los usa solo si existen; `android/key.properties` y los `.keystore` están en `.gitignore`.

## Nombre, icono y versión

Nombre visible «Chess to PGN». Los iconos (Android adaptativo y clásico, Windows `.ico`) salen de `python3 tool/make_icons.py`.
La versión es la de `pubspec.yaml` (`0.3.0+4` → etiqueta `v0.3.0`); las novedades de cada versión van en `CHANGELOG.md`.

Las piezas son SVG de cinco juegos incluidos (`assets/pieces/`); el juego tipográfico usa `assets/fonts/ChessFigures.ttf` (solo los 12 trebejos de DejaVu Sans, 5 kB; licencia en
`assets/fonts/LICENSE-DejaVu.txt`, se regenera con `python3 tool/make_figures_font.py`), no con la fuente del sistema: Android
dibuja el peón ♟ como emoji de color fijo y los peones blancos y negros se veían iguales.
