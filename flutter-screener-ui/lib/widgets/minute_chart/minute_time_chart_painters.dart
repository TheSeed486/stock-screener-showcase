part of '../minute_time_chart.dart';

class MinuteChartPainter extends CustomPainter {
  MinuteChartPainter({
    required this.metrics,
    required this.bars,
    required this.preClose,
    required this.showAvg,
    required this.progress,
  });

  final MinuteChartMetrics metrics;
  final List<MinuteBarModel> bars;
  final double preClose;
  final bool showAvg;
  final double progress;

  static const TextStyle _axisTextStyle = TextStyle(
    fontSize: 11,
    color: AppColors.textSecondary,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    _drawGrid(canvas);
    _drawAxes(canvas);
    _drawTimeLabels(canvas);

    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(
        metrics.chartLeft,
        0,
        metrics.chartWidth,
        metrics.priceHeight,
      ),
    );
    _drawPriceLine(canvas);
    if (showAvg) {
      _drawAvgLine(canvas);
    }
    canvas.restore();

    _drawVolume(canvas);
  }

  void _drawGrid(Canvas canvas) {
    final Paint gridPaint = Paint()
      ..color = AppColors.chartGrid
      ..strokeWidth = 0.4;
    for (final double v in <double>[0, 0.25, 0.5, 0.75, 1]) {
      final double price =
          metrics.maxPrice - (metrics.maxPrice - metrics.minPrice) * v;
      final double y = metrics.priceToY(price);
      canvas.drawLine(
        Offset(metrics.chartLeft, y),
        Offset(metrics.chartRight, y),
        gridPaint,
      );
    }

    for (final double ratio in <double>[0, 0.25, 0.5, 0.75, 1]) {
      final double x = metrics.chartLeft + metrics.chartWidth * ratio;
      canvas.drawLine(
        Offset(x, metrics.infoBandBottom),
        Offset(x, metrics.volumeTop + metrics.volumeHeight),
        gridPaint,
      );
    }

    final Paint bandPaint = Paint()
      ..color = AppColors.divider
      ..strokeWidth = 0.6;
    canvas.drawLine(
      Offset(metrics.chartLeft, metrics.priceHeight),
      Offset(metrics.chartRight, metrics.priceHeight),
      bandPaint,
    );
    canvas.drawLine(
      Offset(metrics.chartLeft, metrics.volumeTop),
      Offset(metrics.chartRight, metrics.volumeTop),
      bandPaint,
    );
  }

  void _drawAxes(Canvas canvas) {
    for (final double v in <double>[0, 0.25, 0.5, 0.75, 1]) {
      final double price =
          metrics.maxPrice - (metrics.maxPrice - metrics.minPrice) * v;
      final double y = metrics.priceToY(price);
      final TextPainter left = TextPainter(
        text: TextSpan(text: price.toStringAsFixed(2), style: _axisTextStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final double leftLabelY = (y - left.height / 2).clamp(
        metrics.infoBandBottom + 2,
        max(metrics.infoBandBottom + 2, metrics.priceBottom - left.height - 2),
      );
      left.paint(
        canvas,
        Offset(max(2, metrics.chartLeft - left.width - 4), leftLabelY),
      );

      final double pct = preClose == 0
          ? 0
          : (price - preClose) / preClose * 100;
      final String pctText = '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%';
      final TextPainter right = TextPainter(
        text: TextSpan(text: pctText, style: _axisTextStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final double rightLabelY = (y - right.height / 2).clamp(
        metrics.infoBandBottom + 2,
        max(metrics.infoBandBottom + 2, metrics.priceBottom - right.height - 2),
      );
      right.paint(canvas, Offset(metrics.chartRight + 4, rightLabelY));
    }
  }

  void _drawTimeLabels(Canvas canvas) {
    const List<int> minutes = <int>[0, 60, 120, 180, 239];
    const List<String> labels = <String>[
      '09:30',
      '10:30',
      '11:30/13:00',
      '14:00',
      '15:00',
    ];
    for (int i = 0; i < minutes.length; i++) {
      final double x = metrics.minuteToX(minutes[i]);
      final TextPainter tp = TextPainter(
        text: TextSpan(text: labels[i], style: _axisTextStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final double minX = metrics.chartLeft + 2;
      final double maxX = metrics.chartRight - tp.width - 2;
      double drawX = x - tp.width / 2;
      if (maxX >= minX) {
        drawX = drawX.clamp(minX, maxX);
      } else {
        drawX = minX;
      }
      final double y =
          metrics.priceHeight + (metrics.timeBandHeight - tp.height) / 2;
      tp.paint(canvas, Offset(drawX, y));
    }
  }

  void _drawPriceLine(Canvas canvas) {
    final List<Offset> points = <Offset>[];
    for (final MinuteBarModel bar in bars) {
      final double x = metrics.minuteToX(bar.minute);
      final double target = bar.price;
      final double price =
          preClose + (target - preClose) * progress.clamp(0.0, 1.0);
      final double y = metrics.priceToY(price);
      points.add(Offset(x, y));
    }
    if (points.length < 2) return;

    final Path linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }

    final Path fillPath = Path()..moveTo(points.first.dx, metrics.priceHeight);
    for (final Offset point in points) {
      fillPath.lineTo(point.dx, point.dy);
    }
    fillPath
      ..lineTo(points.last.dx, metrics.priceHeight)
      ..close();

    final Paint fillPaint = Paint()
      ..shader =
          LinearGradient(
            colors: <Color>[
              AppColors.brand.withValues(alpha: 0.22),
              AppColors.brand.withValues(alpha: 0.02),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(
            Rect.fromLTWH(
              metrics.chartLeft,
              0,
              metrics.chartWidth,
              metrics.priceHeight,
            ),
          )
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    _drawPreCloseAxisLine(canvas);

    final Paint linePaint = Paint()
      ..color = AppColors.brand
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;
    canvas.drawPath(linePath, linePaint);
  }

  void _drawAvgLine(Canvas canvas) {
    if (bars.length < 2) return;
    final Path avgPath = Path();
    for (int i = 0; i < bars.length; i++) {
      final MinuteBarModel bar = bars[i];
      final double x = metrics.minuteToX(bar.minute);
      final double target = bar.avg;
      final double price =
          preClose + (target - preClose) * progress.clamp(0.0, 1.0);
      final double y = metrics.priceToY(price);
      if (i == 0) {
        avgPath.moveTo(x, y);
      } else {
        avgPath.lineTo(x, y);
      }
    }
    final Paint avgPaint = Paint()
      ..color = const Color(0xFFFFA43A)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawPath(avgPath, avgPaint);
  }

  void _drawPreCloseAxisLine(Canvas canvas) {
    if (preClose <= 0) return;
    final double y = metrics
        .priceToY(preClose)
        .clamp(metrics.infoBandBottom, metrics.priceBottom);
    final Paint paint = Paint()
      ..color = AppColors.textMuted.withValues(alpha: 0.9)
      ..strokeWidth = 1.0;
    _drawDashedLine(
      canvas,
      Offset(metrics.chartLeft, y),
      Offset(metrics.chartRight, y),
      paint,
    );
  }

  void _drawVolume(Canvas canvas) {
    if (bars.isEmpty) return;
    final List<int> volumes = <int>[];
    for (int i = 0; i < bars.length; i++) {
      final int prev = i == 0 ? 0 : bars[i - 1].volume;
      final int delta = max(0, bars[i].volume - prev);
      volumes.add(delta);
    }
    final int maxVolume = volumes.reduce(max);
    if (maxVolume <= 0) return;

    final double barWidth = max(
      1.0,
      metrics.chartWidth / (MinuteChartMetrics.totalSlots - 1) * 0.65,
    );
    for (int i = 0; i < bars.length; i++) {
      final MinuteBarModel bar = bars[i];
      final double x = metrics.minuteToX(bar.minute);
      final double ratio = volumes[i] / maxVolume;
      final double height = metrics.volumeHeight * ratio * progress;
      final double top = metrics.volumeTop + metrics.volumeHeight - height;
      final double left = x - barWidth / 2;
      final Color color = i == 0
          ? AppColors.neutral
          : (bar.price >= bars[i - 1].price ? AppColors.rise : AppColors.fall);
      final Rect rect = Rect.fromLTWH(left, top, barWidth, height);
      canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.65));
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const double dash = 3;
    const double gap = 3;
    final double total = (end - start).distance;
    if (total <= 0) return;
    final double dx = end.dx - start.dx;
    final double dy = end.dy - start.dy;
    double progress = 0;
    while (progress < total) {
      final double len = min(dash, total - progress);
      final double t0 = progress / total;
      final double t1 = (progress + len) / total;
      final Offset p0 = Offset(start.dx + dx * t0, start.dy + dy * t0);
      final Offset p1 = Offset(start.dx + dx * t1, start.dy + dy * t1);
      canvas.drawLine(p0, p1, paint);
      progress += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant MinuteChartPainter oldDelegate) {
    return oldDelegate.bars != bars ||
        oldDelegate.preClose != preClose ||
        oldDelegate.progress != progress ||
        oldDelegate.metrics != metrics ||
        oldDelegate.showAvg != showAvg;
  }
}

class _MinuteCrosshairPainter extends CustomPainter {
  _MinuteCrosshairPainter({
    required this.metrics,
    required this.bars,
    required this.preClose,
    required this.state,
    required this.showInfoOverlay,
  });

  final MinuteChartMetrics metrics;
  final List<MinuteBarModel> bars;
  final double preClose;
  final _MinuteCrosshairState state;
  final bool showInfoOverlay;

  @override
  void paint(Canvas canvas, Size size) {
    if (!state.show || bars.isEmpty) return;
    final int index = (state.index ?? (bars.length - 1)).clamp(
      0,
      bars.length - 1,
    );
    final MinuteBarModel bar = bars[index];
    final double x = metrics.minuteToX(bar.minute);
    final double y = metrics.priceToY(bar.price);

    final Paint crossPaint = Paint()
      ..color = const Color(0xFF9E9E9E)
      ..strokeWidth = 0.6;
    canvas.drawLine(
      Offset(x, metrics.infoBandBottom),
      Offset(x, metrics.volumeTop + metrics.volumeHeight),
      crossPaint,
    );
    canvas.drawLine(
      Offset(metrics.chartLeft, y),
      Offset(metrics.chartRight, y),
      crossPaint,
    );

    _drawPriceLabel(canvas, y);
    _drawTimeLabel(canvas, bar.minute);
    if (showInfoOverlay) {
      _drawInfo(canvas, bar);
    }
  }

  void _drawPriceLabel(Canvas canvas, double y) {
    final String label = metrics.yToPrice(y).toStringAsFixed(2);
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: 11,
          color: AppColors.textPrimary,
          fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final double padX = 6;
    final double padY = 3;
    final double boxW = tp.width + padX * 2;
    final double boxH = tp.height + padY * 2;
    final double minY = metrics.infoBandBottom + 2;
    final double maxY = metrics.priceBottom - boxH - 2;
    double boxY = y - boxH / 2;
    if (maxY >= minY) {
      boxY = boxY.clamp(minY, maxY);
    } else {
      boxY = minY;
    }

    void drawBox(double boxX) {
      final Rect rect = Rect.fromLTWH(boxX, boxY, boxW, boxH);
      canvas.drawRect(rect, Paint()..color = Colors.white);
      canvas.drawRect(
        rect,
        Paint()
          ..color = AppColors.border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6,
      );
      tp.paint(canvas, Offset(boxX + padX, boxY + padY));
    }

    drawBox(metrics.chartRight + 2);
    final double leftBoxX = max(2, metrics.chartLeft - boxW - 4);
    drawBox(leftBoxX);
  }

  void _drawTimeLabel(Canvas canvas, int minute) {
    final String label = _formatMinuteLabel(minute);
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: 11,
          color: AppColors.textPrimary,
          fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final double padX = 6;
    final double padY = 2;
    final double boxW = tp.width + padX * 2;
    final double boxH = tp.height + padY * 2;
    final double minX = metrics.chartLeft + 2;
    final double maxX = metrics.chartRight - boxW - 2;
    double boxX = metrics.minuteToX(minute) - boxW / 2;
    if (maxX >= minX) {
      boxX = boxX.clamp(minX, maxX);
    } else {
      boxX = minX;
    }
    final double boxY =
        metrics.priceHeight + (metrics.timeBandHeight - boxH) / 2;
    final Rect rect = Rect.fromLTWH(boxX, boxY, boxW, boxH);
    canvas.drawRect(rect, Paint()..color = Colors.white);
    canvas.drawRect(
      rect,
      Paint()
        ..color = AppColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6,
    );
    tp.paint(canvas, Offset(boxX + padX, boxY + padY));
  }

  void _drawInfo(Canvas canvas, MinuteBarModel bar) {
    final double pct = preClose == 0
        ? 0
        : (bar.price - preClose) / preClose * 100;
    final Color color = pct >= 0 ? AppColors.rise : AppColors.fall;
    final String text =
        '${_formatMinuteLabel(bar.minute)}  '
        '\u4ef7\u683c ${bar.price.toStringAsFixed(2)}  '
        '\u5747\u4ef7 ${bar.avg.toStringAsFixed(2)}  '
        '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%';
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: max(0.0, metrics.chartWidth - 8));
    tp.paint(canvas, Offset(metrics.chartLeft + 4, 2));
  }

  @override
  bool shouldRepaint(covariant _MinuteCrosshairPainter oldDelegate) {
    return oldDelegate.state != state ||
        oldDelegate.metrics != metrics ||
        oldDelegate.bars != bars ||
        oldDelegate.preClose != preClose ||
        oldDelegate.showInfoOverlay != showInfoOverlay;
  }
}
