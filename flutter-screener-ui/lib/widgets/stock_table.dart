import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/models/tdx_models.dart';
import '../theme/app_colors.dart';

typedef StockTableHeaderBuilder = Widget Function(BuildContext context);
typedef StockTableCellBuilder<T> =
    Widget Function(BuildContext context, T item);
typedef StockTableRowColorBuilder<T> =
    Color? Function(T item, int index, bool selected);
typedef StockTableRowSelectionResolver<T> = bool Function(T item);
typedef StockTableRowEnter<T> = void Function(T item);
typedef StockTableRowSecondaryTapDown<T> =
    Future<void> Function(T item, TapDownDetails details);
typedef StockTableVisibleRangeChanged =
    void Function(StockTableVisibleRange range);

class StockTableVisibleRange {
  const StockTableVisibleRange({
    required this.firstVisibleIndex,
    required this.visibleCount,
  });

  final int firstVisibleIndex;
  final int visibleCount;

  int get lastVisibleIndex => firstVisibleIndex + visibleCount - 1;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is StockTableVisibleRange &&
        other.firstVisibleIndex == firstVisibleIndex &&
        other.visibleCount == visibleCount;
  }

  @override
  int get hashCode => Object.hash(firstVisibleIndex, visibleCount);
}

class StockTableColumn<T> {
  const StockTableColumn({
    required this.id,
    required this.minWidth,
    required this.cellBuilder,
    this.label,
    this.flex = 0,
    this.headerBuilder,
    this.headerAlignment = Alignment.centerLeft,
    this.cellAlignment = Alignment.centerLeft,
  }) : assert(flex >= 0);

  final String id;
  final String? label;
  final double minWidth;
  final double flex;
  final StockTableHeaderBuilder? headerBuilder;
  final StockTableCellBuilder<T> cellBuilder;
  final Alignment headerAlignment;
  final Alignment cellAlignment;
}

enum StockTableViewport { compact, medium, expanded }

class StockTableResponsiveBreakpoints {
  const StockTableResponsiveBreakpoints({
    this.compactMaxWidth = 720,
    this.mediumMaxWidth = 1080,
  }) : assert(compactMaxWidth > 0),
       assert(mediumMaxWidth >= compactMaxWidth);

  final double compactMaxWidth;
  final double mediumMaxWidth;

  StockTableViewport resolve(double width) {
    if (width <= compactMaxWidth) {
      return StockTableViewport.compact;
    }
    if (width <= mediumMaxWidth) {
      return StockTableViewport.medium;
    }
    return StockTableViewport.expanded;
  }
}

class StockTableStyle {
  const StockTableStyle({
    this.rowHeight = 54,
    this.headerHeight = 24,
    this.columnGap = 6,
    this.headerPadding = const EdgeInsets.symmetric(horizontal: 8),
    this.rowPadding = const EdgeInsets.symmetric(horizontal: 8),
    this.headerBackgroundColor = Colors.transparent,
    this.headerTextStyle = const TextStyle(
      color: AppColors.textSecondary,
      fontWeight: FontWeight.w600,
      fontSize: 11.5,
      height: 1,
    ),
    this.listPhysics,
    this.baseRowColor = AppColors.surface,
    this.hoverFillColor = AppColors.surfaceMuted,
    this.selectedFillColor = AppColors.selection,
    this.selectedBorderWidth = 0,
    this.selectedBorderColor = AppColors.brand,
    this.selectedBorderRadius = 2,
  });

  final double rowHeight;
  final double headerHeight;
  final double columnGap;
  final EdgeInsetsGeometry headerPadding;
  final EdgeInsetsGeometry rowPadding;
  final Color headerBackgroundColor;
  final TextStyle headerTextStyle;
  final ScrollPhysics? listPhysics;
  final Color baseRowColor;
  final Color hoverFillColor;
  final Color selectedFillColor;
  final double selectedBorderWidth;
  final Color selectedBorderColor;
  final double selectedBorderRadius;
}

