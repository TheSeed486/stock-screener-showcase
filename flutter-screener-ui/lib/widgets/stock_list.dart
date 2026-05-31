import 'package:flutter/material.dart';

import '../data/models/tdx_models.dart';
import '../theme/app_colors.dart';
import 'stock_table.dart';

export 'stock_table.dart';

const Set<StockTableViewport> _stockListAllViewports = <StockTableViewport>{
  StockTableViewport.compact,
  StockTableViewport.medium,
  StockTableViewport.expanded,
};

const double _stockListPrimaryValueFontSize = 13.5;
const double _stockListSecondaryValueFontSize = 12.5;

enum StockListStandardColumn {
  security,
  sparkline,
  latestPrice,
  pctChange,
  lastClose,
  open,
  high,
  low,
  riseSpeed,
  volume,
  commissionRatio,
  amount,
  serverTime,
}

class StockListCompactNumberUnits {
  const StockListCompactNumberUnits({
    required this.tenThousandUnit,
    required this.hundredMillionUnit,
  });

  static const StockListCompactNumberUnits chinese =
      StockListCompactNumberUnits(
        tenThousandUnit: '\u4e07',
        hundredMillionUnit: '\u4ebf',
      );

  static const StockListCompactNumberUnits western =
      StockListCompactNumberUnits(
        tenThousandUnit: 'W',
        hundredMillionUnit: 'B',
      );

  final String tenThousandUnit;
  final String hundredMillionUnit;
}

class StockListRemoteSortBinding {
  const StockListRemoteSortBinding({
    required this.selected,
    required this.ascending,
    required this.onTap,
    this.fontSize = 11.5,
  });

  final bool selected;
  final bool ascending;
  final VoidCallback onTap;
  final double fontSize;
}

class StockListRowViewData {
  const StockListRowViewData({
    required this.key,
    required this.name,
    required this.marketLabel,
    required this.code,
    this.sparklineBars,
    this.preClose,
    this.latestPrice,
    this.pctChange,
    this.lastClose,
    this.open,
    this.high,
    this.low,
    this.riseSpeed,
    this.volume,
    this.commissionRatio,
    this.amount,
    this.note = '',
    this.serverTime,
    this.trendColor,
  });

  final String key;
  final String name;
  final String marketLabel;
  final String code;
  final List<MinuteBarModel>? sparklineBars;
  final double? preClose;
  final double? latestPrice;
  final double? pctChange;
  final double? lastClose;
  final double? open;
  final double? high;
  final double? low;
  final double? riseSpeed;
  final double? volume;
  final double? commissionRatio;
  final double? amount;
  final String note;
  final String? serverTime;
  final Color? trendColor;

  Color get resolvedTrendColor {
    final Color? override = trendColor;
    if (override != null) {
      return override;
    }
    final double? percent = pctChange;
    if (percent != null) {
      return percent >= 0 ? AppColors.rise : AppColors.fall;
    }
    final double? price = latestPrice;
    final double? reference = preClose ?? lastClose;
    if (price != null && reference != null) {
      return StockTableFormatters.compareColor(price, reference);
    }
    return AppColors.textSecondary;
  }

  Color compareToLastClose(double? value) {
    final double? reference = lastClose;
    if (value == null || reference == null) {
      return AppColors.textSecondary;
    }
    return StockTableFormatters.compareColor(value, reference);
  }

  double get sparklineReferencePrice =>
      preClose ?? lastClose ?? latestPrice ?? 0;
}

typedef StockListViewDataBuilder<T> = StockListRowViewData Function(T item);
typedef StockListCustomCellBuilder<T> =
    Widget Function(BuildContext context, T item, StockListRowViewData rowData);

class StockListColumnSchema<T> {
  const StockListColumnSchema.standard({
    required this.id,
    required this.standardColumn,
    required this.minWidth,
    this.label,
    this.flex = 0,
    this.visibleIn = _stockListAllViewports,
    this.headerAlignment,
    this.cellAlignment,
    this.headerBuilder,
    this.remoteSort,
    this.valueFontSize,
    this.compactUnits = StockListCompactNumberUnits.chinese,
  }) : customCellBuilder = null;

