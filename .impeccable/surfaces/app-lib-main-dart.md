---
version: 1
slug: "app-lib-main-dart"
primary_target: "app/lib/main.dart"
related_targets: []
---

# Surface brief: app shell and session (app/lib/main.dart)

Scope: the whole Flutter app (home/session, diagram block, square editor sheet, crop screen, settings).
Visitor mode: Operate. Audience and jobs: see PRODUCT.md. Full build spec: docs/ux-spec.md.

## Direction contract

THESIS: The diagram list is a row of stone chess tables in a plaza. The app owns the municipal-plaza world (stone,
park-bench green, enamel plates); it refuses the chess-site arrangement of a grey shell around a flat green board and
refuses stock Material shapes (stadium buttons, 20 dp outlines).

OWN-WORLD: Stone chess tables of Spanish and Latin-American plazas. Limestone ground, park-bench green shell, stone
boards with a barely visible terrazzo speckle in a polished granite frame, enamel street-name plates (green, inner
white rule, 6 dp corners) for diagram numbers, capture headers, the FAB and the one primary button per screen.
Amber (street lamp) only for doubtful, brick only for errors. Night theme = the plaza at night (basalt ground).
Barlow for UI, Barlow Condensed for plates, numerals and masthead, JetBrains Mono only for FEN/PGN. Standard Material
3 controls with the plate shape language (6 dp radius, 1 dp outlines, no capsules, no shadows).

STORY: The reader sees each diagram set on its own stone table with a numbered plate, compares it with the original
crop, fixes a doubtful square in one tap and sends the position to Lichess, a .pgn file or a share target.

FIRST VIEWPORT: Green masthead "Chess to PGN" with settings; the capture header with its small plate "CAPTURA 1" and
"3 diagramas"; diagram block: enamel plate numeral, status line, Leído/Original segmented control, the stone board
filling the width, "Mueven blancas / negras" under it, then Analizar en Lichess and Copiar FEN. Plate-shaped FAB
"Añadir captura"; export bar at the bottom.

FORM: Plaza stone tables (candidate 7 of 7 on the grounded list, chosen by the owner on the decision page).
seed:31ddeefe4c10e42b

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Signature interaction and motion grammar

Plates: diagram numbers, capture headers, FAB and primary button are enamel plates; nothing else carries the inner
rule. Stone: changing the stone in Ajustes re-lays the board live (200 ms). Comparator: Leído/Original cross-fade
(150 ms) and press-and-hold peek. No other decorative motion.

## Unresolved

History between sessions (undecided product fact). Windows drag-and-drop of images.