class StockTableColumnSpec<T, C> {
  const StockTableColumnSpec({
    required this.id,
    required this.minWidth,
    required this.cellBuilder,
    this.label,
    this.flex = 0,
    this.headerBuilder,
    this.headerAlignment = Alignment.centerLeft,
    this.cellAlignment = Alignment.centerLeft,
    this.visibleIn = const <StockTableViewport>{
      StockTableViewport.compact,
      StockTableViewport.medium,
      StockTableViewport.expanded,
    },
  }) : assert(flex >= 0);

  final C id;
  final String? label;
  final double minWidth;
  final double flex;
  final StockTableHeaderBuilder? headerBuilder;
  final StockTableCellBuilder<T> cellBuilder;
  final Alignment headerAlignment;
  final Alignment cellAlignment;
  final Set<StockTableViewport> visibleIn;

  StockTableColumn<T> toColumn() {
    return StockTableColumn<T>(
      id: _stringId,
      label: label,
      minWidth: minWidth,
      flex: flex,
      headerBuilder: headerBuilder,
      headerAlignment: headerAlignment,
      cellAlignment: cellAlignment,
      cellBuilder: cellBuilder,
    );
  }

  bool isVisibleIn(StockTableViewport viewport) => visibleIn.contains(viewport);

  String get _stringId {
    final Object rawId = id as Object;
    if (rawId is Enum) {
      return rawId.name;
    }
    return '$rawId';
  }
}

typedef StockTableVisibleColumnResolver<T, C> =
    List<C> Function(
      StockTableViewport viewport,
      List<StockTableColumnSpec<T, C>> columns,
    );
typedef StockTableStyleResolver =
    StockTableStyle Function(StockTableViewport viewport);

class StockTablePreset<T, C> {
  const StockTablePreset({
    required this.columns,
    this.style = const StockTableStyle(),
    this.breakpoints = const StockTableResponsiveBreakpoints(),
    this.visibleColumnResolver,
    this.styleResolver,
  });

  final List<StockTableColumnSpec<T, C>> columns;
  final StockTableStyle style;
  final StockTableResponsiveBreakpoints breakpoints;
  final StockTableVisibleColumnResolver<T, C>? visibleColumnResolver;
  final StockTableStyleResolver? styleResolver;

  StockTableResolvedPreset<T> resolve(double width) {
    final StockTableViewport viewport = breakpoints.resolve(width);
    final List<StockTableColumnSpec<T, C>> visibleSpecs =
        _resolveVisibleColumns(viewport);
    return StockTableResolvedPreset<T>(
      viewport: viewport,
      style: styleResolver?.call(viewport) ?? style,
      columns: visibleSpecs
          .map((StockTableColumnSpec<T, C> column) => column.toColumn())
          .toList(growable: false),
    );
  }

  List<StockTableColumnSpec<T, C>> _resolveVisibleColumns(
    StockTableViewport viewport,
  ) {
    if (visibleColumnResolver != null) {
      final List<C> resolvedIds = visibleColumnResolver!(viewport, columns);
      final Map<C, StockTableColumnSpec<T, C>> columnById =
          <C, StockTableColumnSpec<T, C>>{
            for (final StockTableColumnSpec<T, C> column in columns)
              column.id: column,
          };
      final List<StockTableColumnSpec<T, C>> orderedColumns = resolvedIds
          .map((C id) => columnById[id])
          .whereType<StockTableColumnSpec<T, C>>()
          .toList(growable: false);
      if (orderedColumns.isNotEmpty) {
        return orderedColumns;
      }
    }

    final List<StockTableColumnSpec<T, C>> filteredColumns = columns
        .where(
          (StockTableColumnSpec<T, C> column) => column.isVisibleIn(viewport),
        )
        .toList(growable: false);
    if (filteredColumns.isEmpty) {
      return columns;
    }
    return filteredColumns;
  }
}

class StockTableResolvedPreset<T> {
  const StockTableResolvedPreset({
    required this.viewport,
    required this.style,
    required this.columns,
  });

  final StockTableViewport viewport;
  final StockTableStyle style;
  final List<StockTableColumn<T>> columns;
}

