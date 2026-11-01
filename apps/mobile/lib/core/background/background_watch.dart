/// Arka plan bağlantısı — ana izole cephesi.
///
/// Uygulama kapalıyken ön plan servisi olarak relay izleyicisini çalıştırır;
/// görevin kendisi [background_task.dart] içindeki izole edicide yaşar.
library;

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../config/app_config.dart';
import '../identity/key_storage.dart';
import 'background_task.dart';

class BackgroundWatch {
  BackgroundWatch._();

  static bool _initialized = false;
  static final KeyStorage _storage = KeyStorage();

  /// main() içinde çağrılır: eklenti iletişim portunu ve seçenekleri kurar.
  static void init() {
    if (_initialized) return;
    _initialized = true;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'sosyal_background',
        channelName: 'Arka plan bağlantısı',
        channelDescription:
            'Uygulama kapalıyken relay bağlantısını sürdürür',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(20000),
        autoRunOnBoot: false, // Android 14+ arka plandan servise izin vermez
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
      ),
    );
  }

  static Future<bool> isPreferred() => _storage.loadBgWatchEnabled();

  static Future<bool> isRunning() async {
    init();
    return FlutterForegroundTask.isRunningService;
  }

  /// Anahtarı açar; bildirim izni reddedilirse false döner.
  static Future<bool> enable() async {
    init();
    final permission = await FlutterForegroundTask.requestNotificationPermission();
    if (permission != NotificationPermission.granted) return false;

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
      // Servisin tamamen inmesi için kısa bir pay bırak.
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    final result = await FlutterForegroundTask.startService(
      notificationTitle: '${AppConfig.name} arka planda',
      notificationText: 'Relay bağlantısı izleniyor',
      callback: startSosyalTask,
      serviceTypes: [ForegroundServiceTypes.remoteMessaging],
    );
    if (result is! ServiceRequestSuccess) return false;
    await _storage.saveBgWatchEnabled(true);
    return true;
  }

  static Future<void> disable() async {
    init();
    await FlutterForegroundTask.stopService();
    await _storage.saveBgWatchEnabled(false);
  }

  /// Tercih açıksa uygulama açılırken servisi ayağa kaldır
  /// (ör. telefon yeniden başlatıldıysa veya sistem servisi düşürdüyse).
  static Future<void> restore() async {
    try {
      init();
      if (!await _storage.loadBgWatchEnabled()) return;
      if (await FlutterForegroundTask.isRunningService) return;
      final result = await FlutterForegroundTask.startService(
        notificationTitle: '${AppConfig.name} arka planda',
        notificationText: 'Relay bağlantısı izleniyor',
        callback: startSosyalTask,
        serviceTypes: [ForegroundServiceTypes.remoteMessaging],
      );
      if (result is! ServiceRequestSuccess) {
        // İzin geri alınmış olabilir; tercihi temizle ki UI senkron kalsın.
        final permission =
            await FlutterForegroundTask.requestNotificationPermission();
        if (permission != NotificationPermission.granted) {
          await _storage.saveBgWatchEnabled(false);
        }
      }
    } catch (_) {
      // Açılış asla servis yüzünden bloklanmaz.
    }
  }
}
