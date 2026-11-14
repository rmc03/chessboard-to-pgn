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
La versión es la de `pubspec.yaml` (`0.1.0+1` → etiqueta `v0.1.0`).
