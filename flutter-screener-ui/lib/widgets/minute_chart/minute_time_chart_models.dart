part of '../minute_time_chart.dart';

class MinuteChartMetrics {
  const MinuteChartMetrics._({
    required this.size,
    required this.bars,
    required this.preClose,
    required this.chartLeft,
    required this.chartWidth,
    required this.priceHeight,
    required this.volumeHeight,
    required this.volumeTop,
    required this.timeBandHeight,
    required this.minPrice,
    required this.maxPrice,
  });

  factory MinuteChartMetrics.from({
    required Size size,
    required List<MinuteBarModel> bars,
    required double preClose,
  }) {
    const double leftAxisWidth = 46;
    const double rightAxisWidth = 54;
    const double timeBandHeight = 20;
    const double volumeHeightFactor = 0.22;
    final double chartWidth = max(
      1.0,
      size.width - leftAxisWidth - rightAxisWidth,
    );
    final double chartHeight = size.height;
    final double volumeHeight = chartHeight * volumeHeightFactor;
    final double priceHeight = max(
      1.0,
      chartHeight - volumeHeight - timeBandHeight,
    );

    double minPrice = preClose;
    double maxPrice = preClose;
    for (final MinuteBarModel bar in bars) {
      minPrice = min(minPrice, bar.price);
      maxPrice = max(maxPrice, bar.price);
      minPrice = min(minPrice, bar.avg);
      maxPrice = max(maxPrice, bar.avg);
    }

    if (preClose > 0) {
      double delta = max(
        (maxPrice - preClose).abs(),
        (preClose - minPrice).abs(),
      );
      if (delta == 0) {
        delta = max(0.01, preClose * 0.002);
      }
      minPrice = preClose - delta;
      maxPrice = preClose + delta;
    } else if (minPrice == maxPrice) {
      minPrice -= 1;
      maxPrice += 1;
    }

    return MinuteChartMetrics._(
      size: size,
      bars: bars,
      preClose: preClose,
      chartLeft: leftAxisWidth,
      chartWidth: chartWidth,
      priceHeight: priceHeight,
      volumeHeight: volumeHeight,
      volumeTop: priceHeight + timeBandHeight,
      timeBandHeight: timeBandHeight,
      minPrice: minPrice,
      maxPrice: maxPrice,
    );
  }

  final Size size;
  final List<MinuteBarModel> bars;
  final double preClose;
  final double chartLeft;
  final double chartWidth;
  final double priceHeight;
  final double volumeHeight;
  final double volumeTop;
  final double timeBandHeight;
  final double minPrice;
  final double maxPrice;

  static const int totalSlots = 240;

  double get chartRight => chartLeft + chartWidth;
  double get infoBandBottom => 18.0;
  double get priceTop => infoBandBottom + 4.0 + 6.0;
  double get priceBottom => max(priceTop + 1, priceHeight - 20.0);
  double get priceUsableHeight => max(1.0, priceBottom - priceTop);

  double priceToY(double price) {
    final double range = max(0.0001, maxPrice - minPrice);
    final double ratio = ((maxPrice - price) / range).clamp(0.0, 1.0);
    return priceTop + ratio * priceUsableHeight;
  }

  double yToPrice(double y) {
    final double range = max(0.0001, maxPrice - minPrice);
    final double ratio = ((y - priceTop) / priceUsableHeight).clamp(0.0, 1.0);
    return maxPrice - ratio * range;
  }

  double minuteToX(int minute) {
    final double ratio = (minute / max(1, totalSlots - 1)).clamp(0.0, 1.0);
    return chartLeft + ratio * chartWidth;
  }

  int minuteFromDx(double dx) {
    if (chartWidth <= 0) return 0;
    final double ratio = (dx / chartWidth).clamp(0.0, 1.0);
    return (ratio * (totalSlots - 1)).round();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is MinuteChartMetrics &&
        other.size == size &&
        identical(other.bars, bars) &&
        other.preClose == preClose &&
        other.chartLeft == chartLeft &&
        other.chartWidth == chartWidth &&
        other.priceHeight == priceHeight &&
        other.volumeHeight == volumeHeight &&
        other.volumeTop == volumeTop &&
        other.timeBandHeight == timeBandHeight &&
        other.minPrice == minPrice &&
        other.maxPrice == maxPrice;
  }

  @override
  int get hashCode => Object.hash(
    size,
    bars,
    preClose,
    chartLeft,
    chartWidth,
    priceHeight,
    volumeHeight,
    volumeTop,
    timeBandHeight,
    minPrice,
    maxPrice,
  );
}

String _formatMinuteLabel(int minute) {
  int totalMinutes;
  if (minute < 120) {
    totalMinutes = 9 * 60 + 30 + minute;
  } else {
    totalMinutes = 13 * 60 + (minute - 120);
  }
  final int hh = totalMinutes ~/ 60;
  final int mm = totalMinutes % 60;
  return '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
}

int _nearestIndexByMinute(List<MinuteBarModel> bars, int targetMinute) {
  if (bars.isEmpty) return 0;
  int low = 0;
  int high = bars.length - 1;
  while (low <= high) {
    final int mid = (low + high) >> 1;
    final int minute = bars[mid].minute;
    if (minute == targetMinute) {
      return mid;
    }
    if (minute < targetMinute) {
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  if (low <= 0) return 0;
  if (low >= bars.length) return bars.length - 1;
  final int before = low - 1;
  final int after = low;
  final int diffBefore = (bars[before].minute - targetMinute).abs();
  final int diffAfter = (bars[after].minute - targetMinute).abs();
  return diffBefore <= diffAfter ? before : after;
}
