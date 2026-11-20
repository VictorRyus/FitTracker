import 'package:flutter/material.dart';
import 'package:my_flutter_shared/my_flutter_shared.dart'; // 구글 로그인 서비스 가져오기

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final googleSignInService = GoogleSignInService(
        onSignOut: () async => await ApiKeyService().deleteApiKey(),
      );

      final result = await googleSignInService.signIn();

      if (result == null && mounted) {
        // 사용자가 로그인을 취소하거나 창을 닫은 경우
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('로그인이 취소되었습니다.')));
      }
      // ❗ 로그인 성공 시 별도의 Navigator 이동 코드를 절대 넣지 않습니다.
      // main.dart의 StreamBuilder가 알아서 MainScaffold로 넘겨줍니다.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('로그인 오류: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // 다크 테마 배경
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.fitness_center,
              size: 80,
              color: Colors.cyanAccent,
            ),
            const SizedBox(height: 20),
            const Text(
              'FitTracker',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'AI와 함께하는 스마트한 건강 관리',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 60),

            // 로딩 중일 때는 스피너, 아닐 때는 버튼 표시
            _isLoading
                ? const CircularProgressIndicator(color: Colors.cyanAccent)
                : ElevatedButton.icon(
                    onPressed: _handleGoogleSignIn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    icon: const Icon(Icons.login),
                    label: const Text(
                      'Google 계정으로 시작하기',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
