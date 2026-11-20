import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:my_flutter_shared/my_flutter_shared.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ✅ 에러 원인 해결: Firebase 패키지 추가

import 'paywall_screen.dart';
import '../api_key_setup_screen.dart';
import 'login_screen.dart'; // (또는 '../login_screen.dart' 경로에 맞게)

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _version = "0.0.0";
  bool _isPremium = false;

  // ✅ 유저 정보 상태 변수 추가
  String _userName = '';
  String _userEmail = '';
  String? _userPhotoUrl;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final info = await PackageInfo.fromPlatform();
    final premiumStatus = await RevenueCatService().isPremium();
    final user = FirebaseAuth.instance.currentUser; // ✅ 현재 로그인된 유저 정보 가져오기

    setState(() {
      _version = info.version;
      _isPremium = premiumStatus;

      // ✅ 구글 계정 정보 매핑
      _userName = user?.displayName ?? '사용자';
      _userEmail = user?.email ?? '';
      _userPhotoUrl = user?.photoURL;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('프로필'), backgroundColor: Colors.black),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildUserCard(), // ✅ 최상단에 유저 계정 정보 카드 배치
          _buildStatusCard(),
          const SizedBox(height: 20),

          // ─── 통합된 API 키 설정 메뉴 (기존 코드 유지) ───
          ListTile(
            leading: const Icon(Icons.vpn_key, color: Colors.cyan),
            title: const Text(
              'Gemini API 키 설정',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              '무료 프리미엄 혜택을 위한 키 등록',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ApiKeySetupScreen(),
                ),
              );
            },
          ),

          // ───────────────────────────────────────
          _buildMenuTile(Icons.logout, '로그아웃', () => _handleLogout(context)),
          const Divider(color: Colors.grey),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              '버전: $_version',
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // ✅ 구글 계정 정보 UI 함수 (새로 추가)
  Widget _buildUserCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.grey.shade700,
            backgroundImage: _userPhotoUrl != null
                ? NetworkImage(_userPhotoUrl!)
                : null,
            child: _userPhotoUrl == null
                ? const Icon(Icons.person, color: Colors.white, size: 28)
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _userName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _userEmail,
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // (기존 코드 완벽 유지)
  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _isPremium ? 'PRO 멤버십 이용 중' : '무료 버전 이용 중',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (!_isPremium)
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PaywallScreen()),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
              ),
              child: const Text('구독하기', style: TextStyle(color: Colors.black)),
            ),
        ],
      ),
    );
  }

  // (기존 코드 완벽 유지)
  Widget _buildMenuTile(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.cyanAccent),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }

  // (기존 코드 완벽 유지)
  void _handleLogout(BuildContext context) async {
    // 실제 로그아웃 서비스 연결 및 API 키 삭제
    final googleSignInService = GoogleSignInService(
      onSignOut: () async => await ApiKeyService().deleteApiKey(),
    );

    await googleSignInService.signOut();

    if (context.mounted) {
      // 모든 경로를 제거하고 로그인 화면으로 이동
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }
}