  const StockListColumnSchema.custom({
    required this.id,
    required this.minWidth,
    required this.customCellBuilder,
    this.label,
    this.flex = 0,
    this.visibleIn = _stockListAllViewports,
    this.headerAlignment,
    this.cellAlignment,
    this.headerBuilder,
  }) : standardColumn = null,
       remoteSort = null,
       valueFontSize = null,
       compactUnits = StockListCompactNumberUnits.chinese;

  final Object id;
  final StockListStandardColumn? standardColumn;
  final String? label;
  final double minWidth;
  final double flex;
  final Set<StockTableViewport> visibleIn;
  final Alignment? headerAlignment;
  final Alignment? cellAlignment;
  final StockTableHeaderBuilder? headerBuilder;
  final StockListRemoteSortBinding? remoteSort;
  final double? valueFontSize;
  final StockListCompactNumberUnits compactUnits;
  final StockListCustomCellBuilder<T>? customCellBuilder;
}

class StockListSchema<T> {
  const StockListSchema({
    required this.columns,
    this.style = const StockTableStyle(),
    this.breakpoints = const StockTableResponsiveBreakpoints(),
  });

  final List<StockListColumnSchema<T>> columns;
  final StockTableStyle style;
  final StockTableResponsiveBreakpoints breakpoints;
}

class StockListColumns {
  const StockListColumns._();

  static StockListColumnSchema<T> standard<T>({
    required StockListStandardColumn column,
    Object? id,
    String? label,
    double? minWidth,
    double? flex,
    Set<StockTableViewport> visibleIn = _stockListAllViewports,
    double? fontSize,
    StockListRemoteSortBinding? remoteSort,
    StockListCompactNumberUnits units = StockListCompactNumberUnits.chinese,
  }) {
    final Object resolvedId = id ?? column;
    switch (column) {
      case StockListStandardColumn.security:
        return security<T>(
          id: resolvedId,
          label: label,
          minWidth: minWidth ?? 176,
          flex: flex ?? 2.6,
          visibleIn: visibleIn,
        );
      case StockListStandardColumn.sparkline:
        return sparkline<T>(
          id: resolvedId,
          label: label,
          minWidth: minWidth ?? 126,
          flex: flex ?? 1.9,
          visibleIn: visibleIn,
        );
      case StockListStandardColumn.latestPrice:
        return latestPrice<T>(
          id: resolvedId,
          label: label,
          minWidth: minWidth ?? 76,
          flex: flex ?? 1,
          visibleIn: visibleIn,
          fontSize: fontSize ?? _stockListPrimaryValueFontSize,
          remoteSort: remoteSort,
        );
      case StockListStandardColumn.pctChange:
        return pctChange<T>(
          id: resolvedId,
          label: label,
          minWidth: minWidth ?? 84,
          flex: flex ?? 1.1,
          visibleIn: visibleIn,
          fontSize: fontSize ?? _stockListPrimaryValueFontSize,
          remoteSort: remoteSort,
        );
      case StockListStandardColumn.lastClose:
        return lastClose<T>(
          id: resolvedId,
          label: label,
          minWidth: minWidth ?? 72,
          flex: flex ?? 0.8,
          visibleIn: visibleIn,
          fontSize: fontSize ?? _stockListSecondaryValueFontSize,
        );
      case StockListStandardColumn.open:
        return open<T>(
          id: resolvedId,
          label: label,
          minWidth: minWidth ?? 72,
          flex: flex ?? 0.8,
          visibleIn: visibleIn,
          fontSize: fontSize ?? _stockListSecondaryValueFontSize,
        );
      case StockListStandardColumn.high:
        return high<T>(
          id: resolvedId,
          label: label,
          minWidth: minWidth ?? 72,
          flex: flex ?? 0.8,
          visibleIn: visibleIn,
          fontSize: fontSize ?? _stockListSecondaryValueFontSize,
        );
      case StockListStandardColumn.low:
        return low<T>(
          id: resolvedId,
          label: label,
          minWidth: minWidth ?? 72,
          flex: flex ?? 0.8,
          visibleIn: visibleIn,
          fontSize: fontSize ?? _stockListSecondaryValueFontSize,
        );
      case StockListStandardColumn.riseSpeed:
        return riseSpeed<T>(
          id: resolvedId,
          label: label,
          minWidth: minWidth ?? 62,
          flex: flex ?? 0.8,
          visibleIn: visibleIn,
          fontSize: fontSize ?? _stockListSecondaryValueFontSize,
          remoteSort: remoteSort,
        );
      case StockListStandardColumn.volume:
        return volume<T>(
          id: resolvedId,
          label: label,
          minWidth: minWidth ?? 82,
          flex: flex ?? 1,
          visibleIn: visibleIn,
          fontSize: fontSize ?? _stockListSecondaryValueFontSize,
          units: units,
        );
      case StockListStandardColumn.commissionRatio:
        return commissionRatio<T>(
          id: resolvedId,
          label: label,
          minWidth: minWidth ?? 66,
          flex: flex ?? 0.8,
          visibleIn: visibleIn,
          fontSize: fontSize ?? _stockListSecondaryValueFontSize,
        );
      case StockListStandardColumn.amount:
        return amount<T>(
          id: resolvedId,
          label: label,
          minWidth: minWidth ?? 92,
          flex: flex ?? 1.1,
          visibleIn: visibleIn,
          fontSize: fontSize ?? _stockListSecondaryValueFontSize,
          units: units,
        );
      case StockListStandardColumn.serverTime:
        return serverTime<T>(
          id: resolvedId,
          label: label,
          minWidth: minWidth ?? 72,
          flex: flex ?? 0.7,
          visibleIn: visibleIn,
          fontSize: fontSize ?? _stockListSecondaryValueFontSize,
        );
    }
  }

