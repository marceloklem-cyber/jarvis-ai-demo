// Serviços do Android: armazenamento, voz (fala e escuta) e notificações.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/jarvis_core.dart';

/// SharedPreferences como armazenamento do núcleo (grava e confirma).
class PrefsStore implements JarvisStore {
  final SharedPreferences prefs;
  PrefsStore(this.prefs);
  @override
  Future<String?> read(String key) async => prefs.getString(key);
  @override
  Future<bool> write(String key, String value) async {
    try {
      return await prefs.setString(key, value);
    } catch (_) {
      return false;
    }
  }
}

/// Uma voz de síntese disponível no aparelho.
class VoiceInfo {
  final String name, locale;
  const VoiceInfo(this.name, this.locale);
  bool get network => name.contains('network');
  String get label {
    final kind = network ? 'on-line' : 'no aparelho';
    return '$name · $locale · $kind';
  }
}

/// Fala (TTS) com a voz escolhida, aguardando o fim de cada frase.
class Speaker {
  final FlutterTts tts = FlutterTts();
  bool speaking = false;
  final ValueNotifier<bool> speakingNotifier = ValueNotifier(false);

  Future<void> init() async {
    try {
      await tts.awaitSpeakCompletion(true);
      await tts.setLanguage('pt-BR');
    } catch (e) {
      debugPrint('TTS init: $e');
    }
  }

  Future<List<VoiceInfo>> portugueseVoices() async {
    try {
      final raw = await tts.getVoices;
      final list = <VoiceInfo>[];
      if (raw is List) {
        for (final v in raw) {
          if (v is Map) {
            final name = (v['name'] ?? '').toString();
            final locale = (v['locale'] ?? '').toString();
            if (locale.toLowerCase().startsWith('pt')) list.add(VoiceInfo(name, locale));
          }
        }
      }
      list.sort((a, b) {
        int score(VoiceInfo v) => (v.locale.toLowerCase().replaceAll('_', '-') == 'pt-br' ? 2 : 0) + (v.network ? 1 : 0);
        final c = score(b).compareTo(score(a));
        return c != 0 ? c : a.name.compareTo(b.name);
      });
      return list;
    } catch (e) {
      debugPrint('getVoices: $e');
      return const [];
    }
  }

  Future<void> apply(JarvisSettings s) async {
    try {
      if (s.voiceName.isNotEmpty) await tts.setVoice({'name': s.voiceName, 'locale': s.voiceLocale});
      await tts.setSpeechRate(s.rate);
      await tts.setPitch(s.pitch);
    } catch (e) {
      debugPrint('TTS apply: $e');
    }
  }

  /// Fala o texto inteiro, uma frase por vez (evita cortes em textos longos).
  Future<void> say(String text, JarvisSettings s) async {
    await stop();
    await apply(s);
    final parts = RegExp(r'[^.!?;:]+[.!?;:]*').allMatches(text).map((m) => m.group(0)!.trim()).where((x) => x.isNotEmpty).toList();
    final chunks = <String>[];
    for (final p in parts) {
      if (chunks.isNotEmpty && (chunks.last.length + p.length) < 220) {
        chunks[chunks.length - 1] = '${chunks.last} $p';
      } else {
        chunks.add(p);
      }
    }
    speaking = true;
    speakingNotifier.value = true;
    try {
      for (final c in chunks) {
        if (!speaking) break;
        await tts.speak(c);
      }
    } catch (e) {
      debugPrint('TTS speak: $e');
    } finally {
      speaking = false;
      speakingNotifier.value = false;
    }
  }

  Future<void> stop() async {
    speaking = false;
    speakingNotifier.value = false;
    try {
      await tts.stop();
    } catch (_) {}
  }
}

/// Escuta (reconhecimento de fala do Android).
class VoiceListener {
  final stt.SpeechToText speech = stt.SpeechToText();
  bool ready = false;
  String localeId = 'pt_BR';
  void Function(String code)? onError;
  void Function(String status)? onStatus;

