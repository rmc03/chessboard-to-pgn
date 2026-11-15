// What every screen needs from the app, provided explicitly through one InheritedNotifier (no packages):
// the settings (listen to them), the session and the piece-set catalogue.
//
//   final scope = AppScope.of(context);        // rebuilds when a setting changes
//   scope.settings.inkId, scope.session, scope.catalog
//   AppScope.maybeOf(context)                  // null in a tree without the app (plain widget tests)
import 'package:material_ui/material_ui.dart';

import '../session.dart';
import '../settings.dart';
import 'pieces.dart';

class AppScope extends InheritedNotifier<AppSettings> {
  const AppScope({
    super.key,
    required AppSettings settings,
    required this.session,
    required this.catalog,
    required super.child,
  }) : super(notifier: settings);

  /// The user's preferences. Dependents rebuild when any of them changes.
  AppSettings get settings => notifier!;

  /// The working list of diagrams. It is its own `ChangeNotifier`: listen to it where you show it.
  final Session session;

  /// The piece sets.
  final PieceSetCatalog catalog;

  /// The scope above [context], or null when there is none. Registers a dependency on the settings.
  static AppScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>();

  /// The scope above [context]. Registers a dependency on the settings.
  static AppScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(() {
      if (scope == null) {
        throw FlutterError(
          'AppScope.of() called with a context that has no AppScope above it.\n'
          'Wrap the tree in ChessPgnApp (or an AppScope) or use AppScope.maybeOf.',
        );
      }
      return true;
    }());
    return scope!;
  }

  /// The scope above [context] without depending on it (for callbacks such as `onPressed`).
  static AppScope? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>();

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      oldWidget.session != session ||
      oldWidget.catalog != catalog ||
      oldWidget.notifier != notifier ||
      super.updateShouldNotify(oldWidget);
}
