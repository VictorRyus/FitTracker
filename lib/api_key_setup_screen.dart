import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:my_flutter_shared/my_flutter_shared.dart'; // ApiKeyService 경로

class ApiKeySetupScreen extends StatefulWidget {
  const ApiKeySetupScreen({super.key});

  @override
  State<ApiKeySetupScreen> createState() => _ApiKeySetupScreenState();
}

class _ApiKeySetupScreenState extends State<ApiKeySetupScreen> {
  final TextEditingController _keyController = TextEditingController();
  bool _isLoading = false;
  bool _hasExistingKey = false;
  bool _isObscured = true; // API 키 숨김 처리용

  @override
  void initState() {
    super.initState();
    _loadExistingKey();
  }

  Future<void> _loadExistingKey() async {
    final existingKey = await ApiKeyService().getApiKey();
    if (existingKey != null && existingKey.isNotEmpty) {
      setState(() {
        _hasExistingKey = true;
        // 실제 키 원문 대신 앞 8자리 + 마스킹 처리
        if (existingKey.length > 8) {
          _keyController.text =
              '${existingKey.substring(0, 8)}••••••••••••••••••••';
        } else {
          _keyController.text = '••••••••••••••••••••';
        }
      });
    }
  }

  Future<void> _launchUrl() async {
    final url = Uri.parse('https://aistudio.google.com/app/apikey');
    if (!await launchUrl(url)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('링크를 열 수 없습니다.')));
      }
    }
  }

  Future<void> _saveKey() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('API 키를 입력해주세요.')));
      return;
    }

    // 입력값에 마스킹 문자(•)가 포함되어 있다면 변경하지 않은 것으로 간주
    if (key.contains('•')) {
      Navigator.pop(context);
      return;
    }

    setState(() => _isLoading = true);

    // AIza 형식 검사
    if (!key.startsWith('AIza')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('유효하지 않은 API 키 형식입니다. (AIza로 시작)')),
      );
      setState(() => _isLoading = false);
      return;
    }

    // 실제 API 검증 로직 호출
    final isValid = await ApiKeyService().validateApiKey(key);

    if (!isValid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('API 키 인증에 실패했습니다. 키를 다시 확인해주세요.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => _isLoading = false);
      return;
    }

    // 검증 성공 시 저장
    await ApiKeyService().saveApiKey(key);

    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('API 키가 안전하게 저장되었습니다.')));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 스크린샷과 동일한 네이비/다크 배경색 적용
    final backgroundColor = const Color(0xFF13161C);
    final cardColor = const Color(0xFF1E2430);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('설정'),
        backgroundColor: backgroundColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ─── 상단: BYOK 프리미엄 카드 ───
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                // 은은한 청록색 그라데이션 또는 단색 배경
                color: const Color(0xFF182A3A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.cyan.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.cyan.shade600,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '✨ BYOK 프리미엄',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '본인의 Gemini API 키를 입력하시면,\n월 구독료 없이 사진 분석과 AI 코치 등\n모든 프리미엄 기능을 평생 무료로\n이용할 수 있습니다.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildEmojiFeatureRow('📸', '러닝 스크린샷 자동 거리·시간 인식'),
                  _buildEmojiFeatureRow('🍽️', '음식 사진 칼로리 자동 분석'),
                  _buildEmojiFeatureRow('🤖', '날씨 기반 AI 코치 운동 추천'),
                  _buildEmojiFeatureRow('🔢', 'AI 텍스트 칼로리 자동 계산'),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ─── 중단: 구글 AI Studio 버튼 ───
            OutlinedButton(
              onPressed: _launchUrl,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: Colors.cyan),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('🔑 ', style: TextStyle(fontSize: 16)),
                  Text(
                    '구글 AI Studio에서 API 키 발급받기',
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Google 계정만 있으면 무료로 발급받을 수 있어요.',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
            ),
            const SizedBox(height: 32),

            // ─── 하단: API 키 입력 ───
            const Text(
              'Gemini API 키',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _keyController,
              obscureText: _isObscured, // 마스킹 처리 연동
              style: const TextStyle(color: Colors.white, letterSpacing: 2.0),
              decoration: InputDecoration(
                prefixIcon: const Icon(
                  Icons.vpn_key,
                  color: Colors.grey,
                  size: 20,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isObscured ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey,
                  ),
                  onPressed: () {
                    setState(() {
                      _isObscured = !_isObscured;
                    });
                  },
                ),
                hintText: 'AIzaSy...',
                hintStyle: TextStyle(
                  color: Colors.grey.shade600,
                  letterSpacing: 0,
                ),
                filled: true,
                fillColor: cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 보안 안내 박스
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade800),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lock_outline,
                    color: Colors.grey.shade500,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'API 키는 AES-256으로 암호화되어 안전하게 보관되며, '
                      '다른 기기에서도 자동 복원됩니다.',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ─── 최하단: 검증 및 저장 버튼 ───
            ElevatedButton(
              onPressed: _isLoading ? null : _saveKey,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.black,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      _hasExistingKey ? 'API 키 변경' : '검증 및 저장',
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // 이모지와 텍스트를 나란히 배치하는 헬퍼 위젯
  Widget _buildEmojiFeatureRow(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 12),
          Text(
            text,
            style: TextStyle(color: Colors.grey.shade300, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