  Future<bool> init() async {
    if (ready) return true;
    try {
      ready = await speech.initialize(
        onError: (SpeechRecognitionError e) => onError?.call(e.errorMsg),
        onStatus: (s) => onStatus?.call(s),
      );
      if (ready) {
        final locales = await speech.locales();
        for (final l in locales) {
          final id = l.localeId.toLowerCase().replaceAll('-', '_');
          if (id == 'pt_br') {
            localeId = l.localeId;
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('STT init: $e');
      ready = false;
    }
    return ready;
  }

  bool get listening => speech.isListening;

  Future<void> listen({required void Function(String words, bool isFinal) onResult}) async {
    await speech.listen(
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      localeId: localeId,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      listenOptions: stt.SpeechListenOptions(partialResults: true, cancelOnError: true, listenMode: stt.ListenMode.confirmation),
    );
  }

  Future<void> stop() async {
    try {
      await speech.stop();
    } catch (_) {}
  }

  static String explain(String code) {
    switch (code) {
      case 'error_permission':
      case 'error_insufficient_permissions':
        return 'Permissão de microfone negada. Abra Configurações › Aplicativos › JARVIS › Permissões › Microfone › Permitir.';
      case 'error_no_match':
      case 'error_speech_timeout':
        return 'Não entendi. Toque no botão e fale logo em seguida.';
      case 'error_network':
      case 'error_network_timeout':
      case 'error_server':
        return 'Falha de rede no reconhecimento de voz. Verifique a internet ou instale o pacote offline de português no app Google.';
      case 'error_busy':
        return 'O reconhecimento de voz está ocupado. Tente de novo em instantes.';
      case 'error_audio':
        return 'Não consegui acessar o microfone. Verifique se outro aplicativo está usando-o.';
      case 'error_language_not_supported':
      case 'error_language_unavailable':
        return 'Português não está disponível no reconhecimento de voz. Instale o idioma no app Google.';
      default:
        return 'Falha no reconhecimento de voz ($code).';
    }
  }
}

/// Notificações agendadas no Android (funcionam com o app fechado e a tela bloqueada).
class Notifier {
  final FlutterLocalNotificationsPlugin plugin = FlutterLocalNotificationsPlugin();
  static const int summaryId = 9000;
  static const AndroidNotificationDetails _android = AndroidNotificationDetails(
    'jarvis_lembretes',
    'Lembretes',
    channelDescription: 'Avisos de tarefas e compromissos do JARVIS',
    importance: Importance.max,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
  );
  static const NotificationDetails _details = NotificationDetails(android: _android);

  Future<String?> init(void Function(String? payload) onTap) async {
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('America/Sao_Paulo'));
    } catch (_) {}
    await plugin.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) => onTap(r.payload),
    );
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch != null && launch.didNotificationLaunchApp) return launch.notificationResponse?.payload;
    return null;
  }

  AndroidFlutterLocalNotificationsPlugin? get _androidImpl => plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<bool> requestPermission() async {
    final a = _androidImpl;
    if (a == null) return true;
    final ok = await a.requestNotificationsPermission() ?? true;
    return ok;
  }

  Future<bool> enabled() async => await _androidImpl?.areNotificationsEnabled() ?? true;

  Future<void> _schedule(int id, String title, String body, DateTime when, String payload, {DateTimeComponents? repeat}) async {
    final at = tz.TZDateTime.from(when, tz.local);
    try {
      await plugin.zonedSchedule(id, title, body, at, _details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: repeat,
          payload: payload);
    } catch (e) {
      // Sem permissão de alarme exato: agenda no modo aproximado.
      await plugin.zonedSchedule(id, title, body, at, _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: repeat,
          payload: payload);
    }
  }

  /// Recria todos os avisos a partir da agenda.
  Future<void> sync(JarvisEngine engine) async {
    try {
      await plugin.cancelAll();
      for (final n in engine.planNotifications()) {
        await _schedule(n.id, n.title, n.body, n.at, n.payload);
      }
      final s = engine.settings;
      if (s.summaryEnabled) {
        final hm = s.summaryTime.split(':').map(int.parse).toList();
        final now = DateTime.now();
        var first = DateTime(now.year, now.month, now.day, hm[0], hm[1]);
        if (!first.isAfter(now)) first = first.add(const Duration(days: 1));
        await _schedule(summaryId, 'JARVIS · Resumo do dia', 'Toque para ouvir sua agenda de hoje.', first, 'summary', repeat: DateTimeComponents.time);
      }
    } catch (e) {
      debugPrint('Notifier.sync: $e');
    }
  }
}
