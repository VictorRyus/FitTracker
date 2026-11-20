import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; // MainScreen이 있는 곳
import 'statistics_screen.dart';
import 'ai_coaching_screen.dart';
import 'profile_screen.dart';
import 'paywall_screen.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;

  // 1. 진짜 메인 화면(MainScreen)을 첫 번째에 배치합니다.
  final List<Widget> _screens = [
    MainScreen(),
    const StatisticsScreen(),
    const AiCoachingScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // 2. 화면이 그려진 직후 '하루 한 번 결제창' 로직 실행
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showPaywallOnceADay();
    });
  }

  // 💡 하루 한 번 결제창 노출 로직
  Future<void> _showPaywallOnceADay() async {
    final prefs = await SharedPreferences.getInstance();
    final lastShown = prefs.getString('last_paywall_date') ?? "";
    final today = DateTime.now().toIso8601String().substring(
      0,
      10,
    ); // YYYY-MM-DD

    if (lastShown != today) {
      if (mounted) {
        // 결제창 띄우기
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PaywallScreen()),
        );
        // 닫은 후 오늘 날짜 저장 (다음에 안 뜨게 함)
        await prefs.setString('last_paywall_date', today);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.cyanAccent,
        unselectedItemColor: Colors.grey,
        backgroundColor: Colors.black,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: '통계'),
          BottomNavigationBarItem(icon: Icon(Icons.psychology), label: 'AI 코칭'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: '프로필'),
        ],
      ),
    );
  }
}
