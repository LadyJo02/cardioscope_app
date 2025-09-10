import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class ChartWidget extends StatelessWidget {
  const ChartWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          getDrawingHorizontalLine: (value) {
            return const FlLine(
              color: Colors.black12,
              strokeWidth: 1,
            );
          },
          getDrawingVerticalLine: (value) {
            return const FlLine(
              color: Colors.black12,
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 1,
              getTitlesWidget: (double value, TitleMeta meta) {
                const style = TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.black54,
                );
                // --- THIS LINE HAS BEEN CHANGED ---
                final days = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
                final int index = value.toInt();

                if (index >= 0 && index < days.length) {
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    space: 8.0, 
                    child: Text(days[index], style: style),
                  );
                }
                return Container();
              },
            ),
            axisNameWidget: const Text(
              'Recent Days',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.black54,
              ),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                const style = TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.black54,
                );
                if (value % 1 == 0 && value > 0 && value <= 5) {
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    space: 8.0,
                    child: Text(value.toInt().toString(), style: style),
                  );
                }
                return Container();
              },
            ),
            axisNameWidget: const Text(
              'Screenings',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.black54,
              ),
            ),
            axisNameSize: 32,
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: const Color(0xffe7e7e7)),
        ),
        minX: 0,
        maxX: 6,
        minY: 0,
        maxY: 6,
        lineBarsData: [
          LineChartBarData(
            spots: const [
              FlSpot(0, 3.2),
              FlSpot(1, 4.1),
              FlSpot(2, 2.5),
              FlSpot(3, 5.0),
              FlSpot(4, 3.3),
              FlSpot(5, 4.2),
              FlSpot(6, 2.6),
            ],
            isCurved: true,
            color: const Color(0xFFC31C42),
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0xFFC31C42).withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }
}