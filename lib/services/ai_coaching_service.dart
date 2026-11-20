// [FitTracker 전용] fittracker/lib/services/ai_coaching_service.dart
import 'dart:convert';
import 'dart:math' show min; // 디버그 로그를 위한 import
import 'package:http/http.dart' as http;
import 'package:my_flutter_shared/my_flutter_shared.dart';
import 'health_connect_service.dart';
import 'package:flutter/foundation.dart';

class AiCoachingService {
  final HealthConnectService _healthService = HealthConnectService();
  final AccessControlService _accessService = AccessControlService();
  final ApiKeyService _apiKeyService = ApiKeyService();

  Future<String> generateCoaching() async {
    try {
      // 1. 권한 상태 확인
      final accessState = await _accessService.checkAiAccess();

      if (accessState == AiCoachingAccess.noAccess ||
          accessState == AiCoachingAccess.needsApiKey) {
        return "권한이 없거나 API 키가 등록되지 않았습니다.";
      }

      if (accessState == AiCoachingAccess.limitedAccess) {
        final canUse = await _accessService.canUseAiToday();
        if (!canUse) {
          return "오늘의 무료 AI 코칭 횟수(3회)를 모두 소진했습니다.\n프리미엄 구독을 통해 무제한으로 이용해 보세요.";
        }
      }

      // 2. Health Connect 데이터 수집
      bool hasPermission = await _healthService.requestPermissions();
      if (!hasPermission) return "헬스 커넥트 권한이 필요합니다.";

      final distance = await _healthService.getWeeklyDistance();
      final weight = await _healthService.getWeeklyWeight();
      final calories = await _healthService.getWeeklyCalories();

      // 3. Gemini API 호출
      final apiKey = await _apiKeyService.getApiKey();
      if (apiKey == null || apiKey.isEmpty) return "API 키 오류가 발생했습니다.";

      final prompt = '''
당신은 FitTracker 앱의 전문 퍼스널 트레이너이자 영양사입니다.

[사용자 건강 데이터 (최근 7일)]
- 이동 거리 (km): $distance
- 체중 변화 (kg): $weight
- 소모 칼로리 (kcal): $calories

이 정보를 분석하여 아래 3가지 항목을 파이프(|) 기호로만 구분해서 출력하세요.
다른 인사말이나 부가 설명 없이 반드시 아래 형식만 출력하세요.

[출력 형식]
운동 분석 및 추천|식단 조언|동기부여 멘트
''';

      // 🚨 모델 이름을 gemini-2.5-flash 로 변경합니다!
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey',
      );

      // 🚨 [AI] Gemini API 호출 직전 디버그 로그
      debugPrint('[AI] API 키 존재 여부: ${apiKey != null && apiKey.isNotEmpty}');
      debugPrint('[AI] 호출 URL 앞부분: ${url.toString().substring(0, min(50, url.toString().length))}');

      // 중복되었던 부분을 하나로 통합!
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": prompt},
              ],
            },
          ],
        }),
      );

      // 🚨 [AI] 응답 수신 후 디버그 로그
      debugPrint('[AI] 응답 상태코드: ${response.statusCode}');
      debugPrint('[AI] 응답 바디 앞부분: ${response.body.substring(0, min(200, response.body.length))}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final resultText = data['candidates'][0]['content']['parts'][0]['text'];

        // 4. limitedAccess인 경우에만 횟수 차감
        if (accessState == AiCoachingAccess.limitedAccess) {
          await _accessService.incrementDailyUsage();
        }

        return resultText;
      } else {
        return "AI 코칭을 생성하는 중 문제가 발생했습니다. 잠시 후 다시 시도해 주세요.";
      }
    } catch (e) {
      debugPrint('AI 코칭 생성 오류: $e');
      return "데이터를 분석하는 중 오류가 발생했습니다. 네트워크 상태를 확인해 주세요.";
    }
  }
}