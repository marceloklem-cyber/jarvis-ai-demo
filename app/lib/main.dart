// JARVIS AI — app Android (Flutter). Fale e ele anota; pergunte e ele lê a agenda.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/jarvis_core.dart';
import 'services/platform.dart';

const Color kCyan = Color(0xFF63D8FF);
const Color kBg = Color(0xFF070E1A);
const Color kPanel = Color(0xFF0B1929);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JarvisApp());
}

class JarvisApp extends StatelessWidget {
  const JarvisApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JARVIS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: kCyan, brightness: Brightness.dark, surface: kPanel),
        scaffoldBackgroundColor: kBg,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  JarvisEngine? engine;
  final speaker = Speaker();
  final listener = VoiceListener();
  final notifier = Notifier();
  final input = TextEditingController();

  bool listening = false;
  bool finalHandled = false;
  String status = 'Toque no círculo e fale.';
  String heard = '';
  Reply? reply;
  String filter = 'pending';
  String lastText = '';
  DateTime lastAt = DateTime(2000);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    input.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && engine != null) {
      setState(() {});
      notifier.sync(engine!);
    }
    if (state == AppLifecycleState.paused) {
      listener.stop();
    }
  }

  Future<void> _start() async {
    final prefs = await SharedPreferences.getInstance();
    final e = await JarvisEngine.open(PrefsStore(prefs));
    await speaker.init();
    listener.onError = (code) {
      if (!mounted) return;
      setState(() {
        listening = false;
        status = VoiceListener.explain(code);
      });
    };
    listener.onStatus = (s) {
      if (!mounted) return;
      if (s == 'done' || s == 'notListening') {
        setState(() {
          listening = false;
          if (!finalHandled && heard.trim().isEmpty && status == 'Ouvindo…') status = 'Não ouvi nada. Toque e fale novamente.';
        });
      }
    };
    final payload = await notifier.init(_onNotificationTap);
    setState(() => engine = e);
    if (e.loadError == 'corrupt') {
      _snack('Os dados salvos estavam corrompidos; uma cópia foi preservada e a agenda começou vazia.');
    }
    final granted = await notifier.requestPermission();
    if (!granted) _snack('Sem permissão de notificação, os lembretes não vão aparecer. Ative em Configurações › Aplicativos › JARVIS.');
    await notifier.sync(e);
    if (payload != null) {
      _onNotificationTap(payload);
    } else if (e.settings.voiceName.isEmpty) {
      setState(() => status = 'Primeiro acesso: toque em ⚙ para escolher uma voz masculina.');
    }
  }

  void _onNotificationTap(String? payload) {
    final e = engine;
    if (e == null || payload == null) return;
    final text = payload == 'summary' ? e.summaryText() : e.reminderSpeech(payload);
    setState(() => reply = Reply(text, 'info'));
    speaker.say(text, e.settings);
  }

  void _snack(String text, {bool undo = false}) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(text),
      duration: const Duration(seconds: 6),
      action: undo ? SnackBarAction(label: 'Desfazer', onPressed: () => _run('desfazer', fromVoice: false)) : null,
    ));
  }

  Future<void> _run(String text, {required bool fromVoice}) async {
    final e = engine;
    text = text.trim();
    if (e == null || text.isEmpty) return;
    final now = DateTime.now();
    if (text.toLowerCase() == lastText && now.difference(lastAt).inSeconds < 4) return;
    lastText = text.toLowerCase();
    lastAt = now;
    final r = await e.handle(text, source: fromVoice ? 'voice' : 'text');
    if (!mounted) return;
    setState(() {
      reply = r;
      status = r.kind == 'question' ? 'Aguardando sua resposta…' : r.kind == 'error' ? 'Não foi possível concluir.' : 'Pronto.';
      if (r.query != null) {
        filter = switch (r.query!.range) { 'done' => 'done', 'day' => 'all', _ => 'pending' };
      }
    });
    if (r.changed) {
      await notifier.sync(e);
      if (e.canUndo && r.kind != 'question') _snack(r.speech.length > 80 ? '${r.speech.substring(0, 77)}…' : r.speech, undo: true);
    }
    await speaker.say(r.speech, e.settings);
    if (r.kind == 'question' && fromVoice && e.settings.followUp && mounted) {
      await _toggleListen();
    }
  }

  Future<void> _toggleListen() async {
    if (listening || listener.listening) {
      await listener.stop();
      setState(() => listening = false);
      return;
    }
    await speaker.stop();
    final ok = await listener.init();
    if (!ok) {
      setState(() => status = 'Reconhecimento de voz indisponível. Permita o microfone e verifique se o app Google está instalado e ativo.');
      return;
    }
    finalHandled = false;
    setState(() {
      listening = true;
      heard = '';
      status = 'Ouvindo…';
    });
    try {
      await listener.listen(onResult: (words, isFinal) {
        if (!mounted) return;
        setState(() => heard = words);
        if (isFinal && !finalHandled && words.trim().isNotEmpty) {
          finalHandled = true;
          setState(() {
            listening = false;
            status = 'Processando…';
          });
          _run(words, fromVoice: true);
        }
      });
    } catch (err) {
      setState(() {
        listening = false;
        status = 'Não foi possível iniciar o microfone: $err';
      });
    }
  }

  String get greeting {
    final h = DateTime.now().hour;
    final g = h < 12 ? 'Bom dia' : h < 18 ? 'Boa tarde' : 'Boa noite';
    return (engine?.settings.honorific ?? true) ? '$g, senhor.' : '$g.';
  }

  List<Task> get visibleTasks {
    final e = engine;
    if (e == null) return const [];
    final now = DateTime.now();
    final tomorrow = dayKey(DateTime(now.year, now.month, now.day + 1));
    final list = e.tasks.where((t) {
      switch (filter) {
        case 'today':
          return e.inRange(t, 'day', date: dayKey(now));
        case 'tomorrow':
          return e.inRange(t, 'day', date: tomorrow);
        case 'done':
          return t.status == 'completed';
        case 'all':
          return t.status != 'cancelled';
        default:
          return t.status == 'pending';
      }
    }).toList()
      ..sort(JarvisEngine.sortTasks);
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final e = engine;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kBg,
        title: const Text('◉ JARVIS', style: TextStyle(color: kCyan, fontWeight: FontWeight.w800, letterSpacing: 3)),
        actions: [
          IconButton(
            tooltip: 'Ler compromissos pendentes',
            icon: const Icon(Icons.record_voice_over),
            onPressed: e == null ? null : () => _run('quais são os meus compromissos', fromVoice: false),
          ),
          IconButton(
            tooltip: 'Voz e preferências',
            icon: const Icon(Icons.settings),
            onPressed: e == null
                ? null
                : () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsPage(engine: e, speaker: speaker, notifier: notifier)));
                    if (mounted) setState(() {});
                  },
          ),
        ],
      ),
      body: e == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  const SizedBox(height: 8),
                  Center(child: _orb()),
                  const SizedBox(height: 14),
                  Text(greeting, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(status, textAlign: TextAlign.center, style: const TextStyle(color: kCyan, fontWeight: FontWeight.w600)),
                  if (heard.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('“$heard”', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic)),
                    ),
                  if (reply != null) _replyCard(reply!),
                  const SizedBox(height: 14),
                  _commandField(),
                  const SizedBox(height: 18),
                  _filters(),
                  const SizedBox(height: 6),
                  ..._taskList(e),
                  const SizedBox(height: 18),
                  const Text(
                    'Diga, por exemplo: "amanhã às 15h me lembre de ligar para o contador", "quais são meus compromissos?", '
                    '"conclua a tarefa do fornecedor", "transfira a reunião para sexta às 10" ou "desfazer".',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _orb() {
    return ValueListenableBuilder<bool>(
      valueListenable: speaker.speakingNotifier,
      builder: (context, speaking, _) {
        final active = listening || speaking;
        return Semantics(
          button: true,
          label: listening ? 'Parar de ouvir' : 'Falar com o JARVIS',
          child: GestureDetector(
            onTap: _toggleListen,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              width: listening ? 168 : 152,
              height: listening ? 168 : 152,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(colors: [Color(0xFF164B75), Color(0xFF091A2E)]),
                border: Border.all(color: listening ? const Color(0xFF7FF3FF) : const Color(0xFF43D7FF), width: 2),
                boxShadow: [BoxShadow(color: const Color(0xFF00C8FF).withOpacity(active ? 0.75 : 0.35), blurRadius: active ? 48 : 24)],
              ),
              child: Icon(speaking ? Icons.graphic_eq : (listening ? Icons.mic : Icons.mic_none), size: 58, color: const Color(0xFF9DF0FF)),
            ),
          ),
        );
      },
    );
  }

  Widget _replyCard(Reply r) {
    final border = r.kind == 'error' ? const Color(0xFF7A3340) : (r.kind == 'question' ? const Color(0xFF2E7AA0) : const Color(0xFF1E4D68));
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF0B2034), borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(r.speech, style: const TextStyle(fontSize: 15, height: 1.35))),
          IconButton(
            tooltip: 'Repetir',
            icon: const Icon(Icons.replay, size: 20),
            onPressed: () => speaker.say(r.speech, engine!.settings),
          ),
        ],
      ),
    );
  }

  Widget _commandField() {
    void submit() {
      final t = input.text;
      input.clear();
      FocusScope.of(context).unfocus();
      _run(t, fromVoice: false);
    }

    return Row(children: [
      Expanded(
        child: TextField(
          controller: input,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => submit(),
          decoration: InputDecoration(
            hintText: 'Ou digite um comando…',
            filled: true,
            fillColor: const Color(0xFF091522),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
          ),
        ),
      ),
      const SizedBox(width: 8),
      IconButton.filled(onPressed: submit, icon: const Icon(Icons.send), tooltip: 'Executar'),
    ]);
  }

  Widget _filters() {
    const opts = {'pending': 'Pendentes', 'today': 'Hoje', 'tomorrow': 'Amanhã', 'done': 'Concluídas', 'all': 'Todas'};
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final o in opts.entries)
          ChoiceChip(label: Text(o.value), selected: filter == o.key, onSelected: (_) => setState(() => filter = o.key)),
      ],
    );
  }

  List<Widget> _taskList(JarvisEngine e) {
    final items = visibleTasks;
    if (items.isEmpty) {
      return const [Padding(padding: EdgeInsets.all(12), child: Text('Nenhuma tarefa nesta visualização.', style: TextStyle(color: Colors.white54)))];
    }
    final now = DateTime.now();
    final out = <Widget>[];
    String? lastDay;
    for (final t in items) {
      final d = t.due;
      final key = d == null ? 'none' : dayKey(d);
      if (key != lastDay) {
        lastDay = key;
        final label = d == null ? 'SEM DATA' : dayLabel(d, now).toUpperCase();
        out.add(Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 2),
          child: Text(label, style: const TextStyle(color: Color(0xFF7FB8D3), fontSize: 12, letterSpacing: 1)),
        ));
      }
      out.add(_taskTile(e, t, now));
    }
    return out;
  }

  Widget _taskTile(JarvisEngine e, Task t, DateTime now) {
    final d = t.due;
    final bits = <String>[];
    if (d != null) {
      bits.add(t.allDay ? 'dia inteiro' : '${pad(d.hour)}:${pad(d.minute)}');
      if (!t.allDay) bits.add(t.reminderOffsetsMinutes.isEmpty ? 'sem aviso' : 'aviso ${t.reminderOffsetsMinutes.map(describeLead).join(', ')}');
    }
    if (t.recurrenceRule != null) bits.add('↻ ${describeRecurrence(t.recurrenceRule)}');
    final late = e.inRange(t, 'overdue');
    if (late) bits.add('atrasada');
    return Dismissible(
      key: ValueKey(t.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: const Color(0xFF5A1F2A),
        child: const Icon(Icons.delete_outline),
      ),
      onDismissed: (_) async {
        final r = await e.remove(t.id);
        await notifier.sync(e);
        if (!mounted) return;
        setState(() {});
        _snack(r.speech, undo: r.changed);
      },
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Checkbox(
          value: t.status == 'completed',
          onChanged: (v) async {
            final r = await e.setDone(t.id, v ?? false);
            await notifier.sync(e);
            if (!mounted) return;
            setState(() {});
            _snack(r.speech, undo: r.changed);
          },
        ),
        title: Text(
          t.title,
          style: TextStyle(decoration: t.status == 'completed' ? TextDecoration.lineThrough : null, color: t.status == 'completed' ? Colors.white54 : null),
        ),
        subtitle: bits.isEmpty ? null : Text(bits.join(' · '), style: TextStyle(color: late ? const Color(0xFFFFCF5C) : Colors.white60)),
      ),
    );
  }
}

