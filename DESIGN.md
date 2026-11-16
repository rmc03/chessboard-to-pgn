---
name: Chess to PGN
description: Stone chess tables in a Spanish plaza, read by park-bench green enamel plates; limestone by day, basalt by night.
colors:
  park-bench-green: "#1f5c46"
  park-bench-green-night: "#8dd1ad"
  enamel-night: "#266a52"
  shell-night: "#143e30"
  enamel-ink: "#f7f5ee"
  limestone: "#ece8df"
  limestone-raised: "#f4f1e8"
  stone-block: "#e0dbcd"
  stone-block-high: "#d5d0c2"
  stone-block-highest: "#d0cbbd"
  basalt: "#0f1411"
  basalt-block: "#181f1b"
  basalt-block-high: "#232c27"
  ink-green: "#1d2520"
  ink-night: "#e4e8e0"
  ink-soft: "#47524a"
  ink-soft-night: "#a9b3aa"
  rule-green-grey: "#697768"
  rule-green-grey-night: "#6f7e73"
  rule-faint: "#c4bfb0"
  rule-faint-night: "#2c3631"
  selected-mint: "#bbd4c4"
  selected-mint-night: "#2a4c3d"
  street-lamp-text: "#7e4f05"
  street-lamp-text-night: "#f5b44e"
  street-lamp-band: "#f6e2b8"
  street-lamp-mark: "#d98e00"
  street-lamp-lit: "#ffb93d"
  street-lamp-edge: "#241a00"
  brick: "#a3402a"
  brick-night: "#d9694c"
  brick-band: "#f3d3c9"
  granite-frame: "#4a4c48"
  stone-serpentina-light: "#e8e1cd"
  stone-serpentina-dark: "#76927f"
  stone-pizarra-light: "#e9e8e4"
  stone-pizarra-dark: "#7d8590"
  stone-alicante-light: "#eadfcc"
  stone-alicante-dark: "#ab7a6d"
  stone-nogal-light: "#ebd9b8"
  stone-nogal-dark: "#a47d59"
  stone-granito-light: "#e3e1da"
  stone-granito-dark: "#8f918c"
  paper: "#ffffff"
  ink-black: "#000000"
typography:
  masthead:
    fontFamily: "Barlow Condensed, sans-serif"
    fontSize: "28px"
    fontWeight: 700
    lineHeight: 1.1
    letterSpacing: "0.2px"
  numeral:
    fontFamily: "Barlow Condensed, sans-serif"
    fontSize: "30px"
    fontWeight: 700
    lineHeight: 0.95
    letterSpacing: "0px"
    fontFeature: "tnum"
  plate-label:
    fontFamily: "Barlow Condensed, sans-serif"
    fontSize: "16px"
    fontWeight: 700
    lineHeight: 1
    letterSpacing: "1px"
    fontFeature: "tnum"
  plate-caption:
    fontFamily: "Barlow Condensed, sans-serif"
    fontSize: "10px"
    fontWeight: 600
    lineHeight: 1
    letterSpacing: "1.3px"
  headline:
    fontFamily: "Barlow, sans-serif"
    fontSize: "24px"
    fontWeight: 600
    lineHeight: 1.25
  title:
    fontFamily: "Barlow, sans-serif"
    fontSize: "17px"
    fontWeight: 600
    lineHeight: 1.35
    letterSpacing: "0.1px"
  body:
    fontFamily: "Barlow, sans-serif"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.4
    letterSpacing: "0.1px"
  body-small:
    fontFamily: "Barlow, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.4
    letterSpacing: "0.15px"
  label:
    fontFamily: "Barlow, sans-serif"
    fontSize: "15px"
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: "0.1px"
    fontFeature: "tnum"
  data:
    fontFamily: "JetBrains Mono, monospace"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: "0px"
rounded:
  control: "6px"
  container: "10px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
  xxl: "32px"
