import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:health/health.dart';
import 'package:flutter/foundation.dart';

class BodyInfo {
  final double heightM; // 신장 (미터)
  final double weightKg; // 체중 (kg)
  final int ageYears; // 나이

  const BodyInfo({
    required this.heightM,
    required this.weightKg,
    required this.ageYears,
  });

  double get bmi => heightM > 0 ? weightKg / (heightM * heightM) : 0;
  double get recommendedWeight => heightM > 0 ? 22.0 * heightM * heightM : 0;
  double get weightLowerBound => heightM > 0 ? 18.5 * heightM * heightM : 0;
  double get weightUpperBound => heightM > 0 ? 24.9 * heightM * heightM : 0;
  double get bmr =>
      88.36 + (13.4 * weightKg) + (480 * heightM) - (5.7 * ageYears);
  double get recommendedCalorieBurn => bmr * 0.15;
  bool get isComplete => heightM > 0 && weightKg > 0 && ageYears > 0;
}

class BodyInfoService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Health _health = Health();

  String get _uid => _auth.currentUser!.uid;

  Future<BodyInfo> getBodyInfo() async {
    double heightM = await _getHeightFromHealth();
    double weightKg = await _getLatestWeightFromHealth();
    int age = await _getAgeFromFirestore();

    if (heightM == 0 || weightKg == 0 || age == 0) {
      final stored = await _getStoredBodyInfo();
      if (heightM == 0) heightM = stored['heightM'] ?? 0;
      if (weightKg == 0) weightKg = stored['weightKg'] ?? 0;
      if (age == 0) age = (stored['ageYears'] ?? 0).toInt();
    }

    return BodyInfo(heightM: heightM, weightKg: weightKg, ageYears: age);
  }

  Future<void> saveBodyInfo({
    required double heightM,
    required double weightKg,
    required int ageYears,
  }) async {
    await _firestore.collection('users').doc(_uid).set({
      'bodyInfo': {
        'heightM': heightM,
        'weightKg': weightKg,
        'ageYears': ageYears,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
  }

  Future<double> _getHeightFromHealth() async {
    try {
      final now = DateTime.now();
      final data = await _health.getHealthDataFromTypes(
        startTime: now.subtract(const Duration(days: 365)),
        endTime: now,
        types: [HealthDataType.HEIGHT],
      );
      if (data.isEmpty) return 0;
      final value = data.last.value;
      if (value is NumericHealthValue) return value.numericValue.toDouble();
    } catch (e) {
      debugPrint('신장 조회 실패: $e');
    }
    return 0;
  }

  Future<double> _getLatestWeightFromHealth() async {
    try {
      final now = DateTime.now();
      final data = await _health.getHealthDataFromTypes(
        startTime: now.subtract(const Duration(days: 30)),
        endTime: now,
        types: [HealthDataType.WEIGHT],
      );
      if (data.isEmpty) return 0;
      final value = data.last.value;
      if (value is NumericHealthValue) return value.numericValue.toDouble();
    } catch (e) {
      debugPrint('체중 조회 실패: $e');
    }
    return 0;
  }

  Future<Map<String, dynamic>> _getStoredBodyInfo() async {
    try {
      final doc = await _firestore.collection('users').doc(_uid).get();
      return (doc.data()?['bodyInfo'] as Map<String, dynamic>?) ?? {};
    } catch (e) {
      return {};
    }
  }

  Future<int> _getAgeFromFirestore() async {
    try {
      final doc = await _firestore.collection('users').doc(_uid).get();
      return (doc.data()?['bodyInfo']?['ageYears'] ?? 0) as int;
    } catch (e) {
      return 0;
    }
  }
}
