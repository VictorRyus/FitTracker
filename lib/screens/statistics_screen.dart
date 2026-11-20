import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/health_connect_service.dart';
import '../services/body_info_service.dart';
import '../widgets/body_info_bottom_sheet.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

// 🚨 SingleTickerProviderStateMixin 및 수동 TabController 완전 제거됨
class _StatisticsScreenState extends State<StatisticsScreen> {
  final HealthConnectService _healthService = HealthConnectService();
  final BodyInfoService _bodyInfoService = BodyInfoService();

  bool _isLoading = true;

  // 🚨 [수정 2] const 키워드 제거 완료
  BodyInfo _bodyInfo = BodyInfo(heightM: 0, weightKg: 0, ageYears: 0);

  List<double> _wDistance = [];
  List<double> _wWeight = [];
  List<double> _wCal = [];

  List<double> _mDistance = [];
  List<double> _mWeight = [];
  List<double> _mCal = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // 거리(km), 체중, 칼로리로 데이터 통일 및 병렬 로딩
    final results = await Future.wait([
      _healthService.getWeeklyDistance(),
      _healthService.getWeeklyWeight(),
      _healthService.getWeeklyCalories(),
      _healthService.getMonthlyDistance(),
      _healthService.getMonthlyWeight(),
      _healthService.getMonthlyCalories(),
    ]);

    final bodyInfo = await _bodyInfoService.getBodyInfo();

    if (mounted) {
      setState(() {
        _wDistance = results[0] as List<double>;
        _wWeight = results[1] as List<double>;
        _wCal = results[2] as List<double>;
        _mDistance = results[3] as List<double>;
        _mWeight = results[4] as List<double>;
        _mCal = results[5] as List<double>;
        _bodyInfo = bodyInfo;
        _isLoading = false;
      });

      // 신체 정보가 불완전하면 바텀시트 자동 팝업
      if (!bodyInfo.isComplete) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          showBodyInfoBottomSheet(
            context,
            current: _bodyInfo,
            onSave: (h, w, a) async {
              await _bodyInfoService.saveBodyInfo(
                heightM: h,
                weightKg: w,
                ageYears: a,
              );
              await _loadData(); // 저장 후 차트 재렌더링
            },
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🚨 [수정 1] DefaultTabController를 최상단에 배치하여 탭 로직 일원화
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('건강 통계', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.black,
          actions: [
            IconButton(
              icon: const Icon(Icons.tune, color: Colors.cyanAccent),
              tooltip: '신체 정보 설정',
              onPressed: () =>
                  showBodyInfoBottomSheet(
                    context,
                    current: _bodyInfo,
                    onSave: (h, w, a) async {
                      await _bodyInfoService.saveBodyInfo(
                        heightM: h,
                        weightKg: w,
                        ageYears: a,
                      );
                      await _loadData();
                    },
                  ),
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.cyanAccent,
            labelColor: Colors.cyanAccent,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: '주간'),
              Tab(text: '월간'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(
          child: CircularProgressIndicator(color: Colors.cyanAccent),
        )
            : TabBarView(
          children: [
            _buildTabContent(isWeekly: true),
            _buildTabContent(isWeekly: false),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent({required bool isWeekly}) {
    final distanceData = isWeekly ? _wDistance : _mDistance;
    final weightData = isWeekly ? _wWeight : _mWeight;
    final calData = isWeekly ? _wCal : _mCal;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildChartCard(
          title: '거리',
          icon: Icons.directions_run,
          chart: _buildLineChart(
            distanceData,
            yUnit: 'km',
            guidelineValue: 5.0,
            guidelineLabel: 'WHO 권장 5km',
            isWeekly: isWeekly,
          ),
        ),
        const SizedBox(height: 20),
        _buildChartCard(
          title: '체중',
          icon: Icons.monitor_weight,
          chart: _buildLineChart(
            weightData,
            yUnit: 'kg',
            guidelineValue: _bodyInfo.heightM > 0
                ? _bodyInfo.recommendedWeight
                : null,
            guidelineLabel: _bodyInfo.heightM > 0
                ? 'BMI22 권장 ${_bodyInfo.recommendedWeight.toStringAsFixed(1)}kg'
                : null,
            isWeekly: isWeekly,
          ),
        ),
        const SizedBox(height: 20),
        _buildChartCard(
          title: '소모 칼로리',
          icon: Icons.local_fire_department,
          chart: _buildLineChart(
            calData,
            yUnit: 'kcal',
            guidelineValue: _bodyInfo.isComplete
                ? _bodyInfo.recommendedCalorieBurn
                : 300,
            guidelineLabel: '권장 소모량',
            isWeekly: isWeekly,
          ),
        ),
      ],
    );
  }

  Widget _buildChartCard({
    required String title,
    required IconData icon,
    required Widget chart,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.cyanAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(height: 200, child: chart),
        ],
      ),
    );
  }

  Widget _buildLineChart(List<double> data, {
    required String yUnit,
    double? guidelineValue,
    String? guidelineLabel,
    required bool isWeekly,
  }) {
    // 🚨 수정: '데이터가 없습니다' 분기문을 제거하여 0인 상태에서도 차트와 가이드라인이 보이게 합니다.
    // final hasData = data.any((v) => v > 0);
    // if (!hasData) { ... } -> 삭제

    // 가이드라인이 데이터보다 높을 경우를 대비해 최대 높이(maxY) 설정
    double maxY = 1.0;
    for (var v in data) {
      if (v > maxY) maxY = v;
    }
    if (guidelineValue != null && guidelineValue > maxY) {
      maxY = guidelineValue * 1.2; // 가이드라인보다 20% 더 높게 여백 설정
    }

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        // Y축 최대값 고정
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              getTitlesWidget: (value, meta) =>
                  Text(
                    '${value.toStringAsFixed(1)}$yUnit',
                    style: const TextStyle(color: Colors.grey, fontSize: 9),
                  ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              // 🚨 간격을 1로 고정하여 중복 호출 방지
              interval: 1,
              getTitlesWidget: (value, meta) {
                const days = ['월', '화', '수', '목', '금', '토', '일'];
                final idx = value.toInt();

                if (isWeekly) {
                  // 🚨 정수값일 때만 레이블 표시 (중복 방지 핵심)
                  if (value != value.toInt().toDouble()) return const SizedBox();
                  if (idx < 0 || idx >= days.length) return const SizedBox();

                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      days[idx],
                      style: const TextStyle(color: Colors.grey, fontSize: 10),
                    ),
                  );
                } else {
                  if (idx % 5 != 0) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${idx + 1}일',
                      style: const TextStyle(color: Colors.grey, fontSize: 10),
                    ),
                  );
                }
              },
            ),
          ),
          topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
        ),
        extraLinesData: guidelineValue != null
            ? ExtraLinesData(horizontalLines: [
          HorizontalLine(
            y: guidelineValue,
            color: Colors.amber.withOpacity(0.8),
            strokeWidth: 1.5,
            dashArray: [6, 4],
            label: HorizontalLineLabel(
              show: true,
              alignment: Alignment.topRight,
              labelResolver: (_) => ' $guidelineLabel',
              style: const TextStyle(color: Colors.amber, fontSize: 10),
            ),
          ),
        ])
            : null,
        lineBarsData: [
          LineChartBarData(
            spots: data
                .asMap()
                .entries
                .map((e) => FlSpot(e.key.toDouble(), e.value))
                .toList(),
            isCurved: true,
            color: Colors.cyanAccent,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.cyanAccent.withOpacity(0.08),
            ),
          ),
        ],
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: Colors.grey.withOpacity(0.15), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
      ),
    );
  }
}
