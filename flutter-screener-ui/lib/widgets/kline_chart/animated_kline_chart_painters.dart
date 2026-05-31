part of '../animated_kline_chart.dart';

class _ChartBodyPainter extends CustomPainter {
  _ChartBodyPainter({required this.params});

  final _PainterParams params;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    _drawGrid(canvas, params);

    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(params.chartLeft, 0, params.chartWidth, params.chartHeight),
    );
    canvas.translate(params.chartLeft, 0);
    for (int i = 0; i < params.candles.length; i++) {
      final int absIndex = params.startIndex + i;
      final double x =
          (absIndex + 0.5) * params.candleWidth - params.scrollOffset;
      _drawSingleDay(canvas, params, i, x);
    }
    canvas.restore();

    _drawExtremes(canvas, params);
  }

  void _drawGrid(Canvas canvas, _PainterParams params) {
    final grid = Paint()
      ..color = params.style.priceGridLineColor
      ..strokeWidth = 0.4
      ..style = PaintingStyle.stroke;

    for (final v in <double>[0, 0.25, 0.5, 0.75, 1]) {
      final y = ((params.maxPrice - params.minPrice) * v) + params.minPrice;
      final dy = params.fitPrice(y);
      canvas.drawLine(
        Offset(params.chartLeft, dy),
        Offset(params.chartLeft + params.chartWidth, dy),
        grid,
      );
    }

    for (final int absIndex in params.timeMarkerAbsoluteIndices()) {
      final double x = params.canvasXForAbsoluteIndex(absIndex);
      if (x <= params.chartLeft || x >= params.plotRight) {
        continue;
      }
      canvas.drawLine(
        Offset(x, params.infoBandBottom),
        Offset(x, params.priceHeight),
        grid,
      );
    }
  }

  void _drawSingleDay(Canvas canvas, _PainterParams params, int i, double x) {
    final candle = params.candles[i];
    final double bodyWidth = max(params.candleWidth * 0.56, 1.0);
    final double wickWidth = max(params.candleWidth * 0.025, 0.3);
    final double borderWidth = max(0.3, bodyWidth * 0.03);

    final bool isUp = candle.close >= candle.open;
    final Color color = isUp
        ? params.style.priceGainColor
        : params.style.priceLossColor;

    final double openY = params.fitPrice(candle.open);
    final double closeY = params.fitPrice(candle.close);
    final double highY = params.fitPrice(candle.high);
    final double lowY = params.fitPrice(candle.low);

    final Paint wickPaint = Paint()
      ..strokeWidth = wickWidth
      ..strokeCap = StrokeCap.square
      ..color = color;
    canvas.drawLine(Offset(x, highY), Offset(x, lowY), wickPaint);

    final double top = min(openY, closeY);
    final double bottom = max(openY, closeY);
    final double bodyHeight = max(1.0, bottom - top);
    final Rect bodyRect = Rect.fromLTWH(
      x - bodyWidth / 2,
      top,
      bodyWidth,
      bodyHeight,
    );
    if (isUp) {
      final Paint bodyFill = Paint()
        ..style = PaintingStyle.fill
        ..color = AppColors.background;
      final Paint bodyStroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..color = color;
      canvas.drawRect(bodyRect, bodyFill);
      canvas.drawRect(bodyRect, bodyStroke);
    } else {
      final Paint bodyFill = Paint()
        ..style = PaintingStyle.fill
        ..color = color;
      final Paint bodyStroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..color = color;
      canvas.drawRect(bodyRect, bodyFill);
      canvas.drawRect(bodyRect, bodyStroke);
    }

    final double volumeBase = params.volumeBottom;
    final double volumeTop = params.fitVolume(candle.volume);
    final double volHeight = max(1.0, volumeBase - volumeTop);
    final Rect volRect = Rect.fromLTWH(
      x - bodyWidth / 2,
      volumeBase - volHeight,
      bodyWidth,
      volHeight,
    );
    if (isUp) {
      final Paint volFill = Paint()
        ..style = PaintingStyle.fill
        ..color = AppColors.background;
      final Paint volStroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..color = color.withValues(alpha: 0.9);
      canvas.drawRect(volRect, volFill);
      canvas.drawRect(volRect, volStroke);
    } else {
      final Paint volFill = Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.9);
      final Paint volStroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..color = color.withValues(alpha: 0.9);
      canvas.drawRect(volRect, volFill);
      canvas.drawRect(volRect, volStroke);
    }
  }

  void _drawExtremes(Canvas canvas, _PainterParams params) {
    if (params.candles.isEmpty) return;
    int? highIndex;
    int? lowIndex;
    double? maxPrice;
    double? minPrice;
    for (int i = 0; i < params.candles.length; i++) {
      final int absIndex = params.startIndex + i;
      final double candleLeft =
          absIndex * params.candleWidth - params.scrollOffset;
      final double candleRight = candleLeft + params.candleWidth;
      if (candleRight <= 0 || candleLeft >= params.chartWidth) {
        continue;
      }
      final c = params.candles[i];
      if (maxPrice == null || c.high > maxPrice) {
        maxPrice = c.high;
        highIndex = i;
      }
      if (minPrice == null || c.low < minPrice) {
        minPrice = c.low;
        lowIndex = i;
      }
    }
    if (highIndex == null ||
        lowIndex == null ||
        maxPrice == null ||
        minPrice == null) {
      return;
    }

    void drawTag(int index, double price, bool isHigh) {
      const double sideInset = 8.0;
      final int absIndex = params.startIndex + index;
      final double rawX =
          params.chartLeft +
          (absIndex + 0.5) * params.candleWidth -
          params.scrollOffset;
      final double x = rawX.clamp(
        params.chartLeft + sideInset,
        params.plotRight - sideInset,
      );
      final double y = params.fitPrice(price);
      final double lineLen = 12;
      final Paint linePaint = Paint()
        ..color = const Color(0xFF1F1F1F)
        ..strokeWidth = 0.8;
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: price.toStringAsFixed(2),
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF1F1F1F),
            fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final double safeLeft = params.chartLeft + sideInset;
      final double safeRight = params.plotRight - sideInset;
      final bool preferRight = x + lineLen + 4 + tp.width <= safeRight;
      final Offset lineStart = Offset(x, y);
      final Offset lineEnd = Offset(
        preferRight ? min(safeRight, x + lineLen) : max(safeLeft, x - lineLen),
        y,
      );
      canvas.drawLine(lineStart, lineEnd, linePaint);
      final double textY = isHigh
          ? max(params.infoBandBottom + 2, y - tp.height - 2)
          : min(params.priceHeight - tp.height - 2, y + 2);
      final double textX = preferRight
          ? min(safeRight - tp.width, lineEnd.dx + 4)
          : max(safeLeft, lineEnd.dx - tp.width - 4);
      tp.paint(canvas, Offset(textX, textY));
    }

    drawTag(highIndex, maxPrice, true);
    drawTag(lowIndex, minPrice, false);
  }

  @override
  bool shouldRepaint(_ChartBodyPainter oldDelegate) {
    final a = params;
    final b = oldDelegate.params;
    if (a.size != b.size ||
        a.candleWidth != b.candleWidth ||
        a.startIndex != b.startIndex ||
        a.scrollOffset != b.scrollOffset) {
      return true;
    }
    if (a.maxPrice != b.maxPrice ||
        a.minPrice != b.minPrice ||
        a.maxVol != b.maxVol ||
        a.minVol != b.minVol) {
      return true;
    }
    if (!_sameKlineCandleSeries(a.candles, b.candles)) return true;
    if (a.style != b.style) return true;
    return false;
  }
}

