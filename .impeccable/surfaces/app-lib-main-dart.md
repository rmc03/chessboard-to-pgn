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

THESIS: One spot ink prints everything. The app owns the idea that board and interface are a single two-ink print
job; it refuses the chess-site arrangement of a dark grey shell around an independently coloured green board.

OWN-WORLD: Two-ink Spanish chess magazines. Black plus one flat ink (cobalt by default; tournament green, garnet,
wood, plum, graphite). Ink-coloured masthead app bar, mid-tone ink dark squares, big condensed diagram numerals in
ink, square-cornered boards with a 1 dp rule, tonal surfaces, no shadows. Archivo for UI, Archivo Condensed for
numerals and masthead, JetBrains Mono only for FEN/PGN. Standard Material 3 controls throughout.

STORY: The reader sees their diagrams re-set like a magazine page, flips each one against the original crop, fixes a
doubtful square in one tap, and sends the position to Lichess, a .pgn file or a share target.

FIRST VIEWPORT: Ink masthead with title and settings action; below it the first capture group header, then diagram
block 1: large ink numeral and status line, Leído/Original segmented comparator over a full-width board, the
"Mueven blancas / negras" caption control directly under the board, then Analizar en Lichess. Extended FAB
"Añadir captura" bottom right; export bar pinned at the bottom.

FORM: Magazine-set diagram list (candidate 7 of 7 on the grounded list). seed:31ddeefe4c10e42b

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Signature interaction and motion grammar

Re-inking: choosing an ink in Ajustes re-inks masthead, board and selection states live (200 ms theme lerp).
Comparator: Leído/Original cross-fade (150 ms) and press-and-hold peek. No other decorative motion.

## Unresolved

History between sessions (undecided product fact). Windows drag-and-drop of images.
