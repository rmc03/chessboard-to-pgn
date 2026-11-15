# Piece set licences

The SVG files in this directory are third-party artwork taken unmodified from the
Lichess repository (`https://github.com/lichess-org/lila`, `public/piece/<id>/`).
Authors and licences are as stated in lila's `COPYING.md` ("Exceptions (free)").
Only sets with licences allowing free redistribution including commercial use are
bundled. `tool/fetch_pieces.py` re-downloads them (celtic: the CSS `<style>` block
is inlined into attributes so flutter_svg renders it; the drawing is unchanged).

| Set | Author | Licence line in COPYING.md |
|---|---|---|
| merida | Armando Hernandez Marroquin | `public/piece/merida \| Armando Hernandez Marroquin \| GPLv2+` |
| cburnett | Colin M.L. Burnett | `public/piece/cburnett \| Colin M.L. Burnett \| GPLv2+` |
| chessnut | Alexis Luengas (https://github.com/LexLuengas/chessnut-pieces) | `public/piece/chessnut \| Alexis Luengas \| Apache 2.0` |
| mpchess | Maxime Chupin (https://github.com/chupinmaxime) | `public/piece/mpchess \| Maxime Chupin \| GPL3v3+` (sic; GPLv3+) |
| celtic | Maurizio Monge (https://github.com/maurimo/chess-art) | `public/piece/celtic \| Maurizio Monge \| MIT` |

## Notice

The **merida, cburnett and mpchess** SVG files are GPL-licensed artwork
(GPLv2+, GPLv2+ and GPLv3+) bundled with the app. They remain under those
licences; chessnut is Apache-2.0 and celtic is MIT. Attribution to the authors
above is given here and in the app's sets.json (`author`, `license`).

## Full licence texts

- GPLv2: https://www.gnu.org/licenses/gpl-2.0.txt
- GPLv3: https://www.gnu.org/licenses/gpl-3.0.txt
- Apache 2.0: https://github.com/LexLuengas/chessnut-pieces/blob/master/LICENSE.txt
- MIT (celtic): https://github.com/maurimo/chess-art/blob/main/LICENSE