  static StockListColumnSchema<T> security<T>({
    Object id = StockListStandardColumn.security,
    String? label,
    double minWidth = 176,
    double flex = 2.6,
    Set<StockTableViewport> visibleIn = _stockListAllViewports,
  }) {
    return StockListColumnSchema<T>.standard(
      id: id,
      standardColumn: StockListStandardColumn.security,
      label: label,
      minWidth: minWidth,
      flex: flex,
      visibleIn: visibleIn,
    );
  }

  static StockListColumnSchema<T> sparkline<T>({
    Object id = StockListStandardColumn.sparkline,
    String? label,
    double minWidth = 126,
    double flex = 1.9,
    Set<StockTableViewport> visibleIn = _stockListAllViewports,
  }) {
    return StockListColumnSchema<T>.standard(
      id: id,
      standardColumn: StockListStandardColumn.sparkline,
      label: label,
      minWidth: minWidth,
      flex: flex,
      visibleIn: visibleIn,
      headerAlignment: Alignment.center,
      cellAlignment: Alignment.center,
    );
  }

  static StockListColumnSchema<T> latestPrice<T>({
    Object id = StockListStandardColumn.latestPrice,
    String? label,
    double minWidth = 76,
    double flex = 1,
    Set<StockTableViewport> visibleIn = _stockListAllViewports,
    double fontSize = _stockListPrimaryValueFontSize,
    StockListRemoteSortBinding? remoteSort,
  }) {
    return StockListColumnSchema<T>.standard(
      id: id,
      standardColumn: StockListStandardColumn.latestPrice,
      label: label,
      minWidth: minWidth,
      flex: flex,
      visibleIn: visibleIn,
      headerAlignment: Alignment.centerRight,
      cellAlignment: Alignment.centerRight,
      valueFontSize: fontSize,
      remoteSort: remoteSort,
    );
  }

  static StockListColumnSchema<T> pctChange<T>({
    Object id = StockListStandardColumn.pctChange,
    String? label,
    double minWidth = 84,
    double flex = 1.1,
    Set<StockTableViewport> visibleIn = _stockListAllViewports,
    double fontSize = _stockListPrimaryValueFontSize,
    StockListRemoteSortBinding? remoteSort,
  }) {
    return StockListColumnSchema<T>.standard(
      id: id,
      standardColumn: StockListStandardColumn.pctChange,
      label: label,
      minWidth: minWidth,
      flex: flex,
      visibleIn: visibleIn,
      headerAlignment: Alignment.centerRight,
      cellAlignment: Alignment.centerRight,
      valueFontSize: fontSize,
      remoteSort: remoteSort,
    );
  }