components:
  masthead:
    backgroundColor: "{colors.park-bench-green}"
    textColor: "{colors.limestone-raised}"
    typography: "{typography.masthead}"
    height: "56px"
  plate:
    backgroundColor: "{colors.park-bench-green}"
    textColor: "{colors.enamel-ink}"
    typography: "{typography.plate-label}"
    rounded: "{rounded.control}"
    padding: "6px 12px"
  plate-numeral:
    backgroundColor: "{colors.park-bench-green}"
    textColor: "{colors.enamel-ink}"
    typography: "{typography.numeral}"
    rounded: "{rounded.control}"
    height: "48px"
    width: "62px"
  plate-night:
    backgroundColor: "{colors.enamel-night}"
    textColor: "{colors.enamel-ink}"
    rounded: "{rounded.control}"
  button-primary:
    backgroundColor: "{colors.park-bench-green}"
    textColor: "{colors.enamel-ink}"
    typography: "{typography.label}"
    rounded: "{rounded.control}"
    height: "48px"
  button-tonal:
    backgroundColor: "{colors.selected-mint}"
    textColor: "{colors.ink-green}"
    typography: "{typography.label}"
    rounded: "{rounded.control}"
    height: "48px"
  button-text:
    textColor: "{colors.park-bench-green}"
    typography: "{typography.label}"
    rounded: "{rounded.control}"
    height: "48px"
  segmented-selected:
    backgroundColor: "{colors.selected-mint}"
    textColor: "{colors.ink-green}"
    typography: "{typography.label}"
    rounded: "{rounded.control}"
    height: "48px"
  chip-selected:
    backgroundColor: "{colors.selected-mint}"
    textColor: "{colors.ink-green}"
    typography: "{typography.label}"
    rounded: "{rounded.control}"
  diagram-block:
    backgroundColor: "{colors.stone-block}"
    textColor: "{colors.ink-green}"
    rounded: "{rounded.container}"
    padding: "16px"
  bottom-sheet:
    backgroundColor: "{colors.stone-block}"
    rounded: "{rounded.container}"
  warning-band:
    backgroundColor: "{colors.street-lamp-band}"
    textColor: "{colors.street-lamp-text}"
    rounded: "{rounded.control}"
  field:
    textColor: "{colors.ink-green}"
    rounded: "{rounded.control}"
    height: "48px"
  fen-line:
    textColor: "{colors.ink-soft}"
    typography: "{typography.data}"
---

# Design System: Chess to PGN

## Overview

**Creative North Star: "The Plaza Stone Table"**

Each chess diagram in the session is a stone table in a Spanish or Latin-American plaza: a board of speckled stone set in a polished granite frame, lying on limestone ground under a park-bench green shell. Identification is by enamel street-name plates (the diagram number, the capture header, the one primary action), never by decoration. By night the same plaza goes to basalt and the amber of a street lamp is the only warm light. The app is an Operate tool: the reader compares, fixes one doubtful square and sends the position away; the world supplies materials and a signature, not scenery.

The board is the constant of the system. It is the same stone in light and dark, the same frame, the same pieces; only the amber of doubt glows in the night theme. Everything around it is standard Material 3 (adaptive; Android first, Windows too) re-dressed in the plate language: 6 dp corners, 1 dp outlines, no capsules, no shadows. Depth is tonal and by rule, never by blur.

The system refuses the chess-site arrangement of a grey shell around a flat green board, and stock Material shapes (stadium buttons, 20 dp outlines). Spanish UI copy; plates are written in capitals.

**Key Characteristics:**
- Limestone ground, park-bench green shell, basalt at night; stone boards in a granite frame.
- Four things are enamel plates and nothing else: the diagram number, the capture header, the FAB and the one primary button of a screen.
- Amber means "look again" (doubtful) and only that; brick means error and only that.
- Flat and tonal: no shadows anywhere; 1 dp rules and tonal containers carry separation.
- Barlow for UI, Barlow Condensed for plates, numerals and the masthead, JetBrains Mono only for FEN and PGN.

## Colors

A muted civic palette: one green doing three jobs (shell, enamel, primary), warm limestone neutrals tinted toward that green, and two signal colors held in reserve. Token values live in the frontmatter; the night variants carry a `-night` suffix.

### Primary
- **Park-Bench Green** (`park-bench-green`): the shell (app bar), the enamel of plates, the FAB and the primary button, and the Material `primary` in light. In night it lifts to **Night Mint** (`park-bench-green-night`) for text and icons; the plate enamel becomes **Night Enamel** (`enamel-night`) so it reads on basalt, and the shell deepens to **Night Shell** (`shell-night`). Text and inner rules on enamel are **Enamel Ink** (`enamel-ink`).

### Secondary
- **Selected Mint** (`selected-mint`, night `selected-mint-night`): the one fill for a selected segment, selected chip and tonal button. Selection is fill plus stronger weight plus the check, never fill alone.

### Tertiary (signals)
- **Street-Lamp Amber** (`street-lamp-mark`, lit `street-lamp-lit` at night, edge `street-lamp-edge`): the doubtful mark on the board (2 dp ring and corner triangle with a thin dark edge so it reads on light and mid-tone squares). It is a mark, never a text color. Text and icons about doubt use **Lamp Text** (`street-lamp-text`, night `street-lamp-text-night`); bands use **Lamp Band** (`street-lamp-band`).
- **Brick** (`brick`, night `brick-night`, band `brick-band`): errors only.

