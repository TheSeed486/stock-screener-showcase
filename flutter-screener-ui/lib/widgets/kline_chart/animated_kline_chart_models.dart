part of '../animated_kline_chart.dart';

class _KlineCandle {
  _KlineCandle({
    required this.timestamp,
    required this.open,
    required this.close,
    required this.high,
    required this.low,
    required this.volume,
  });

  final int timestamp;
  final double open;
  final double close;
  final double high;
  final double low;
  final double volume;

  bool sameData(_KlineCandle other) {
    return timestamp == other.timestamp &&
        open == other.open &&
        close == other.close &&
        high == other.high &&
        low == other.low &&
        volume == other.volume;
  }

  static List<_KlineCandle> fromBars(List<SecurityKlineModel> bars) {
    if (bars.isEmpty) return <_KlineCandle>[];
    return List<_KlineCandle>.generate(bars.length, (int i) {
      final b = bars[i];
      return _KlineCandle(
        timestamp: b.datetime.millisecondsSinceEpoch,
        open: b.open,
        close: b.close,
        high: b.high,
        low: b.low,
        volume: b.volume,
      );
    });
  }
}

class ChartStyle {
  final double volumeHeightFactor;
  final double priceLabelLeftWidth;
  final double priceLabelWidth;
  final double timeLabelHeight;
  final TextStyle timeLabelStyle;
  final TextStyle priceLabelStyle;
  final Color priceGainColor;
  final Color priceLossColor;
  final Color volumeColor;
  final Color priceGridLineColor;

  const ChartStyle({
    this.volumeHeightFactor = 0.2,
    this.priceLabelLeftWidth = 46.0,
    this.priceLabelWidth = 48.0,
    this.timeLabelHeight = 24.0,
    this.timeLabelStyle = const TextStyle(fontSize: 16, color: Colors.grey),
    this.priceLabelStyle = const TextStyle(fontSize: 12, color: Colors.grey),
    this.priceGainColor = Colors.green,
    this.priceLossColor = Colors.red,
    this.volumeColor = Colors.grey,
    this.priceGridLineColor = Colors.grey,
  });
}

class _PainterParams {
  final List<_KlineCandle> candles;
  final List<_KlineCandle> allCandles;
  final ChartStyle style;
  final Size size;
  final double candleWidth;
  final int startIndex;
  final double scrollOffset;
  final double maxPrice;
  final double minPrice;
  final double maxVol;
  final double minVol;

  _PainterParams({
    required this.candles,
    required this.allCandles,
    required this.style,
    required this.size,
    required this.candleWidth,
    required this.startIndex,
    required this.scrollOffset,
    required this.maxPrice,
    required this.minPrice,
    required this.maxVol,
    required this.minVol,
  });

  double get chartLeft => style.priceLabelLeftWidth;
  double get chartWidth =>
      max(1.0, size.width - style.priceLabelWidth - style.priceLabelLeftWidth);
  double get chartHeight => size.height - style.timeLabelHeight;
  double get volumeHeight => chartHeight * style.volumeHeightFactor;
  double get priceHeight => chartHeight - volumeHeight - timeBandHeight;
  double get timeBandHeight => timeBand;
  double get plotRight => chartLeft + chartWidth;
  double get volumeTop => priceHeight + timeBandHeight + volumeGap;
  double get volumeBottom => chartHeight - volumeBottomPadding;
  double get volumeUsableHeight => max(1.0, volumeBottom - volumeTop);
  double get infoBandTop => 0.0;
  double get infoBandBottom => infoBandHeight;
  double get pricePaddingTop => infoBandBottom + infoBandGap + priceTopPadding;
  double get pricePaddingBottom => priceBottomPadding;

  int getCandleIndexFromOffset(double x) {
    if (candles.isEmpty) return 0;
    final double globalX = scrollOffset + x;
    final int abs = (globalX / candleWidth).floor();
    final int rel = abs - startIndex;
    return rel.clamp(0, candles.length - 1);
  }

