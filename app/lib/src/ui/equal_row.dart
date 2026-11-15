// A row of [columns] equally wide cells whose children all get the height of the tallest one.
//
// The diagram blocks of a row differ in height (a castling row, a forced-turn line, a long status), and a row of
// uneven surfaces looks ragged. `IntrinsicHeight` would fix it but cannot measure a `LayoutBuilder` (the board
// lives in one), so this render object lays the children out twice: loosely to find the tallest, then tightly.
// A row with fewer children than [columns] (the last one) keeps the cell width of a full row.
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class EqualHeightRow extends MultiChildRenderObjectWidget {
  const EqualHeightRow({
    super.key,
    required this.columns,
    required this.gap,
    required super.children,
  });

  final int columns;
  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderEqualHeightRow(columns, gap);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _RenderEqualHeightRow)
      ..columns = columns
      ..gap = gap;
  }
}

class _RowParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderEqualHeightRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _RowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _RowParentData> {
  _RenderEqualHeightRow(this._columns, this._gap);

  int _columns;
  double _gap;

  set columns(int value) {
    if (value == _columns) return;
    _columns = value;
    markNeedsLayout();
  }

  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _RowParentData) child.parentData = _RowParentData();
  }

  double _cellWidth(double maxWidth) =>
      (maxWidth - _gap * (_columns - 1)) / _columns;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    assert(
      debugCannotComputeDryLayout(
        reason: 'The children (a LayoutBuilder among them) are measured by laying them out.',
      ),
    );
    return Size.zero;
  }

  @override
  void performLayout() {
    final cell = _cellWidth(constraints.maxWidth);
    var tallest = 0.0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      c.layout(BoxConstraints.tightFor(width: cell), parentUsesSize: true);
      if (c.size.height > tallest) tallest = c.size.height;
    }
    var x = 0.0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      if (c.size.height != tallest) {
        c.layout(BoxConstraints.tight(Size(cell, tallest)), parentUsesSize: true);
      }
      (c.parentData! as _RowParentData).offset = Offset(x, 0);
      x += cell + _gap;
    }
    size = constraints.constrain(Size(constraints.maxWidth, tallest));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