// `StockTableView` stays as the low-level renderer; presets let feature pages
// declare columns/styles responsively without rebuilding the shell wiring.
class StockTablePresetView<T, C> extends StatelessWidget {
  const StockTablePresetView({
    super.key,
    required this.items,
    required this.preset,
    this.scrollController,
    this.listPhysics,
    this.emptyBuilder,
    this.onRowTap,
    this.onRowEnter,
    this.onRowExit,
    this.onRowSecondaryTapDown,
    this.isRowSelected,
    this.rowBackgroundBuilder,
    this.onLoadMore,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.loadMoreExtent = 160,
    this.onVerticalScrollIdle,
    this.onVisibleRangeChanged,
  });

  final List<T> items;
  final StockTablePreset<T, C> preset;
  final ScrollController? scrollController;
  final ScrollPhysics? listPhysics;
  final WidgetBuilder? emptyBuilder;
  final ValueChanged<T>? onRowTap;
  final StockTableRowEnter<T>? onRowEnter;
  final VoidCallback? onRowExit;
  final StockTableRowSecondaryTapDown<T>? onRowSecondaryTapDown;
  final StockTableRowSelectionResolver<T>? isRowSelected;
  final StockTableRowColorBuilder<T>? rowBackgroundBuilder;
  final VoidCallback? onLoadMore;
  final bool hasMore;
  final bool isLoadingMore;
  final double loadMoreExtent;
  final VoidCallback? onVerticalScrollIdle;
  final StockTableVisibleRangeChanged? onVisibleRangeChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final StockTableResolvedPreset<T> resolvedPreset = preset.resolve(
          constraints.maxWidth,
        );
        final StockTableStyle style = resolvedPreset.style;
        return StockTableView<T>(
          items: items,
          columns: resolvedPreset.columns,
          scrollController: scrollController,
          rowHeight: style.rowHeight,
          headerHeight: style.headerHeight,
          columnGap: style.columnGap,
          headerPadding: style.headerPadding,
          rowPadding: style.rowPadding,
          headerBackgroundColor: style.headerBackgroundColor,
          listPhysics: listPhysics ?? style.listPhysics,
          emptyBuilder: emptyBuilder,
          onRowTap: onRowTap,
          onRowEnter: onRowEnter,
          onRowExit: onRowExit,
          onRowSecondaryTapDown: onRowSecondaryTapDown,
          isRowSelected: isRowSelected,
          rowBackgroundBuilder: rowBackgroundBuilder,
          onLoadMore: onLoadMore,
          hasMore: hasMore,
          isLoadingMore: isLoadingMore,
          loadMoreExtent: loadMoreExtent,
          onVerticalScrollIdle: onVerticalScrollIdle,
          onVisibleRangeChanged: onVisibleRangeChanged,
          baseRowColor: style.baseRowColor,
          hoverFillColor: style.hoverFillColor,
          selectedFillColor: style.selectedFillColor,
          headerTextStyle: style.headerTextStyle,
          selectedBorderWidth: style.selectedBorderWidth,
          selectedBorderColor: style.selectedBorderColor,
          selectedBorderRadius: style.selectedBorderRadius,
        );
      },
    );
  }
}

class StockTableView<T> extends StatefulWidget {
  const StockTableView({
    super.key,
    required this.items,
    required this.columns,
    this.scrollController,
    this.rowHeight = 54,
    this.headerHeight = 24,
    this.columnGap = 6,
    this.headerPadding = const EdgeInsets.symmetric(horizontal: 8),
    this.rowPadding = const EdgeInsets.symmetric(horizontal: 8),
    this.headerBackgroundColor = Colors.transparent,
    this.listPhysics,
    this.emptyBuilder,
    this.onRowTap,
    this.onRowEnter,
    this.onRowExit,
    this.onRowSecondaryTapDown,
    this.isRowSelected,
    this.rowBackgroundBuilder,
    this.onLoadMore,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.loadMoreExtent = 160,
    this.onVerticalScrollIdle,
    this.onVisibleRangeChanged,
    this.baseRowColor = AppColors.surface,
    this.hoverFillColor = AppColors.surfaceMuted,
    this.selectedFillColor = AppColors.selection,
    this.headerTextStyle = const TextStyle(
      color: AppColors.textSecondary,
      fontWeight: FontWeight.w600,
      fontSize: 11.5,
      height: 1,
    ),
    this.selectedBorderWidth = 0,
    this.selectedBorderColor = AppColors.brand,
    this.selectedBorderRadius = 2,
  });

