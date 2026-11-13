import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'board_view.dart';
import 'chess.dart';
import 'diagram.dart';

class DiagramCard extends StatefulWidget {
  const DiagramCard({
    super.key,
    required this.number,
    required this.diagram,
    this.onChanged,
  });

  final int number;
  final Diagram diagram;
  final VoidCallback? onChanged;

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
                  child: Text(
                    cls == 0 ? 'vacía' : glyph(cls),
                    style: TextStyle(fontSize: cls == 0 ? 14 : 28),
                  ),
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
                      ? Text(
                          '${d.doubtfulCount} casilla(s) dudosa(s) en ámbar',
                          textAlign: TextAlign.right,
                          style: const TextStyle(color: Color(0xFFE65100)),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
            if (d.fallback)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'No se encontró un marco: se usó toda la imagen como un único tablero.',
                ),
              ),
            const SizedBox(height: 8),
            BoardView(grid: d.grid, doubtful: d.isDoubtful, onTap: _edit),
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
            SelectableText(
              d.fen,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            for (final p in problems)
              Text('⚠ $p', style: const TextStyle(color: Color(0xFFC62828))),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Copiar FEN'),
                onPressed: () => Clipboard.setData(ClipboardData(text: d.fen)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
