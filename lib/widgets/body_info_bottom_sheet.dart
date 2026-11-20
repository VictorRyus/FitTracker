import 'package:flutter/material.dart';
import '../services/body_info_service.dart';

Future<void> showBodyInfoBottomSheet(
  BuildContext context, {
  required BodyInfo current,
  required Function(double height, double weight, int age) onSave,
}) {
  final heightCtrl = TextEditingController(
    text: current.heightM > 0 ? (current.heightM * 100).toStringAsFixed(0) : '',
  );
  final weightCtrl = TextEditingController(
    text: current.weightKg > 0 ? current.weightKg.toStringAsFixed(1) : '',
  );
  final ageCtrl = TextEditingController(
    text: current.ageYears > 0 ? current.ageYears.toString() : '',
  );

  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.grey.shade900,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    // 🚨 [수정 3] StatefulBuilder로 감싸기 완료
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModalState) {
        // 🚨 [수정 3] 로컬 함수로 선언하여 네임스페이스 충돌 원천 차단
        Widget buildField(
          TextEditingController ctrl,
          String label,
          String unit,
          TextInputType keyboardType,
        ) {
          return TextField(
            controller: ctrl,
            keyboardType: keyboardType,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(color: Colors.grey),
              suffixText: unit,
              suffixStyle: const TextStyle(color: Colors.grey),
              filled: true,
              fillColor: Colors.grey.shade800,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_outline, color: Colors.cyanAccent),
                  const SizedBox(width: 8),
                  const Text(
                    '신체 정보 입력',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Health Connect에서 정보를 가져오지 못했습니다.\n입력하신 정보는 맞춤 가이드라인 계산에 사용됩니다.',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              ),
              const SizedBox(height: 24),

              // 🚨 로컬 함수 호출로 교체됨
              buildField(heightCtrl, '키', 'cm', TextInputType.number),
              const SizedBox(height: 12),
              buildField(
                weightCtrl,
                '체중',
                'kg',
                const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              buildField(ageCtrl, '나이', '세', TextInputType.number),
              const SizedBox(height: 24),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  final h = double.tryParse(heightCtrl.text) ?? 0;
                  final w = double.tryParse(weightCtrl.text) ?? 0;
                  final a = int.tryParse(ageCtrl.text) ?? 0;
                  if (h > 0 && w > 0 && a > 0) {
                    onSave(h / 100.0, w, a);
                    Navigator.pop(ctx);
                  }
                },
                child: const Text(
                  '저장 및 가이드라인 적용',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