  static StockListColumnSchema<T> lastClose<T>({
    Object id = StockListStandardColumn.lastClose,
    String? label,
    double minWidth = 72,
    double flex = 0.8,
    Set<StockTableViewport> visibleIn = _stockListAllViewports,
    double fontSize = _stockListSecondaryValueFontSize,
  }) {
    return _standardNumeric<T>(
      id: id,
      column: StockListStandardColumn.lastClose,
      label: label,
      minWidth: minWidth,
      flex: flex,
      visibleIn: visibleIn,
      fontSize: fontSize,
    );
  }

  static StockListColumnSchema<T> open<T>({
    Object id = StockListStandardColumn.open,
    String? label,
    double minWidth = 72,
    double flex = 0.8,
    Set<StockTableViewport> visibleIn = _stockListAllViewports,
    double fontSize = _stockListSecondaryValueFontSize,
  }) {
    return _standardNumeric<T>(
      id: id,
      column: StockListStandardColumn.open,
      label: label,
      minWidth: minWidth,
      flex: flex,
      visibleIn: visibleIn,
      fontSize: fontSize,
    );
  }

  static StockListColumnSchema<T> high<T>({
    Object id = StockListStandardColumn.high,
    String? label,
    double minWidth = 72,
    double flex = 0.8,
    Set<StockTableViewport> visibleIn = _stockListAllViewports,
    double fontSize = _stockListSecondaryValueFontSize,
  }) {
    return _standardNumeric<T>(
      id: id,
      column: StockListStandardColumn.high,
      label: label,
      minWidth: minWidth,
      flex: flex,
      visibleIn: visibleIn,
      fontSize: fontSize,
    );
  }

  static StockListColumnSchema<T> low<T>({
    Object id = StockListStandardColumn.low,
    String? label,
    double minWidth = 72,
    double flex = 0.8,
    Set<StockTableViewport> visibleIn = _stockListAllViewports,
    double fontSize = _stockListSecondaryValueFontSize,
  }) {
    return _standardNumeric<T>(
      id: id,
      column: StockListStandardColumn.low,
      label: label,
      minWidth: minWidth,
      flex: flex,
      visibleIn: visibleIn,
      fontSize: fontSize,
    );
  }

  static StockListColumnSchema<T> riseSpeed<T>({
    Object id = StockListStandardColumn.riseSpeed,
    String? label,
    double minWidth = 62,
    double flex = 0.8,
    Set<StockTableViewport> visibleIn = _stockListAllViewports,
    double fontSize = _stockListSecondaryValueFontSize,
    StockListRemoteSortBinding? remoteSort,
  }) {
    return StockListColumnSchema<T>.standard(
      id: id,
      standardColumn: StockListStandardColumn.riseSpeed,
      label: label,
      minWidth: minWidth,
      flex: flex,
      visibleIn: visibleIn,
      headerAlignment: Alignment.centerRight,
      cellAlignment: Alignment.centerRight,
      valueFontSize: fontSize,
      remoteSort: remoteSort,
    );
  }

  static StockListColumnSchema<T> volume<T>({
    Object id = StockListStandardColumn.volume,
    String? label,
    double minWidth = 82,
    double flex = 1,
    Set<StockTableViewport> visibleIn = _stockListAllViewports,
    double fontSize = _stockListSecondaryValueFontSize,
    StockListCompactNumberUnits units = StockListCompactNumberUnits.chinese,
  }) {
    return StockListColumnSchema<T>.standard(
      id: id,
      standardColumn: StockListStandardColumn.volume,
      label: label,
      minWidth: minWidth,
      flex: flex,
      visibleIn: visibleIn,
      headerAlignment: Alignment.centerRight,
      cellAlignment: Alignment.centerRight,
      valueFontSize: fontSize,
      compactUnits: units,
    );
  }

