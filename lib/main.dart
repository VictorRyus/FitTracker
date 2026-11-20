// ============================================================
// 💪 헬스 기록 앱 v15 — AdMob 배너 광고 추가
//
// [v15 신규] #1. AdMob 배너 광고
//      MobileAds.instance.initialize() → main() 에서 초기화
//      MainScreen bottomNavigationBar 영역에 배너 고정 배치
//      광고 단위 ID: ca-app-pub-9640460679881796/6213595372
//      로드 실패 시 빈 공간 없이 자연스럽게 숨김 처리
//      FAB(동기화·추가) 버튼과 겹치지 않는 레이아웃 유지
//
// [v14 유지] BYOK API Key 관리 (SharedPreferences)
// [v14 유지] SettingsScreen (네온 시안 테마)
// [v14 유지] MainScreen AppBar ⚙️ 설정 버튼
//
// [v13 유지] AuthWrapper, LoginScreen, Firebase 공식 SDK
// [v13 유지] users/{uid}/records/ 유저별 데이터 격리
// [v13 유지] 로그아웃 다이얼로그
// [v12 유지] fl_chart 체중 그래프, HC 자동 병합, AI 코치,
//            네온 시안 AppColors, 좌우 FAB
//
// ─────────────────────────────────────────────────────────────
// [필수 pubspec.yaml 패키지]
//   firebase_core, firebase_auth, cloud_firestore, google_sign_in
//   health, permission_handler, image_picker
//   flutter_dotenv, fl_chart, http
//   shared_preferences, url_launcher
//   google_mobile_ads           ← v15 신규
//
// [.env]  GEMINI_API_KEY=fallback_key  (선택 — 없어도 동작)
//
// [Firebase] flutterfire configure → firebase_options.dart 생성
//   google-services.json (Android) / GoogleService-Info.plist (iOS)
//
// [Android build.gradle] minSdkVersion 26
// [AndroidManifest]
//   INTERNET, ACTIVITY_RECOGNITION,
//   health.READ_STEPS, health.READ_WEIGHT, READ_MEDIA_IMAGES
//   <queries> com.google.android.apps.healthdata
//   <!-- url_launcher용 -->
//   <queries>
//     <intent><action android:name="android.intent.action.VIEW"/>
//       <data android:scheme="https"/></intent>
//   </queries>
//   <!-- AdMob 앱 ID (AndroidManifest application 태그 내부) -->
//   <meta-data
//     android:name="com.google.android.gms.ads.APPLICATION_ID"
//     android:value="ca-app-pub-9640460679881796~XXXXXXXXXX"/>
//
// [iOS Info.plist]
//   HealthKit 권한, NSPhotoLibraryUsageDescription
//   LSApplicationQueriesSchemes: https
//   <!-- AdMob 앱 ID -->
//   <key>GADApplicationIdentifier</key>
//   <string>ca-app-pub-9640460679881796~XXXXXXXXXX</string>
// ============================================================

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:health/health.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:my_flutter_shared/my_flutter_shared.dart'; // 공유 패키지
import 'screens/main_scaffold.dart';

// firebase_options.dart는 flutterfire configure 후 자동 생성
// import 'firebase_options.dart';

// ── [v14] BYOK Gemini API Key 헬퍼 ──────────────────────────────
const _kPrefGeminiKey = 'user_gemini_api_key';
const _kGeminiBase =
    'https://generativelanguage.googleapis.com/v1beta/models/'
    'gemini-2.5-flash:generateContent?key=';

/// 사용자 저장 키 → .env 폴백 → null 순으로 키를 반환
Future<String?> _loadGeminiKey() async {
  final prefs = await SharedPreferences.getInstance();
  final userKey = prefs.getString(_kPrefGeminiKey)?.trim() ?? '';
  if (userKey.isNotEmpty) return userKey;
  final envKey = dotenv.env['GEMINI_API_KEY']?.trim() ?? '';
  if (envKey.isNotEmpty) return envKey;
  return null;
}

/// 호출 전 반드시 null 체크 필요 — null이면 SnackBar 후 중단
Future<String?> _getGeminiUrl() async {
  final key = await _loadGeminiKey();
  if (key == null) return null;
  return '$_kGeminiBase$key';
}

// ── [v15] AdMob 광고 단위 ID ──────────────────────────────────
const _kAdUnitId = 'ca-app-pub-9640460679881796/6213595372';

// ── KST 유틸리티 ────────────────────────────────────────────────
DateTime nowKst() => DateTime.now().toUtc().add(const Duration(hours: 9));
DateTime toKst(DateTime utc) => utc.toUtc().add(const Duration(hours: 9));
bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

// ── 네온 시안 색상 팔레트 ────────────────────────────────────────
class AppColors {
  static const background = Color(0xFF0F172A);
  static const card = Color(0xFF1E293B);
  static const cardBorder = Color(0xFF2D3E55);
  static const accent = Color(0xFF00E5FF);
  static const accentGlow = Color(0x3300E5FF);
  static const green = Color(0xFF2ECC71);
  static const red = Color(0xFFE74C3C);
  static const orange = Color(0xFFFF9500);
  static const textPrimary = Color(0xFFE8EAF6);
  static const textSub = Color(0xFF8899AA);
}

const List<String> kDayLabels = ['월', '화', '수', '목', '금', '토', '일'];

// ============================================================
// main
// ============================================================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  // Firebase 초기화
  await Firebase.initializeApp();

  // [v15] AdMob 초기화 — Firebase 초기화 직후 호출
  await MobileAds.instance.initialize();

  // ── [수정 2] RevenueCat 초기화 (dart-define 방식 적용) ──
  const String rcApiKey = String.fromEnvironment(
    'RC_API_KEY_ANDROID',
    defaultValue: '',
  );
  if (rcApiKey.isNotEmpty) {
    await RevenueCatService().initialize(rcApiKey);
  } else {
    debugPrint('경고: RevenueCat API 키가 설정되지 않았습니다. (--dart-define 확인 필요)');
  }

  // ── [v1.1 추가] 의존성 주입: 로그아웃 시 API 키도 삭제 ──
  final googleSignInService = GoogleSignInService(
    onSignOut: () async {
      await ApiKeyService().deleteApiKey();
    },
  );

  // ── [v1.1 추가] API 키 보안 마이그레이션 리스너 ──
  FirebaseAuth.instance.authStateChanges().listen((User? user) {
    if (user != null) {
      // SharedPreferences에 평문으로 남은 키가 있다면 암호화하여 이전
      ApiKeyService().migrateFromSharedPreferences();
    }
  });

  // 기존 HealthApp 실행 유지
  runApp(const HealthApp());
}

class HealthApp extends StatelessWidget {
  const HealthApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FitTracker',
      theme: ThemeData.dark(),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // 로딩 상태
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: Colors.cyanAccent),
              ),
            );
          }
          // 로그인 상태 (데이터가 있으면 메인 탭 화면으로)
          if (snapshot.hasData && snapshot.data != null) {
            return const MainScaffold();
          }
          // 비로그인 상태 (데이터가 없으면 로그인 화면으로)
          return const LoginScreen();
        },
      ),
    );
  }
}

// ============================================================
// [v13 #1] AuthWrapper
// ============================================================
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            ),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          return const MainScreen();
        }
        return const LoginScreen();
      },
    );
  }
}

// ============================================================
// [v13 #2] LoginScreen
// ============================================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  String _errorMsg = '';

  late final AnimationController _glowCtrl;
  late final Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMsg = '';
    });
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      setState(() {
        _errorMsg = '로그인 중 오류가 발생했어요.\n$e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // 로고 + 글로우
              AnimatedBuilder(
                animation: _glowAnim,
                builder: (_, __) => Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.card,
                    border: Border.all(
                      color: AppColors.accent.withOpacity(_glowAnim.value),
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withOpacity(
                          _glowAnim.value * 0.35,
                        ),
                        blurRadius: 40,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.fitness_center_rounded,
                    color: AppColors.accent,
                    size: 54,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              const Text(
                '헬스 기록',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '운동과 식단을 기록하고\nAI 코치의 맞춤 추천을 받아보세요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSub,
                  fontSize: 15,
                  height: 1.6,
                ),
              ),

              const Spacer(flex: 2),

              _featureRow(Icons.auto_graph_rounded, '체중·러닝·칼로리 자동 기록'),
              const SizedBox(height: 14),
              _featureRow(Icons.phone_android_rounded, 'Health Connect 자동 동기화'),
              const SizedBox(height: 14),
              _featureRow(Icons.smart_toy_rounded, 'Gemini AI 날씨 기반 운동 추천'),

              const Spacer(flex: 3),

              if (_errorMsg.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.red.withOpacity(0.4)),
                  ),
                  child: Text(
                    _errorMsg,
                    style: const TextStyle(color: AppColors.red, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),

              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _signInWithGoogle,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.background,
                    disabledBackgroundColor: AppColors.accent.withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.background,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.account_circle_rounded, size: 26),
                            SizedBox(width: 12),
                            Text(
                              'Google 계정으로 시작하기',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '로그인하면 데이터가 클라우드에 안전하게 저장됩니다.',
                style: TextStyle(color: AppColors.textSub, fontSize: 11),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _featureRow(IconData icon, String text) => Row(
    children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.accentGlow,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.accent, size: 19),
      ),
      const SizedBox(width: 14),
      Text(
        text,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      ),
    ],
  );
}

