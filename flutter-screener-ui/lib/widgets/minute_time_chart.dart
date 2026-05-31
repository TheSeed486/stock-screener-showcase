import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models/tdx_models.dart';
import '../theme/app_colors.dart';

part 'minute_chart/minute_time_chart_models.dart';
part 'minute_chart/minute_time_chart_painters.dart';

class MinuteTimeChart extends StatefulWidget {
  const MinuteTimeChart({
    super.key,
    required this.bars,
    required this.preClose,
    required this.currentPrice,
    this.dataIdentity,
    this.showAvg = true,
    this.onStepHistoricalDay,
    this.onExitHistorical,
    this.onFocusedBarChanged,
    this.showInfoOverlay = true,
  });

  final List<MinuteBarModel> bars;
  final double preClose;
  final double currentPrice;
  final Object? dataIdentity;
  final bool showAvg;
  final ValueChanged<int>? onStepHistoricalDay;
  final VoidCallback? onExitHistorical;
  final ValueChanged<MinuteBarModel?>? onFocusedBarChanged;
  final bool showInfoOverlay;

  @override
  State<MinuteTimeChart> createState() => _MinuteTimeChartState();
}

class _MinuteCrosshairState {
  const _MinuteCrosshairState({this.show = false, this.index});

  final bool show;
  final int? index;

  _MinuteCrosshairState copyWith({bool? show, int? index}) {
    return _MinuteCrosshairState(
      show: show ?? this.show,
      index: index ?? this.index,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _MinuteCrosshairState &&
        other.show == show &&
        other.index == index;
  }

  @override
  int get hashCode => Object.hash(show, index);
}

class _MinuteTimeChartState extends State<MinuteTimeChart> {
  final FocusNode _focusNode = FocusNode();
  final ValueNotifier<_MinuteCrosshairState> _crosshair =
      ValueNotifier<_MinuteCrosshairState>(const _MinuteCrosshairState());
  int _animationSeed = 0;
  bool _animateSeries = true;

  @override
  void initState() {
    super.initState();
    _scheduleFocusRequest();
  }

  @override
  void dispose() {
    _crosshair.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MinuteTimeChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool dataIdentityChanged =
        oldWidget.dataIdentity != widget.dataIdentity;
    final bool shouldAnimate =
        !dataIdentityChanged &&
        ((oldWidget.bars.isEmpty && widget.bars.isNotEmpty) ||
            oldWidget.preClose != widget.preClose);
    _animateSeries = shouldAnimate;
    if (dataIdentityChanged) {
      _animationSeed++;
      _animateSeries = false;
      _hideCrosshair();
      _scheduleFocusRequest();
      return;
    }
    if (shouldAnimate) {
      _animationSeed++;
    }
    if (!identical(oldWidget.bars, widget.bars) ||
        oldWidget.bars.length != widget.bars.length) {
      _scheduleFocusRequest();
      final _MinuteCrosshairState state = _crosshair.value;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _emitFocusedBarChanged(state);
        }
      });
    }
  }

  void _scheduleFocusRequest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _focusNode.context == null ||
          _focusNode.hasFocus ||
          !_focusNode.canRequestFocus) {
        return;
      }
      _focusNode.requestFocus();
    });
  }

  void _updateCrosshair(Offset localPosition, MinuteChartMetrics metrics) {
    final double dx = (localPosition.dx - metrics.chartLeft).clamp(
      0.0,
      metrics.chartWidth,
    );
    final int minute = metrics.minuteFromDx(dx);
    final int index = _nearestIndexByMinute(widget.bars, minute);
    final _MinuteCrosshairState next = _MinuteCrosshairState(
      show: true,
      index: index,
    );
    if (next != _crosshair.value) {
      _crosshair.value = next;
      _emitFocusedBarChanged(next);
    }
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  void _hideCrosshair() {
    if (_crosshair.value.show) {
      _crosshair.value = const _MinuteCrosshairState();
      _emitFocusedBarChanged(_crosshair.value);
    }
  }

  void _stepCrosshair(int delta) {
    if (widget.bars.isEmpty) return;
    final bool hasCrosshair =
        _crosshair.value.show && _crosshair.value.index != null;
    final int next = hasCrosshair
        ? ((_crosshair.value.index! + delta).clamp(0, widget.bars.length - 1))
        : (delta < 0 ? widget.bars.length - 1 : 0);
    final _MinuteCrosshairState updated = _MinuteCrosshairState(
      show: true,
      index: next,
    );
    if (updated != _crosshair.value) {
      _crosshair.value = updated;
      _emitFocusedBarChanged(updated);
    }
  }

  void _emitFocusedBarChanged(_MinuteCrosshairState state) {
    final ValueChanged<MinuteBarModel?>? callback = widget.onFocusedBarChanged;
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

  @override
  Widget build(BuildContext context) {
    if (widget.bars.isEmpty) {
      return const Center(
        child: Text(
          '\u5206\u65f6\u6570\u636e\u4e0d\u8db3',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = constraints.biggest;
        final MinuteChartMetrics metrics = MinuteChartMetrics.from(
          size: size,
          bars: widget.bars,
          preClose: widget.preClose,
        );

        final Widget chart = TweenAnimationBuilder<double>(
          key: ValueKey<int>(_animationSeed),
          tween: Tween<double>(begin: _animateSeries ? 0 : 1, end: 1),
          duration: _animateSeries
              ? const Duration(milliseconds: 180)
              : Duration.zero,
          curve: Curves.easeOutCubic,
          builder: (BuildContext context, double progress, Widget? child) {
            return Stack(
              children: <Widget>[
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      // Keep the time band and the minute series in one base
                      // painter so the minute chart stays visually unified.
                      painter: MinuteChartPainter(
                        metrics: metrics,
                        bars: widget.bars,
                        preClose: widget.preClose,
                        showAvg: widget.showAvg,
                        progress: progress,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: RepaintBoundary(
                    child: IgnorePointer(
                      child: ValueListenableBuilder<_MinuteCrosshairState>(
                        valueListenable: _crosshair,
                        builder: (_, state, _) {
                          return CustomPaint(
                            painter: _MinuteCrosshairPainter(
                              metrics: metrics,
                              bars: widget.bars,
                              preClose: widget.preClose,
                              state: state,
                              showInfoOverlay: widget.showInfoOverlay,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) =>
              _updateCrosshair(event.localPosition, metrics),
          onPointerMove: (event) =>
              _updateCrosshair(event.localPosition, metrics),
          onPointerHover: (event) =>
              _updateCrosshair(event.localPosition, metrics),
          child: MouseRegion(
            onHover: (event) => _updateCrosshair(event.localPosition, metrics),
            child: Focus(
              focusNode: _focusNode,
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent || event is KeyRepeatEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
                      widget.onStepHistoricalDay != null) {
                    widget.onStepHistoricalDay!(-1);
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
                      widget.onStepHistoricalDay != null) {
                    widget.onStepHistoricalDay!(1);
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                    _stepCrosshair(-1);
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                    _stepCrosshair(1);
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.escape) {
                    if (_crosshair.value.show) {
                      _hideCrosshair();
                    }
                    return KeyEventResult.ignored;  // 冒泡到页面层统一处理退出
                  }
                }
                return KeyEventResult.ignored;
              },
              child: chart,
            ),
          ),
        );
      },
    );
  }
}