### Neutral
- **Limestone** (`limestone`) is the page; **Limestone Raised** (`limestone-raised`) the lightest surface; **Stone Block** (`stone-block`, `stone-block-high`, `stone-block-highest`) the containers (diagram blocks, sheets, dialogs, menus) in rising tone. Night: **Basalt** (`basalt`) page, `basalt-block` and `basalt-block-high` containers.
- **Ink Green** (`ink-green`, night `ink-night`) text; **Soft Ink** (`ink-soft`, night `ink-soft-night`) secondary text.
- **Rule Green-Grey** (`rule-green-grey`, night `rule-green-grey-night`) the 1 dp outline of controls; **Rule Faint** (`rule-faint`, night `rule-faint-night`) dividers and menu edges.

### The Board (fixed, theme-independent)
- **Stones** (setting "Piedra", five): Serpentina (default, `stone-serpentina-*`), Pizarra, Rojo Alicante, Nogal, Granito. Each is a light and a dark square; the dark square is a mid tone (L* 55-65) so a white piece body keeps 3:1. Only the board changes with the stone; the shell is always park-bench green.
- **Granite Frame** (`granite-frame`): polished 135 degree gradient, fine white and black grains, light bevel top-left, shade bottom-right, 3-6 dp wide. **Paper** and **Ink Black** are the printed style (hatched pieces on white).
- The selection ring is derived from park-bench green, darkened until it holds 3.2:1 on both squares of the stone.

### Named Rules
**The Reserved Signal Rule.** Amber is only "doubtful"; brick is only "error". Neither is ever decoration, a button fill or a brand accent.
**The Constant Board Rule.** The board and its pieces do not change with theme brightness. Do not tint, dim or invert them; adjust the shell around them.
**The Stone Speckle Rule.** Texture on stone is 16-34 % chips and is almost invisible on purpose: legible first, texture after.

## Typography

**UI Font:** Barlow (400, 500, 600, 700)
**Plate Font:** Barlow Condensed (600, 700)
**Data Font:** JetBrains Mono (400, 500), FEN and PGN only

**Character:** Barlow is a civic, signage-adjacent grotesque; its condensed cut is the street-name plate. Barlow sets small for its size, so the body starts at 15 sp.

### Hierarchy
- **Masthead** (Condensed 700, 28/1.1, +0.2): the app bar title and screen titles in the shell.
- **Numeral** (Condensed 700, 30/0.95, tabular): the big diagram number on a plate.
- **Plate label** (Condensed 700, 16, +1.0, capitals): "CAPTURA 1". **Plate caption** (Condensed 600, 10, +1.3, capitals): "DIAGRAMA" over the numeral.
- **Headline** (Barlow 600, 24/1.25): dialog titles. Scale is about 1.2 (12, 13, 15, 17, 21, 24, 29, 35, 42, 50, 60) mapped to the Material roles.
- **Title** (600, 17/1.35, 15/1.35): section and list titles.
- **Body** (400, 15/1.4; large 17; small 13): sentences and hints; keep lines to about 65 characters.
- **Label** (600, 15/1.3, tabular figures; medium 500/13, small 500/12): button, chip and segment text in sentence case. A selected segment goes to 700.
- **Data** (Mono 400, 13/1.5): the FEN line and PGN text.

### Named Rules
**The Plate Voice Rule.** Barlow Condensed is for plates, numerals and the masthead only. Running UI text is Barlow.
**The Mono Is Data Rule.** JetBrains Mono appears only where the text is a position or a game record.
**The Tabular Rule.** Numerals and counters use tabular figures.

## Layout

A single scrolling column of diagram blocks on a 4 dp grid (4, 8, 12, 16, 24, 32). Side gutter is 16 dp, 24 dp from 600 dp wide. Blocks are padded 16 dp, with 8-12 dp between their rows and a 16 dp gap between blocks. The board fills the block width. Width classes: 600 (medium), 840 (expanded), 1240 (wide): the list becomes a grid of tables rather than stretching a single table. Sheets cap at 640 dp. The export bar sits at the bottom with the FAB as its last item; the list reserves space under it. Minimum touch target is 48 dp. Text scaling is respected; plates cap it at 1.3 so a plate never outgrows its row.

## Elevation & Depth

Flat and tonal. There are no shadows: elevation is 0 on app bar, FAB, buttons, sheets, dialogs, menus, snackbar. Layering is done by container tone (limestone, then stone block, then raised) and by 1 dp rules (`outline` on controls, `outlineVariant` on menus). The only gradients are material ones: the granite frame of the board and the faint gloss on the upper half of an enamel plate (10 % off-white, hard stop at 45 %). The only glow is the lamp halo on the doubtful mark in the night theme.