  final List<T> items;
  final List<StockTableColumn<T>> columns;
  final ScrollController? scrollController;
  final double rowHeight;
  final double headerHeight;
  final double columnGap;
  final EdgeInsetsGeometry headerPadding;
  final EdgeInsetsGeometry rowPadding;
  final Color headerBackgroundColor;
  final ScrollPhysics? listPhysics;
  final WidgetBuilder? emptyBuilder;
  final ValueChanged<T>? onRowTap;
  final StockTableRowEnter<T>? onRowEnter;
  final VoidCallback? onRowExit;
  final StockTableRowSecondaryTapDown<T>? onRowSecondaryTapDown;
  final StockTableRowSelectionResolver<T>? isRowSelected;
  final StockTableRowColorBuilder<T>? rowBackgroundBuilder;
  final VoidCallback? onLoadMore;
  final bool hasMore;
  final bool isLoadingMore;
  final double loadMoreExtent;
  final VoidCallback? onVerticalScrollIdle;
  final StockTableVisibleRangeChanged? onVisibleRangeChanged;
  final Color baseRowColor;
  final Color hoverFillColor;
  final Color selectedFillColor;
  final TextStyle headerTextStyle;
  final double selectedBorderWidth;
  final Color selectedBorderColor;
  final double selectedBorderRadius;

  @override
  State<StockTableView<T>> createState() => _StockTableViewState<T>();
}

class _StockTableViewState<T> extends State<StockTableView<T>> {
  StockTableVisibleRange? _lastVisibleRange;

  @override
  void initState() {
    super.initState();
    _scheduleVisibleRangeEmit();
  }

