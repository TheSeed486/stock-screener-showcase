import 'dart:async';
import 'dart:math';
import 'dart:ui' show FontFeature, lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models/tdx_models.dart';
import '../theme/app_colors.dart';

part 'kline_chart/animated_kline_chart_models.dart';
part 'kline_chart/animated_kline_chart_painters.dart';

bool _isIntradayKlineCategory(KlineCategory category) {
  switch (category) {
    case KlineCategory.min1:
    case KlineCategory.min5:
    case KlineCategory.min15:
    case KlineCategory.min30:
    case KlineCategory.hour1:
      return true;
    case KlineCategory.daily:
    case KlineCategory.weekly:
    case KlineCategory.monthly:
    case KlineCategory.quarterly:
    case KlineCategory.yearly:
      return false;
  }
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String _formatYmd(DateTime value) =>
    '${value.year}.${_twoDigits(value.month)}.${_twoDigits(value.day)}';

String _formatYm(DateTime value) => '${value.year}.${_twoDigits(value.month)}';

String _formatMd(DateTime value) =>
    '${_twoDigits(value.month)}.${_twoDigits(value.day)}';

String _formatHm(DateTime value) =>
    '${_twoDigits(value.hour)}:${_twoDigits(value.minute)}';

int _quarterOf(DateTime value) => ((value.month - 1) ~/ 3) + 1;

String _formatQuarter(DateTime value) => '${value.year}Q${_quarterOf(value)}';

bool _isSameCalendarDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String formatKlineAxisLabel(
  DateTime value, {
  required KlineCategory category,
  required int visibleDataCount,
  DateTime? previousValue,
}) {
  if (_isIntradayKlineCategory(category)) {
    final bool dayChanged =
        previousValue == null || !_isSameCalendarDay(previousValue, value);
    if (dayChanged) {
      if (visibleDataCount <= 18) {
        return '${_formatMd(value)} ${_formatHm(value)}';
      }
      return _formatMd(value);
    }
    return _formatHm(value);
  }

  switch (category) {
    case KlineCategory.daily:
    case KlineCategory.weekly:
      final bool yearOrMonthChanged =
          previousValue == null ||
          previousValue.year != value.year ||
          previousValue.month != value.month;
      return yearOrMonthChanged ? _formatYm(value) : _formatMd(value);
    case KlineCategory.monthly:
      final bool yearChanged =
          previousValue == null || previousValue.year != value.year;
      return yearChanged ? _formatYm(value) : _twoDigits(value.month);
    case KlineCategory.quarterly:
      final bool yearChanged =
          previousValue == null || previousValue.year != value.year;
      return yearChanged ? _formatQuarter(value) : 'Q${_quarterOf(value)}';
    case KlineCategory.yearly:
      return value.year.toString();
    case KlineCategory.min1:
    case KlineCategory.min5:
    case KlineCategory.min15:
    case KlineCategory.min30:
    case KlineCategory.hour1:
      return _formatHm(value);
  }
}

String formatKlineCrosshairTimeLabel(
  DateTime value, {
  required KlineCategory category,
}) {
  if (_isIntradayKlineCategory(category)) {
    return '${_formatYmd(value)} ${_formatHm(value)}';
  }
  switch (category) {
    case KlineCategory.daily:
    case KlineCategory.weekly:
      return _formatYmd(value);
    case KlineCategory.monthly:
      return _formatYm(value);
    case KlineCategory.quarterly:
      return _formatQuarter(value);
    case KlineCategory.yearly:
      return value.year.toString();
    case KlineCategory.min1:
    case KlineCategory.min5:
    case KlineCategory.min15:
    case KlineCategory.min30:
    case KlineCategory.hour1:
      return '${_formatYmd(value)} ${_formatHm(value)}';
  }
}

String formatKlineInfoDateLabel(
  DateTime value, {
  required KlineCategory category,
}) {
  return formatKlineCrosshairTimeLabel(value, category: category);
}

String? formatKlineInfoWeekdayLabel(
  DateTime value, {
  required KlineCategory category,
}) {
  if (category != KlineCategory.daily) {
    return null;
  }
  const List<String> weekdays = <String>[
    '星期一',
    '星期二',
    '星期三',
    '星期四',
    '星期五',
    '星期六',
    '星期日',
  ];
  return weekdays[(value.weekday - 1).clamp(0, weekdays.length - 1)];
}

class AnimatedKlineChart extends StatefulWidget {
  const AnimatedKlineChart({
    super.key,
    required this.bars,
    required this.currentPrice,
    required this.klineCategory,
    this.dataIdentity,
    this.onActivateBar,
    this.onFocusedBarChanged,
    this.initialVisibleCandleCount = 90,
    this.visibleCandleCount,
    this.snapToCandle = false,
    this.showInfoOverlay = true,
    this.onReachStart,
    this.initialFocusedTime,
  }) : assert(initialVisibleCandleCount >= 3),
       assert(visibleCandleCount == null || visibleCandleCount >= 3);

  final List<SecurityKlineModel> bars;
  final double currentPrice;
  final KlineCategory klineCategory;
  final Object? dataIdentity;
  final ValueChanged<SecurityKlineModel>? onActivateBar;
  final ValueChanged<SecurityKlineModel?>? onFocusedBarChanged;
  final ValueChanged<int>? onReachStart;
  final DateTime? initialFocusedTime;
  final int initialVisibleCandleCount;
  final int? visibleCandleCount;
  final bool snapToCandle;
  final bool showInfoOverlay;

  @override
  State<AnimatedKlineChart> createState() => _AnimatedKlineChartState();
}

class _CrosshairState {
  const _CrosshairState({this.show = false, this.index});

  final bool show;
  final int? index;

  _CrosshairState copyWith({bool? show, int? index}) {
    return _CrosshairState(show: show ?? this.show, index: index ?? this.index);
  }

  @override
  bool operator ==(Object other) {
    return other is _CrosshairState &&
        other.show == show &&
        other.index == index;
  }

  @override
  int get hashCode => Object.hash(show, index);
}

class _AnimatedKlineChartState extends State<AnimatedKlineChart> {
  late List<_KlineCandle> _candles;
  int _barSeriesSignature = 0;
  late ChartStyle _style;
  late double _candleWidth;
  late double _scrollOffset;
  double? _prevChartWidth;
  late double _prevCandleWidth;
  double? _initialAnchorUnit;
  final ValueNotifier<_CrosshairState> _crosshair =
      ValueNotifier<_CrosshairState>(const _CrosshairState());
  final ValueNotifier<String> _debugInfo = ValueNotifier<String>('');
  bool _debugMode = false;
  int _lastVisibleCount = 0;
  double? _lastChartWidth;
  final FocusNode _chartFocus = FocusNode();
  Timer? _keyRepeatTimer;
  Timer? _keyRepeatDelay;
  int _keyRepeatDir = 0;
  int _loadingSerial = 0;
  double _keyPanRemainder = 0;
  bool _suppressChartAnimation = false;
  Timer? _animationResetTimer;

  @override
  void initState() {
    super.initState();
    _style = _buildStyle();
    _rebuildCandles();
    if (widget.initialFocusedTime != null) {
      final DateTime target = widget.initialFocusedTime!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _restoreCrosshair(target);
      });
    }
    _scheduleFocusRequest();
  }

  @override
  void dispose() {
    _keyRepeatTimer?.cancel();
    _keyRepeatDelay?.cancel();
    _animationResetTimer?.cancel();
    _stopKeyPan();
    _crosshair.dispose();
    _debugInfo.dispose();
    _chartFocus.dispose();
    super.dispose();
  }

  void _suppressAnimationPulse() {
    if (!_suppressChartAnimation) {
      setState(() {
        _suppressChartAnimation = true;
      });
    }
    _scheduleAnimationReset();
  }

  void _suppressAnimationForNextBuild() {
    _suppressChartAnimation = true;
    _scheduleAnimationReset();
  }

  void _scheduleAnimationReset() {
    _animationResetTimer?.cancel();
    _animationResetTimer = Timer(const Duration(milliseconds: 120), () {
      if (mounted && _suppressChartAnimation) {
        setState(() {
          _suppressChartAnimation = false;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant AnimatedKlineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialFocusedTime != null &&
        widget.initialFocusedTime != oldWidget.initialFocusedTime) {
      final DateTime target = widget.initialFocusedTime!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _restoreCrosshair(target);
      });
    }
    final bool dataIdentityChanged =
        oldWidget.dataIdentity != widget.dataIdentity;
    final int newSignature = _computeBarSeriesSignature(widget.bars);
    final bool barsChanged = newSignature != _barSeriesSignature;
    if (oldWidget.visibleCandleCount != widget.visibleCandleCount) {
      _prevChartWidth = null;
    }
    // 保存加载状态：barsChanged 末尾会清 loadingSerial，dataIdentityChanged 据此判断是否重置视口
    final int loadingSerial = _loadingSerial;
    if (barsChanged) {
      final int oldLen = _candles.length;
      _rebuildCandles(newSignature);
      if (loadingSerial > 0) {
        if (_candles.length > oldLen) {
          final int added = _candles.length - oldLen;
          _scrollOffset += added * _candleWidth;
          // 同步调整十字光标 index，避免数据加载后光标跳到别的蜡烛上
          final _CrosshairState cross = _crosshair.value;
          if (cross.show && cross.index != null) {
            _crosshair.value = _CrosshairState(show: true, index: cross.index! + added);
          }
        }
        _loadingSerial = 0;
      }
    }
    if (dataIdentityChanged) {
      if (loadingSerial == 0) {
        _resetViewportForDatasetChange();
      }
      _scheduleFocusRequest();
      if (loadingSerial == 0) {
        return;
      }
    }
    if (barsChanged) {
      _scheduleFocusRequest();
      final _CrosshairState state = _crosshair.value;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _emitFocusedBarChanged(state);
        }
      });
    }
  }

  void _emitFocusedBarChanged(_CrosshairState state) {
    final ValueChanged<SecurityKlineModel?>? callback =
        widget.onFocusedBarChanged;
    if (callback == null) {
      return;
    }
    if (!state.show || state.index == null || widget.bars.isEmpty) {
      callback(null);
      return;
    }
    final int index = state.index!.clamp(0, widget.bars.length - 1);
    callback(widget.bars[index]);
  }

  void _restoreCrosshair(DateTime target) {
    final int targetMs = target.millisecondsSinceEpoch;
    for (int i = 0; i < _candles.length; i++) {
      if (_candles[i].timestamp == targetMs) {
        _crosshair.value = _CrosshairState(show: true, index: i);
        debugPrint('[chart] crosshair restored index=$i ts=$targetMs candles=${_candles.length}');
        return;
      }
    }
    debugPrint('[chart] crosshair restore NOT FOUND target=$targetMs candles=${_candles.length} firstTs=${_candles.isNotEmpty ? _candles.first.timestamp : "empty"}');
  }

  void _scheduleFocusRequest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _chartFocus.context == null ||
          _chartFocus.hasFocus ||
          !_chartFocus.canRequestFocus) {
        return;
      }
      _chartFocus.requestFocus();
    });
  }

  bool get _useDiscreteViewport => true;

  bool get _snapToCandle =>
      _useDiscreteViewport ||
      widget.snapToCandle ||
      widget.visibleCandleCount != null;

  int _computeBarSeriesSignature(List<SecurityKlineModel> bars) {
    return Object.hashAll(
      bars.map(
        (SecurityKlineModel bar) => Object.hash(
          bar.datetime.millisecondsSinceEpoch,
          bar.open,
          bar.close,
          bar.high,
          bar.low,
          bar.volume,
          bar.amount,
        ),
      ),
    );
  }

  ChartStyle _buildStyle() {
    return ChartStyle(
      volumeHeightFactor: 0.2,
      priceLabelLeftWidth: 46,
      priceLabelWidth: 54,
      timeLabelHeight: 24,
      timeLabelStyle: const TextStyle(
        fontSize: 11,
        color: Color(0xFF3A3A3A),
        fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
      ),
      priceLabelStyle: const TextStyle(
        fontSize: 11,
        color: Color(0xFF3A3A3A),
        fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
      ),
      priceGainColor: const Color(0xFFFF5722),
      priceLossColor: const Color(0xFF00b99a),
      volumeColor: const Color(0xFF00b99a),
      priceGridLineColor: const Color(0xFFEAEAEA),
    );
  }

  void _rebuildCandles([int? signature]) {
    _candles = _KlineCandle.fromBars(widget.bars);
    _barSeriesSignature = signature ?? _computeBarSeriesSignature(widget.bars);
  }

  void _resetViewportForDatasetChange() {
    _stopKeyRepeat();
    _prevChartWidth = null;
    _lastChartWidth = null;
    _lastVisibleCount = 0;
    _hideCrosshair();
    _suppressAnimationForNextBuild();
  }

  @override
  Widget build(BuildContext context) {
    if (_candles.length < 3) {
      return const Center(
        child: Text(
          'K线数据不足',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final size = constraints.biggest;
        final rawWidth =
            size.width - _style.priceLabelWidth - _style.priceLabelLeftWidth;
        final chartWidth = max(1.0, rawWidth);
        _lastChartWidth = chartWidth;
        _handleResize(chartWidth);

        final int start = _startIndex(chartWidth);
        final int end = _endIndex(chartWidth, start);
        final List<_KlineCandle> candlesInRange = _candles
            .getRange(start, end)
            .toList();

        final maxPrice = candlesInRange.map((c) => c.high).reduce(max);
        final minPrice = candlesInRange.map((c) => c.low).reduce(min);
        final maxVol = candlesInRange.map((c) => c.volume).reduce(max);
        final minVol = candlesInRange.map((c) => c.volume).reduce(min);
        _lastVisibleCount = candlesInRange.length;

        final chart = TweenAnimationBuilder<_PainterParams>(
          tween: _PainterParamsTween(
            end: _PainterParams(
              candles: candlesInRange,
              allCandles: _candles,
              style: _style,
              size: size,
              candleWidth: _candleWidth,
              maxPrice: maxPrice,
              minPrice: minPrice,
              maxVol: maxVol,
              minVol: minVol,
              startIndex: start,
              scrollOffset: _scrollOffset,
            ),
          ),
          duration: _suppressChartAnimation
              ? Duration.zero
              : const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          builder: (_, _PainterParams params, _) {
            return SizedBox(
              width: size.width,
              height: size.height,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _ChartBodyPainter(params: params),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _ChartOverlayPainter(
                            params: params,
                            klineCategory: widget.klineCategory,
                            getPriceLabel: _defaultPriceLabel,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: IgnorePointer(
                        child: ValueListenableBuilder<_CrosshairState>(
                          valueListenable: _crosshair,
                          builder: (_, state, _) {
                            return CustomPaint(
                              painter: _CrosshairPainter(
                                params: params,
                                state: state,
                                klineCategory: widget.klineCategory,
                                showInfoOverlay: widget.showInfoOverlay,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  if (_debugMode)
                    Positioned(
                      left: params.chartLeft + 6,
                      top: 6,
                      child: ValueListenableBuilder<String>(
                        valueListenable: _debugInfo,
                        builder: (_, text, _) {
                          return Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.9),
                              border: Border.all(
                                color: AppColors.border,
                                width: 0.6,
                              ),
                            ),
                            child: Text(
                              text,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textPrimary,
                                fontFeatures: <FontFeature>[
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerHover: (event) => _handleHover(event, chartWidth),
          onPointerDown: (event) =>
              _updateCrosshair(event.localPosition, chartWidth),
          onPointerMove: (event) =>
              _updateCrosshair(event.localPosition, chartWidth),
          onPointerSignal: (signal) {
            if (signal is PointerScrollEvent) {
              final RenderBox box = context.findRenderObject() as RenderBox;
              final int? previouslyFocusedIndex = _crosshair.value.show
                  ? _crosshair.value.index
                  : null;
              final Offset localPosition = box.globalToLocal(signal.position);
              _updateCrosshair(localPosition, chartWidth);
              final Offset local =
                  localPosition - Offset(_style.priceLabelLeftWidth, 0);
              final double dy = signal.scrollDelta.dy;
              if (dy.abs() > 0) {
                _onScaleStart(
                  local,
                  chartWidth,
                  anchorUnit: previouslyFocusedIndex == null
                      ? null
                      : previouslyFocusedIndex + 0.5,
                );
                _onScaleUpdate(dy > 0 ? 0.9 : 1.1, local, chartWidth);
              }
            }
          },
          child: MouseRegion(
            onHover: (event) => _handleHover(event, chartWidth),
            child: Focus(
              focusNode: _chartFocus,
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is KeyRepeatEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                      event.logicalKey == LogicalKeyboardKey.arrowRight) {
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                }
                if (event is KeyDownEvent) {
                  if (HardwareKeyboard.instance.isControlPressed &&
                      event.logicalKey == LogicalKeyboardKey.keyD) {
                    setState(() {
                      _debugMode = !_debugMode;
                    });
                    if (!_debugMode) {
                      _debugInfo.value = '';
                    }
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                    _startKeyRepeat(-1);
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                    _startKeyRepeat(1);
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.numpadEnter) {
                    final int? selectedIndex = _crosshair.value.show
                        ? _crosshair.value.index
                        : null;
                    if (selectedIndex != null &&
                        selectedIndex >= 0 &&
                        selectedIndex < widget.bars.length &&
                        widget.onActivateBar != null) {
                      widget.onActivateBar!(widget.bars[selectedIndex]);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.escape) {
                    if (_crosshair.value.show) {
                      _hideCrosshair();
                    }
                    return KeyEventResult.ignored;  // 冒泡到页面层，K线不处理但分时退出
                  }
                } else if (event is KeyUpEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                      event.logicalKey == LogicalKeyboardKey.arrowRight) {
                    _stopKeyRepeat();
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: GestureDetector(
                onScaleStart: (details) => _onScaleStart(
                  details.localFocalPoint -
                      Offset(_style.priceLabelLeftWidth, 0),
                  chartWidth,
                ),
                onScaleUpdate: (details) => _onScaleUpdate(
                  details.scale,
                  details.localFocalPoint -
                      Offset(_style.priceLabelLeftWidth, 0),
                  chartWidth,
                ),
                child: chart,
              ),
            ),
          ),
        );
      },
    );
  }

  String _defaultPriceLabel(double price) => price.toStringAsFixed(2);

  int _minVisibleCandleCount() {
    if (_candles.isEmpty) return 3;
    if (widget.visibleCandleCount != null) {
      return widget.visibleCandleCount!.clamp(3, _candles.length);
    }
    return min(14, _candles.length);
  }

  int _maxVisibleCandleCount() {
    if (_candles.isEmpty) return 3;
    if (widget.visibleCandleCount != null) {
      return widget.visibleCandleCount!.clamp(3, _candles.length);
    }
    return _candles.length;
  }

  int _clampVisibleCandleCount(int count) {
    return count.clamp(_minVisibleCandleCount(), _maxVisibleCandleCount());
  }

  int _visibleCandleCountForWidth(double chartWidth, [double? candleWidth]) {
    if (_candles.isEmpty || chartWidth <= 0) {
      return _minVisibleCandleCount();
    }
    final double width = candleWidth ?? _candleWidth;
    if (width <= 0) {
      return _minVisibleCandleCount();
    }
    return _clampVisibleCandleCount((chartWidth / width).round());
  }

  double _quantizeCandleWidth(double chartWidth, double candleWidth) {
    final int visibleCount = _visibleCandleCountForWidth(
      chartWidth,
      candleWidth,
    );
    return chartWidth / visibleCount;
  }

  void _handleResize(double chartWidth) {
    if (chartWidth == _prevChartWidth) return;
    if (_prevChartWidth != null) {
      final int visibleCount = _visibleCandleCountForWidth(
        _prevChartWidth!,
        _candleWidth,
      );
      final int leftIndex = (_scrollOffset / _candleWidth).round().clamp(
        0,
        max(0, _candles.length - 1),
      );
      _candleWidth = chartWidth / visibleCount;
      _scrollOffset = leftIndex * _candleWidth;
      _scrollOffset = _snapOffset(_scrollOffset, _candleWidth);
      _scrollOffset = _clampScroll(_scrollOffset, chartWidth);
    } else {
      final int count = _clampVisibleCandleCount(
        min(
          _candles.length,
          max(3, widget.visibleCandleCount ?? widget.initialVisibleCandleCount),
        ),
      );
      _candleWidth = chartWidth / count;
      _scrollOffset = max(0, _candles.length * _candleWidth - chartWidth);
      _scrollOffset = _snapOffset(_scrollOffset, _candleWidth);
      _scrollOffset = _clampScroll(_scrollOffset, chartWidth);
    }
    _prevChartWidth = chartWidth;
  }

  double _getMinCandleWidth(double chartWidth) =>
      chartWidth / _maxVisibleCandleCount();

  double _getMaxCandleWidth(double chartWidth) =>
      chartWidth / _minVisibleCandleCount();

  double _maxScrollOffset(double chartWidth, [double? candleWidth]) {
    final double width = candleWidth ?? _candleWidth;
    if (_candles.isEmpty) return 0;
    return max(0, _candles.length * width - chartWidth);
  }

  double _clampScroll(double offset, double chartWidth, [double? candleWidth]) {
    final double width = candleWidth ?? _candleWidth;
    final double maxOffset = _maxScrollOffset(chartWidth, width);
    return offset.clamp(0.0, maxOffset);
  }

  double _clampZoomScroll(
    double offset,
    double chartWidth,
    double candleWidth,
    double focalDx,
  ) {
    if (_candles.isEmpty) {
      return offset;
    }
    final double clampedFocalDx = _clampFocalDx(focalDx, chartWidth);
    final double minOffset = candleWidth / 2 - clampedFocalDx;
    final double maxOffset =
        (_candles.length - 0.5) * candleWidth - clampedFocalDx;
    if (minOffset > maxOffset) {
      return (minOffset + maxOffset) / 2;
    }
    return offset.clamp(minOffset, maxOffset);
  }

  double _snapOffset(double offset, double candleWidth) {
    if (!_snapToCandle) return offset;
    if (candleWidth <= 0) return offset;
    return (offset / candleWidth).round() * candleWidth;
  }

  double _snapOffsetKeepingIndexVisible(
    int index,
    double chartWidth,
    double offset,
    double candleWidth,
  ) {
    if (!_snapToCandle) return offset;
    double snapped = _snapOffset(offset, candleWidth);
    final double left = index * candleWidth;
    final double right = left + candleWidth;
    final double minVisible = right - chartWidth;
    final double maxVisible = left;
    if (minVisible <= maxVisible) {
      snapped = snapped.clamp(minVisible, maxVisible);
    }
    return snapped;
  }

  int _startIndex(double chartWidth) {
    if (_candles.isEmpty) return 0;
    final int idx = (_scrollOffset / _candleWidth).floor();
    return idx.clamp(0, _candles.length - 1);
  }

  int _endIndex(double chartWidth, int startIndex) {
    if (_candles.isEmpty) return 0;
    final int visibleCount = max(1, (chartWidth / _candleWidth).ceil() + 1);
    final int end = startIndex + visibleCount;
    return end.clamp(1, _candles.length);
  }

  int _indexFromDx(double dx, double chartWidth) {
    final double clampedDx = _clampFocalDx(dx, chartWidth);
    final double half = _candleWidth / 2;
    final double globalX = _scrollOffset + clampedDx - half;
    final int idx = (globalX / _candleWidth).round();
    return idx.clamp(0, _candles.length - 1);
  }

  double _scrollOffsetForIndex(
    int index,
    double chartWidth,
    double baseOffset, [
    double? candleWidth,
  ]) {
    final double width = candleWidth ?? _candleWidth;
    final double left = index * width;
    final double right = left + width;
    double next = baseOffset;
    if (left < baseOffset) {
      next = left;
    } else if (right > baseOffset + chartWidth) {
      next = right - chartWidth;
    }
    next = _snapOffsetKeepingIndexVisible(index, chartWidth, next, width);
    return _clampScroll(next, chartWidth, width);
  }

  double _clampFocalDx(double dx, double chartWidth) {
    if (chartWidth <= 0) {
      return 0;
    }
    final double maxDx = chartWidth > 0.001 ? chartWidth - 0.001 : 0.0;
    return dx.clamp(0.0, maxDx);
  }

  int _anchorIndexFromUnit(double anchorUnit) {
    if (_candles.isEmpty) {
      return 0;
    }
    return (anchorUnit - 0.5).round().clamp(0, _candles.length - 1);
  }

  double _ensureIndexPartiallyVisible(
    int index,
    double chartWidth,
    double offset, [
    double? candleWidth,
  ]) {
    if (_candles.isEmpty || chartWidth <= 0) {
      return offset;
    }
    final double width = candleWidth ?? _candleWidth;
    final double halfWidth = width / 2;
    final double center = (index + 0.5) * width - offset;
    if (center + halfWidth <= 0 || center - halfWidth >= chartWidth) {
      return _scrollOffsetForIndex(index, chartWidth, offset, width);
    }
    return offset;
  }

  void _onScaleStart(
    Offset focalPoint,
    double chartWidth, {
    double? anchorUnit,
  }) {
    _prevCandleWidth = _candleWidth;
    if (anchorUnit != null) {
      _initialAnchorUnit = anchorUnit;
      return;
    }
    final double clampedFocalDx = _clampFocalDx(focalPoint.dx, chartWidth);
    _initialAnchorUnit =
        (_scrollOffset + clampedFocalDx) / max(_prevCandleWidth, 0.0001);
  }

  void _onScaleUpdate(double scale, Offset focalPoint, double chartWidth) {
    _suppressAnimationPulse();
    final double rawCandleWidth = (_prevCandleWidth * scale).clamp(
      _getMinCandleWidth(chartWidth),
      _getMaxCandleWidth(chartWidth),
    );
    // 防止手势抖动触发量化跳变：rawCandleWidth 跟当前 _candleWidth 差异 <2% 时保持原值
    final bool intentionalZoom =
        (_candleWidth > 0 && (rawCandleWidth - _candleWidth).abs() / _candleWidth > 0.02);
    final double candleWidth =
        intentionalZoom ? _quantizeCandleWidth(chartWidth, rawCandleWidth) : _candleWidth;
    final double clampedFocalDx = _clampFocalDx(focalPoint.dx, chartWidth);
    final double anchor = _initialAnchorUnit ??
        (_scrollOffset + clampedFocalDx) / max(_candleWidth, 0.001);
    final int anchorIndex = _anchorIndexFromUnit(anchor);
    final double rawOffset = anchor * candleWidth - clampedFocalDx;
    // 手势试图滚过左边界：offset 已接近 0 且手指继续往左拖
    final bool reachedStart = rawOffset < 0 && _scrollOffset < _candleWidth;
    double nextOffset = _clampZoomScroll(
      rawOffset,
      chartWidth,
      candleWidth,
      clampedFocalDx,
    );
    nextOffset = _ensureIndexPartiallyVisible(
      anchorIndex,
      chartWidth,
      nextOffset,
      candleWidth,
    );

    setState(() {
      _candleWidth = candleWidth;
      _scrollOffset = nextOffset;
    });
    // 缩放达到极限时触发加载更多（不依赖 intentionalZoom，因为极限时差值恒为 0）
    final double minW = _getMinCandleWidth(chartWidth);
    final bool zoomedOutToLimit = scale < 1.0 && _candleWidth <= minW * 1.01;
    if ((reachedStart || zoomedOutToLimit) &&
        widget.onReachStart != null && _loadingSerial == 0 && _candles.length >= 3) {
      _loadingSerial = 1;
      final int requestCount = max(110, _maxVisibleCandleCount());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onReachStart?.call(requestCount);
      });
    }
  }

  void _updateCrosshair(Offset localPosition, double chartWidth) {
    final double chartLeft = _style.priceLabelLeftWidth;
    final double chartRight = chartLeft + chartWidth;
    if (localPosition.dx < chartLeft || localPosition.dx > chartRight) {
      _hideCrosshair();
      return;
    }

    final double dx = localPosition.dx - chartLeft;
    final int abs = _indexFromDx(dx, chartWidth);
    final _CrosshairState next = _CrosshairState(show: true, index: abs);
    if (next != _crosshair.value) {
      _crosshair.value = next;
      _emitFocusedBarChanged(next);
    }
    if (!_chartFocus.hasFocus) {
      _chartFocus.requestFocus();
    }
  }

  void _handleHover(PointerHoverEvent event, double chartWidth) {
    if (!_crosshair.value.show && event.delta == Offset.zero) {
      return;
    }
    _updateCrosshair(event.localPosition, chartWidth);
  }

  void _hideCrosshair() {
    if (!_crosshair.value.show) return;
    _crosshair.value = const _CrosshairState();
    _emitFocusedBarChanged(_crosshair.value);
  }

  void _stepCrosshair(int delta) {
    if (_lastVisibleCount <= 0) return;
    final double chartWidth = _lastChartWidth ?? 0;
    if (chartWidth <= 0) return;
    _suppressAnimationPulse();
    final bool hasCrosshair =
        _crosshair.value.show && _crosshair.value.index != null;
    final int nextAbs;
    if (hasCrosshair) {
      final int currentAbs = _crosshair.value.index!.clamp(
        0,
        max(0, _candles.length - 1),
      );
      nextAbs = (currentAbs + delta).clamp(0, max(0, _candles.length - 1));
    } else {
      final int start = _startIndex(chartWidth);
      final int endExclusive = _endIndex(chartWidth, start);
      nextAbs = delta < 0 ? max(start, endExclusive - 1) : start;
    }

    final double nextOffset = _scrollOffsetForIndex(
      nextAbs,
      chartWidth,
      _scrollOffset,
    );
    if (nextOffset != _scrollOffset) {
      setState(() {
        _scrollOffset = nextOffset;
      });
    }

    final _CrosshairState next = _CrosshairState(show: true, index: nextAbs);
    if (next != _crosshair.value) {
      _crosshair.value = next;
      _emitFocusedBarChanged(next);
    }

    if (_debugMode) {
      final double maxOffset = _maxScrollOffset(chartWidth, _candleWidth);
      final double dx = (nextAbs + 0.5) * _candleWidth - nextOffset;
      final double candleLeft = nextAbs * _candleWidth;
      final double candleRight = candleLeft + _candleWidth;
      final double viewLeft = nextOffset;
      final double viewRight = nextOffset + chartWidth;
      _debugInfo.value =
          'abs:$nextAbs  dx:${dx.toStringAsFixed(2)}\n'
          'scroll:${nextOffset.toStringAsFixed(2)}  max:${maxOffset.toStringAsFixed(2)}\n'
          'view:[${viewLeft.toStringAsFixed(2)}, ${viewRight.toStringAsFixed(2)}]\n'
          'candle:[${candleLeft.toStringAsFixed(2)}, ${candleRight.toStringAsFixed(2)}]';
    }
  }

  void _startKeyRepeat(int dir) {
    if (_keyRepeatDir == dir &&
        (_keyRepeatTimer?.isActive == true ||
            _keyRepeatDelay?.isActive == true)) {
      return;
    }
    _keyRepeatTimer?.cancel();
    _keyRepeatDelay?.cancel();
    _keyRepeatDir = dir;
    _keyPanRemainder = 0;
    _stepCrosshair(dir);
    _keyRepeatDelay = Timer(const Duration(milliseconds: 180), () {
      _startKeyPan(dir);
    });
  }

  void _stopKeyRepeat() {
    _keyRepeatTimer?.cancel();
    _keyRepeatTimer = null;
    _keyRepeatDelay?.cancel();
    _keyRepeatDelay = null;
    _stopKeyPan();
    _keyRepeatDir = 0;
    _keyPanRemainder = 0;
  }

  void _startKeyPan(int dir) {
    _stopKeyPan();
    _keyPanRemainder = 0;
    const double dt = 1 / 60;
    _keyRepeatTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _animateKeyPan(dir, dt),
    );
  }

  void _stopKeyPan() {
    _keyRepeatTimer?.cancel();
    _keyRepeatTimer = null;
  }

  void _animateKeyPan(int dir, double dt) {
    final double chartWidth = _lastChartWidth ?? 0;
    if (chartWidth <= 0) return;
    _suppressAnimationPulse();
    const double speed = 24;
    _keyPanRemainder += dir * speed * dt;
    final int step = _keyPanRemainder.truncate();
    if (step == 0) return;
    _keyPanRemainder -= step;
    _stepCrosshair(step);
  }
}