  static StockListColumnSchema<T> commissionRatio<T>({
    Object id = StockListStandardColumn.commissionRatio,
    String? label,
    double minWidth = 66,
    double flex = 0.8,
    Set<StockTableViewport> visibleIn = _stockListAllViewports,
    double fontSize = _stockListSecondaryValueFontSize,
  }) {
    return _standardPercent<T>(
      id: id,
      column: StockListStandardColumn.commissionRatio,
      label: label,
      minWidth: minWidth,
      flex: flex,
      visibleIn: visibleIn,
      fontSize: fontSize,
    );
  }

  static StockListColumnSchema<T> amount<T>({
    Object id = StockListStandardColumn.amount,
    String? label,
    double minWidth = 92,
    double flex = 1.1,
    Set<StockTableViewport> visibleIn = _stockListAllViewports,
    double fontSize = _stockListSecondaryValueFontSize,
    StockListCompactNumberUnits units = StockListCompactNumberUnits.chinese,
  }) {
    return StockListColumnSchema<T>.standard(
      id: id,
      standardColumn: StockListStandardColumn.amount,
      label: label,
      minWidth: minWidth,
      flex: flex,
      visibleIn: visibleIn,
      headerAlignment: Alignment.centerRight,
      cellAlignment: Alignment.centerRight,
      valueFontSize: fontSize,
      compactUnits: units,
    );
  }

  static StockListColumnSchema<T> serverTime<T>({
    Object id = StockListStandardColumn.serverTime,
    String? label,
    double minWidth = 72,
    double flex = 0.7,
    Set<StockTableViewport> visibleIn = _stockListAllViewports,
    double fontSize = _stockListSecondaryValueFontSize,
  }) {
    return StockListColumnSchema<T>.standard(
      id: id,
      standardColumn: StockListStandardColumn.serverTime,
      label: label,
      minWidth: minWidth,
      flex: flex,
      visibleIn: visibleIn,
      headerAlignment: Alignment.centerRight,
      cellAlignment: Alignment.centerRight,
      valueFontSize: fontSize,
    );
  }

  static StockListColumnSchema<T> custom<T>({
    required Object id,
    required double minWidth,
    required StockListCustomCellBuilder<T> cellBuilder,
    String? label,
    double flex = 0,
    Set<StockTableViewport> visibleIn = _stockListAllViewports,
    Alignment? headerAlignment,
    Alignment? cellAlignment,
    StockTableHeaderBuilder? headerBuilder,
  }) {
    return StockListColumnSchema<T>.custom(
      id: id,
      minWidth: minWidth,
      customCellBuilder: cellBuilder,
      label: label,
      flex: flex,
      visibleIn: visibleIn,
      headerAlignment: headerAlignment,
      cellAlignment: cellAlignment,
      headerBuilder: headerBuilder,
    );
  }

  static StockListColumnSchema<T> _standardNumeric<T>({
    required Object id,
    required StockListStandardColumn column,
    required double minWidth,
    required double flex,
    required Set<StockTableViewport> visibleIn,
    required double fontSize,
    String? label,
  }) {
    return StockListColumnSchema<T>.standard(
      id: id,
      standardColumn: column,
      label: label,
      minWidth: minWidth,
      flex: flex,
      visibleIn: visibleIn,
      headerAlignment: Alignment.centerRight,
      cellAlignment: Alignment.centerRight,
      valueFontSize: fontSize,
    );
  }

  static StockListColumnSchema<T> _standardPercent<T>({
    required Object id,
    required StockListStandardColumn column,
    required double minWidth,
    required double flex,
    required Set<StockTableViewport> visibleIn,
    required double fontSize,
    String? label,
  }) {
    return StockListColumnSchema<T>.standard(
      id: id,
      standardColumn: column,
      label: label,
      minWidth: minWidth,
      flex: flex,
      visibleIn: visibleIn,
      headerAlignment: Alignment.centerRight,
      cellAlignment: Alignment.centerRight,
      valueFontSize: fontSize,
    );
  }
}

