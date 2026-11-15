// The export bar pinned at the bottom of the session: how many diagrams, "Guardar .pgn", "Compartir" (Android
// only) and "Copiar PGN" in the overflow menu. On wide windows the extended FAB lives inside it, docked at the
// end ([trailing]), so the one primary action and the exports read as one bar.
import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'home_actions.dart';
import 'tokens.dart';

class ExportBar extends StatelessWidget {
  const ExportBar({
    super.key,
    required this.count,
    required this.actions,
    this.trailing,
    this.horizontalPadding,
  });

  /// Diagrams in the session.
  final int count;
  final HomeActions actions;

  /// The docked FAB on wide windows.
  final Widget? trailing;

  /// Side padding; the screen's gutter by default (wide windows align it with the content column).
  final double? horizontalPadding;

  static String countText(int n) => n == 1 ? '1 diagrama' : '$n diagramas';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final gutter = horizontalPadding ?? Space.gutter(width);
    // Wide enough to name the share action instead of showing its icon only.
    final labelled = width >= 560;

    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.tonalIcon(
          key: const ValueKey('save-pgn'),
          onPressed: () => unawaited(actions.saveAll(context)),
          icon: const Icon(Icons.save_alt),
          label: const Text('Guardar .pgn'),
        ),
        if (actions.canShare) ...[
          const SizedBox(width: Space.sm),
          if (labelled)
            TextButton.icon(
              key: const ValueKey('share-all'),
              onPressed: () => unawaited(actions.share(context, actions.session.allPgn)),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Compartir'),
            )
          else
            IconButton(
              key: const ValueKey('share-all'),
              tooltip: 'Compartir',
              onPressed: () => unawaited(actions.share(context, actions.session.allPgn)),
              icon: const Icon(Icons.share_outlined),
            ),
        ],
        PopupMenuButton<String>(
          tooltip: 'Más opciones',
          icon: const Icon(Icons.more_vert),
          onSelected: (_) => unawaited(
            actions.copy(
              context,
              actions.session.allPgn,
              'PGN de ${countText(count)} copiado',
            ),
          ),
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'copy',
              child: Row(
                children: [
                  Icon(Icons.content_copy, size: 20),
                  SizedBox(width: Space.md),
                  Text('Copiar PGN'),
                ],
              ),
            ),
          ],
        ),
      ],
    );

    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(gutter, Space.sm, gutter, Space.sm),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: Space.xs,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: Space.md),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          countText(count),
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    ),
                    buttons,
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: Space.lg),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