// ============================================================
// MainScreen
// ============================================================
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // [v13] Firestore 참조 — users/{uid}/records
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  CollectionReference<Map<String, dynamic>> get _recordsRef => FirebaseFirestore
      .instance
      .collection('users')
      .doc(_uid)
      .collection('records');

  bool _isLoading = true;
  String _errorMessage = '';

  String _lastCalorie = '-';
  String _lastRunningKm = '-';
  bool _lastWeightDone = false;

  List<Map<String, dynamic>> _allRecords = [];

  int _periodIndex = 0;
  late DateTime _baseDate;
  late int _selectedDayIndex;

  int _weightPeriodIndex = 2;
  late DateTime _weightBaseDate;

  late final DateTime _todayKst;

  bool _isWeatherLoading = true;
  Map<String, dynamic>? _weatherData;
  String _weatherEmoji = '🌤️';
  bool _isAiCoachLoading = false;
  String _aiCoachMessage = '';

  bool _isHealthSyncing = false;

  // ── [v15] AdMob 배너 광고 ─────────────────────────────────────
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _todayKst = nowKst();
    _baseDate = _todayKst;
    _weightBaseDate = _todayKst;
    _selectedDayIndex = _todayKst.weekday - 1;
    _loadDataFromFirebase();
    _fetchWeatherOnly();
    _loadBannerAd(); // [v15] 배너 광고 로드
  }

  @override
  void dispose() {
    _bannerAd?.dispose(); // [v15] 광고 객체 메모리 해제
    super.dispose();
  }

  // ── [v15] 배너 광고 로드 ──────────────────────────────────────
  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: _kAdUnitId,
      size: AdSize.banner, // 320×50 표준 배너
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) {
            setState(() => _isBannerAdLoaded = true);
          }
        },
        onAdFailedToLoad: (ad, error) {
          // 로드 실패 시 객체 해제 후 배너를 숨김 — 빈 공간 차지 안 함
          debugPrint('[AdMob] 배너 로드 실패: ${error.message}');
          ad.dispose();
          if (mounted) {
            setState(() {
              _bannerAd = null;
              _isBannerAdLoaded = false;
            });
          }
        },
        onAdOpened: (ad) => debugPrint('[AdMob] 배너 클릭됨'),
        onAdClosed: (ad) => debugPrint('[AdMob] 배너 닫힘'),
      ),
    )..load();
  }

  // ── [v15] 배너 광고 위젯 ──────────────────────────────────────
  /// bottomNavigationBar 에 넣을 광고 컨테이너.
  /// 광고가 로드되지 않았으면 SizedBox.shrink() 반환 → 공간 차지 없음.
  Widget _buildBannerAdWidget() {
    if (!_isBannerAdLoaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }
    return Container(
      // 앱 배경과 이질감 없도록 동일 색상 + 얇은 상단 구분선
      color: AppColors.background,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 1, color: AppColors.cardBorder),
          SafeArea(
            top: false,
            child: SizedBox(
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),
          ),
        ],
      ),
    );
  }

  // ── 날씨 (자동) ─────────────────────────────────────────────
  Future<void> _fetchWeatherOnly() async {
    setState(() => _isWeatherLoading = true);
    try {
      final res = await http.get(
        Uri.parse(
          'https://api.open-meteo.com/v1/forecast'
          '?latitude=36.019&longitude=129.343&current_weather=true',
        ),
      );
      if (res.statusCode != 200) {
        setState(() => _isWeatherLoading = false);
        return;
      }
      final cw =
          (jsonDecode(res.body) as Map<String, dynamic>)['current_weather']
              as Map<String, dynamic>;
      setState(() {
        _weatherData = {
          'temperature': (cw['temperature'] as num).toDouble(),
          'windspeed': (cw['windspeed'] as num).toDouble(),
          'weathercode': cw['weathercode'] as int,
        };
        _weatherEmoji = _wmoToEmoji(cw['weathercode'] as int);
        _isWeatherLoading = false;
      });
    } catch (e) {
      debugPrint('[날씨 오류] $e');
      setState(() => _isWeatherLoading = false);
    }
  }

  // ── AI 코치 (수동) ───────────────────────────────────────────
  Future<void> _askAiCoach() async {
    if (_isAiCoachLoading) return;
    // [v14] BYOK 키 검증
    final geminiUrl = await _getGeminiUrl();
    if (geminiUrl == null) {
      _showNoKeySnack();
      return;
    }
    setState(() {
      _isAiCoachLoading = true;
      _aiCoachMessage = '';
    });
    try {
      final temp = _weatherData?['temperature'] as double? ?? 20.0;
      final wind = _weatherData?['windspeed'] as double? ?? 0.0;
      final code = _weatherData?['weathercode'] as int? ?? 0;
      final res = await http.post(
        Uri.parse(geminiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {
                  'text':
                      '현재 기온은 ${temp.toStringAsFixed(1)}도, '
                      '풍속은 ${wind.toStringAsFixed(1)}km/h야. '
                      '날씨 코드는 $code이야. '
                      '사용자가 오늘 러닝을 할지, 실내 웨이트를 할지, 휴식을 할지 '
                      '날씨 상황에 맞춰 1~2문장으로 다정하게 한국어로 추천해 줘. '
                      '부가 설명이나 인사말 없이 추천 문장만 출력해.',
                },
              ],
            },
          ],
        }),
      );
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        setState(
          () => _aiCoachMessage =
              (j['candidates'][0]['content']['parts'][0]['text'] as String)
                  .trim(),
        );
      } else {
        setState(() => _aiCoachMessage = '추천 메시지를 불러오지 못했어요.');
      }
    } catch (e) {
      setState(() => _aiCoachMessage = '네트워크 오류로 추천을 불러오지 못했어요.');
    } finally {
      setState(() => _isAiCoachLoading = false);
    }
  }

  String _wmoToEmoji(int c) {
    if (c == 0) return '☀️';
    if (c <= 2) return '🌤️';
    if (c == 3) return '☁️';
    if (c <= 49) return '🌫️';
    if (c <= 59) return '🌦️';
    if (c <= 69) return '🌧️';
    if (c <= 79) return '🌨️';
    if (c <= 84) return '🌧️';
    if (c <= 99) return '⛈️';
    return '🌤️';
  }

  // ── 기간 이동 ────────────────────────────────────────────────
  void _movePeriod(int dir, {bool isWeight = false}) {
    setState(() {
      if (isWeight) {
        switch (_weightPeriodIndex) {
          case 0:
            _weightBaseDate = _weightBaseDate.add(Duration(days: 7 * dir));
            break;
          case 1:
            final m = _weightBaseDate.month + dir;
            if (m < 1) {
              _weightBaseDate = DateTime(_weightBaseDate.year - 1, 12, 1);
            } else if (m > 12)
              _weightBaseDate = DateTime(_weightBaseDate.year + 1, 1, 1);
            else
              _weightBaseDate = DateTime(_weightBaseDate.year, m, 1);
            break;
          case 2:
            _weightBaseDate = DateTime(_weightBaseDate.year + dir, 1, 1);
            break;
        }
      } else {
        switch (_periodIndex) {
          case 0:
            _baseDate = _baseDate.add(Duration(days: 7 * dir));
            _selectedDayIndex =
                isSameDay(_mondayOf(_baseDate), _mondayOf(_todayKst))
                ? _todayKst.weekday - 1
                : 0;
            break;
          case 1:
            final m = _baseDate.month + dir;
            if (m < 1) {
              _baseDate = DateTime(_baseDate.year - 1, 12, 1);
            } else if (m > 12)
              _baseDate = DateTime(_baseDate.year + 1, 1, 1);
            else
              _baseDate = DateTime(_baseDate.year, m, 1);
            break;
          case 2:
            _baseDate = DateTime(_baseDate.year + dir, 1, 1);
            break;
        }
      }
    });
  }

  DateTime _mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  // ============================================================
  // [v13 #3] Firestore SDK 로드
  // ============================================================
  Future<void> _loadDataFromFirebase() async {
    if (_uid.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = '로그인 정보 없음';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final snap = await _recordsRef
          .orderBy('createdAt', descending: true)
          .get();
      final List<Map<String, dynamic>> parsed = [];

      for (final doc in snap.docs) {
        final data = doc.data();
        final ts = data['createdAt'];
        DateTime kstTime;
        if (ts is Timestamp) {
          kstTime = toKst(ts.toDate());
        } else if (ts is String) {
          final dt = DateTime.tryParse(ts);
          kstTime = dt != null ? toKst(dt) : nowKst();
        } else {
          continue;
        }
        parsed.add({
          'docId': doc.id,
          'kstTime': kstTime,
          'calorie': (data['calorie'] as num?)?.toInt() ?? 0,
          'runningKm': (data['runningKm'] as num?)?.toDouble() ?? 0.0,
          'weight': (data['weight'] as num?)?.toDouble() ?? 0.0,
          'isWeightDone': data['isWeightDone'] as bool? ?? false,
          'food': data['food'] as String? ?? '',
          'source': 'firebase',
        });
      }

      int todayKcal = 0;
      double todayKm = 0.0;
      bool todayWt = false;
      for (final r in parsed) {
        if (!isSameDay(r['kstTime'] as DateTime, _todayKst)) continue;
        todayKcal += r['calorie'] as int;
        todayKm += r['runningKm'] as double;
        if (r['isWeightDone'] == true) todayWt = true;
      }

      setState(() {
        _isLoading = false;
        _allRecords = parsed;
        _lastCalorie = todayKcal.toString();
        _lastRunningKm = todayKm.toStringAsFixed(1);
        _lastWeightDone = todayWt;
      });
      await _fetchLocalHealthDataForBaseDate();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '데이터 로드 오류\n$e';
      });
    }
  }

  // ── HC 스마트 병합 (v12 유지) ─────────────────────────────────
  Future<void> _fetchLocalHealthDataForBaseDate() async {
    setState(() => _isHealthSyncing = true);
    try {
      final status = await Permission.activityRecognition.request();
      if (status.isDenied || status.isPermanentlyDenied) return;

      final health = Health();
      final types = [HealthDataType.STEPS, HealthDataType.WEIGHT];
      final perms = [HealthDataAccess.READ, HealthDataAccess.READ];
      if (!await health.requestAuthorization(types, permissions: perms)) return;

      final firstDay = DateTime(_baseDate.year, _baseDate.month, 1);
      final lastDay = DateTime(
        _baseDate.year,
        _baseDate.month + 1,
        0,
        23,
        59,
        59,
      );
      final effectiveEnd = lastDay.isAfter(_todayKst) ? _todayKst : lastDay;

      final Map<DateTime, double> dailySteps = {};
      for (int i = 0; i < 31; i++) {
        final cur = firstDay.add(Duration(days: i));
        if (cur.month != _baseDate.month || cur.isAfter(_todayKst)) break;
        final end = DateTime(cur.year, cur.month, cur.day, 23, 59, 59);
        final steps = await health.getTotalStepsInInterval(cur, end);
        if (steps != null && steps >= 100) dailySteps[cur] = steps.toDouble();
      }

      final Map<DateTime, double> dailyWeight = {};
      try {
        final wPts = await health.getHealthDataFromTypes(
          startTime: firstDay,
          endTime: effectiveEnd,
          types: [HealthDataType.WEIGHT],
        );
        for (final pt in wPts) {
          final key = DateTime(
            pt.dateFrom.year,
            pt.dateFrom.month,
            pt.dateFrom.day,
          );
          double kg = 0.0;
          if (pt.value is NumericHealthValue) {
            kg = (pt.value as NumericHealthValue).numericValue.toDouble();
          }
          if (kg > 0) dailyWeight[key] = kg;
        }
      } catch (e) {
        debugPrint('[HC 체중 오류] $e');
      }

      if (dailySteps.isEmpty && dailyWeight.isEmpty) return;

      final allDays = <DateTime>{...dailySteps.keys, ...dailyWeight.keys};
      final Map<DateTime, List<int>> fbIdx = {};
      for (var i = 0; i < _allRecords.length; i++) {
        final r = _allRecords[i];
        if ((r['source'] as String?) != 'firebase') continue;
        final dt = r['kstTime'] as DateTime;
        final key = DateTime(dt.year, dt.month, dt.day);
        fbIdx.putIfAbsent(key, () => []).add(i);
      }

      final List<Map<String, dynamic>> auto = [];
      final List<Map<String, dynamic>> updated = List.from(_allRecords);

      for (final day in allDays) {
        final dayKey = DateTime(day.year, day.month, day.day);
        final hcKm = dailySteps.containsKey(dayKey)
            ? double.parse((dailySteps[dayKey]! * 0.0007).toStringAsFixed(2))
            : 0.0;
        final hcWt = dailyWeight[dayKey] ?? 0.0;
        final indices = fbIdx[dayKey];

        if (indices != null && indices.isNotEmpty) {
          for (final idx in indices) {
            final rec = Map<String, dynamic>.from(updated[idx]);
            bool chg = false;
            if ((rec['runningKm'] as double) == 0.0 && hcKm > 0) {
              rec['runningKm'] = hcKm;
              rec['hcEnrichedKm'] = true;
              chg = true;
            }
            if ((rec['weight'] as double) == 0.0 && hcWt > 0) {
              rec['weight'] = hcWt;
              rec['hcEnrichedWeight'] = true;
              chg = true;
            }
            if (chg) updated[idx] = rec;
          }
        } else {
          if (hcKm <= 0 && hcWt <= 0) continue;
          auto.add({
            'kstTime': DateTime(dayKey.year, dayKey.month, dayKey.day, 6, 0),
            'calorie': 0,
            'runningKm': hcKm,
            'weight': hcWt,
            'isWeightDone': false,
            'food': '',
            'source': 'health_connect',
            'isAutoSync': true,
            'steps': dailySteps.containsKey(dayKey)
                ? dailySteps[dayKey]!.toInt()
                : 0,
          });
        }
      }

      final merged = [...updated, ...auto];
      merged.sort(
        (a, b) =>
            (b['kstTime'] as DateTime).compareTo(a['kstTime'] as DateTime),
      );
      setState(() => _allRecords = merged);
    } catch (e) {
      debugPrint('[HC 오류] $e');
    } finally {
      setState(() => _isHealthSyncing = false);
    }
  }

  // ── 차트 데이터 ──────────────────────────────────────────────
  List<Map<String, dynamic>> _generateChartData(DateTime base, int period) {
    switch (period) {
      case 0:
        final monday = _mondayOf(base);
        final days = List.generate(7, (i) => monday.add(Duration(days: i)));
        final kc = {for (var i = 0; i < 7; i++) i: 0};
        final km = {for (var i = 0; i < 7; i++) i: 0.0};
        final wt = {for (var i = 0; i < 7; i++) i: <double>[]};
        for (final r in _allRecords) {
          final dt = r['kstTime'] as DateTime;
          final idx = days.indexWhere((d) => isSameDay(d, dt));
          if (idx < 0) continue;
          kc[idx] = kc[idx]! + (r['calorie'] as int);
          km[idx] = km[idx]! + (r['runningKm'] as double);
          final w = r['weight'] as double;
          if (w > 0) wt[idx]!.add(w);
        }
        return List.generate(7, (i) {
          final w = wt[i]!;
          final dd = days[i];
          return {
            'day': '${dd.day}(${kDayLabels[i]})',
            'date': dd,
            'kcal': kc[i]!,
            'km': km[i]!,
            'weight': w.isEmpty ? 0.0 : w.reduce((a, b) => a + b) / w.length,
          };
        });

      case 1:
        final mo = base.month;
        final yr = base.year;
        final kc = {for (var i = 0; i < 5; i++) i: 0};
        final km = {for (var i = 0; i < 5; i++) i: 0.0};
        final wt = {for (var i = 0; i < 5; i++) i: <double>[]};
        for (final r in _allRecords) {
          final dt = r['kstTime'] as DateTime;
          if (dt.year != yr || dt.month != mo) continue;
          final wi = ((dt.day - 1) ~/ 7).clamp(0, 4);
          kc[wi] = kc[wi]! + (r['calorie'] as int);
          km[wi] = km[wi]! + (r['runningKm'] as double);
          final w = r['weight'] as double;
          if (w > 0) wt[wi]!.add(w);
        }
        return List.generate(5, (i) {
          final w = wt[i]!;
          return {
            'day': '${i + 1}주',
            'date': DateTime(yr, mo, (i * 7) + 1),
            'kcal': kc[i]!,
            'km': km[i]!,
            'weight': w.isEmpty ? 0.0 : w.reduce((a, b) => a + b) / w.length,
          };
        });

      default:
        final yr = base.year;
        final kc = {for (var i = 1; i <= 12; i++) i: 0};
        final km = {for (var i = 1; i <= 12; i++) i: 0.0};
        final wt = {for (var i = 1; i <= 12; i++) i: <double>[]};
        for (final r in _allRecords) {
          final dt = r['kstTime'] as DateTime;
          if (dt.year != yr) continue;
          kc[dt.month] = kc[dt.month]! + (r['calorie'] as int);
          km[dt.month] = km[dt.month]! + (r['runningKm'] as double);
          final w = r['weight'] as double;
          if (w > 0) wt[dt.month]!.add(w);
        }
        return List.generate(12, (i) {
          final m = i + 1;
          final w = wt[m]!;
          return {
            'day': '$m월',
            'date': DateTime(yr, m, 1),
            'kcal': kc[m]!,
            'km': km[m]!,
            'weight': w.isEmpty ? 0.0 : w.reduce((a, b) => a + b) / w.length,
          };
        });
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
  String _fmtTime(DateTime k) => '${_pad(k.hour)}:${_pad(k.minute)}';

  DateTime? _selectedDate() {
    for (final item in _generateChartData(_baseDate, _periodIndex)) {
      if ((item['date'] as DateTime).weekday - 1 == _selectedDayIndex) {
        return item['date'] as DateTime;
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _filteredTimeline() {
    final sel = _selectedDate();
    if (sel == null) return [];
    return _allRecords
        .where((r) => isSameDay(r['kstTime'] as DateTime, sel))
        .toList()
      ..sort(
        (a, b) =>
            (a['kstTime'] as DateTime).compareTo(b['kstTime'] as DateTime),
      );
  }

  Future<void> _goToAddScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddRecordScreen(allRecords: _allRecords),
      ),
    );
    _loadDataFromFirebase();
  }

  Future<void> _onSyncTapped() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('서버 및 기기 데이터를 동기화합니다.'),
        backgroundColor: AppColors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
    await _loadDataFromFirebase();
    _fetchWeatherOnly();
  }

  // ── [v14] API 키 없음 안내 SnackBar ──────────────────────────
  void _showNoKeySnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('설정에서 API 키를 먼저 등록해 주세요!'),
        backgroundColor: AppColors.orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: '설정으로',
          textColor: AppColors.background,
          onPressed: _goToSettings,
        ),
      ),
    );
  }

  // ── [v14] 설정 화면 이동 ─────────────────────────────────────
  Future<void> _goToSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  // ── [v13 #4] 로그아웃 ───────────────────────────────────────
  Future<void> _onLogoutTapped() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '로그아웃',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          '정말 로그아웃 하시겠습니까?\n다음에 다시 로그인하면 데이터가 유지됩니다.',
          style: TextStyle(color: AppColors.textSub, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: AppColors.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '로그아웃',
              style: TextStyle(
                color: AppColors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await GoogleSignIn().signOut();
      await FirebaseAuth.instance.signOut();
    }
  }

  String _buildPeriodLabel(DateTime base, int period) {
    switch (period) {
      case 0:
        final mo = _mondayOf(base);
        final su = mo.add(const Duration(days: 6));
        return '${mo.month}/${mo.day} ~ ${su.month}/${su.day}';
      case 1:
        return '${base.year}년 ${base.month}월';
      case 2:
        return '${base.year}년';
      default:
        return '';
    }
  }

  bool _canGoNext(DateTime base, int period) {
    switch (period) {
      case 0:
        return _mondayOf(base).isBefore(_mondayOf(_todayKst));
      case 1:
        return base.year < _todayKst.year ||
            (base.year == _todayKst.year && base.month < _todayKst.month);
      case 2:
        return base.year < _todayKst.year;
      default:
        return false;
    }
  }

  // ── Build ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    // [v15] 광고가 로드된 경우 배너 높이만큼 스크롤 하단 패딩 추가
    // 배너(50) + 구분선(1) + 기존 FAB 여백(100) = 151
    final double scrollBottomPadding = _isBannerAdLoaded ? 151.0 : 100.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.accentGlow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.fitness_center,
                color: AppColors.accent,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              '헬스 기록',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            if (_isHealthSyncing) ...[
              const SizedBox(width: 10),
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.green,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                '동기화 중',
                style: TextStyle(color: AppColors.green, fontSize: 10),
              ),
            ],
          ],
        ),
      ),

      // ── [v15] bottomNavigationBar 에 배너 광고 배치 ─────────────
      // FAB은 배너 위에 렌더링되므로 광고에 절대 가려지지 않음.
      bottomNavigationBar: _buildBannerAdWidget(),

      // [v12 유지] 좌=흰색 동기화, 우=시안 추가
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            FloatingActionButton(
              heroTag: 'fab_sync',
              onPressed: (_isLoading || _isHealthSyncing)
                  ? null
                  : _onSyncTapped,
              backgroundColor: Colors.white,
              elevation: 6,
              tooltip: '데이터 동기화',
              child: (_isLoading || _isHealthSyncing)
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF1E293B),
                      ),
                    )
                  : const Icon(Icons.sync_rounded, color: Color(0xFF1E293B)),
            ),
            FloatingActionButton(
              heroTag: 'fab_add',
              onPressed: _goToAddScreen,
              backgroundColor: AppColors.accent,
              elevation: 4,
              tooltip: '기록 추가',
              child: const Icon(Icons.add, color: AppColors.background),
            ),
          ],
        ),
      ),

      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppColors.accent),
                  SizedBox(height: 16),
                  Text(
                    'Firestore에서 불러오는 중...',
                    style: TextStyle(color: AppColors.textSub),
                  ),
                ],
              ),
            )
          : _buildMainContent(scrollBottomPadding),
    );
  }

  Widget _buildMainContent(double bottomPadding) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAiCoachCard(),
        const SizedBox(height: 16),
        if (_errorMessage.isNotEmpty) _buildErrorBanner(),
        _buildSummaryRow(),
        const SizedBox(height: 24),
        _buildRunningCalorieCard(),
        const SizedBox(height: 16),
        _buildWeightCard(),
        const SizedBox(height: 24),
        _buildRoutineBadges(),
        const SizedBox(height: 24),
        _buildTimeline(),
        const SizedBox(height: 24),
      ],
    ),
  );

  Widget _buildErrorBanner() => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.red.withOpacity(0.15),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.red.withOpacity(0.4)),
    ),
    child: Row(
      children: [
        const Icon(Icons.cloud_off_rounded, color: AppColors.red, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _errorMessage.replaceAll('\n', ' '),
            style: const TextStyle(color: AppColors.red, fontSize: 12),
          ),
        ),
        GestureDetector(
          onTap: _loadDataFromFirebase,
          child: const Text(
            '재시도',
            style: TextStyle(
              color: AppColors.accent,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );

  // ── AI 코치 카드 ─────────────────────────────────────────────
  Widget _buildAiCoachCard() {
    String wi = '';
    if (_weatherData != null) {
      wi =
          '$_weatherEmoji  '
          '${(_weatherData!['temperature'] as double).toStringAsFixed(1)}°C  '
          '💨 ${(_weatherData!['windspeed'] as double).toStringAsFixed(1)} km/h';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.accent.withOpacity(0.12), AppColors.card],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.accent.withOpacity(0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accentGlow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.accent.withOpacity(0.5)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🤖', style: TextStyle(fontSize: 13)),
                    SizedBox(width: 4),
                    Text(
                      'AI 코치',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (_isWeatherLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.textSub,
                  ),
                )
              else if (wi.isNotEmpty)
                Text(
                  wi,
                  style: const TextStyle(
                    color: AppColors.textSub,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (_isAiCoachLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accent,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'AI 코치가 분석 중이에요...',
                    style: TextStyle(color: AppColors.textSub, fontSize: 13),
                  ),
                ],
              ),
            )
          else if (_aiCoachMessage.isNotEmpty) ...[
            Text(
              _aiCoachMessage,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                height: 1.65,
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _askAiCoach,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.refresh_rounded,
                    size: 13,
                    color: AppColors.textSub,
                  ),
                  SizedBox(width: 4),
                  Text(
                    '다시 추천받기',
                    style: TextStyle(color: AppColors.textSub, fontSize: 11),
                  ),
                ],
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _askAiCoach,
                icon: const Text('✨', style: TextStyle(fontSize: 16)),
                label: const Text(
                  '오늘의 운동 추천받기',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.background,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Center(
              child: Text(
                '날씨 데이터를 기반으로 Gemini AI가 추천해요',
                style: TextStyle(color: AppColors.textSub, fontSize: 10),
              ),
            ),
          ],
          if (!_isWeatherLoading && _weatherData != null) ...[
            const SizedBox(height: 8),
            const Text(
              '📍 포항 기준 · Open-Meteo',
              style: TextStyle(color: AppColors.textSub, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  // ── 요약 카드 ─────────────────────────────────────────────────
  Widget _buildSummaryRow() => Row(
    children: [
      Expanded(
        child: _statCard(
          icon: Icons.local_fire_department,
          label: '오늘 칼로리',
          value: _lastCalorie,
          unit: 'kcal',
          color: AppColors.red,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _statCard(
          icon: Icons.directions_run,
          label: '오늘 러닝',
          value: _lastRunningKm,
          unit: 'km',
          color: AppColors.orange,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _statCard(
          icon: Icons.fitness_center,
          label: '웨이트',
          value: _lastWeightDone ? '완료' : '미완',
          unit: '',
          color: _lastWeightDone ? AppColors.green : AppColors.textSub,
        ),
      ),
    ],
  );

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (unit.isNotEmpty)
            Text(
              unit,
              style: const TextStyle(color: AppColors.textSub, fontSize: 10),
            ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: AppColors.textSub, fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ── 카드1: 러닝/칼로리 ────────────────────────────────────────
  Widget _buildRunningCalorieCard() {
    final cd = _generateChartData(_baseDate, _periodIndex);
    final kmT = _periodIndex == 1
        ? '🏃 월간 러닝 거리 (주차별)'
        : _periodIndex == 2
        ? '🏃 연간 러닝 거리 (월별)'
        : '🏃 주간 러닝 거리';
    final calT = _periodIndex == 1
        ? '🔥 월간 칼로리 (주차별)'
        : _periodIndex == 2
        ? '🔥 연간 칼로리 (월별)'
        : '🔥 주간 칼로리';
    return _darkCard(
      title: '',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _periodToggle(
            selected: _periodIndex,
            onChanged: (i) => setState(() => _periodIndex = i),
          ),
          const SizedBox(height: 12),
          _periodNav(
            label: _buildPeriodLabel(_baseDate, _periodIndex),
            onPrev: () => _movePeriod(-1),
            onNext: _canGoNext(_baseDate, _periodIndex)
                ? () => _movePeriod(1)
                : null,
          ),
          const SizedBox(height: 16),
          Text(
            kmT,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _barGraph(
            chartData: cd,
            data: cd.map((e) => e['km'] as double).toList(),
            color: AppColors.orange,
            unit: 'km',
            decimals: 1,
            periodIndex: _periodIndex,
            selectedDay: _selectedDayIndex,
            onTap: (i, item) => _onRunningBarTapped(i, item),
          ),
          const SizedBox(height: 24),
          Text(
            calT,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _barGraph(
            chartData: cd,
            data: cd.map((e) => (e['kcal'] as int).toDouble()).toList(),
            color: AppColors.red,
            unit: 'kcal',
            decimals: 0,
            periodIndex: _periodIndex,
            selectedDay: _selectedDayIndex,
            onTap: (i, item) => _onRunningBarTapped(i, item),
          ),
        ],
      ),
    );
  }

  // ── 카드2: 체중 ───────────────────────────────────────────────
  Widget _buildWeightCard() {
    final wtT = _weightPeriodIndex == 1
        ? '⚖️ 월간 체중 추이'
        : _weightPeriodIndex == 2
        ? '⚖️ 연간 체중 추이'
        : '⚖️ 주간 체중 추이';
    return _darkCard(
      title: '',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _periodToggle(
            selected: _weightPeriodIndex,
            onChanged: (i) => setState(() => _weightPeriodIndex = i),
          ),
          const SizedBox(height: 12),
          _periodNav(
            label: _buildPeriodLabel(_weightBaseDate, _weightPeriodIndex),
            onPrev: () => _movePeriod(-1, isWeight: true),
            onNext: _canGoNext(_weightBaseDate, _weightPeriodIndex)
                ? () => _movePeriod(1, isWeight: true)
                : null,
          ),
          const SizedBox(height: 16),
          Text(
            wtT,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _flWeightLineChart(),
        ],
      ),
    );
  }

  void _onRunningBarTapped(int index, Map<String, dynamic> item) {
    final date = item['date'] as DateTime;
    setState(() {
      switch (_periodIndex) {
        case 2:
          _baseDate = DateTime(date.year, date.month, 1);
          _periodIndex = 1;
          break;
        case 1:
          _baseDate = date;
          _periodIndex = 0;
          _selectedDayIndex = 0;
          break;
        case 0:
          _selectedDayIndex = index;
          break;
      }
    });
  }

  Widget _periodToggle({
    required int selected,
    required void Function(int) onChanged,
  }) => Center(
    child: Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: ToggleButtons(
        isSelected: [selected == 0, selected == 1, selected == 2],
        onPressed: onChanged,
        borderRadius: BorderRadius.circular(10),
        selectedColor: AppColors.background,
        color: AppColors.textSub,
        fillColor: AppColors.accent,
        borderColor: Colors.transparent,
        selectedBorderColor: Colors.transparent,
        constraints: const BoxConstraints(minWidth: 80, minHeight: 36),
        children: const [
          Text('주간', style: TextStyle(fontWeight: FontWeight.bold)),
          Text('월간', style: TextStyle(fontWeight: FontWeight.bold)),
          Text('연간', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    ),
  );

  Widget _periodNav({
    required String label,
    required VoidCallback onPrev,
    VoidCallback? onNext,
  }) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      _navBtn(icon: Icons.chevron_left_rounded, onTap: onPrev),
      Text(
        label,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
      _navBtn(icon: Icons.chevron_right_rounded, onTap: onNext),
    ],
  );

  Widget _navBtn({required IconData icon, VoidCallback? onTap}) {
    final en = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: en
              ? AppColors.accentGlow
              : AppColors.cardBorder.withOpacity(0.3),
          shape: BoxShape.circle,
          border: Border.all(
            color: en ? AppColors.accent : AppColors.cardBorder,
          ),
        ),
        child: Icon(
          icon,
          size: 20,
          color: en ? AppColors.accent : AppColors.textSub.withOpacity(0.4),
        ),
      ),
    );
  }

  Widget _barGraph({
    required List<Map<String, dynamic>> chartData,
    required List<double> data,
    required Color color,
    required String unit,
    required int periodIndex,
    required int selectedDay,
    required void Function(int, Map<String, dynamic>) onTap,
    int decimals = 0,
  }) {
    if (chartData.isEmpty) {
      return const SizedBox(
        height: 60,
        child: Center(
          child: Text(
            '데이터가 없어요',
            style: TextStyle(color: AppColors.textSub, fontSize: 12),
          ),
        ),
      );
    }
    final maxV = data.reduce(math.max).clamp(0.001, double.infinity);
    final bw = chartData.length >= 12
        ? 18.0
        : chartData.length >= 7
        ? 24.0
        : 32.0;
    final ls = chartData.length >= 12
        ? 8.5
        : chartData.length >= 7
        ? 9.0
        : 10.5;
    final vs = chartData.length >= 12 ? 8.0 : 9.0;

    return SizedBox(
      height: 130,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(chartData.length, (i) {
          final item = chartData[i];
          final val = data[i];
          final ratio = (val / maxV).clamp(0.0, 1.0);
          final hl = (periodIndex == 0)
              ? (isSameDay(item['date'] as DateTime, _todayKst) ||
                    i == selectedDay)
              : ((item['date'] as DateTime).month == _todayKst.month &&
                    (item['date'] as DateTime).year == _todayKst.year);

          return GestureDetector(
            onTap: () => onTap(i, item),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (val > 0)
                  Text(
                    decimals > 0
                        ? val.toStringAsFixed(decimals)
                        : val.toInt().toString(),
                    style: TextStyle(
                      color: hl ? color : AppColors.textSub,
                      fontSize: vs,
                    ),
                  )
                else
                  SizedBox(height: vs + 3),
                const SizedBox(height: 2),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOut,
                  width: bw,
                  height: math.max(80 * ratio, val > 0 ? 4.0 : 0.0),
                  decoration: BoxDecoration(
                    gradient: val > 0
                        ? LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: hl
                                ? [color, color.withOpacity(0.5)]
                                : [
                                    AppColors.cardBorder,
                                    AppColors.textSub.withOpacity(0.3),
                                  ],
                          )
                        : null,
                    color: val == 0
                        ? AppColors.cardBorder.withOpacity(0.3)
                        : null,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item['day'] as String,
                  overflow: TextOverflow.visible,
                  softWrap: false,
                  style: TextStyle(
                    color: hl ? color : AppColors.textSub,
                    fontSize: ls,
                    fontWeight: hl ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── fl_chart 체중 선형 그래프 (네온 시안) ─────────────────────
  Widget _flWeightLineChart() {
    DateTime rs, re;
    switch (_weightPeriodIndex) {
      case 0:
        rs = _mondayOf(_weightBaseDate);
        re = rs.add(const Duration(days: 6, hours: 23, minutes: 59));
        break;
      case 1:
        rs = DateTime(_weightBaseDate.year, _weightBaseDate.month, 1);
        re = DateTime(
          _weightBaseDate.year,
          _weightBaseDate.month + 1,
          0,
          23,
          59,
        );
        break;
      default:
        rs = DateTime(_weightBaseDate.year, 1, 1);
        re = DateTime(_weightBaseDate.year, 12, 31, 23, 59);
    }

    final List<_WeightPoint> raw = [];
    for (final r in _allRecords) {
      final dt = r['kstTime'] as DateTime;
      final w = r['weight'] as double;
      if (w <= 0 || dt.isBefore(rs) || dt.isAfter(re)) continue;
      final dk = DateTime(dt.year, dt.month, dt.day);
      raw.removeWhere((p) => isSameDay(p.date, dk));
      raw.add(_WeightPoint(date: dk, weight: w));
    }
    raw.sort((a, b) => a.date.compareTo(b.date));

    if (raw.isEmpty) {
      return Container(
        height: 160,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.monitor_weight_outlined,
              color: AppColors.textSub,
              size: 32,
            ),
            const SizedBox(height: 8),
            const Text(
              '이 기간에 체중 기록이 없어요',
              style: TextStyle(color: AppColors.textSub, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              _weightPeriodIndex == 0
                  ? '+ 버튼으로 체중을 기록해보세요!'
                  : '다른 기간을 선택하거나\nHealth Connect를 동기화해 보세요.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSub, fontSize: 11),
            ),
          ],
        ),
      );
    }

    final spots = raw
        .map((p) => FlSpot(p.date.millisecondsSinceEpoch / 1e9, p.weight))
        .toList();
    final minX = spots.first.x;
    final maxX = spots.last.x;
    final ws = spots.map((s) => s.y).toList();
    final minW = ws.reduce(math.min);
    final maxW = ws.reduce(math.max);
    final yPad = math.max((maxW - minW) * 0.25, 1.0);
    final minY = (minW - yPad).floorToDouble();
    final maxY = (maxW + yPad).ceilToDouble();
    final xi = spots.length <= 1
        ? (maxX - minX + 1.0)
        : (maxX - minX) / math.min(spots.length - 1, 5).clamp(1, 100);

    const cyan = AppColors.accent;
    const cyanDim = Color(0x5500E5FF);
    const cyanGlw = Color(0x1A00E5FF);

    return SizedBox(
      height: 200,
      child: Padding(
        padding: const EdgeInsets.only(right: 12, top: 8, bottom: 4),
        child: LineChart(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          LineChartData(
            minX: minX - xi * 0.3,
            maxX: maxX + xi * 0.3,
            minY: minY,
            maxY: maxY,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: math.max((maxY - minY) / 4, 0.5),
              getDrawingHorizontalLine: (_) => FlLine(
                color: AppColors.cardBorder.withOpacity(0.6),
                strokeWidth: 1,
                dashArray: [4, 4],
              ),
            ),
            borderData: FlBorderData(
              show: true,
              border: Border(
                bottom: BorderSide(
                  color: AppColors.cardBorder.withOpacity(0.8),
                  width: 1,
                ),
                left: BorderSide(
                  color: AppColors.cardBorder.withOpacity(0.8),
                  width: 1,
                ),
              ),
            ),
            titlesData: FlTitlesData(
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 44,
                  interval: math.max((maxY - minY) / 4, 0.5),
                  getTitlesWidget: (v, m) {
                    if (v == m.min || v == m.max) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      meta: m,
                      space: 4,
                      child: Text(
                        v.toStringAsFixed(1),
                        style: const TextStyle(
                          color: AppColors.textSub,
                          fontSize: 9.5,
                        ),
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  interval: xi,
                  getTitlesWidget: (v, m) {
                    FlSpot? cl;
                    double md = double.infinity;
                    for (final s in spots) {
                      final d = (s.x - v).abs();
                      if (d < md) {
                        md = d;
                        cl = s;
                      }
                    }
                    if (cl == null || md > xi * 0.6) {
                      return const SizedBox.shrink();
                    }
                    final dt = DateTime.fromMillisecondsSinceEpoch(
                      (cl.x * 1e9).toInt(),
                    );
                    final lb = _weightPeriodIndex == 2
                        ? '${dt.month}월'
                        : '${dt.month}/${dt.day}';
                    return SideTitleWidget(
                      meta: m,
                      space: 4,
                      child: Text(
                        lb,
                        style: const TextStyle(
                          color: AppColors.textSub,
                          fontSize: 9.5,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              enabled: true,
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => AppColors.card,
                tooltipBorderRadius: BorderRadius.circular(10),
                tooltipPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                getTooltipItems: (ts) => ts.map((s) {
                  final dt = DateTime.fromMillisecondsSinceEpoch(
                    (s.x * 1e9).toInt(),
                  );
                  return LineTooltipItem(
                    '${dt.month}/${dt.day}(${kDayLabels[dt.weekday - 1]})\n${s.y.toStringAsFixed(1)} kg',
                    const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                }).toList(),
              ),
              getTouchedSpotIndicator: (bd, si) => si
                  .map(
                    (i) => TouchedSpotIndicatorData(
                      FlLine(
                        color: cyanDim,
                        strokeWidth: 1.5,
                        dashArray: [4, 3],
                      ),
                      FlDotData(
                        show: true,
                        getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                          radius: 5,
                          color: cyan,
                          strokeWidth: 2,
                          strokeColor: AppColors.card,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                curveSmoothness: 0.35,
                preventCurveOverShooting: true,
                isStrokeCapRound: true,
                barWidth: 2.5,
                gradient: LinearGradient(
                  colors: [
                    cyan.withOpacity(0.6),
                    cyan,
                    const Color(0xFFAAF4FF),
                  ],
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    colors: [cyanDim, cyanGlw],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                    radius: spots.length <= 7 ? 4.5 : 3.0,
                    color: cyan,
                    strokeWidth: 1.5,
                    strokeColor: AppColors.card,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 루틴 뱃지 ────────────────────────────────────────────────
  Widget _buildRoutineBadges() {
    final cd = _generateChartData(_baseDate, 0);
    final Set<int> act = {};
    for (var i = 0; i < cd.length; i++) {
      if ((cd[i]['kcal'] as int) > 0 ||
          (cd[i]['km'] as double) > 0 ||
          (cd[i]['weight'] as double) > 0) {
        act.add(i);
      }
    }
    final isThisWeek = isSameDay(_mondayOf(_baseDate), _mondayOf(_todayKst));
    final todayIdx = isThisWeek ? _todayKst.weekday - 1 : -1;

    return _darkCard(
      title: '🗓️ 루틴 현황  (탭하면 해당 날의 기록을 볼 수 있어요)',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(7, (i) {
          final isA = act.contains(i);
          final isT = i == todayIdx;
          final isS = i == _selectedDayIndex;
          final bg = isS
              ? AppColors.accent
              : isA
              ? AppColors.green.withOpacity(0.25)
              : AppColors.cardBorder;
          final tc = isS
              ? AppColors.background
              : isA
              ? AppColors.green
              : AppColors.textSub;

          return GestureDetector(
            onTap: () => setState(() => _selectedDayIndex = i),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: bg,
                    border: isT
                        ? Border.all(color: AppColors.accent, width: 2)
                        : isS
                        ? Border.all(color: AppColors.background, width: 1.5)
                        : null,
                    boxShadow: isS
                        ? [
                            BoxShadow(
                              color: AppColors.accent.withOpacity(0.45),
                              blurRadius: 10,
                            ),
                          ]
                        : isA
                        ? [
                            BoxShadow(
                              color: AppColors.green.withOpacity(0.25),
                              blurRadius: 6,
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      kDayLabels[i],
                      style: TextStyle(
                        color: tc,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  cd.isNotEmpty ? '${(cd[i]['date'] as DateTime).day}' : '',
                  style: TextStyle(
                    color: isS
                        ? AppColors.accent
                        : isA
                        ? AppColors.green
                        : AppColors.textSub.withOpacity(0.6),
                    fontSize: 9,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isS
                        ? AppColors.accent
                        : isA
                        ? AppColors.green
                        : Colors.transparent,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── 타임라인 ─────────────────────────────────────────────────
  Widget _buildTimeline() {
    final sel = _selectedDate();
    final tl = _filteredTimeline();
    String title = '⏱️ 타임라인';
    if (sel != null) {
      title = isSameDay(sel, _todayKst)
          ? '⏱️ 오늘의 타임라인'
          : '⏱️ ${sel.month}/${sel.day}(${kDayLabels[sel.weekday - 1]}) 타임라인';
    }
    return _darkCard(
      title: title,
      child: tl.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  sel == null
                      ? '날짜 데이터를 불러올 수 없어요.'
                      : '이 날의 기록이 없어요.\n+ 버튼으로 추가해보세요!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSub,
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
              ),
            )
          : Column(
              children: List.generate(tl.length, (i) {
                final rec = tl[i];
                final kt = rec['kstTime'] as DateTime;
                final fd = rec['food'] as String;
                final kc = rec['calorie'] as int;
                final rn = rec['runningKm'] as double;
                final wv = rec['weight'] as double;
                final wd = rec['isWeightDone'] as bool;
                final as_ = rec['isAutoSync'] as bool? ?? false;
                final st = rec['steps'] as int?;
                final ek = rec['hcEnrichedKm'] as bool? ?? false;
                final ew = rec['hcEnrichedWeight'] as bool? ?? false;
                final il = i == tl.length - 1;

                final pts = <String>[];
                if (fd.isNotEmpty) pts.add(fd);
                if (kc > 0) pts.add('$kc kcal');
                if (rn > 0) {
                  pts.add(
                    ek
                        ? '러닝 ${rn.toStringAsFixed(1)}km 📱'
                        : '러닝 ${rn.toStringAsFixed(1)}km',
                  );
                }
                if (wd) pts.add('웨이트 ✅');
                if (wv > 0) {
                  pts.add(
                    ew
                        ? '체중 ${wv.toStringAsFixed(1)}kg 📱'
                        : '체중 ${wv.toStringAsFixed(1)}kg',
                  );
                }
                if (as_ && st != null && st > 0) {
                  pts.add(
                    '${st.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}보 📱',
                  );
                }
                final sum = pts.isEmpty ? '(내용 없음)' : pts.join('  •  ');
                final eb = ek || ew;

                final IconData di;
                final Color dc;
                if (as_) {
                  di = Icons.phone_android;
                  dc = AppColors.green;
                } else if (eb) {
                  di = Icons.sync;
                  dc = AppColors.accent;
                } else if (fd.isNotEmpty || kc > 0) {
                  di = Icons.restaurant;
                  dc = AppColors.red;
                } else if (rn > 0) {
                  di = Icons.directions_run;
                  dc = AppColors.orange;
                } else {
                  di = Icons.fitness_center;
                  dc = AppColors.green;
                }

                String? sl;
                if (as_) {
                  sl = '📱 헬스 커넥트 자동 연동';
                } else if (eb) {
                  final en = <String>[];
                  if (ek) en.add('러닝');
                  if (ew) en.add('체중');
                  sl = '📱 ${en.join('·')} 헬스 커넥트로 자동 보완';
                }

                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 46,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            as_ ? '자동' : _fmtTime(kt),
                            style: const TextStyle(
                              color: AppColors.textSub,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      Column(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: dc.withOpacity(0.15),
                              border: Border.all(color: dc, width: 1.5),
                            ),
                            child: Icon(di, color: dc, size: 13),
                          ),
                          if (!il)
                            Expanded(
                              child: Container(
                                width: 1.5,
                                color: AppColors.cardBorder,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(top: 6, bottom: il ? 0 : 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sum,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                              ),
                              if (sl != null)
                                Text(
                                  sl,
                                  style: const TextStyle(
                                    color: AppColors.textSub,
                                    fontSize: 10,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
    );
  }

  Widget _darkCard({required String title, required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.cardBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) ...[
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
        ],
        child,
      ],
    ),
  );
}

// ── 체중 데이터 포인트 ────────────────────────────────────────
class _WeightPoint {
  final DateTime date;
  final double weight;
  const _WeightPoint({required this.date, required this.weight});
}

// ============================================================
// AddRecordScreen — [v13] Firestore SDK 저장
// ============================================================
class AddRecordScreen extends StatefulWidget {
  final List<Map<String, dynamic>> allRecords;
  const AddRecordScreen({super.key, required this.allRecords});
  @override
  State<AddRecordScreen> createState() => _AddRecordScreenState();
}

class _AddRecordScreenState extends State<AddRecordScreen> {
  final _weightCtrl = TextEditingController();
  final _foodCtrl = TextEditingController();
  final _calorieCtrl = TextEditingController();
  final _runningCtrl = TextEditingController();

  bool _isWeightDone = false;
  bool _isAiLoading = false;
  bool _isSaving = false;
  bool _isRunningImgLoading = false;
  bool _isFoodImgLoading = false;

  late DateTime _selectedKst;
  final _picker = ImagePicker();

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  CollectionReference<Map<String, dynamic>> get _recordsRef => FirebaseFirestore
      .instance
      .collection('users')
      .doc(_uid)
      .collection('records');

  @override
  void initState() {
    super.initState();
    _selectedKst = nowKst();
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _foodCtrl.dispose();
    _calorieCtrl.dispose();
    _runningCtrl.dispose();
    super.dispose();
  }

  Future<void> _analyzeRunningImage() async {
    // [v14] BYOK 키 검증
    final geminiUrl = await _getGeminiUrl();
    if (geminiUrl == null) {
      _snack('설정에서 API 키를 먼저 등록해 주세요!', isError: true);
      return;
    }
    setState(() => _isRunningImgLoading = true);
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await File(picked.path).readAsBytes();
      final b64 = base64Encode(bytes);
      final mime =
          picked.mimeType ??
          (picked.path.toLowerCase().endsWith('.png')
              ? 'image/png'
              : 'image/jpeg');
      final yr = DateTime.now().year;

      final res = await http.post(
        Uri.parse(geminiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {
                  'text':
                      '이 사진은 러닝 앱 스크린샷이야. 올해는 $yr년이야. '
                      '사진에서 운동을 시작한 날짜와 시간을 유추해서 '
                      '무조건 \'YYYY-MM-DD|HH:MM|거리\' 형식으로 대답해. '
                      '시간은 반드시 24시간제(예: 오후 8시 9분 → 20:09)로 변환해서 적어. '
                      '날짜/시간을 찾을 수 없으면 그 부분만 NONE으로 적어. '
                      '(예: 2026-03-09|20:09|5.2 또는 NONE|NONE|5.2). '
                      '부가 설명 절대 금지.',
                },
                {
                  'inline_data': {'mime_type': mime, 'data': b64},
                },
              ],
            },
          ],
        }),
      );
      if (res.statusCode != 200) {
        _snack(
          'Gemini 오류: ${(jsonDecode(res.body))['error']?['message']}',
          isError: true,
        );
        return;
      }
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final raw = j['candidates'][0]['content']['parts'][0]['text'] as String;
      final pts = raw.trim().split('|');
      if (pts.length < 3) {
        _snack('사진에서 정보를 읽지 못했어요.', isError: true);
        return;
      }

      final dp = pts[0].trim();
      final tp = pts[1].trim();
      final dist = pts[2].trim();
      final dm = RegExp(r'\d+\.?\d*').firstMatch(dist);
      if (dm != null) setState(() => _runningCtrl.text = dm.group(0)!);

      bool tu = false;
      if (dp != 'NONE' && tp != 'NONE') {
        final dM = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(dp);
        final tM = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(tp);
        if (dM != null && tM != null) {
          final y = int.parse(dM.group(1)!);
          final mo = int.parse(dM.group(2)!);
          final d = int.parse(dM.group(3)!);
          final h = int.parse(tM.group(1)!);
          final mi = int.parse(tM.group(2)!);
          if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31 && h <= 23 && mi <= 59) {
            setState(() => _selectedKst = DateTime(y, mo, d, h, mi));
            tu = true;
          }
        }
      } else if (dp != 'NONE') {
        final dM = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(dp);
        if (dM != null) {
          final y = int.parse(dM.group(1)!);
          final mo = int.parse(dM.group(2)!);
          final d = int.parse(dM.group(3)!);
          if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) {
            setState(
              () => _selectedKst = DateTime(
                y,
                mo,
                d,
                _selectedKst.hour,
                _selectedKst.minute,
              ),
            );
            tu = true;
          }
        }
      }
      final ds = dm?.group(0) ?? '?';
      if (tu) {
        _snack('🏃 ${ds}km 읽기 완료! 사진에 기록된 시간으로 설정되었어요.');
      } else if (dm != null)
        _snack('🏃 러닝 거리 ${ds}km를 사진에서 읽었어요!');
      else
        _snack('사진에서 정보를 찾지 못했어요.', isError: true);
    } catch (e) {
      _snack('사진 분석 중 오류가 발생했어요.', isError: true);
    } finally {
      setState(() => _isRunningImgLoading = false);
    }
  }

  Future<void> _analyzeFoodImage() async {
    // [v14] BYOK 키 검증
    final geminiUrl = await _getGeminiUrl();
    if (geminiUrl == null) {
      _snack('설정에서 API 키를 먼저 등록해 주세요!', isError: true);
      return;
    }
    setState(() => _isFoodImgLoading = true);
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await File(picked.path).readAsBytes();
      final b64 = base64Encode(bytes);
      final mime =
          picked.mimeType ??
          (picked.path.toLowerCase().endsWith('.png')
              ? 'image/png'
              : 'image/jpeg');

      final res = await http.post(
        Uri.parse(geminiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {
                  'text':
                      '이 사진의 음식이 무엇인지 분석하고 칼로리를 추정해 줘. '
                      '넌 한국의 영양사야. '
                      '한국인들이 주로 먹는 식단과 대중적인 음식을 우선적으로 고려해서 판단해 줘. '
                      '반드시 \'음식명|칼로리숫자\' 형태로만 대답해. '
                      '(예: 제육볶음|600). 부가 설명 절대 금지.',
                },
                {
                  'inline_data': {'mime_type': mime, 'data': b64},
                },
              ],
            },
          ],
        }),
      );
      if (res.statusCode != 200) {
        _snack(
          'Gemini 오류: ${(jsonDecode(res.body))['error']?['message']}',
          isError: true,
        );
        return;
      }
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final raw = j['candidates'][0]['content']['parts'][0]['text'] as String;
      final trimmed = raw.trim();
      if (!trimmed.contains('|')) {
        _snack('AI 응답 형식이 예상과 달라요.', isError: true);
        return;
      }
      final pts = trimmed.split('|');
      final foodName = pts[0].trim();
      final calStr = pts.length > 1
          ? RegExp(r'\d+').firstMatch(pts[1])?.group(0) ?? ''
          : '';
      setState(() {
        _foodCtrl.text = _foodCtrl.text.isEmpty
            ? foodName
            : '${_foodCtrl.text}, $foodName';
        if (calStr.isNotEmpty) _calorieCtrl.text = calStr;
      });
      _snack('🍽️ $foodName (약 ${calStr}kcal)을 인식했어요!');
    } catch (e) {
      _snack('사진 분석 중 오류가 발생했어요.', isError: true);
    } finally {
      setState(() => _isFoodImgLoading = false);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _selectedKst.hour,
        minute: _selectedKst.minute,
      ),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.accent,
            surface: AppColors.card,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    final today = nowKst();
    setState(
      () => _selectedKst = DateTime(
        today.year,
        today.month,
        today.day,
        picked.hour,
        picked.minute,
      ),
    );
  }

  Future<void> _calcAI() async {
    final food = _foodCtrl.text.trim();
    if (food.isEmpty) {
      _snack('음식 정보를 먼저 입력해주세요!', isError: true);
      return;
    }
    // [v14] BYOK 키 검증
    final geminiUrl = await _getGeminiUrl();
    if (geminiUrl == null) {
      _snack('설정에서 API 키를 먼저 등록해 주세요!', isError: true);
      return;
    }
    setState(() => _isAiLoading = true);
    try {
      final res = await http.post(
        Uri.parse(geminiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'system_instruction': {
            'parts': [
              {
                'text':
                    '사용자가 먹은 음식 목록을 줄 거야. 총 칼로리를 계산해서 오직 숫자만(예: 650) 대답해. 부가 설명은 절대 하지 마.',
              },
            ],
          },
          'contents': [
            {
              'parts': [
                {'text': food},
              ],
            },
          ],
        }),
      );
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        final m = RegExp(r'\d+').firstMatch(
          (j['candidates'][0]['content']['parts'][0]['text'] as String).trim(),
        );
        if (m != null) {
          setState(() => _calorieCtrl.text = m.group(0)!);
          _snack('🎉 AI 계산 완료: ${m.group(0)} kcal');
        } else {
          _snack('AI 응답에서 숫자를 찾지 못했어요.', isError: true);
        }
      } else {
        _snack(
          'Gemini 오류: ${(jsonDecode(res.body))['error']?['message']}',
          isError: true,
        );
      }
    } catch (e) {
      _snack('네트워크 오류가 발생했어요.', isError: true);
    } finally {
      setState(() => _isAiLoading = false);
    }
  }

  // [v13] Firestore SDK 저장
  Future<void> _save() async {
    final weight = _weightCtrl.text.trim();
    final food = _foodCtrl.text.trim();
    final calorie = _calorieCtrl.text.trim();
    final running = _runningCtrl.text.trim();

    if (weight.isEmpty &&
        food.isEmpty &&
        calorie.isEmpty &&
        running.isEmpty &&
        !_isWeightDone) {
      _snack('최소 한 가지 이상 입력해주세요!', isError: true);
      return;
    }
    if (running.isNotEmpty) {
      final inputKm = double.tryParse(running);
      if (inputKm != null && inputKm > 0) {
        final dup = widget.allRecords.any((r) {
          if ((r['source'] as String?) != 'firebase') return false;
          if (!isSameDay(r['kstTime'] as DateTime, _selectedKst)) return false;
          return ((r['runningKm'] as double) - inputKm).abs() < 0.01;
        });
        if (dup) {
          _snack('이미 같은 날짜에 동일한 러닝(거리) 기록이 존재해요.', isError: true);
          return;
        }
      }
    }
    if (_uid.isEmpty) {
      _snack('로그인이 필요합니다.', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _recordsRef.add({
        'weight': double.tryParse(weight) ?? 0.0,
        'food': food,
        'calorie': int.tryParse(calorie) ?? 0,
        'runningKm': double.tryParse(running) ?? 0.0,
        'isWeightDone': _isWeightDone,
        'createdAt': Timestamp.fromDate(
          _selectedKst.subtract(const Duration(hours: 9)), // KST → UTC
        ),
      });
      _snack('✅ Firestore에 저장 완료!');
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack('저장 오류: $e', isError: true);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.red : AppColors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final td = '${_pad(_selectedKst.hour)}:${_pad(_selectedKst.minute)}';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          '기록 추가',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.textSub),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: _pickTime,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accentGlow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.accent, width: 1.5),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.access_time_rounded,
                      color: AppColors.accent,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '기록 시간 (KST)',
                          style: TextStyle(
                            color: AppColors.textSub,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          td,
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '수정',
                        style: TextStyle(
                          color: AppColors.background,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text(
                '* 기본값은 KST 현재 시간이에요. 탭해서 수정하세요.',
                style: TextStyle(color: AppColors.textSub, fontSize: 11),
              ),
            ),
            const SizedBox(height: 20),

            _card(
              title: '🏋️ 신체 & 운동 (선택 입력)',
              child: Column(
                children: [
                  _field(
                    ctrl: _weightCtrl,
                    label: '체중',
                    hint: '예) 72.5  (선택)',
                    suffix: 'kg',
                    icon: Icons.monitor_weight_outlined,
                    keyboard: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: _field(
                          ctrl: _runningCtrl,
                          label: '러닝 거리',
                          hint: '예) 5.2  (선택)',
                          suffix: 'km',
                          icon: Icons.directions_run,
                          keyboard: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: '러닝 앱 스크린샷으로 거리·시간 자동 입력',
                        child: _imgIconBtn(
                          isLoading: _isRunningImgLoading,
                          onTap: _analyzeRunningImage,
                          icon: Icons.photo_library_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.fitness_center,
                          color: AppColors.textSub,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            '웨이트 운동 완료 (선택)',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Checkbox(
                          value: _isWeightDone,
                          activeColor: AppColors.accent,
                          checkColor: AppColors.background,
                          side: const BorderSide(color: AppColors.textSub),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          onChanged: (v) =>
                              setState(() => _isWeightDone = v ?? false),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _card(
              title: '🍽️ 음식 & 칼로리 (선택 입력)',
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _foodCtrl,
                          maxLines: 3,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: _inputDeco(
                            hint: '예) 공기밥 1공기, 된장찌개, 삼겹살 200g (선택)',
                            icon: Icons.restaurant_menu,
                            ctrl: _foodCtrl,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: '음식 사진으로 음식명·칼로리 자동 입력',
                        child: _imgIconBtn(
                          isLoading: _isFoodImgLoading,
                          onTap: _analyzeFoodImage,
                          icon: Icons.camera_alt_outlined,
                        ),
                      ),
                    ],
                  ),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        '📷 사진으로 음식·칼로리 자동 인식',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textSub,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isAiLoading ? null : _calcAI,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.background,
                        disabledBackgroundColor: AppColors.accent.withOpacity(
                          0.4,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: _isAiLoading
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: AppColors.background,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  '계산 중...',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('✨', style: TextStyle(fontSize: 17)),
                                SizedBox(width: 8),
                                Text(
                                  'AI 칼로리 계산하기 (텍스트)',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _field(
                    ctrl: _calorieCtrl,
                    label: '섭취 칼로리',
                    hint: 'AI/사진 분석 결과가 자동 입력돼요 (선택)',
                    suffix: 'kcal',
                    icon: Icons.local_fire_department_outlined,
                    keyboard: TextInputType.number,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '* AI 결과 또는 사진 분석 결과를 직접 수정할 수 있어요.',
                    style: TextStyle(fontSize: 11, color: AppColors.textSub),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 58,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.background,
                  disabledBackgroundColor: AppColors.accent.withOpacity(0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: _isSaving
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppColors.background,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            '저장 중...',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_upload_outlined, size: 22),
                          SizedBox(width: 10),
                          Text(
                            'Firestore에 저장하기',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                '저장하면 메인 화면 타임라인에 바로 나타나요!',
                style: TextStyle(fontSize: 12, color: AppColors.textSub),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _imgIconBtn({
    required bool isLoading,
    required VoidCallback onTap,
    required IconData icon,
  }) => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      color: isLoading ? AppColors.cardBorder : AppColors.accentGlow,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isLoading ? AppColors.cardBorder : AppColors.accent,
      ),
    ),
    child: isLoading
        ? const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            ),
          )
        : IconButton(
            onPressed: onTap,
            icon: Icon(icon, color: AppColors.accent, size: 22),
          ),
  );

  Widget _card({required String title, required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.cardBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );

  Widget _field({
    required TextEditingController ctrl,
    required String label,
    required String hint,
    required String suffix,
    required IconData icon,
    required TextInputType keyboard,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textSub,
        ),
      ),
      const SizedBox(height: 6),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: ctrl,
        builder: (_, __, ___) => TextField(
          controller: ctrl,
          keyboardType: keyboard,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: _inputDeco(
            hint: hint,
            suffix: suffix,
            icon: icon,
            ctrl: ctrl,
          ),
        ),
      ),
    ],
  );

  InputDecoration _inputDeco({
    required String hint,
    String? suffix,
    required IconData icon,
    required TextEditingController ctrl,
  }) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.textSub, fontSize: 13),
    suffixText: ctrl.text.isEmpty ? suffix : null,
    suffixStyle: const TextStyle(
      color: AppColors.textSub,
      fontWeight: FontWeight.w500,
    ),
    suffixIcon: ctrl.text.isNotEmpty
        ? IconButton(
            icon: const Icon(Icons.cancel, color: AppColors.textSub, size: 18),
            onPressed: () {
              ctrl.clear();
              setState(() {});
            },
            splashRadius: 16,
            tooltip: '내용 지우기',
          )
        : null,
    prefixIcon: Icon(icon, color: AppColors.textSub, size: 20),
    filled: true,
    fillColor: AppColors.background,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.cardBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.cardBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.accent, width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );
}

// ============================================================
// [v14] SettingsScreen — BYOK Gemini API 키 관리
// ============================================================
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _keyCtrl = TextEditingController();
  bool _isSaving = false;
  bool _obscure = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedKey();
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  // 저장된 키 미리 로드
  Future<void> _loadSavedKey() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kPrefGeminiKey) ?? '';
    setState(() {
      _keyCtrl.text = saved;
      _isLoading = false;
    });
  }

  // SharedPreferences에 저장
  Future<void> _saveKey() async {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) {
      _snack('API 키를 입력해 주세요.', isError: true);
      return;
    }
    setState(() => _isSaving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefGeminiKey, key);
      _snack('✅ API 키가 성공적으로 저장되었습니다.');
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack('저장 중 오류가 발생했어요: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // AI Studio 링크 열기
  Future<void> _openAiStudio() async {
    final uri = Uri.parse('https://aistudio.google.com/app/apikey');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _snack('브라우저를 열 수 없어요.', isError: true);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.red : AppColors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          '설정',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.textSub),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 안내 카드 ──────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.accent.withOpacity(0.13),
                          AppColors.card,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.accent.withOpacity(0.45),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 제목 배지
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accentGlow,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.accent.withOpacity(0.5),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('✨', style: TextStyle(fontSize: 13)),
                              SizedBox(width: 5),
                              Text(
                                'BYOK 프리미엄',
                                style: TextStyle(
                                  color: AppColors.accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          '본인의 Gemini API 키를 입력하시면,\n월 구독료 없이 사진 분석과 AI 코치 등\n모든 프리미엄 기능을 평생 무료로\n이용할 수 있습니다.',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            height: 1.7,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // 기능 목록
                        _featureItem('📸', '러닝 스크린샷 자동 거리·시간 인식'),
                        const SizedBox(height: 8),
                        _featureItem('🍽️', '음식 사진 칼로리 자동 분석'),
                        const SizedBox(height: 8),
                        _featureItem('🤖', '날씨 기반 AI 코치 운동 추천'),
                        const SizedBox(height: 8),
                        _featureItem('🔢', 'AI 텍스트 칼로리 자동 계산'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── AI Studio 링크 버튼 ───────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openAiStudio,
                      icon: const Text('🔑', style: TextStyle(fontSize: 18)),
                      label: const Text(
                        '구글 AI Studio에서 API 키 발급받기',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: const BorderSide(
                          color: AppColors.accent,
                          width: 1.5,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Center(
                    child: Text(
                      'Google 계정만 있으면 무료로 발급받을 수 있어요.',
                      style: TextStyle(color: AppColors.textSub, fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── API 키 입력 필드 ──────────────────────────
                  const Text(
                    'Gemini API 키',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSub,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _keyCtrl,
                    obscureText: _obscure,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontFamily: 'monospace',
                      fontSize: 14,
                      letterSpacing: 0.5,
                    ),
                    decoration: InputDecoration(
                      hintText: 'AIzaSy...',
                      hintStyle: const TextStyle(
                        color: AppColors.textSub,
                        fontSize: 13,
                      ),
                      prefixIcon: const Icon(
                        Icons.vpn_key_rounded,
                        color: AppColors.textSub,
                        size: 20,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: AppColors.textSub,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                        tooltip: _obscure ? '키 표시' : '키 숨기기',
                      ),
                      filled: true,
                      fillColor: AppColors.card,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: AppColors.cardBorder,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: AppColors.cardBorder,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: AppColors.accent,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 저장 위치 안내
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          color: AppColors.textSub,
                          size: 15,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'API 키는 이 기기에만 안전하게 저장되며,\n외부 서버로 전송되지 않습니다.',
                            style: TextStyle(
                              color: AppColors.textSub,
                              fontSize: 11,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── 저장 버튼 ─────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveKey,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.background,
                        disabledBackgroundColor: AppColors.accent.withOpacity(
                          0.4,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _isSaving
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: AppColors.background,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text(
                                  '저장 중...',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.save_rounded, size: 21),
                                SizedBox(width: 10),
                                Text(
                                  'API 키 저장하기',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── 삭제 버튼 ─────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: _isSaving ? null : _deleteKey,
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.red,
                        size: 18,
                      ),
                      label: const Text(
                        '저장된 API 키 삭제',
                        style: TextStyle(color: AppColors.red, fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  // 키 삭제
  Future<void> _deleteKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'API 키 삭제',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          '저장된 API 키를 삭제하시겠어요?\n삭제하면 AI 기능을 사용할 수 없게 됩니다.',
          style: TextStyle(color: AppColors.textSub, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: AppColors.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '삭제',
              style: TextStyle(
                color: AppColors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefGeminiKey);
    setState(() => _keyCtrl.clear());
    _snack('API 키가 삭제되었습니다.');
  }

  Widget _featureItem(String emoji, String text) => Row(
    children: [
      Text(emoji, style: const TextStyle(fontSize: 15)),
      const SizedBox(width: 10),
      Text(
        text,
        style: const TextStyle(color: AppColors.textSub, fontSize: 13),
      ),
    ],
  );
}
