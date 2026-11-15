import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'chess.dart';
import 'diagram.dart';
import 'ui/board.dart';
import 'ui/pieces.dart';
import 'ui/theme.dart';
import 'ui/tokens.dart';

class DiagramCard extends StatefulWidget {
  const DiagramCard({
    super.key,
    required this.number,
    required this.diagram,
    this.onChanged,
    this.onAdjust,
    this.onSharePgn,
  });

  final int number;
  final Diagram diagram;
  final VoidCallback? onChanged;

  /// "Ajustar recorte": re-read this diagram from a hand-drawn region. Hidden when null.
  final VoidCallback? onAdjust;

  /// "Compartir PGN" for this diagram only. Hidden when null.
  final VoidCallback? onSharePgn;

  @override
  State<DiagramCard> createState() => _DiagramCardState();
}

class _DiagramCardState extends State<DiagramCard> {
  Diagram get d => widget.diagram;

  Future<void> _edit(int sq) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Casilla ${squareName(sq)}'),
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var cls = 0; cls < classSymbols.length; cls++)
                OutlinedButton(
                  key: ValueKey('pick-$cls'),
                  onPressed: () => Navigator.pop(context, cls),
                  child: cls == 0
                      ? const Text('vacía')
                      : PieceView(cls, size: 30),
                ),
            ],
          ),
        ],
      ),
    );
    if (picked == null) return;
    setState(() => d.setSquare(sq, picked));
    widget.onChanged?.call();
  }

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text('$what copiado')));
  }

  @override
  Widget build(BuildContext context) {
    final problems = d.problems;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Diagrama ${widget.number}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: d.doubtfulCount > 0
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 20,
                              color: context.app.warning,
                            ),
                            const SizedBox(width: Space.xs),
                            Flexible(
                              child: Text(
                                '${d.doubtfulCount} casilla(s) dudosa(s) en ámbar',
                                textAlign: TextAlign.right,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: context.app.warning),
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
                PopupMenuButton<String>(
                  key: const ValueKey('card-menu'),
                  tooltip: 'Más acciones',
                  onSelected: (v) {
                    switch (v) {
                      case 'fen':
                        _copy(d.fen, 'FEN');
                      case 'pgn':
                        _copy(d.pgn(widget.number), 'PGN');
                      case 'share':
                        widget.onSharePgn?.call();
                      case 'adjust':
                        widget.onAdjust?.call();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'fen',
                      child: Text('Copiar FEN'),
                    ),
                    const PopupMenuItem(
                      value: 'pgn',
                      child: Text('Copiar PGN'),
                    ),
                    if (widget.onSharePgn != null)
                      const PopupMenuItem(
                        value: 'share',
                        child: Text('Compartir PGN'),
                      ),
                    if (widget.onAdjust != null)
                      const PopupMenuItem(
                        value: 'adjust',
                        child: Text('Ajustar recorte'),
                      ),
                  ],
                ),
              ],
            ),
            if (d.fallback && !d.manual)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'No se encontró un marco: se usó toda la imagen como un único tablero.',
                ),
              ),
            const SizedBox(height: 8),
            BoardView(diagram: d, onTap: _edit),
            const SizedBox(height: 8),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                const Text('Mueven:'),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'w', label: Text('Blancas')),
                    ButtonSegment(value: 'b', label: Text('Negras')),
                  ],
                  selected: {d.turn},
                  onSelectionChanged: (s) {
                    setState(() => d.turn = s.first);
                    widget.onChanged?.call();
                  },
                ),
              ],
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Enroques posibles (según rey y torres)'),
              value: d.castlingPossible,
              onChanged: (v) {
                setState(() => d.castlingPossible = v ?? true);
                widget.onChanged?.call();
              },
            ),
            SelectableText(d.fen, style: context.app.mono),
            for (final p in problems)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 20,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(
                        p,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  ],
                ),
              ),
            if (widget.onAdjust != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.crop),
                  label: const Text('Ajustar recorte'),
                  onPressed: widget.onAdjust,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
