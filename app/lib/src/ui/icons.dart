// The icons of the app: Hugeicons (stroke rounded, MIT), one stroke width everywhere. docs/icons.md is the
// dictionary: one meaning = one icon in the whole app. Screens write `AppIcon(AppIcons.crop)`, never `Icons.*`
// and never `HugeIcon` directly, so the stroke, the size and the colour come from one place.
import 'package:hugeicons/hugeicons.dart';
import 'package:material_ui/material_ui.dart';

/// The data of one Hugeicons icon (a list of SVG elements).
typedef AppIconData = List<List<dynamic>>;

/// The single stroke width of every icon (24 dp grid).
const double appIconStroke = 1.8;

/// An icon of the app. Colour and size come from the ambient [IconTheme] (buttons, list tiles and the app bar set
/// them), or from [color] and [size] when given.
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });

  final AppIconData icon;

  /// Defaults to the size of the [IconTheme] (24 dp when there is none).
  final double? size;

  /// Defaults to the colour of the [IconTheme].
  final Color? color;

  /// Announced by screen readers; icons are decorative (hidden) without it.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final icon = HugeIcon(
      icon: this.icon,
      size: size ?? theme.size ?? 24,
      color: color,
      strokeWidth: appIconStroke,
    );
    return semanticLabel == null
        ? ExcludeSemantics(child: icon)
        : Semantics(
            label: semanticLabel,
            image: true,
            excludeSemantics: true,
            child: icon,
          );
  }
}

/// Every meaning of docs/icons.md. Add a row there first when a new action needs an icon.
abstract final class AppIcons {
  static const AppIconData settings = HugeIcons.strokeRoundedSettings02;
  static const AppIconData addCapture = HugeIcons.strokeRoundedImageAdd02;
  static const AppIconData crop = HugeIcons.strokeRoundedCrop;
  static const AppIconData delete = HugeIcons.strokeRoundedDelete02;
  static const AppIconData deleteAll = HugeIcons.strokeRoundedDelete04;
  static const AppIconData share = HugeIcons.strokeRoundedShare08;
  static const AppIconData copy = HugeIcons.strokeRoundedCopy01;
  static const AppIconData save = HugeIcons.strokeRoundedDownload04;
  static const AppIconData openExternal = HugeIcons.strokeRoundedLinkSquare02;
  static const AppIconData flip = HugeIcons.strokeRoundedArrowUpDown;
  static const AppIconData warning = HugeIcons.strokeRoundedAlert02;
  static const AppIconData error = HugeIcons.strokeRoundedAlertCircle;
  static const AppIconData lock = HugeIcons.strokeRoundedSquareLock02;
  static const AppIconData go = HugeIcons.strokeRoundedArrowRight01;
  static const AppIconData close = HugeIcons.strokeRoundedCancel01;
  static const AppIconData retry = HugeIcons.strokeRoundedRefresh;
  static const AppIconData undo = HugeIcons.strokeRoundedUndo02;
  static const AppIconData zoomIn = HugeIcons.strokeRoundedZoomInArea;
  static const AppIconData zoomOut = HugeIcons.strokeRoundedZoomOutArea;
  static const AppIconData fitAll = HugeIcons.strokeRoundedFullScreen;
  static const AppIconData check = HugeIcons.strokeRoundedTick02;
  static const AppIconData info = HugeIcons.strokeRoundedInformationCircle;
  static const AppIconData privacy = HugeIcons.strokeRoundedSquareLock02;
  static const AppIconData licenses = HugeIcons.strokeRoundedLicense;
  static const AppIconData noBoard = HugeIcons.strokeRoundedSearch01;

  /// Overflow menu (⋮). Not in the dictionary table: the three-dots menu is the one Material convention kept.
  static const AppIconData more = HugeIcons.strokeRoundedMoreVertical;

  /// Back arrow of a pushed screen.
  static const AppIconData back = HugeIcons.strokeRoundedArrowLeft01;
}
