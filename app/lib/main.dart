import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'src/session.dart';
import 'src/settings.dart';
import 'src/ui/licenses.dart';
import 'src/ui/home_page.dart';
import 'src/ui/localizations.dart';
import 'src/ui/pieces.dart';
import 'src/ui/scope.dart';
import 'src/ui/theme.dart';
import 'src/ui/tokens.dart';

/// Version shown in Ajustes. Keep equal to `version:` in pubspec.yaml (without the build number); a test
/// checks it.
const String kAppVersion = '0.2.1';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  final settings = await AppSettings.load();
  final catalog = await PieceSetCatalog.load();
  settings.ensurePieceSet(
    catalog.ids,
    fallback: catalog.find(defaultPieceSetId) != null
        ? defaultPieceSetId
        : PieceSetCatalog.fallbackId,
  );
  // The first frame already has the pieces of the chosen set (no pop-in).
  await catalog.ensureLoaded(settings.pieceSetId);
  registerBundledLicenses();
  runApp(
    ChessPgnApp(
      settings: settings,
      session: Session(),
      catalog: catalog,
      appVersion: kAppVersion,
    ),
  );
}

/// The app: provides the settings, the session and the piece catalogue (see [AppScope]) and builds the
/// Material app with the theme of the chosen ink. Everything is optional so a test can start it bare.
class ChessPgnApp extends StatefulWidget {
  const ChessPgnApp({
    super.key,
    this.settings,
    this.session,
    this.catalog,
    this.appVersion = kAppVersion,
    this.home,
  });

  /// Defaults to in-memory settings.
  final AppSettings? settings;

  /// Defaults to a new session with the real reader.
  final Session? session;

  /// Defaults to the built-in typographic set only.
  final PieceSetCatalog? catalog;
  final String appVersion;

  /// The first screen; defaults to [HomePage]. The screenshot harness puts the screen it renders here.
  final Widget? home;

  @override
  State<ChessPgnApp> createState() => _ChessPgnAppState();
}

class _ChessPgnAppState extends State<ChessPgnApp>
    with WidgetsBindingObserver {
  late final AppSettings _settings = widget.settings ?? AppSettings();
  late final Session _session = widget.session ?? Session();
  late final PieceSetCatalog _catalog =
      widget.catalog ?? PieceSetCatalog.builtIn();

  late bool _reduceMotion = _systemReducesMotion();
  String? _themedInk;
  late ThemeData _light, _dark;

  bool _systemReducesMotion() =>
      WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
          .disableAnimations;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAccessibilityFeatures() {
    final now = _systemReducesMotion();
    if (now != _reduceMotion) setState(() => _reduceMotion = now);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.session == null) _session.dispose();
    if (widget.catalog == null) _catalog.dispose();
    super.dispose();
  }

  /// The two themes of the current ink; the same objects until the ink changes, so changing anything else
  /// (style, coordinates, pieces) does not restart the theme animation.
  void _themeFor(String inkId) {
    if (_themedInk == inkId) return;
    final ink = inkById(inkId);
    _light = buildTheme(ink, Brightness.light);
    _dark = buildTheme(ink, Brightness.dark);
    _themedInk = inkId;
  }

  @override
  Widget build(BuildContext context) => AppScope(
    settings: _settings,
    session: _session,
    catalog: _catalog,
    child: ListenableBuilder(
      listenable: _settings,
      builder: (context, _) {
        _themeFor(_settings.inkId);
        return MaterialApp(
          title: 'Chess to PGN',
          debugShowCheckedModeBanner: false,
          theme: _light,
          darkTheme: _dark,
          themeMode: _settings.themeMode,
          // Re-inking is a ~200 ms theme lerp; the system's "remove animations" turns it into a cut.
          themeAnimationDuration: _reduceMotion
              ? Duration.zero
              : Motion.medium,
          themeAnimationCurve: Motion.standard,
          locale: SpanishMaterialLocalizations.locale,
          supportedLocales: const [SpanishMaterialLocalizations.locale],
          localizationsDelegates: SpanishMaterialLocalizations.delegates,
          builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: context.app.systemOverlay,
            child: child!,
          ),
          home: widget.home ?? const HomePage(),
        );
      },
    ),
  );
}