### Named Rules
**The No Shadow Rule.** Separation comes from tone and rule, never from a blurred shadow.
**The Lamp Only Rule.** A glow exists solely as the lit lamp of a doubtful square at night.

## Shapes

Small, firm rounded rectangles: 6 dp for controls (buttons, segments, chips, fields, snackbar, tooltip, menus, plates, FAB) and 10 dp for containers (diagram blocks, cards, dialogs, top corners of sheets). Never a capsule, never a stadium. Outlines are 1 dp; keyboard focus is a 2 dp ring in the text color. The signature silhouette is the enamel plate: a 6 dp rounded rectangle with an inner off-white rule 3 dp from the edge, 1.5 dp thick, its radius reduced by the inset. The board carries a hairline inside the granite frame and a folded-corner triangle for doubt. Icons are Hugeicons stroke-rounded at one stroke width (1.8), one meaning per icon.

## Components

### Plates
- **Character:** the street-name plate; the only enamel.
- **Numeral plate:** at least 62 x 48 dp, "DIAGRAMA" caption over a Condensed numeral. **Label plate:** at least 30 dp high, capitals.
- **Muted plate:** for something that is not yours (the example on the empty screen): stone fill, 1 dp outline, no enamel and no inner rule.
- **Used only for:** diagram number, capture header, FAB, the one primary button.

### Buttons
- **Shape:** 6 dp, minimum 64 x 48 dp, label 15 sp 600 in sentence case.
- **Primary (plate):** one per screen (for example "Leer este tablero"); enamel fill, Enamel Ink text, inner rule. Disabled it falls back to a plain tonal button, since a dead plate would still look pressable.
- **Tonal:** Selected Mint fill (export "Guardar", "Analizar en Lichess"). **Text:** primary-color label, no fill ("Restablecer"). **Icon:** 48 dp targets, 6 dp shape.
- **FAB:** a plate ("Añadir captura"), extended, no shadow.
- **Focus:** 2 dp ring in the text color over the state layer; hover 8 %, focus 16 %.

### Segmented control and chips
- Selected = Selected Mint fill, 700 weight and a check (Leído | Original, Mueven blancas | negras); unselected = transparent with a 1 dp outline. Chips follow the same rule with the check kept.

### Diagram block
- Stone Block container, 10 dp corners, 16 dp padding: plate numeral and status line (amber when doubtful), the comparator, the framed board with coordinates, side to move, actions, and the FEN line in mono. A doubtful block surfaces its count and "Revisar dudosas" in the header.

### Board
- Painted in one pass (frame, squares, speckle, coordinates, pieces, marks). Tap a square to edit. Press and hold shows the original crop; Leído and Original cross-fade in 150 ms.

### Inputs, sheets, menus
- Fields: 6 dp outline in `outline`, 2 dp primary on focus, brick on error. Bottom sheet: Stone Block, 10 dp top corners, 32 x 4 drag handle. Dialogs 10 dp. Menus 6 dp with a 1 dp rule.

### Navigation and shell
- Green masthead app bar (Condensed title, left aligned, actions at the right), the capture header row, and the bottom export bar (count, warnings, Save, Share, Copy, then the FAB). Crop screen: the picture sits on basalt in both themes (like paper on a stone slab) with a limestone control panel below.

## Do's and Don'ts

### Do:
- **Do** let the board stay the same stone in light and dark; change the stone only through "Piedra", and re-lay it live in 200 ms.
- **Do** keep enamel to four things: diagram number, capture header, FAB, the one primary button.
- **Do** use 6 dp for controls, 10 dp for containers, 1 dp outlines, 48 dp targets.
- **Do** read all color from the theme (`ColorScheme`, `AppTheme`); the only files with colour literals are tokens and theme.
- **Do** mark doubt with amber ring plus corner triangle plus words ("dudosa"), so it never relies on color.
- **Do** keep motion to state changes of 150-250 ms and drop it when the system asks to remove animations.

### Don't:
- **Don't** put a grey shell around a flat green board, or use stadium buttons or 20 dp outlines.
- **Don't** use shadows, blur or glow for elevation.
- **Don't** give a card, row or chip the inner rule of a plate: if everything is a plate, nothing is.
- **Don't** use amber for anything but doubt, or brick for anything but error.
- **Don't** set UI text in Condensed or in JetBrains Mono.
- **Don't** use Material `Icons.*` or glyph icons; use `AppIcon(AppIcons.*)`.
- **Don't** add decorative motion beyond the stone re-lay and the Leído/Original cross-fade.