  @override
  void didUpdateWidget(covariant StockTableView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length ||
        oldWidget.rowHeight != widget.rowHeight ||
        oldWidget.onVisibleRangeChanged != widget.onVisibleRangeChanged ||
        oldWidget.scrollController != widget.scrollController) {
      _scheduleVisibleRangeEmit(resetLastRange: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextDirection textDirection = Directionality.of(context);
    final EdgeInsets resolvedHeaderPadding = widget.headerPadding.resolve(
      textDirection,
    );
    final EdgeInsets resolvedRowPadding = widget.rowPadding.resolve(
      textDirection,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double horizontalPadding = math.max(
          resolvedHeaderPadding.horizontal,
          resolvedRowPadding.horizontal,
        );
        final _StockTableMetrics<T> metrics = _StockTableMetrics<T>.fromWidth(
          math.max(0, constraints.maxWidth - horizontalPadding),
          widget.columns,
          widget.columnGap,
        );
        final double listItemExtent = widget.rowHeight + 1;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: metrics.contentWidth + horizontalPadding,
            height: constraints.maxHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Container(
                  height: widget.headerHeight,
                  color: widget.headerBackgroundColor,
                  child: Padding(
                    padding: widget.headerPadding,
                    child: _StockTableRowSlots<T>(
                      columns: widget.columns,
                      columnGap: widget.columnGap,
                      widthFor: metrics.widthFor,
                      childBuilder:
                          (BuildContext context, StockTableColumn<T> column) {
                            final Widget child =
                                column.headerBuilder?.call(context) ??
                                Align(
                                  alignment: column.headerAlignment,
                                  child: Text(
                                    column.label ?? '',
                                    overflow: TextOverflow.ellipsis,
                                    style: widget.headerTextStyle,
                                  ),
                                );
                            return child;
                          },
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: widget.items.isEmpty
                      ? (widget.emptyBuilder?.call(context) ??
                            const SizedBox.expand())
                      : NotificationListener<ScrollNotification>(
                          onNotification: (ScrollNotification notification) {
                            if (notification.metrics.axis != Axis.vertical) {
                              return false;
                            }
                            _emitVisibleRangeForMetrics(
                              notification.metrics,
                              itemExtent: listItemExtent,
                            );
                            final bool nearListEnd =
                                notification.metrics.extentAfter <=
                                widget.loadMoreExtent;
                            if (nearListEnd &&
                                widget.hasMore &&
                                !widget.isLoadingMore &&
                                widget.onLoadMore != null) {
                              widget.onLoadMore!();
                            }
                            if (notification is ScrollEndNotification) {
                              widget.onVerticalScrollIdle?.call();
                            }
                            return false;
                          },
                          child: ListView.builder(
                            controller: widget.scrollController,
                            padding: EdgeInsets.zero,
                            physics: widget.listPhysics,
                            cacheExtent: widget.rowHeight * 6,
                            itemExtent: listItemExtent,
                            itemCount: widget.items.length,
                            itemBuilder: (BuildContext context, int index) {
                              final T item = widget.items[index];
                              final bool selected =
                                  widget.isRowSelected?.call(item) ?? false;
                              final Color backgroundColor =
                                  widget.rowBackgroundBuilder?.call(
                                    item,
                                    index,
                                    selected,
                                  ) ??
                                  _defaultRowBackgroundColor(
                                    selectedFillColor: widget.selectedFillColor,
                                    baseRowColor: widget.baseRowColor,
                                    selected: selected,
                                  );
                              final BoxDecoration decoration = _rowDecoration(
                                backgroundColor: backgroundColor,
                                selected: selected,
                                selectedBorderWidth: widget.selectedBorderWidth,
                                selectedBorderColor: widget.selectedBorderColor,
                                selectedBorderRadius:
                                    widget.selectedBorderRadius,
                              );

                              return DecoratedBox(
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: AppColors.divider,
                                    ),
                                  ),
                                ),
                                child: RepaintBoundary(
                                  child: MouseRegion(
                                    onEnter: (_) =>
                                        widget.onRowEnter?.call(item),
                                    onExit: (_) => widget.onRowExit?.call(),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: Ink(
                                        decoration: decoration,
                                        child: InkWell(
                                          onTap: widget.onRowTap == null
                                              ? null
                                              : () => widget.onRowTap!(item),
                                          borderRadius:
                                              selected &&
                                                  widget.selectedBorderWidth > 0
                                              ? BorderRadius.circular(
                                                  widget.selectedBorderRadius,
                                                )
                                              : null,
                                          onSecondaryTapDown:
                                              widget.onRowSecondaryTapDown ==
                                                  null
                                              ? null
                                              : (TapDownDetails details) =>
                                                    widget
                                                        .onRowSecondaryTapDown!(
                                                      item,
                                                      details,
                                                    ),
                                          splashFactory: NoSplash.splashFactory,
                                          overlayColor:
                                              WidgetStateProperty.resolveWith((
                                                Set<WidgetState> states,
                                              ) {
                                                if (states.contains(
                                                  WidgetState.pressed,
                                                )) {
                                                  return widget.hoverFillColor
                                                      .withValues(
                                                        alpha: selected
                                                            ? 0.28
                                                            : 0.64,
                                                      );
                                                }
                                                if (states.contains(
                                                  WidgetState.hovered,
                                                )) {
                                                  return widget.hoverFillColor
                                                      .withValues(
                                                        alpha: selected
                                                            ? 0.18
                                                            : 0.9,
                                                      );
                                                }
                                                return Colors.transparent;
                                              }),
                                          splashColor: Colors.transparent,
                                          highlightColor: Colors.transparent,
                                          hoverColor: Colors.transparent,
                                          child: SizedBox(
                                            height: widget.rowHeight,
                                            child: Padding(
                                              padding: widget.rowPadding,
                                              child: _StockTableRowSlots<T>(
                                                columns: widget.columns,
                                                columnGap: widget.columnGap,
                                                widthFor: metrics.widthFor,
                                                childBuilder:
                                                    (
                                                      BuildContext context,
                                                      StockTableColumn<T>
                                                      column,
                                                    ) {
                                                      return Align(
                                                        alignment: column
                                                            .cellAlignment,
                                                        child: column
                                                            .cellBuilder(
                                                              context,
                                                              item,
                                                            ),
                                                      );
                                                    },
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _scheduleVisibleRangeEmit({bool resetLastRange = false}) {
    if (resetLastRange) {
      _lastVisibleRange = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.onVisibleRangeChanged == null) {
        return;
      }
      final ScrollController? scrollController = widget.scrollController;
      if (scrollController == null || !scrollController.hasClients) {
        return;
      }
      _emitVisibleRangeForMetrics(
        scrollController.position,
        itemExtent: widget.rowHeight + 1,
      );
    });
  }

  void _emitVisibleRangeForMetrics(
    ScrollMetrics metrics, {
    required double itemExtent,
  }) {
    final StockTableVisibleRangeChanged? onVisibleRangeChanged =
        widget.onVisibleRangeChanged;
    if (onVisibleRangeChanged == null || widget.items.isEmpty) {
      return;
    }
    final int itemCount = widget.items.length;
    final int firstVisibleIndex = (metrics.pixels / itemExtent).floor().clamp(
      0,
      itemCount - 1,
    );
    final int visibleCount = math.max(
      1,
      (metrics.viewportDimension / itemExtent).ceil(),
    );
    final int clampedVisibleCount = visibleCount.clamp(
      1,
      itemCount - firstVisibleIndex,
    );
    final StockTableVisibleRange nextRange = StockTableVisibleRange(
      firstVisibleIndex: firstVisibleIndex,
      visibleCount: clampedVisibleCount,
    );
    if (_lastVisibleRange == nextRange) {
      return;
    }
    _lastVisibleRange = nextRange;
    onVisibleRangeChanged(nextRange);
  }
}

Color _defaultRowBackgroundColor({
  required Color selectedFillColor,
  required Color baseRowColor,
  required bool selected,
}) {
  if (selected) {
    return selectedFillColor;
  }
  return baseRowColor;
}

BoxDecoration _rowDecoration({
  required Color backgroundColor,
  required bool selected,
  required double selectedBorderWidth,
  required Color selectedBorderColor,
  required double selectedBorderRadius,
}) {
  return BoxDecoration(
    color: backgroundColor,
    borderRadius: BorderRadius.circular(
      selected && selectedBorderWidth > 0 ? selectedBorderRadius : 0,
    ),
    border: selected && selectedBorderWidth > 0
        ? Border.all(color: selectedBorderColor, width: selectedBorderWidth)
        : null,
  );
}

class StockIdentityCell extends StatelessWidget {
  const StockIdentityCell({
    super.key,
    required this.name,
    required this.marketLabel,
    required this.code,
    this.nameFontSize = 14.5,
    this.metaFontSize = 11.5,
  });

  final String name;
  final String marketLabel;
  final String code;
  final double nameFontSize;
  final double metaFontSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: nameFontSize,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: Text(
                code,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: metaFontSize,
                  height: 1,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              marketLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.rise,
                fontWeight: FontWeight.w600,
                fontSize: metaFontSize,
                height: 1,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// Presentation-only remote sort header. It reflects the active sort state and
// delegates tap handling to the caller, which can then issue an API request.
class StockTableRemoteSortHeader extends StatelessWidget {
  const StockTableRemoteSortHeader({
    super.key,
    required this.label,
    required this.selected,
    required this.ascending,
    this.onTap,
    this.alignment = Alignment.centerRight,
    this.textAlign = TextAlign.right,
    this.fontSize = 11.5,
  });

  final String label;
  final bool selected;
  final bool ascending;
  final VoidCallback? onTap;
  final Alignment alignment;
  final TextAlign textAlign;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final IconData icon = selected
        ? (ascending ? Icons.arrow_drop_up : Icons.arrow_drop_down)
        : Icons.unfold_more;
    final Color activeColor = selected
        ? AppColors.brand
        : AppColors.textSecondary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Align(
        alignment: alignment,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              textAlign: textAlign,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: activeColor,
                fontWeight: FontWeight.w600,
                fontSize: fontSize,
                height: 1,
              ),
            ),
            Icon(
              icon,
              size: 16,
              color: selected ? AppColors.brand : AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class StockTableNumericText extends StatelessWidget {
  const StockTableNumericText(
    this.text, {
    super.key,
    this.color = AppColors.textSecondary,
    this.fontSize = 12.5,
    this.fontWeight = FontWeight.w600,
    this.textAlign = TextAlign.right,
    this.height = 1,
  });

  final String text;
  final Color color;
  final double fontSize;
  final FontWeight fontWeight;
  final TextAlign textAlign;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: textAlign,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
        fontWeight: fontWeight,
        fontSize: fontSize,
        height: height,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
  }
}

class StockTableFormatters {
  const StockTableFormatters._();

  static String signedPercent(double value, {int fractionDigits = 2}) {
    final String sign = value >= 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(fractionDigits)}%';
  }

  static String compactNumber(
    double value, {
    String tenThousandUnit = '万',
    String hundredMillionUnit = '亿',
    int scaledFractionDigits = 2,
    int plainFractionDigits = 0,
  }) {
    if (value >= 100000000) {
      return '${(value / 100000000).toStringAsFixed(scaledFractionDigits)}$hundredMillionUnit';
    }
    if (value >= 10000) {
      return '${(value / 10000).toStringAsFixed(scaledFractionDigits)}$tenThousandUnit';
    }
    return value.toStringAsFixed(plainFractionDigits);
  }

  static Color compareColor(
    double value,
    double reference, {
    Color riseColor = AppColors.rise,
    Color fallColor = AppColors.fall,
    Color neutralColor = AppColors.textSecondary,
  }) {
    if (value > reference) {
      return riseColor;
    }
    if (value < reference) {
      return fallColor;
    }
    return neutralColor;
  }
}

class StockTableSparklineCell extends StatelessWidget {
  const StockTableSparklineCell({
    super.key,
    required this.bars,
    required this.preClose,
    required this.trendColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
  });

  final List<MinuteBarModel>? bars;
  final double preClose;
  final Color trendColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Padding(
        padding: padding,
        child: CustomPaint(
          painter: _StockTableSparklinePainter(
            bars: bars ?? const <MinuteBarModel>[],
            preClose: preClose,
            trendColor: trendColor,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _StockTableSparklinePainter extends CustomPainter {
  const _StockTableSparklinePainter({
    required this.bars,
    required this.preClose,
    required this.trendColor,
  });

  final List<MinuteBarModel> bars;
  final double preClose;
  final Color trendColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Paint referencePaint = Paint()
      ..color = AppColors.textMuted.withValues(alpha: 0.34)
      ..strokeWidth = 1;

    _drawDashedLine(
      canvas,
      Offset(rect.left, rect.center.dy),
      Offset(rect.right, rect.center.dy),
      referencePaint,
      dash: 3,
      gap: 2,
    );

    if (bars.length < 2 || preClose <= 0) {
      return;
    }

    double maxDeviation = preClose * 0.002;
    for (final MinuteBarModel bar in bars) {
      maxDeviation = math.max(maxDeviation, (bar.price - preClose).abs());
    }
    final double minPrice = preClose - maxDeviation * 1.15;
    final double maxPrice = preClose + maxDeviation * 1.15;
    final double range = math.max(0.0001, maxPrice - minPrice);

    double yForPrice(double price) {
      final double t = (price - minPrice) / range;
      return rect.bottom - t * rect.height;
    }

    // X-axis spans the full 240-minute trading day (09:30–15:00), not just bars.length.
    const int totalSlots = 240;
    final Path linePath = Path();
    for (int i = 0; i < bars.length; i += 1) {
      final double dx = rect.left + rect.width * (bars[i].minute / math.max(1, totalSlots - 1));
      final double dy = yForPrice(bars[i].price).clamp(rect.top, rect.bottom);
      if (i == 0) {
        linePath.moveTo(dx, dy);
      } else {
        linePath.lineTo(dx, dy);
      }
    }

    final Paint linePaint = Paint()
      ..color = trendColor.withValues(alpha: 0.9)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    final MinuteBarModel lastBar = bars.last;
    final double lastDx = rect.left + rect.width * (lastBar.minute / math.max(1, totalSlots - 1));
    canvas.drawCircle(
      Offset(lastDx, yForPrice(lastBar.price).clamp(rect.top, rect.bottom)),
      1.4,
      Paint()..color = trendColor,
    );
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    final double length = end.dx - start.dx;
    double dx = 0;
    while (dx < length) {
      final double next = math.min(dx + dash, length);
      canvas.drawLine(
        Offset(start.dx + dx, start.dy),
        Offset(start.dx + next, start.dy),
        paint,
      );
      dx += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _StockTableSparklinePainter oldDelegate) {
    return !listEquals(oldDelegate.bars, bars) ||
        oldDelegate.preClose != preClose ||
        oldDelegate.trendColor != trendColor;
  }
}

class _StockTableRowSlots<T> extends StatelessWidget {
  const _StockTableRowSlots({
    required this.columns,
    required this.columnGap,
    required this.widthFor,
    required this.childBuilder,
  });

  final List<StockTableColumn<T>> columns;
  final double columnGap;
  final double Function(String id) widthFor;
  final Widget Function(BuildContext context, StockTableColumn<T> column)
  childBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double desiredWidth =
            columns.fold<double>(
              0,
              (double sum, StockTableColumn<T> column) =>
                  sum + widthFor(column.id),
            ) +
            math.max(0, columns.length - 1) * columnGap;
        final double overflowWidth =
            constraints.hasBoundedWidth && desiredWidth > constraints.maxWidth
            ? desiredWidth - constraints.maxWidth
            : 0;

        final List<Widget> children = <Widget>[];
        for (int index = 0; index < columns.length; index += 1) {
          if (index > 0) {
            children.add(SizedBox(width: columnGap));
          }
          final StockTableColumn<T> column = columns[index];
          double columnWidth = widthFor(column.id);
          if (overflowWidth > 0 && index == columns.length - 1) {
            columnWidth = math.max(0, columnWidth - overflowWidth);
          }
          children.add(
            SizedBox(width: columnWidth, child: childBuilder(context, column)),
          );
        }
        return Row(mainAxisSize: MainAxisSize.min, children: children);
      },
    );
  }
}

class _StockTableMetrics<T> {
  const _StockTableMetrics({required this.contentWidth, required this.widths});

  factory _StockTableMetrics.fromWidth(
    double targetWidth,
    List<StockTableColumn<T>> columns,
    double columnGap,
  ) {
    final Map<String, double> widths = <String, double>{
      for (final StockTableColumn<T> column in columns)
        column.id: column.minWidth,
    };

    final double baseWidth =
        columns.fold<double>(
          0,
          (double sum, StockTableColumn<T> column) => sum + column.minWidth,
        ) +
        math.max(0, columns.length - 1) * columnGap;
    final double extraWidth = math.max(0, targetWidth - baseWidth);
    final double totalFlex = columns.fold<double>(
      0,
      (double sum, StockTableColumn<T> column) => sum + column.flex,
    );

    if (extraWidth > 0 && totalFlex > 0) {
      for (final StockTableColumn<T> column in columns) {
        if (column.flex <= 0) {
          continue;
        }
        widths[column.id] =
            widths[column.id]! + extraWidth * column.flex / totalFlex;
      }
    }

    final double contentWidth = math.max(targetWidth, baseWidth);
    final double allocatedWidth =
        widths.values.fold<double>(
          0,
          (double sum, double width) => sum + width,
        ) +
        math.max(0, columns.length - 1) * columnGap;
    final double roundingError = allocatedWidth - contentWidth;
    if (roundingError > 0 && columns.isNotEmpty) {
      final StockTableColumn<T> lastColumn = columns.last;
      final String lastColumnId = lastColumn.id;
      widths[lastColumnId] = math.max(
        lastColumn.minWidth,
        widths[lastColumnId]! - roundingError,
      );
    }

    return _StockTableMetrics(contentWidth: contentWidth, widths: widths);
  }

  final double contentWidth;
  final Map<String, double> widths;

  double widthFor(String id) => widths[id]!;
}
