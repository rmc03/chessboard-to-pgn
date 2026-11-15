// The export bar pinned at the bottom of the session, ONE row: how many diagrams (and how many of them have
// warnings), "Guardar .pgn", "Compartir" (Android only) and "Copiar PGN". Where the labels do not fit (a phone at
// large text) the buttons turn into icon buttons with tooltips instead of wrapping. On wide windows the extended
// FAB lives inside it, docked at the end ([trailing]), so the one primary action and the exports read as one bar.
import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../diagram.dart';
import '../export.dart' as exporter;
import 'home_actions.dart';
import 'icons.dart';
import 'theme.dart';
import 'tokens.dart';

class ExportBar extends StatelessWidget {
  const ExportBar({
    super.key,
    required this.actions,
    this.trailing,
    this.horizontalPadding,
    this.onWarnings,
  });

  final HomeActions actions;

  /// The docked FAB on wide windows.
  final Widget? trailing;

  /// Side padding; the screen's gutter by default (wide windows align it with the content column).
  final double? horizontalPadding;

  /// The user tapped the count of diagrams with warnings: the screen goes to the first one.
  final void Function(Diagram firstFlagged)? onWarnings;

  static String countText(int n) => exporter.diagramsText(n);

  static double _width(String text, TextStyle? style, TextScaler scaler) =>
      (TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout()).width;

  @override
  Widget build(BuildContext context) {
    final session = actions.session;
    // The bar follows the session and every diagram in it: confirming a doubtful square changes the warnings.
    return ListenableBuilder(
      listenable: Listenable.merge([session, actions, ...session.diagrams]),
      builder: (context, _) => _bar(context),
    );
  }

  Widget _bar(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final session = actions.session;
    final width = MediaQuery.sizeOf(context).width;
    final scaler = MediaQuery.textScalerOf(context);
    final gutter = horizontalPadding ?? Space.gutter(width);
    final count = session.diagramCount;
    final flagged = session.flagged;
    final countText = ExportBar.countText(count);
    final warnText = flagged.isEmpty
        ? null
        : exporter.warningsText(flagged.length);
    final inline = width >= Breakpoint.medium;
    final canShare = actions.canShare;

    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(gutter, Space.sm, gutter, Space.sm),
          child: LayoutBuilder(
            builder: (context, c) {
              // Do the labels fit? Measured with the real text scale, so the answer is right at any font size.
              final saveLabel = _width(
                'Guardar .pgn',
                theme.textTheme.labelLarge,
                scaler,
              );
              final countW = _width(
                countText,
                theme.textTheme.titleSmall,
                scaler,
              );
              final warnW = warnText == null
                  ? 0.0
                  : 24 + _width(warnText, theme.textTheme.labelMedium, scaler);
              final left = inline
                  ? countW + warnW + Space.lg
                  : math.max(countW, warnW);
              final saveFull = saveLabel + 72;
              final need =
                  left +
                  Space.md +
                  saveFull +
                  (canShare ? minTarget : 0) +
                  minTarget;
              final labelled = trailing != null || c.maxWidth >= need;
              final shareLabelled = labelled && width >= 560;

              final summary = _summary(
                context,
                countText: countText,
                warnText: warnText,
                inline: inline,
                first: flagged.isEmpty ? null : flagged.first,
              );

              return Row(
                children: [
                  Expanded(child: summary),
                  if (labelled)
                    FilledButton.tonalIcon(
                      key: const ValueKey('save-pgn'),
                      onPressed: () => unawaited(actions.saveAll(context)),
                      icon: const AppIcon(AppIcons.save),
                      label: const Text('Guardar .pgn'),
                    )
                  else
                    IconButton.filledTonal(
                      key: const ValueKey('save-pgn'),
                      tooltip: 'Guardar .pgn',
                      onPressed: () => unawaited(actions.saveAll(context)),
                      icon: const AppIcon(AppIcons.save),
                    ),
                  if (canShare) ...[
                    const SizedBox(width: Space.xs),
                    if (shareLabelled)
                      TextButton.icon(
                        key: const ValueKey('share-all'),
                        onPressed: _share(context, count),
                        icon: const AppIcon(AppIcons.share),
                        label: const Text('Compartir'),
                      )
                    else
                      IconButton(
                        key: const ValueKey('share-all'),
                        tooltip: 'Compartir o copiar PGN',
                        onPressed: _share(context, count),
                        icon: const AppIcon(AppIcons.share),
                      ),
                  ],
                  IconButton(
                    key: const ValueKey('copy-all'),
                    tooltip: 'Copiar PGN',
                    onPressed: () => unawaited(
                      actions.copy(
                        context,
                        actions.session.allPgn,
                        'PGN de ${ExportBar.countText(count)} copiado',
                      ),
                    ),
                    icon: const AppIcon(AppIcons.copy),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: Space.lg),
                    trailing!,
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  VoidCallback _share(BuildContext context, int count) =>
      () => unawaited(
        actions.sharePgn(
          context,
          actions.session.allPgn,
          copied: 'PGN de ${ExportBar.countText(count)} copiado',
        ),
      );

  /// "3 diagramas" and, when some have doubts or problems, "3 con avisos" with the warning icon: below 600 dp
  /// under the count, from 600 dp after it ("3 diagramas · 2 con avisos"). Tapping it goes to the first one.
  Widget _summary(
    BuildContext context, {
    required String countText,
    required String? warnText,
    required bool inline,
    required Diagram? first,
  }) {
    final theme = Theme.of(context);
    final app = context.app;
    final countLine = Semantics(
      liveRegion: true,
      child: Text(countText, style: theme.textTheme.titleSmall),
    );
    if (warnText == null || first == null) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minTarget),
        child: Row(children: [countLine]),
      );
    }
    final warning = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(AppIcons.warning, size: 18, color: app.warning),
        const SizedBox(width: Space.xs),
        Flexible(
          child: Text(
            warnText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(color: app.warning),
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      label: '$countText, $warnText. Ir al primero',
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('export-warnings'),
        onTap: onWarnings == null ? null : () => onWarnings!(first),
        borderRadius: BorderRadius.circular(Corner.control),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minTarget),
          child: Row(
            children: [
              Flexible(
                child: inline
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          countLine,
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.sm,
                            ),
                            child: Text(
                              '·',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Flexible(child: warning),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [countLine, warning],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
