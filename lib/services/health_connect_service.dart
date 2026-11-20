// [FitTracker 전용] fittracker/lib/services/health_connect_service.dart
import 'package:health/health.dart';
import 'package:flutter/foundation.dart';

class HealthConnectService {
  // [수정 1] HealthFactory (deprecated) -> Health() 싱글톤으로 변경
  final Health _health = Health();

  // [수정 1] 권한 요청 로직 단순화
  Future<bool> requestPermissions() async {
    final types = [
      HealthDataType.STEPS,
      HealthDataType.WEIGHT,
      HealthDataType.ACTIVE_ENERGY_BURNED,
    ];

    try {
      return await _health.requestAuthorization(types);
    } catch (e) {
      debugPrint('권한 요청 실패: $e');
      return false;
    }
  }

  // 기준일 계산 (오늘 포함 최근 7일)
  DateTime get _startDate => DateTime.now()
      .subtract(const Duration(days: 6))
      .copyWith(hour: 0, minute: 0, second: 0);
  DateTime get _endDate => DateTime.now();

  // 주간 거리 수집 (거리 데이터가 없으면 걸음 수로 추정)
  Future<List<double>> getWeeklyDistance() async {
    List<double> rawDist = await _getDailyData(
      start: _startDate,
      end: DateTime.now(),
      type: HealthDataType.DISTANCE_DELTA,
    );

    // 🚨 보정 로직: 거리 데이터가 전부 0이라면 걸음 수 데이터로 대체
    if (!rawDist.any((v) => v > 0)) {
      final steps = await _getDailyData(
        start: _startDate,
        end: DateTime.now(),
        type: HealthDataType.STEPS,
      );
      // 걸음 수 * 0.7m (평균 보폭) 적용
      rawDist = steps.map((s) => s * 0.7).toList();
    }

    return rawDist.map((v) => v / 1000.0).toList(); // m -> km 변환
  }

  // 월간 거리 수집 (동일 로직 적용)
  Future<List<double>> getMonthlyDistance() async {
    List<double> rawDist = await _getDailyData(
      start: _monthStart,
      end: DateTime.now(),
      type: HealthDataType.DISTANCE_DELTA,
    );

    if (!rawDist.any((v) => v > 0)) {
      final steps = await _getDailyData(
        start: _monthStart,
        end: DateTime.now(),
        type: HealthDataType.STEPS,
      );
      rawDist = steps.map((s) => s * 0.7).toList();
    }

    return rawDist.map((v) => v / 1000.0).toList();
  }

  // 최근 7일 체중 집계
  Future<List<double>> getWeeklyWeight() async {
    List<double> weightList = List.filled(7, 0.0);
    try {
      final data = await _health.getHealthDataFromTypes(
        startTime: _startDate,
        endTime: _endDate,
        types: [HealthDataType.WEIGHT], // 👈 원래 대괄호 [] 안에 있던 영어를 그대로 유지해 주세요!
      );
      for (var point in data) {
        int dayIndex = point.dateFrom.difference(_startDate).inDays;
        if (dayIndex >= 0 && dayIndex < 7) {
          weightList[dayIndex] = (point.value as num).toDouble();
        }
      }
    } catch (e) {
      debugPrint('체중 불러오기 실패: $e');
    }
    return weightList;
  }

  // 최근 7일 소모 칼로리 집계
  Future<List<double>> getWeeklyCalories() async {
    List<double> caloriesList = List.filled(7, 0.0);
    try {
      final data = await _health.getHealthDataFromTypes(
        startTime: _startDate,
        endTime: _endDate,
        types: [
          HealthDataType.ACTIVE_ENERGY_BURNED,
        ], // 👈 원래 대괄호 [] 안에 있던 영어를 그대로 유지해 주세요!
      );
      for (var point in data) {
        int dayIndex = point.dateFrom.difference(_startDate).inDays;
        if (dayIndex >= 0 && dayIndex < 7) {
          caloriesList[dayIndex] += (point.value as num).toDouble();
        }
      }
    } catch (e) {
      debugPrint('칼로리 불러오기 실패: $e');
    }
    return caloriesList;
  }

  // ── [신규] 공통 헬퍼: 날짜 범위 기반 일별 데이터 집계 ──
  Future<List<double>> _getDailyData({
    required DateTime start,
    required DateTime end,
    required HealthDataType type,
  }) async {
    final days =
        end.difference(start.copyWith(hour: 0, minute: 0, second: 0)).inDays +
        1;
    final result = List<double>.filled(days, 0.0);

    try {
      final data = await _health.getHealthDataFromTypes(
        startTime: start,
        endTime: end,
        types: [type],
      );

      for (var point in data) {
        final idx = point.dateFrom
            .difference(start.copyWith(hour: 0, minute: 0, second: 0))
            .inDays;
        if (idx >= 0 && idx < days) {
          // 최신 health 패키지에서는 NumericHealthValue로 형변환하여 값을 가져옵니다.
          final value = point.value;
          if (value is NumericHealthValue) {
            if (type == HealthDataType.WEIGHT) {
              result[idx] = value.numericValue.toDouble(); // 체중은 마지막 값 유지
            } else {
              result[idx] += value.numericValue.toDouble(); // 걸음/칼로리는 합산
            }
          }
        }
      }
    } catch (e) {
      debugPrint('헬스 데이터 집계 실패($type): $e');
    }
    return result;
  }

  // ── [신규] 월간 메서드 (이번 달 1일부터 오늘까지) ──
  DateTime get _monthStart =>
      DateTime(DateTime.now().year, DateTime.now().month, 1);

  Future<List<double>> getMonthlyWeight() async {
    return await _getDailyData(
      start: _monthStart,
      end: DateTime.now(),
      type: HealthDataType.WEIGHT,
    );
  }

  Future<List<double>> getMonthlyCalories() async {
    return await _getDailyData(
      start: _monthStart,
      end: DateTime.now(),
      type: HealthDataType.ACTIVE_ENERGY_BURNED,
    );
  }
}
