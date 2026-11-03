/// Yerelleştirme regresyon testi.
///
/// v1.0.3–v1.0.10 arasındaki "gri kutu" hatası, MaterialApp'de
/// `supportedLocales: [tr, en]` bildirilip `localizationsDelegates` içine
/// Global* delegeleri eklemeyi unutmaktan kaynaklanıyordu. Türkçe yerelde
/// MaterialLocalizations null kalıyor, her TextField çöküyor ve release
/// derlemede çöken widget'ın yerine gri ErrorWidget kutusu çiziliyordu.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sosyal/features/auth/login_page.dart';

Widget _wrap({required bool withDelegates}) {
  return MaterialApp(
    locale: const Locale('tr'),
    localizationsDelegates: withDelegates
        ? const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ]
        : const [],
    supportedLocales: const [Locale('tr'), Locale('en')],
    home: LoginPage(onAuthenticated: () async {}),
  );
}

void main() {
  testWidgets('Türkçe yerelde giriş ekranı çökmeden çizilir', (tester) async {
    await tester.pumpWidget(_wrap(withDelegates: true));
    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsWidgets);
    expect(find.text('Giriş yap'), findsOneWidget);
  });

  testWidgets('Global delegeler olmadan TextField Türkçe yerelde çöker',
      (tester) async {
    await tester.pumpWidget(_wrap(withDelegates: false));
    // Hatayı koruyan beklenen davranış: delege yokken çökme yaşanmalı.
    expect(tester.takeException(), isNotNull);
  });
}