  double chartXForAbsoluteIndex(int absIndex) {
    return (absIndex + 0.5) * candleWidth - scrollOffset;
  }

  double canvasXForAbsoluteIndex(int absIndex) {
    return chartLeft + chartXForAbsoluteIndex(absIndex);
  }

  List<int> timeMarkerAbsoluteIndices({int minSpacingPx = 90}) {
    if (candles.isEmpty) {
      return const <int>[];
    }
    final int markerCount = max(1, chartWidth ~/ minSpacingPx);
    final Set<int> seen = <int>{};
    final List<int> indices = <int>[];
    for (int i = 1; i <= markerCount; i++) {
      final int relIndex = ((candles.length * i) / (markerCount + 1))
          .round()
          .clamp(0, candles.length - 1);
      final int absIndex = startIndex + relIndex;
      if (seen.add(absIndex)) {
        indices.add(absIndex);
      }
    }
    return indices;
  }

  double fitPrice(double y) {
    final double usable = max(
      1.0,
      priceHeight - pricePaddingTop - pricePaddingBottom,
    );
    return pricePaddingTop + usable * (maxPrice - y) / (maxPrice - minPrice);
  }

  double priceFromY(double y) {
    final double usable = max(
      1.0,
      priceHeight - pricePaddingTop - pricePaddingBottom,
    );
    final double t = ((y - pricePaddingTop) / usable).clamp(0.0, 1.0);
    return maxPrice - t * (maxPrice - minPrice);
  }

  double fitVolume(double y) {
    if (maxVol <= minVol) {
      return volumeTop + volumeUsableHeight / 2;
    }
    final double ratio = ((y - minVol) / (maxVol - minVol)).clamp(0.0, 1.0);
    return volumeBottom - ratio * volumeUsableHeight;
  }

  static const double volumeGap = 6.0;
  static const double volumeBottomPadding = 2.0;
  static const double timeBand = 14.0;
  static const double infoBandHeight = 18.0;
  static const double infoBandGap = 4.0;
  static const double priceTopPadding = 6.0;
  static const double priceBottomPadding = 20.0;

  static _PainterParams lerp(_PainterParams a, _PainterParams b, double t) {
    double lerpField(double Function(_PainterParams p) getField) =>
        lerpDouble(getField(a), getField(b), t)!;
    return _PainterParams(
      candles: b.candles,
      allCandles: b.allCandles,
      style: b.style,
      size: b.size,
      candleWidth: b.candleWidth,
      startIndex: b.startIndex,
      scrollOffset: b.scrollOffset,
      maxPrice: lerpField((p) => p.maxPrice),
      minPrice: lerpField((p) => p.minPrice),
      maxVol: lerpField((p) => p.maxVol),
      minVol: lerpField((p) => p.minVol),
    );
  }

  bool shouldRepaint(_PainterParams other) {
    if (size != other.size ||
        candleWidth != other.candleWidth ||
        startIndex != other.startIndex ||
        scrollOffset != other.scrollOffset) {
      return true;
    }
    if (maxPrice != other.maxPrice ||
        minPrice != other.minPrice ||
        maxVol != other.maxVol ||
        minVol != other.minVol) {
      return true;
    }
    if (!_sameKlineCandleSeries(candles, other.candles)) return true;
    if (!_sameKlineCandleSeries(allCandles, other.allCandles)) return true;
    if (style != other.style) return true;
    return false;
  }
}

bool _sameKlineCandleSeries(List<_KlineCandle> a, List<_KlineCandle> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (int index = 0; index < a.length; index += 1) {
    if (!a[index].sameData(b[index])) {
      return false;
    }
  }
  return true;
}

class _PainterParamsTween extends Tween<_PainterParams> {
  _PainterParamsTween({required _PainterParams super.end});

  @override
  _PainterParams lerp(double t) => _PainterParams.lerp(begin ?? end!, end!, t);
}

typedef PriceLabelGetter = String Function(double price);