class StockListSurface<T> extends StatefulWidget {
  const StockListSurface({
    super.key,
    required this.items,
    required this.schema,
    required this.rowBuilder,
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
  final StockListSchema<T> schema;
  final StockListViewDataBuilder<T> rowBuilder;
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
  State<StockListSurface<T>> createState() => _StockListSurfaceState<T>();
}

class _StockListSurfaceState<T> extends State<StockListSurface<T>> {
  final Map<T, StockListRowViewData> _rowDataCache =
      <T, StockListRowViewData>{};

  @override
  void didUpdateWidget(covariant StockListSurface<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rowBuilder != widget.rowBuilder ||
        oldWidget.schema != widget.schema) {
      _rowDataCache.clear();
      return;
    }
    final Set<T> liveItems = widget.items.toSet();
    _rowDataCache.removeWhere(
      (T item, StockListRowViewData rowData) => !liveItems.contains(item),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StockTablePresetView<T, Object>(
      items: widget.items,
      preset: _buildPreset(),
      scrollController: widget.scrollController,
      listPhysics: widget.listPhysics,
      emptyBuilder: widget.emptyBuilder,
      onRowTap: widget.onRowTap,
      onRowEnter: widget.onRowEnter,
      onRowExit: widget.onRowExit,
      onRowSecondaryTapDown: widget.onRowSecondaryTapDown,
      isRowSelected: widget.isRowSelected,
      rowBackgroundBuilder: widget.rowBackgroundBuilder,
      onLoadMore: widget.onLoadMore,
      hasMore: widget.hasMore,
      isLoadingMore: widget.isLoadingMore,
      loadMoreExtent: widget.loadMoreExtent,
      onVerticalScrollIdle: widget.onVerticalScrollIdle,
      onVisibleRangeChanged: widget.onVisibleRangeChanged,
    );
  }

  StockListRowViewData _rowDataFor(T item) {
    return _rowDataCache.putIfAbsent(item, () => widget.rowBuilder(item));
  }

  StockTablePreset<T, Object> _buildPreset() {
    return StockTablePreset<T, Object>(
      style: widget.schema.style,
      breakpoints: widget.schema.breakpoints,
      columns: widget.schema.columns
          .map(_toTableColumn)
          .toList(growable: false),
    );
  }

  StockTableColumnSpec<T, Object> _toTableColumn(
    StockListColumnSchema<T> column,
  ) {
    return StockTableColumnSpec<T, Object>(
      id: column.id,
      label: _resolvedLabel(column),
      minWidth: column.minWidth,
      flex: column.flex,
      visibleIn: column.visibleIn,
      headerAlignment:
          column.headerAlignment ?? _defaultHeaderAlignment(column),
      cellAlignment: column.cellAlignment ?? _defaultCellAlignment(column),
      headerBuilder: _buildHeaderBuilder(column),
      cellBuilder: (BuildContext context, T item) {
        final StockListRowViewData rowData = _rowDataFor(item);
        final StockListCustomCellBuilder<T>? customCellBuilder =
            column.customCellBuilder;
        if (customCellBuilder != null) {
          return customCellBuilder(context, item, rowData);
        }
        return _buildStandardCell(column, rowData);
      },
    );
  }

  StockTableHeaderBuilder? _buildHeaderBuilder(
    StockListColumnSchema<T> column,
  ) {
    if (column.headerBuilder != null) {
      return column.headerBuilder;
    }
    final StockListRemoteSortBinding? remoteSort = column.remoteSort;
    if (remoteSort == null) {
      return null;
    }
    final String label = _resolvedLabel(column) ?? '';
    return (_) => StockTableRemoteSortHeader(
      label: label,
      selected: remoteSort.selected,
      ascending: remoteSort.ascending,
      onTap: remoteSort.onTap,
      alignment: column.headerAlignment ?? _defaultHeaderAlignment(column),
      textAlign: _textAlignFor(
        column.headerAlignment ?? _defaultHeaderAlignment(column),
      ),
      fontSize: remoteSort.fontSize,
    );
  }

  Widget _buildStandardCell(
    StockListColumnSchema<T> column,
    StockListRowViewData row,
  ) {
    final StockListStandardColumn standardColumn = column.standardColumn!;
    switch (standardColumn) {
      case StockListStandardColumn.security:
        return StockIdentityCell(
          name: row.name,
          marketLabel: row.marketLabel,
          code: row.code,
        );
      case StockListStandardColumn.sparkline:
        return StockTableSparklineCell(
          bars: row.sparklineBars,
          preClose: row.sparklineReferencePrice,
          trendColor: row.resolvedTrendColor,
        );
      case StockListStandardColumn.latestPrice:
        return StockTableNumericText(
          _priceText(row.latestPrice),
          color: row.resolvedTrendColor,
          fontSize: column.valueFontSize ?? _stockListPrimaryValueFontSize,
          textAlign: _textAlignFor(
            column.cellAlignment ?? _defaultCellAlignment(column),
          ),
        );
      case StockListStandardColumn.pctChange:
        return StockTableNumericText(
          _percentText(row.pctChange),
          color: row.resolvedTrendColor,
          fontSize: column.valueFontSize ?? _stockListPrimaryValueFontSize,
          textAlign: _textAlignFor(
            column.cellAlignment ?? _defaultCellAlignment(column),
          ),
        );
      case StockListStandardColumn.lastClose:
        return StockTableNumericText(
          _priceText(row.lastClose),
          color: AppColors.textSecondary,
          fontSize: column.valueFontSize ?? _stockListSecondaryValueFontSize,
          textAlign: _textAlignFor(
            column.cellAlignment ?? _defaultCellAlignment(column),
          ),
        );
      case StockListStandardColumn.open:
        return StockTableNumericText(
          _priceText(row.open),
          color: row.compareToLastClose(row.open),
          fontSize: column.valueFontSize ?? _stockListSecondaryValueFontSize,
          textAlign: _textAlignFor(
            column.cellAlignment ?? _defaultCellAlignment(column),
          ),
        );
      case StockListStandardColumn.high:
        return StockTableNumericText(
          _priceText(row.high),
          color: row.compareToLastClose(row.high),
          fontSize: column.valueFontSize ?? _stockListSecondaryValueFontSize,
          textAlign: _textAlignFor(
            column.cellAlignment ?? _defaultCellAlignment(column),
          ),
        );
      case StockListStandardColumn.low:
        return StockTableNumericText(
          _priceText(row.low),
          color: row.compareToLastClose(row.low),
          fontSize: column.valueFontSize ?? _stockListSecondaryValueFontSize,
          textAlign: _textAlignFor(
            column.cellAlignment ?? _defaultCellAlignment(column),
          ),
        );
      case StockListStandardColumn.riseSpeed:
        return StockTableNumericText(
          _percentText(row.riseSpeed),
          color: _directionalColor(row.riseSpeed),
          fontSize: column.valueFontSize ?? _stockListSecondaryValueFontSize,
          textAlign: _textAlignFor(
            column.cellAlignment ?? _defaultCellAlignment(column),
          ),
        );
      case StockListStandardColumn.volume:
        return StockTableNumericText(
          _compactNumberText(row.volume, column.compactUnits),
          color: AppColors.textSecondary,
          fontSize: column.valueFontSize ?? _stockListSecondaryValueFontSize,
          textAlign: _textAlignFor(
            column.cellAlignment ?? _defaultCellAlignment(column),
          ),
        );
      case StockListStandardColumn.commissionRatio:
        return StockTableNumericText(
          _percentText(row.commissionRatio),
          color: _directionalColor(row.commissionRatio),
          fontSize: column.valueFontSize ?? _stockListSecondaryValueFontSize,
          textAlign: _textAlignFor(
            column.cellAlignment ?? _defaultCellAlignment(column),
          ),
        );
      case StockListStandardColumn.amount:
        return StockTableNumericText(
          _compactNumberText(row.amount, column.compactUnits),
          color: AppColors.textSecondary,
          fontSize: column.valueFontSize ?? _stockListSecondaryValueFontSize,
          textAlign: _textAlignFor(
            column.cellAlignment ?? _defaultCellAlignment(column),
          ),
        );
      case StockListStandardColumn.serverTime:
        return StockTableNumericText(
          row.serverTime ?? '--',
          color: AppColors.textSecondary,
          fontSize: column.valueFontSize ?? _stockListSecondaryValueFontSize,
          textAlign: _textAlignFor(
            column.cellAlignment ?? _defaultCellAlignment(column),
          ),
        );
    }
  }

  String? _resolvedLabel(StockListColumnSchema<T> column) {
    return column.label ?? _defaultLabelFor(column.standardColumn);
  }

  Alignment _defaultHeaderAlignment(StockListColumnSchema<T> column) {
    final StockListStandardColumn? standardColumn = column.standardColumn;
    if (standardColumn == StockListStandardColumn.sparkline) {
      return Alignment.center;
    }
    if (_isNumeric(standardColumn)) {
      return Alignment.centerRight;
    }
    return Alignment.centerLeft;
  }

  Alignment _defaultCellAlignment(StockListColumnSchema<T> column) {
    return _defaultHeaderAlignment(column);
  }

  bool _isNumeric(StockListStandardColumn? column) {
    switch (column) {
      case StockListStandardColumn.latestPrice:
      case StockListStandardColumn.pctChange:
      case StockListStandardColumn.lastClose:
      case StockListStandardColumn.open:
      case StockListStandardColumn.high:
      case StockListStandardColumn.low:
      case StockListStandardColumn.riseSpeed:
      case StockListStandardColumn.volume:
      case StockListStandardColumn.commissionRatio:
      case StockListStandardColumn.amount:
      case StockListStandardColumn.serverTime:
        return true;
      case StockListStandardColumn.security:
      case StockListStandardColumn.sparkline:
      case null:
        return false;
    }
  }

  String? _defaultLabelFor(StockListStandardColumn? column) {
    switch (column) {
      case StockListStandardColumn.security:
        return '\u80a1\u7968';
      case StockListStandardColumn.sparkline:
        return '\u5206\u65f6';
      case StockListStandardColumn.latestPrice:
        return '\u6700\u65b0\u4ef7';
      case StockListStandardColumn.pctChange:
        return '\u6da8\u8dcc\u5e45';
      case StockListStandardColumn.lastClose:
        return '\u6628\u6536';
      case StockListStandardColumn.open:
        return '\u4eca\u5f00';
      case StockListStandardColumn.high:
        return '\u6700\u9ad8';
      case StockListStandardColumn.low:
        return '\u6700\u4f4e';
      case StockListStandardColumn.riseSpeed:
        return '\u6da8\u901f';
      case StockListStandardColumn.volume:
        return '\u73b0\u91cf';
      case StockListStandardColumn.commissionRatio:
        return '\u59d4\u6bd4';
      case StockListStandardColumn.amount:
        return '\u6210\u4ea4\u989d';
      case StockListStandardColumn.serverTime:
        return '\u65f6\u95f4';
      case null:
        return null;
    }
  }

  String _priceText(double? value) =>
      value == null ? '--' : value.toStringAsFixed(2);

  String _percentText(double? value) {
    if (value == null) {
      return '--';
    }
    return StockTableFormatters.signedPercent(value);
  }

  String _compactNumberText(double? value, StockListCompactNumberUnits units) {
    if (value == null) {
      return '--';
    }
    return StockTableFormatters.compactNumber(
      value,
      tenThousandUnit: units.tenThousandUnit,
      hundredMillionUnit: units.hundredMillionUnit,
    );
  }

  Color _directionalColor(double? value) {
    if (value == null) {
      return AppColors.textSecondary;
    }
    return value >= 0 ? AppColors.rise : AppColors.fall;
  }

  TextAlign _textAlignFor(Alignment alignment) {
    if (alignment.x <= -0.5) {
      return TextAlign.left;
    }
    if (alignment.x >= 0.5) {
      return TextAlign.right;
    }
    return TextAlign.center;
  }
}
