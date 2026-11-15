# Product

<!-- impeccable:product-schema 1 -->

## Platform

android

Flutter. Se publica para Android (principal) y Windows x64 (secundario, misma interfaz Material adaptada a ventana
ancha con ratón y teclado). No hay versión web ni iOS.

## Users

Dos perfiles con el mismo peso (confirmado por el autor):

- **Lector**: jugador que lee libros de ajedrez digitales en el móvil, hace una captura de pantalla de la página y
  quiere pasar a PGN los diagramas que le interesan, uno o varios cada vez, sin teclear la posición.
- **Entrenador o autor**: prepara material; convierte muchos diagramas seguidos de varias páginas y necesita revisarlos
  rápido y sacarlos juntos en un archivo.

Los dos conocen la notación (FEN, PGN, nombres de casillas) y reconocen de un vistazo si una posición está bien.

## Product Purpose

Convertir diagramas de ajedrez **digitales** (capturas de libros, PDF, webs) en posiciones PGN/FEN, en el propio
dispositivo y sin conexión. Éxito: de la captura al PGN correcto en segundos, con el usuario seguro de que la
posición es la del libro porque ha podido compararla y corregirla.

## Positioning

Todo ocurre en el dispositivo (sin cuenta, sin servidor, sin permisos de almacenamiento), lee **todos** los diagramas
de una página a la vez y señala las casillas de las que duda en lugar de dar una posición por buena en silencio.
Es software libre.

## Operating Context

- Entrada: una imagen de la galería (captura de pantalla de una página con uno o varios diagramas enmarcados) o un
  recorte de un solo tablero. No es para fotos de tableros físicos.
- Flujo: elegir imagen → la app encuentra los tableros y los lee → el usuario compara cada tablero con el original,
  corrige casillas tocándolas, indica quién mueve y los enroques → exporta.
- Si un tablero no se detecta o se lee mal, el usuario lo encierra a mano con un rectángulo (recorte aproximado).
- Salida, por orden de uso confirmado: **abrir en el análisis de Lichess**, **guardar un archivo `.pgn`** para una
  base de datos (ChessBase, SCID…), **compartir** (texto o archivo). Copiar FEN/PGN sigue disponible.
- Un diagrama solo da la colocación de las piezas: el turno, los enroques y la captura al paso los confirma el usuario.

## Capabilities and Constraints

- Lectura con un clasificador por casilla (13 clases) ejecutado en Dart puro; ~0,25 s por tablero en escritorio,
  sin medir en móvil. Cada casilla trae una confianza; por debajo del umbral es «dudosa».
- La posición se valida con las reglas (reyes, peones, jaques imposibles) y los problemas se muestran en texto.
- Varios diagramas por imagen; el PGN conjunto lleva una partida `[SetUp "1"]` por diagrama.
- Compartir solo existe en Android; guardar `.pgn` usa el diálogo del sistema en Android y Windows.
- Idioma de la interfaz: **solo español** (confirmado).
- Sin historial entre sesiones (hoy la lista se pierde al cerrar la app). No decidido si debe haberlo.
- Términos: diagrama, tablero, casilla, casilla dudosa, recortar, mueven blancas/negras, enroque, FEN, PGN.

## Brand Commitments

- Nombre visible: «Chess to PGN». Icono de la app ya publicado (`app/tool/make_icons.py`).
- Voz: directa, de usuario a usuario, sin tecnicismos de visión artificial; honesta sobre lo que no sabe
  («casillas dudosas», «no se detectó ningún tablero»).

## Evidence on Hand

- Capturas reales de páginas de libros usadas en las pruebas (no se redistribuyen; no están en el repositorio).
- Fijaciones de prueba en `app/test/fixtures/`.
- Cifras de precisión medidas en `README.md`. No hay testimonios, usuarios ni métricas de uso: no inventarlos.

## Product Principles

1. **Comparar antes que confiar.** La posición leída siempre se presenta de forma que cotejarla con el original sea
   inmediato; lo dudoso se señala, nunca se esconde.
2. **Corregir cuesta un toque.** Arreglar una casilla, el turno o un recorte no debe sacar al usuario de la lista.
3. **El resultado sale por donde el usuario lo necesita.** Lichess, archivo `.pgn` y compartir están a la vista; no hay
   que buscar cómo llevarse la posición.
4. **Sirve para uno y para veinte.** El mismo flujo vale para un diagrama suelto y para una tanda de páginas.
5. **Nada sale del dispositivo sin una acción explícita.**

## Accessibility & Inclusion

Las piezas blancas y negras deben distinguirse sin depender del color del sistema ni de fuentes del sistema (fallo real
en Android con el peón emoji). Las casillas dudosas no pueden señalarse solo con color. Objetivos táctiles de 48 dp y
texto que siga el tamaño de fuente del sistema.
