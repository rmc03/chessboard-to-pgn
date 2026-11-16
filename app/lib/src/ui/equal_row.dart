// A row of [columns] equally wide cells whose children all get the height of the tallest one.
//
// The diagram blocks of a row differ in height (a castling row, a forced-turn line, a long status), and a row of
// uneven surfaces looks ragged. `IntrinsicHeight` would fix it but cannot measure a `LayoutBuilder` (the board
// lives in one), so this render object lays the children out twice: loosely to find the tallest, then tightly.
// A row with fewer children than [columns] (the last one) keeps the cell width of a full row.
//
// The header of a block (its plate and status) can also differ in height from one block of the row to the next
// (an impossible position adds lines, a doubtful square adds a review row). A block marks its header with
// [RowHeaderSlot]; the row gives every slot in it the height of the tallest header, so the boards below line up
// across the row whatever the statuses are. A slot outside a row is a plain box.
import 'dart:math' as math;

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

/// The header of a block in an [EqualHeightRow]: it is as tall as the tallest header of the row (its content keeps
/// the top). Anywhere else it is as tall as its child.
class RowHeaderSlot extends SingleChildRenderObjectWidget {
  const RowHeaderSlot({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHeaderSlot();
}

class _RenderHeaderSlot extends RenderShiftedBox {
  _RenderHeaderSlot() : super(null);

  double _minHeight = 0;
  _RenderEqualHeightRow? _row;

  /// Height of the content, before the row stretches the slot (only the slot may read its child's size, so it
  /// keeps it for the row).
  double naturalHeight = 0;

  void setMinHeight(double value) {
    if (value == _minHeight) return;
    _minHeight = value;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    RenderObject? node = parent;
    while (node != null && node is! _RenderEqualHeightRow) {
      node = node.parent;
    }
    _row = node as _RenderEqualHeightRow?;
    _row?._slots.add(this);
  }

  @override
  void detach() {
    _row?._slots.remove(this);
    _row = null;
    super.detach();
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      math.max(super.computeMinIntrinsicHeight(width), _minHeight);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      math.max(super.computeMaxIntrinsicHeight(width), _minHeight);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final size =
        child?.getDryLayout(
          constraints.loosen().copyWith(minWidth: constraints.minWidth),
        ) ??
        Size(constraints.minWidth, 0);
    return constraints.constrain(
      Size(size.width, math.max(size.height, _minHeight)),
    );
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      naturalHeight = 0;
      size = constraints.constrain(Size(constraints.minWidth, _minHeight));
      return;
    }
    child.layout(
      BoxConstraints(
        minWidth: constraints.minWidth,
        maxWidth: constraints.maxWidth,
      ),
      parentUsesSize: true,
    );
    naturalHeight = child.size.height;
    size = constraints.constrain(
      Size(child.size.width, math.max(child.size.height, _minHeight)),
    );
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
  final Set<_RenderHeaderSlot> _slots = {};

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
    if (child.parentData is! _RowParentData) {
      child.parentData = _RowParentData();
    }
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
    final loose = BoxConstraints.tightFor(width: cell);
    for (var c = firstChild; c != null; c = childAfter(c)) {
      c.layout(loose, parentUsesSize: true);
    }
    // Headers: every slot takes the height of the tallest one. Changing a slot while the row is laying out is
    // what `invokeLayoutCallback` allows; the cells are then laid out again with the new headers.
    if (_slots.isNotEmpty) {
      final header = _slots.map((s) => s.naturalHeight).reduce(math.max);
      if (_slots.any((s) => s._minHeight != header)) {
        invokeLayoutCallback<BoxConstraints>((_) {
          for (final s in _slots) {
            s.setMinHeight(header);
          }
        });
        for (var c = firstChild; c != null; c = childAfter(c)) {
          c.layout(loose, parentUsesSize: true);
        }
      }
    }
    for (var c = firstChild; c != null; c = childAfter(c)) {
      if (c.size.height > tallest) tallest = c.size.height;
    }
    var x = 0.0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      if (c.size.height != tallest) {
        c.layout(
          BoxConstraints.tight(Size(cell, tallest)),
          parentUsesSize: true,
        );
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
