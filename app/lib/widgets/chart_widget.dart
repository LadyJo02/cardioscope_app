import 'dart:math';

import 'package:cardioscope_app/utils/app_colors.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class ChartWidget extends StatelessWidget {
  final List<int> counts;
  const ChartWidget({super.key, required this.counts});

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (int i = 0; i < counts.length; i++) {
      spots.add(FlSpot(i.toDouble(), counts[i].toDouble()));
    }

    final maxCount = counts.isEmpty ? 1 : counts.reduce(max);
    int step = 5;
    while (step < maxCount) {
      step *= 2;
    }
    final maxY = (maxCount + step / 2).ceilToDouble();

    return LineChart(
      LineChartData(
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (touchedSpot) => Colors.white,
            getTooltipItems: (touchedSpots) {
              return touchedSpots
                  .map((spot) => LineTooltipItem(
                        '${spot.y.toInt()}',
                        const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ))
                  .toList();
            },
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          getDrawingHorizontalLine: (value) =>
              const FlLine(color: Colors.black12, strokeWidth: 1),
          getDrawingVerticalLine: (value) =>
              const FlLine(color: Colors.black12, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 1,
              getTitlesWidget: (double value, TitleMeta meta) {
                const days = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
                const style = TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.black54);
                final i = value.toInt();
                if (i >= 0 && i < days.length) {
                  return SideTitleWidget(
                    meta: meta,
                    space: 8.0,
                    child: Text(days[i], style: style),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: step.toDouble() / 2,
              getTitlesWidget: (double value, TitleMeta meta) {
                if (value % (step / 2) == 0) {
                  return SideTitleWidget(
                    meta: meta,
                    space: 8.0,
                    child: Text(
                      value.toInt().toString(),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.black54),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            axisNameWidget: const Text(
              'Screenings',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
            ),
            axisNameSize: 32,
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(
            show: true, border: Border.all(color: const Color(0xffe7e7e7))),
        minX: 0,
        maxX: 6,
        minY: 0,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppColors.primary,
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.primary.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }
}