class _ChartOverlayPainter extends CustomPainter {
  _ChartOverlayPainter({
    required this.params,
    required this.klineCategory,
    required this.getPriceLabel,
  });

  final _PainterParams params;
  final KlineCategory klineCategory;
  final PriceLabelGetter getPriceLabel;

  @override
  void paint(Canvas canvas, Size size) {
    _drawTimeBandBackground(canvas, params);
    _drawTimeLabels(canvas, params);
    _drawPriceLabels(canvas, params);
  }

  void _drawTimeBandBackground(Canvas canvas, _PainterParams params) {
    final Rect bandRect = Rect.fromLTWH(
      params.chartLeft,
      params.priceHeight,
      params.chartWidth,
      params.timeBandHeight,
    );
    canvas.drawRect(bandRect, Paint()..color = Colors.white);
  }

  void _drawTimeLabels(Canvas canvas, _PainterParams params) {
    final double band = params.timeBandHeight;
    final double minY = params.priceHeight + 1;
    DateTime? previousMarkerTime;
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(
        params.chartLeft,
        params.priceHeight,
        params.chartWidth,
        params.timeBandHeight,
      ),
    );
    for (final int absIndex in params.timeMarkerAbsoluteIndices()) {
      if (absIndex < 0 || absIndex >= params.allCandles.length) {
        continue;
      }
      final _KlineCandle candle = params.allCandles[absIndex];
      final int visibleDataCount = params.candles.length;
      final DateTime currentTime = DateTime.fromMillisecondsSinceEpoch(
        candle.timestamp,
      );
      final TextPainter timeTp = TextPainter(
        text: TextSpan(
          text: formatKlineAxisLabel(
            currentTime,
            category: klineCategory,
            visibleDataCount: visibleDataCount,
            previousValue: previousMarkerTime,
          ),
          style: params.style.timeLabelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final double maxY = params.priceHeight + band - timeTp.height - 1;
      double y = params.priceHeight + max(1.0, (band - timeTp.height) / 2);
      if (maxY >= minY) {
        y = y.clamp(minY, maxY);
      } else {
        y = minY;
      }
      final double x = params.canvasXForAbsoluteIndex(absIndex);
      timeTp.paint(canvas, Offset(x - timeTp.width / 2, y));
      previousMarkerTime = currentTime;
    }
    canvas.restore();
  }

  void _drawPriceLabels(Canvas canvas, _PainterParams params) {
    for (final double v in <double>[0, 0.25, 0.5, 0.75, 1]) {
      final double y =
          ((params.maxPrice - params.minPrice) * v) + params.minPrice;
      final TextPainter priceTp = TextPainter(
        text: TextSpan(
          text: getPriceLabel(y),
          style: params.style.priceLabelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final double labelY = (params.fitPrice(y) - priceTp.height / 2).clamp(
        params.infoBandBottom + 2,
        max(2.0, params.priceHeight - priceTp.height - 2),
      );
      final double leftX = max(2, params.chartLeft - priceTp.width - 4);
      priceTp.paint(canvas, Offset(leftX, labelY));
      priceTp.paint(canvas, Offset(params.plotRight + 4, labelY));
    }
  }

  @override
  bool shouldRepaint(_ChartOverlayPainter oldDelegate) {
    return params.shouldRepaint(oldDelegate.params) ||
        klineCategory != oldDelegate.klineCategory ||
        getPriceLabel != oldDelegate.getPriceLabel;
  }
}

class _CrosshairPainter extends CustomPainter {
  _CrosshairPainter({
    required this.params,
    required this.state,
    required this.klineCategory,
    required this.showInfoOverlay,
  });

  final _PainterParams params;
  final _CrosshairState state;
  final KlineCategory klineCategory;
  final bool showInfoOverlay;

  @override
  void paint(Canvas canvas, Size size) {
    if (params.candles.isEmpty) return;
    _drawVolumeFooter(canvas, params, state);
    if (!state.show) return;
    if (showInfoOverlay) {
      canvas.drawRect(
        Rect.fromLTWH(
          params.chartLeft,
          params.infoBandTop,
          params.chartWidth,
          params.infoBandBottom,
        ),
        Paint()..color = Colors.white,
      );
    }
    _drawCrosshair(canvas, params, state);
  }

  int _resolveAbsIndex(_PainterParams params, _CrosshairState state) {
    if (params.allCandles.isEmpty) return 0;
    final int fallback = min(
      params.allCandles.length - 1,
      params.startIndex + params.candles.length - 1,
    );
    final int abs = (state.index ?? fallback).clamp(
      0,
      params.allCandles.length - 1,
    );
    return abs;
  }

  void _drawVolumeFooter(
    Canvas canvas,
    _PainterParams params,
    _CrosshairState state,
  ) {
    final int absIndex = _resolveAbsIndex(params, state);
    final double vol = state.show
        ? params.allCandles[absIndex].volume
        : params.allCandles.last.volume;
    final String text = '成交量 VOLUME:${_formatVolumeWan(vol)}';
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF1F1F1F),
          fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final double y = params.chartHeight + params.style.timeLabelHeight - 2;
    tp.paint(canvas, Offset(params.chartLeft + 4, y - tp.height));
  }

  void _drawCrosshair(
    Canvas canvas,
    _PainterParams params,
    _CrosshairState state,
  ) {
    final int absIndex = _resolveAbsIndex(params, state);
    final _KlineCandle candle = params.allCandles[absIndex];
    final double chartLocalX =
        (absIndex + 0.5) * params.candleWidth - params.scrollOffset;
    final double clampedX = chartLocalX.clamp(0.0, params.chartWidth);
    final double x = params.chartLeft + clampedX;
    final double y = params
        .fitPrice(candle.close)
        .clamp(0.0, params.priceHeight);

    final Paint crossPaint = Paint()
      ..color = const Color(0xFF9E9E9E)
      ..strokeWidth = 0.6;
    canvas.drawLine(
      Offset(x, params.infoBandBottom),
      Offset(x, params.chartHeight),
      crossPaint,
    );
    canvas.drawLine(
      Offset(params.chartLeft, y),
      Offset(params.chartLeft + params.chartWidth, y),
      crossPaint,
    );

    _drawCrosshairPriceLabel(canvas, params, y);
    _drawCrosshairTimeLabel(canvas, params, candle.timestamp, chartLocalX);
    if (showInfoOverlay) {
      _drawCrosshairInfo(canvas, params, absIndex, candle);
    }
  }

  void _drawCrosshairPriceLabel(
    Canvas canvas,
    _PainterParams params,
    double y,
  ) {
    final String label = params.priceFromY(y).toStringAsFixed(2);
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
    final double minY = params.infoBandBottom + 2;
    final double maxY = params.priceHeight - boxH - 2;
    double boxY = y - boxH / 2;
    if (maxY >= minY) {
      boxY = boxY.clamp(minY, maxY);
    } else {
      boxY = minY;
    }
    void drawBox(double boxX) {
      final Rect rect = Rect.fromLTWH(boxX, boxY, boxW, boxH);
      canvas.drawRect(
        rect,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = AppColors.border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6,
      );
      tp.paint(canvas, Offset(boxX + padX, boxY + padY));
    }

    drawBox(params.chartLeft + params.chartWidth + 2);
    final double leftBoxX = max(2, params.chartLeft - boxW - 4);
    drawBox(leftBoxX);
  }

  void _drawCrosshairTimeLabel(
    Canvas canvas,
    _PainterParams params,
    int timestamp,
    double x,
  ) {
    final String label = formatKlineCrosshairTimeLabel(
      DateTime.fromMillisecondsSinceEpoch(timestamp),
      category: klineCategory,
    );
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
    final double minX = params.chartLeft + 2;
    final double maxX = params.chartLeft + params.chartWidth - boxW - 2;
    double boxX = params.chartLeft + x - boxW / 2;
    if (maxX >= minX) {
      boxX = boxX.clamp(minX, maxX);
    } else {
      boxX = minX;
    }
    final double bandY = params.priceHeight;
    final double boxY = bandY + (params.timeBandHeight - boxH) / 2;
    final Rect rect = Rect.fromLTWH(boxX, boxY, boxW, boxH);
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = AppColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6,
    );
    tp.paint(canvas, Offset(boxX + padX, boxY + padY));
  }

  void _drawCrosshairInfo(
    Canvas canvas,
    _PainterParams params,
    int absIndex,
    _KlineCandle candle,
  ) {
    final double prevClose = absIndex > 0
        ? params.allCandles[absIndex - 1].close
        : candle.open;
    final double diff = candle.close - prevClose;
    final double pct = prevClose == 0 ? 0 : diff / prevClose * 100;
    final Color diffColor = diff >= 0
        ? params.style.priceGainColor
        : params.style.priceLossColor;
    final DateTime time = DateTime.fromMillisecondsSinceEpoch(candle.timestamp);
    final String date = formatKlineInfoDateLabel(time, category: klineCategory);
    final String? weekday = formatKlineInfoWeekdayLabel(
      time,
      category: klineCategory,
    );
    final TextStyle baseStyle = const TextStyle(
      fontSize: 11,
      color: AppColors.textPrimary,
      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    );
    final TextPainter tp = TextPainter(
      text: TextSpan(
        style: baseStyle,
        children: <TextSpan>[
          TextSpan(text: weekday == null ? '$date  ' : '$date $weekday  '),
          TextSpan(
            text:
                '${diff >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%(${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(2)})  ',
            style: TextStyle(color: diffColor, fontWeight: FontWeight.w600),
          ),
          TextSpan(text: '开:${candle.open.toStringAsFixed(2)}  '),
          TextSpan(text: '高:${candle.high.toStringAsFixed(2)}  '),
          TextSpan(text: '低:${candle.low.toStringAsFixed(2)}  '),
          TextSpan(text: '收:${candle.close.toStringAsFixed(2)}  '),
          TextSpan(text: '量:${_formatVolumeWan(candle.volume)}'),
        ],
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: max(0.0, params.chartWidth - 8));
    final double textY = max(2.0, (params.infoBandBottom - tp.height) / 2);
    tp.paint(canvas, Offset(params.chartLeft + 4, textY));
  }

  String _formatVolumeWan(double value) {
    final double wan = value / 10000;
    return '${wan.toStringAsFixed(2)} 万';
  }

  @override
  bool shouldRepaint(_CrosshairPainter oldDelegate) =>
      params.shouldRepaint(oldDelegate.params) ||
      state != oldDelegate.state ||
      klineCategory != oldDelegate.klineCategory ||
      showInfoOverlay != oldDelegate.showInfoOverlay;
}
