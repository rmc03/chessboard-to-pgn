# Cambios

El flujo de release copia en las notas de cada versión la sección `## <versión>` de este archivo.

## 0.2.0

- **Recortar a mano**: si un diagrama no se detecta o se lee mal, encierra el tablero con un rectángulo (esquinas
  arrastrables); basta con un recorte aproximado, el programa se ajusta solo a la cuadrícula. Cada diagrama tiene
  además **Ajustar recorte** para repetir su lectura.
- **Compartir** (Android) como texto o como archivo `.pgn`, y **Guardar .pgn** con el diálogo del sistema (Android y
  Windows). Menú ⋮ en cada diagrama: copiar FEN o PGN, compartir y ajustar recorte.
- **Lecturas erróneas corregidas en recortes ajustados.** Con una imagen recortada justo en el borde del tablero (o
  cortando un poco las casillas del borde), la cuadrícula quedaba desplazada hasta media casilla y aparecían
  "tableros" falsos; eso producía piezas mal leídas, incluido el color cambiado. Ahora la cuadrícula se ajusta igual
  con o sin margen.
- **Más tableros encontrados en capturas alejadas** (página con zoom pequeño).
- **Lectura 3–4 veces más rápida** (cálculo vectorial SIMD en el clasificador).
