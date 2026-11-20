// [FitTracker 전용] fittracker/lib/screens/ai_coaching_screen.dart
import 'package:flutter/material.dart';
import 'package:my_flutter_shared/my_flutter_shared.dart';
import '../services/ai_coaching_service.dart';
import 'paywall_screen.dart';
import '../api_key_setup_screen.dart';

class AiCoachingScreen extends StatefulWidget {
  const AiCoachingScreen({super.key});

  @override
  State<AiCoachingScreen> createState() => _AiCoachingScreenState();
}

class _AiCoachingScreenState extends State<AiCoachingScreen> {
  final AiCoachingService _coachingService = AiCoachingService();
  final AccessControlService _accessService = AccessControlService();

  bool _isLoading = true;
  // 🚨 [수정됨] 단일 텍스트에서 List 배열로 변경
  List<String> _coachingResults = [];
  int _todayUsageCount = 0;
  AiCoachingAccess _accessState = AiCoachingAccess.noAccess;

  @override
  void initState() {
    super.initState();
    _checkAccessAndStart();
  }

  Future<void> _checkAccessAndStart() async {
    setState(() => _isLoading = true);

    final accessState = await _accessService.checkAiAccess();
    int usageCount = 0;

    if (accessState == AiCoachingAccess.limitedAccess) {
      usageCount = await _accessService.getTodayUsageCount();
    }

    if (!mounted) return;

    setState(() {
      _accessState = accessState;
      _todayUsageCount = usageCount;
      _isLoading = false;
    });
  }

  // AI 분석 수행 메인 로직
  Future<void> _generateCoaching() async {
    setState(() => _isLoading = true);

    try {
      final result = await _coachingService.generateCoaching();

      if (_accessState == AiCoachingAccess.limitedAccess) {
        _todayUsageCount = await _accessService.getTodayUsageCount();
      }

      if (mounted) {
        setState(() {
          // 🚨 [수정됨] 파이프 분리 파싱 로직 적용
          final parts = result.split('|');
          // 🚨 [AI] 파이프 파싱 결과 디버그 로그
          debugPrint('[AI] 파싱 결과 parts 수: ${parts.length}');
          debugPrint('[AI] 첫 번째 파트: ${parts.isNotEmpty ? parts[0] : "없음"}');

          if (parts.length >= 3) {
            _coachingResults = parts.take(3).toList();
          } else {
            // 에러 메시지나 형식이 안 맞을 경우 단일 카드로 통째로 보여줌
            _coachingResults = [result, '', ''];
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('분석 중 오류가 발생했습니다: $e'))
        );
      }
    }
  }

  Future<void> _handleReanalyze() async {
    if (_accessState == AiCoachingAccess.limitedAccess) {
      final canUse = await _accessService.canUseAiToday();
      if (!canUse) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('오늘의 무료 코칭 횟수(3회)를 모두 소진했습니다.')),
        );
        return;
      }
    }
    await _generateCoaching();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('AI 맞춤 코칭'),
        backgroundColor: Colors.black,
      ),
      body: SafeArea(
        child: _isLoading ? _buildLoading() : _buildBodyByAccess(),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.cyanAccent),
          SizedBox(height: 24),
          Text(
            'AI가 데이터를 분석하고 있습니다...',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildBodyByAccess() {
    if (_accessState == AiCoachingAccess.noAccess) {
      return _buildLockedUI(
        icon: Icons.lock_outline,
        title: '프리미엄 전용 기능',
        description: 'AI 맞춤 코칭은 구독자 전용 기능입니다.\n지금 구독하고 매일 맞춤 코칭을 받아보세요.',
        buttonText: '프리미엄 구독하기',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PaywallScreen()),
        ),
      );
    }

    if (_accessState == AiCoachingAccess.needsApiKey) {
      return _buildLockedUI(
        icon: Icons.api_outlined,
        title: 'API 키 설정 필요',
        description: 'AI 기능을 사용하려면 Gemini API 키가 필요합니다.\n프로필 또는 설정에서 키를 등록해주세요.',
        buttonText: 'API 키 설정하러 가기',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ApiKeySetupScreen()),
        ),
      );
    }

    return _buildResult();
  }

  Widget _buildLockedUI({
    required IconData icon,
    required String title,
    required String description,
    required String buttonText,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Colors.cyanAccent.withOpacity(0.5)),
          const SizedBox(height: 24),
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, height: 1.5),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: Text(
              buttonText,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // 🚨 [수정됨] 3개 카드로 나뉘는 결과 화면 UI
  Widget _buildResult() {
    final titles = ['🏃 운동 처방', '🥗 식단 조언', '🔥 동기 부여'];

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: _coachingResults.isEmpty
                  ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    '버튼을 눌러 나만의 AI 코칭을 시작해보세요!',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
                  : Column(
                children: [
                  const Text(
                    '✨ AI 분석 결과',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (int i = 0; i < _coachingResults.length; i++) ...[
                    if (_coachingResults[i].trim().isNotEmpty)
                      _buildResultCard(
                        i < titles.length ? titles[i] : '추가 조언',
                        _coachingResults[i],
                      ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_accessState == AiCoachingAccess.limitedAccess)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  Text(
                    'BYOK 무료 이용: $_todayUsageCount / 3회', // 🚨 문구 수정
                    style: TextStyle(
                      color: _todayUsageCount >= 3
                          ? Colors.redAccent
                          : Colors.orangeAccent,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '구독 시 무제한 이용 가능', // 🚨 설명 추가
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ElevatedButton.icon(
            onPressed: _handleReanalyze,
            icon: const Icon(Icons.psychology),
            label: const Text(
              'AI에게 코칭 받기',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 🚨 [수정됨] 개별 결과 카드 위젯
  Widget _buildResultCard(String title, String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.cyanAccent,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            content.trim(),
            style: const TextStyle(
              color: Colors.white,
              height: 1.6,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}