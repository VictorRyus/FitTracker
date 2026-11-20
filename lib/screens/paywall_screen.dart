// [FitTracker 전용] fittracker/lib/screens/paywall_screen.dart
import 'package:flutter/material.dart';
import 'package:my_flutter_shared/my_flutter_shared.dart'; // 공유 패키지

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final RevenueCatService _rcService = RevenueCatService();
  bool _isLoading = false;
  String _selectedPlan = 'annual'; // 기본 선택: 연간

  Future<void> _handlePurchase() async {
    setState(() => _isLoading = true);
    try {
      bool isSuccess = _selectedPlan == 'annual'
          ? await _rcService.purchaseAnnual()
          : await _rcService.purchaseMonthly();

      if (isSuccess && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Premium 구독이 완료되었습니다! 🚀')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      // 사용자가 취소한 경우 예외가 발생할 수 있으므로 조용히 처리
      debugPrint('결제 중단: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRestore() async {
    setState(() => _isLoading = true);
    try {
      bool restored = await _rcService.restorePurchases();
      if (mounted) {
        if (restored) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('구매 내역이 복원되었습니다.')));
          Navigator.of(context).pop(true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('복원할 프리미엄 구독 내역이 없습니다.')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _handleRestore,
            child: const Text('구매 복원', style: TextStyle(color: Colors.white70)),
          ),
        ],
        elevation: 0,
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.workspace_premium,
                    size: 80,
                    color: Colors.amber,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'FitTracker Premium',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '무제한 AI 헬스 코칭으로\n당신의 건강을 완벽하게 관리하세요.',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const Spacer(),
                  // 나란히 표시되는 플랜 카드 (Row 활용)
                  Row(
                    children: [
                      Expanded(
                        child: _buildPlanCard(
                          planId: 'monthly',
                          title: '월간',
                          price: '₩2,900 / 월',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildPlanCard(
                          planId: 'annual',
                          title: '연간',
                          price: '₩19,900 / 년',
                          badgeText: '월 대비 43% 절약',
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handlePurchase,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.amber.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '지금 바로 시작하기',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '구독은 언제든지 Google Play 설정에서 취소할 수 있습니다.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildPlanCard({
    required String planId,
    required String title,
    required String price,
    String? badgeText,
  }) {
    final isSelected = _selectedPlan == planId;
    return GestureDetector(
      onTap: () => setState(() => _selectedPlan = planId),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.amber.withOpacity(0.1)
              : Colors.transparent,
          border: Border.all(
            color: isSelected ? Colors.amber : Colors.grey.shade800,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            if (badgeText != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badgeText,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              title,
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              price,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