// ======================================================= preferências e voz
class SettingsPage extends StatefulWidget {
  final JarvisEngine engine;
  final Speaker speaker;
  final Notifier notifier;
  const SettingsPage({super.key, required this.engine, required this.speaker, required this.notifier});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<VoiceInfo> voices = [];
  bool loading = true;
  bool? notifOn;

  JarvisSettings get s => widget.engine.settings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await widget.speaker.portugueseVoices();
    final n = await widget.notifier.enabled();
    if (!mounted) return;
    setState(() {
      voices = v;
      notifOn = n;
      loading = false;
    });
  }

  Future<void> _save() async {
    await widget.engine.saveSettings();
    await widget.notifier.sync(widget.engine);
  }

  Future<void> _preview([VoiceInfo? v]) async {
    if (v != null) {
      s.voiceName = v.name;
      s.voiceLocale = v.locale;
    }
    final h = DateTime.now().hour;
    final g = h < 12 ? 'Bom dia' : h < 18 ? 'Boa tarde' : 'Boa noite';
    await widget.speaker.say('$g${s.honorific ? ', senhor' : ''}. Aqui é o JARVIS. Sua agenda está organizada e pronta para novos compromissos.', s);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voz e preferências'), backgroundColor: kBg),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Voz', style: TextStyle(color: kCyan, fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 4),
          const Text(
            'O Android não informa se a voz é masculina ou feminina. Toque em ▶ para ouvir cada uma e marque a que preferir.',
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
          if (loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          if (!loading && voices.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Nenhuma voz em português encontrada.', style: TextStyle(color: Color(0xFFFFCF5C))),
            ),
          for (final v in voices)
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: v.name,
              groupValue: s.voiceName,
              title: Text(v.name, style: const TextStyle(fontSize: 14)),
              subtitle: Text(v.label.replaceFirst('${v.name} · ', ''), style: const TextStyle(fontSize: 12)),
              secondary: IconButton(icon: const Icon(Icons.play_arrow), tooltip: 'Ouvir', onPressed: () => _preview(v)),
              onChanged: (_) async {
                setState(() {
                  s.voiceName = v.name;
                  s.voiceLocale = v.locale;
                });
                await _save();
                await _preview();
              },
            ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF2A240D), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF6B5A1D))),
            child: const Text(
              'Para ter mais vozes (inclusive masculinas): Configurações do Android › Gerenciamento geral › Idioma › Conversão de texto em voz '
              '› mecanismo "Serviços de voz do Google" › engrenagem › Instalar dados de voz › Português (Brasil). '
              'O caminho varia um pouco conforme o modelo. Depois volte aqui.',
              style: TextStyle(color: Color(0xFFFFE9A8), fontSize: 13),
            ),
          ),
          Text('Velocidade: ${s.rate.toStringAsFixed(2)}'),
          Slider(value: s.rate.clamp(0.3, 0.7), min: 0.3, max: 0.7, divisions: 20, onChanged: (v) => setState(() => s.rate = v), onChangeEnd: (_) => _save()),
          Text('Tom (mais baixo = mais grave): ${s.pitch.toStringAsFixed(2)}'),
          Slider(value: s.pitch.clamp(0.6, 1.3), min: 0.6, max: 1.3, divisions: 35, onChanged: (v) => setState(() => s.pitch = v), onChangeEnd: (_) => _save()),
          Row(children: [
            FilledButton.icon(onPressed: () => _preview(), icon: const Icon(Icons.volume_up), label: const Text('Ouvir prévia')),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () async {
                setState(() {
                  s.rate = 0.48;
                  s.pitch = 0.9;
                });
                await _save();
              },
              child: const Text('Restaurar padrão'),
            ),
          ]),
          const Divider(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tratar por "senhor"'),
            value: s.honorific,
            onChanged: (v) async {
              setState(() => s.honorific = v);
              await _save();
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Perguntar a antecedência ao agendar compromissos'),
            value: s.askLead,
            onChanged: (v) async {
              setState(() => s.askLead = v);
              await _save();
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Antecedência padrão de compromissos'),
            trailing: DropdownButton<int>(
              value: const [5, 10, 15, 30, 60, 120].contains(s.defaultLead) ? s.defaultLead : 15,
              items: const [5, 10, 15, 30, 60, 120].map((m) => DropdownMenuItem(value: m, child: Text(describeLead(m)))).toList(),
              onChanged: (v) async {
                if (v == null) return;
                setState(() => s.defaultLead = v);
                await _save();
              },
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Reabrir o microfone quando o JARVIS fizer uma pergunta'),
            value: s.followUp,
            onChanged: (v) async {
              setState(() => s.followUp = v);
              await _save();
            },
          ),
          const Divider(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Resumo diário'),
            subtitle: Text('Notificação às ${s.summaryTime}; ao tocar, o JARVIS lê a agenda.'),
            value: s.summaryEnabled,
            onChanged: (v) async {
              setState(() => s.summaryEnabled = v);
              await _save();
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Horário do resumo'),
            trailing: TextButton(
              child: Text(s.summaryTime),
              onPressed: () async {
                final hm = s.summaryTime.split(':').map(int.parse).toList();
                final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: hm[0], minute: hm[1]));
                if (picked == null) return;
                setState(() => s.summaryTime = '${pad(picked.hour)}:${pad(picked.minute)}');
                await _save();
              },
            ),
          ),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Notificações'),
            subtitle: Text(notifOn == false ? 'Desativadas — os lembretes não vão aparecer.' : 'Ativadas.'),
            trailing: notifOn == false
                ? FilledButton(
                    onPressed: () async {
                      await widget.notifier.requestPermission();
                      final n = await widget.notifier.enabled();
                      if (mounted) setState(() => notifOn = n);
                    },
                    child: const Text('Permitir'),
                  )
                : const Icon(Icons.check_circle, color: kCyan),
          ),
          const SizedBox(height: 8),
          const Text(
            'Dica: em aparelhos Samsung, para os avisos não atrasarem, deixe o JARVIS como "Sem restrições" em '
            'Configurações › Aplicativos › JARVIS › Bateria.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Text('Versão $coreVersion', style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }
}
