// Faz 1 uçtan uca testi — gerçek Android cihaz/emülatör + gerçek relay.
//
//   ./scripts/relay-start.sh
//   adb reverse tcp:7777 tcp:7777
//   cd apps/mobile && flutter test integration_test/phase1_test.dart
//
// Doğrulananlar:
//   1) Uygulama açılır, bellekte anahtar üretir ve npub gösterir
//   2) Relay'e bağlanır (durum göstergesi "Bağlı")
//   3) kind:0 profil eventi yayınlanır, relay kabul eder (OK)
//   4) Event akışta listelenir

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:sosyal/main.dart' as app;

/// Koşul sağlanana kadar kare kare ilerler (gerçek ağ beklemesi için).
Future<void> pumpUntil(
  WidgetTester tester,
  String description,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw TestFailure('Zaman aşımı: $description');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('npub gösterilir, relay bağlanır, profil yayınlanır', (tester) async {
    app.main();
    await tester.pump();

    // 1) Anahtar üretildi ve npub ekranda.
    await pumpUntil(
      tester,
      'npub görünür',
      () => find.textContaining('npub1').evaluate().isNotEmpty,
    );
    final npubText = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .first
        .data!;
    expect(npubText.startsWith('npub1'), isTrue);
    // bech32 npub her zaman 63 karakterdir.
    expect(npubText.length, 63);

    // 2) Relay bağlantısı kuruldu ("Bağlı" ve buton etkin).
    await pumpUntil(
      tester,
      'relay bağlantısı',
      () => find.text('Bağlı').evaluate().isNotEmpty,
    );
    final button = find.widgetWithText(FilledButton, "Relay'e gönder");
    expect(button, findsOneWidget);
    await pumpUntil(
      tester,
      'gönder butonu etkin',
      () => tester.widget<FilledButton>(button).onPressed != null,
    );

    // 3) Profil yayınla.
    await tester.tap(button);
    await pumpUntil(
      tester,
      'yayın onayı',
      () => find.text('Profil yayınlandı').evaluate().isNotEmpty,
    );

    // 4) Event akışta görünür (gönderenin kendi kaydı).
    await pumpUntil(
      tester,
      'event listede',
      () => find.text('mitsune').evaluate().isNotEmpty,
    );

    // ignore: avoid_print
    print('FAZ1-TEST-TAMAM npub=$npubText');
  });
}
