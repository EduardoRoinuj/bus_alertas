import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'api.dart';

/// Notificação do sistema + voz + vibração quando chega um autocarro.
class Notifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  final _tts = FlutterTts();
  bool soundOn = true;

  static const _channel = AndroidNotificationDetails(
    'arrivals',
    'Chegadas de autocarros',
    channelDescription: 'Alerta quando um autocarro chega a uma paragem',
    importance: Importance.max,
    priority: Priority.high,
    ticker: 'Autocarro na paragem',
    enableVibration: true,
    playSound: true,
  );

  Future<void> init() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    try {
      await _tts.setLanguage('pt-PT');
      await _tts.setSpeechRate(0.5);
    } catch (_) {}
  }

  Future<void> arrival(Alert a, {required bool inForeground}) async {
    HapticFeedback.heavyImpact();
    await _plugin.show(
      id: a.id,
      title: 'Autocarro na paragem ${a.stopName}',
      body: a.message,
      notificationDetails: const NotificationDetails(android: _channel),
    );
    if (soundOn) {
      try {
        await _tts.speak('Atenção. Autocarro chegou à paragem ${a.stopName}.');
      } catch (_) {}
    }
  }
}
