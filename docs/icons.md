# Iconos — Hugeicons (stroke rounded)

Decisión del autor: todos los iconos de la app salen del paquete `hugeicons` (^4.4.0, MIT, estilo *stroke
rounded*). Nada de `Icons.*` de Material ni de glifos de texto. Uso:

```dart
import 'package:hugeicons/hugeicons.dart';
const HugeIcon(icon: HugeIcons.strokeRoundedCrop)   // hereda color y tamaño de IconTheme
```

Trazo único en toda la app: el del tema (`AppIcon` en `lib/src/ui/icons.dart` fija `strokeWidth: 1.8` y el tamaño;
los botones usan siempre `AppIcon`, nunca `HugeIcon` directo). Diccionario (una acción = un icono en toda la app):

| Acción / significado | Icono |
|---|---|
| Ajustes | `strokeRoundedSettings02` |
| Añadir captura / elegir captura | `strokeRoundedImageAdd02` |
| Recortar a mano / ajustar recorte / recortar otro tablero | `strokeRoundedCrop` |
| Quitar (diagrama, captura) | `strokeRoundedDelete02` |
| Quitar todas las capturas | `strokeRoundedDelete04` |
| Compartir | `strokeRoundedShare08` |
| Copiar (FEN, PGN, enlace) | `strokeRoundedCopy01` |
| Guardar .pgn | `strokeRoundedDownload04` |
| Analizar en Lichess (abre fuera) | `strokeRoundedLinkSquare02` |
| Ver desde las negras (girar) | `strokeRoundedArrowUpDown` |
| Casilla dudosa / avisos | `strokeRoundedAlert02` |
| Error / posición imposible | `strokeRoundedAlertCircle` |
| Turno forzado (candado) | `strokeRoundedSquareLock02` |
| Ir / revisar (chevron) | `strokeRoundedArrowRight01` |
| Cerrar | `strokeRoundedCancel01` |
| Reintentar | `strokeRoundedRefresh` |
| Deshacer | `strokeRoundedUndo02` |
| Acercar / alejar / ver toda la imagen | `strokeRoundedZoomInArea` / `strokeRoundedZoomOutArea` / `strokeRoundedFullScreen` |
| Confirmado / seleccionado | `strokeRoundedTick02` |
| Información / privacidad | `strokeRoundedInformationCircle` / `strokeRoundedSquareLock02` |
| Licencias | `strokeRoundedLicense` |
| Sin tablero encontrado | `strokeRoundedSearch01` |

Si una acción nueva necesita icono, se añade aquí primero.
