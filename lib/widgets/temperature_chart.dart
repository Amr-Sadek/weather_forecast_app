import 'package:flutter/material.dart';

import '../models/forecast_model.dart';

class TemperatureChart extends StatelessWidget {
  final List<ForecastModel> forecast;

  const TemperatureChart({super.key, required this.forecast});

  @override
  Widget build(BuildContext context) {
    final items = forecast.take(8).toList();

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.075),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.show_chart_rounded,
                color: Colors.white.withOpacity(0.75),
                size: 19,
              ),
              const SizedBox(width: 8),
              const Text(
                'Temperature Trend',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          SizedBox(
            height: 150,
            width: double.infinity,
            child: CustomPaint(
              painter: _TemperatureChartPainter(
                temperatures: items.map((item) => item.temperature).toList(),
              ),
            ),
          ),

          const SizedBox(height: 8),

          Row(
            children: [
              for (int i = 0; i < items.length; i++)
                Expanded(
                  child: Text(
                    i == 0 ? 'Now' : _formatHour(items[i].dateTime),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.50),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatHour(DateTime dateTime) {
    final hour = dateTime.hour;

    if (hour == 0) return '12 AM';
    if (hour == 12) return '12 PM';

    return hour < 12 ? '$hour AM' : '${hour - 12} PM';
  }
}

class _TemperatureChartPainter extends CustomPainter {
  final List<double> temperatures;

  _TemperatureChartPainter({required this.temperatures});

  @override
  void paint(Canvas canvas, Size size) {
    if (temperatures.length < 2) {
      return;
    }

    final double minTemperature = temperatures.reduce((a, b) => a < b ? a : b);

    final double maxTemperature = temperatures.reduce((a, b) => a > b ? a : b);

    final double range = (maxTemperature - minTemperature).abs() < 1
        ? 1
        : (maxTemperature - minTemperature);

    final Path linePath = Path();
    final Path fillPath = Path();

    final double horizontalPadding = 12;
    final double topPadding = 15;
    final double bottomPadding = 25;

    final double chartWidth = size.width - (horizontalPadding * 2);

    final double chartHeight = size.height - topPadding - bottomPadding;

    for (int i = 0; i < temperatures.length; i++) {
      final double x =
          horizontalPadding + (chartWidth * (i / (temperatures.length - 1)));

      final double normalized = (temperatures[i] - minTemperature) / range;

      final double y = topPadding + chartHeight - (normalized * chartHeight);

      if (i == 0) {
        linePath.moveTo(x, y);
        fillPath.moveTo(x, y);
      } else {
        linePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(
      horizontalPadding + chartWidth,
      size.height - bottomPadding,
    );

    fillPath.lineTo(horizontalPadding, size.height - bottomPadding);

    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x5588D8FF), Color(0x001C8DCC)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawPath(
      linePath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    for (int i = 0; i < temperatures.length; i++) {
      final double x =
          horizontalPadding + (chartWidth * (i / (temperatures.length - 1)));

      final double normalized = (temperatures[i] - minTemperature) / range;

      final double y = topPadding + chartHeight - (normalized * chartHeight);

      canvas.drawCircle(Offset(x, y), 4, Paint()..color = Colors.white);

      canvas.drawCircle(
        Offset(x, y),
        2,
        Paint()..color = const Color(0xFF2B83C6),
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text: '${temperatures[i].round()}°',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();

      textPainter.paint(
        canvas,
        Offset(x - (textPainter.width / 2), y - textPainter.height - 7),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TemperatureChartPainter oldDelegate) {
    return oldDelegate.temperatures != temperatures;
  }
}
