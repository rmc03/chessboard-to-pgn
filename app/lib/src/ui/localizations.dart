// Spanish strings for the Material widgets the app uses (tooltips, the licences page, the text selection
// toolbar, dialog and sheet labels). The app is Spanish only and does not depend on flutter_localizations, so
// this class overrides the English defaults of [DefaultMaterialLocalizations] one by one. Dates and times are
// not used anywhere in the app and keep their defaults.
import 'package:flutter/foundation.dart';
// The Cupertino delegate is needed only so Flutter does not report the `es` locale as unsupported (material_ui
// depends on cupertino_ui, so it is always present; the app never shows Cupertino widgets).
// ignore: depend_on_referenced_packages
import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoLocalizations, DefaultCupertinoLocalizations;
import 'package:material_ui/material_ui.dart';

class SpanishMaterialLocalizations extends DefaultMaterialLocalizations {
  const SpanishMaterialLocalizations();

  static const LocalizationsDelegate<MaterialLocalizations> delegate =
      _SpanishDelegate();

  static const Locale locale = Locale('es');

  /// Every delegate the app needs for [locale].
  static const List<LocalizationsDelegate<dynamic>> delegates = [
    delegate,
    _SpanishCupertinoDelegate(),
  ];

  @override
  String get openAppDrawerTooltip => 'Abrir el menú de navegación';
  @override
  String get backButtonTooltip => 'Atrás';
  @override
  String get clearButtonTooltip => 'Borrar el texto';
  @override
  String get closeButtonTooltip => 'Cerrar';
  @override
  String get deleteButtonTooltip => 'Quitar';
  @override
  String get moreButtonTooltip => 'Más acciones';
  @override
  String get showMenuTooltip => 'Mostrar el menú';
  @override
  String get drawerLabel => 'Menú de navegación';
  @override
  String get popupMenuLabel => 'Menú emergente';
  @override
  String get dialogLabel => 'Diálogo';
  @override
  String get alertDialogLabel => 'Aviso';
  @override
  String get searchFieldLabel => 'Buscar';
  @override
  String get scrimLabel => 'Fondo atenuado';
  @override
  String get bottomSheetLabel => 'Hoja inferior';
  @override
  String scrimOnTapHint(String modalRouteContentName) =>
      'Cerrar $modalRouteContentName';
  @override
  String aboutListTileTitle(String applicationName) =>
      'Acerca de $applicationName';
  @override
  String get licensesPageTitle => 'Licencias';
  @override
  String licensesPackageDetailText(int licenseCount) => switch (licenseCount) {
    0 => 'Sin licencias',
    1 => '1 licencia',
    _ => '$licenseCount licencias',
  };
  @override
  String get cancelButtonLabel => 'Cancelar';
  @override
  String get closeButtonLabel => 'Cerrar';
  @override
  String get continueButtonLabel => 'Continuar';
  @override
  String get copyButtonLabel => 'Copiar';
  @override
  String get cutButtonLabel => 'Cortar';
  @override
  String get okButtonLabel => 'Aceptar';
  @override
  String get pasteButtonLabel => 'Pegar';
  @override
  String get selectAllButtonLabel => 'Seleccionar todo';
  @override
  String get lookUpButtonLabel => 'Buscar';
  @override
  String get searchWebButtonLabel => 'Buscar en la web';
  @override
  String get shareButtonLabel => 'Compartir';
  @override
  String get saveButtonLabel => 'Guardar';
  @override
  String get viewLicensesButtonLabel => 'Ver licencias';
  @override
  String get modalBarrierDismissLabel => 'Descartar';
  @override
  String get menuDismissLabel => 'Cerrar el menú';
  @override
  String get expandedIconTapHint => 'Contraer';
  @override
  String get collapsedIconTapHint => 'Expandir';
  @override
  String get expansionTileExpandedHint => 'toca dos veces para contraer';
  @override
  String get expansionTileCollapsedHint => 'toca dos veces para expandir';
  @override
  String get expansionTileExpandedTapHint => 'Contraer';
  @override
  String get expansionTileCollapsedTapHint => 'Expandir para ver más';
  @override
  String get refreshIndicatorSemanticLabel => 'Actualizar';
}

class _SpanishDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const _SpanishDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'es';

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      SynchronousFuture<MaterialLocalizations>(
        const SpanishMaterialLocalizations(),
      );

  @override
  bool shouldReload(_SpanishDelegate old) => false;
}

/// Cupertino widgets are not used (Android and Windows); this only declares the locale as supported.
class _SpanishCupertinoDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _SpanishCupertinoDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'es';

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      DefaultCupertinoLocalizations.load(const Locale('en'));

  @override
  bool shouldReload(_SpanishCupertinoDelegate old) => false;
}
