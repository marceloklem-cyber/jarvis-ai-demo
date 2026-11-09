// Testes do núcleo do app — mesmos cenários da versão web (tests/core.test.js).
// Rodam no GitHub antes de gerar o APK:  flutter test
import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_app/core/jarvis_core.dart';

DateTime mon() => DateTime(2026, 11, 9, 10, 0); // segunda, 09/11/2026 10:00

class Clock {
  DateTime now;
  Clock(this.now);
}

Future<(JarvisEngine, Clock, MemoryStore)> engine([DateTime? start]) async {
  final c = Clock(start ?? mon());
  final st = MemoryStore();
  final e = await JarvisEngine.open(st, now: () => c.now);
  return (e, c, st);
}

String local(DateTime? d) => d == null ? 'null' : '${d.year}-${pad(d.month)}-${pad(d.day)} ${pad(d.hour)}:${pad(d.minute)}';

String at(String cmd, [DateTime? now]) {
  final n = now ?? mon();
  final it = parse(cmd, n);
  expect(it.type, 'create', reason: cmd);
  return local(resolveWhen(it.when!, n, it.recurrence).due);
}

void main() {
  test('1. amanhã às 15 horas me lembre de ligar para o contador', () async {
    final (e, _, _) = await engine();
    final r = await e.handle('Jarvis, amanhã às 15 horas me lembre de ligar para o contador.');
    final t = e.tasks.single;
    expect(t.title, 'Ligar para o contador');
    expect(local(t.due), '2026-11-10 15:00');
    expect(t.reminderOffsetsMinutes, [0]);
    expect(r.speech, contains('amanhã às 15 horas'));
  });

  test('2 e 3. agende reunião → pergunta antecedência → "me avise 30 minutos antes"', () async {
    final (e, _, _) = await engine();
    final r = await e.handle('Jarvis, agende reunião com o contador amanhã às 14 horas.');
    expect(r.kind, 'question');
    expect(e.tasks.single.title, 'Reunião com o contador');
    expect(local(e.tasks.single.due), '2026-11-10 14:00');
    await e.handle('Me avise 30 minutos antes.');
    expect(e.tasks.single.reminderOffsetsMinutes, [30]);
    expect(e.tasks.length, 1);
  });

  test('4. consultas não criam tarefas e leem os itens', () async {
    final (e, _, _) = await engine();
    await e.handle('hoje às 16h pagar fornecedor');
    await e.handle('amanhã às 15 horas me lembre de ligar para o contador');
    await e.handle('crie tarefa revisar contrato');
    expect((await e.handle('O que tenho hoje?')).speech, contains('Hoje o senhor tem 1 item: às 16 horas, Pagar fornecedor'));
    expect((await e.handle('O que tenho amanhã?')).speech, contains('Amanhã o senhor tem 1 item: às 15 horas, Ligar para o contador'));
    final p = await e.handle('Quais são os meus compromissos?');
    expect(p.speech, contains('3 itens'));
    expect(p.speech, contains('Revisar contrato'));
    expect(e.tasks.length, 3);
  });

  test('5. transfira minha reunião de sexta para segunda às 9 horas', () async {
    final (e, _, _) = await engine();
    e.settings.askLead = false;
    await e.handle('agende reunião com o contador sexta às 14h');
    await e.handle('agende reunião de obra quinta às 10h');
    await e.handle('Transfira minha reunião de sexta para segunda às 9 horas.');
    expect(local(e.tasks.firstWhere((t) => t.title == 'Reunião com o contador').due), '2026-11-16 09:00');
    expect(local(e.tasks.firstWhere((t) => t.title == 'Reunião de obra').due), '2026-11-12 10:00');
  });

  test('5b. ambiguidade pergunta e aceita o número', () async {
    final (e, _, _) = await engine();
    e.settings.askLead = false;
    await e.handle('agende reunião com o contador sexta às 14h');
    await e.handle('agende reunião de obra quinta às 10h');
    final r = await e.handle('transfira a reunião para terça às 11h');
    expect(r.kind, 'question');
    await e.handle('sim');
    expect(e.tasks.length, 2);
    await e.handle('a segunda');
    expect(e.tasks.where((t) => local(t.due) == '2026-11-10 11:00').length, 1);
  });

  test('6. pendência sem horário inventado', () async {
    final (e, _, _) = await engine();
    await e.handle('Crie tarefa revisar contrato.');
    expect(e.tasks.single.title, 'Revisar contrato');
    expect(e.tasks.single.dueAt, isNull);
  });

  test('7. resumo diário', () async {
    final (e, _, _) = await engine();
    await e.handle('Todos os dias às 8 horas me apresente minhas tarefas.');
    expect(e.tasks, isEmpty);
    expect(e.settings.summaryEnabled, isTrue);
    expect(e.settings.summaryTime, '08:00');
  });

  test('8. conclua a tarefa de ligar para o fornecedor', () async {
    final (e, _, _) = await engine();
    await e.handle('me lembre de ligar para o fornecedor amanhã às 9h');
    await e.handle('crie tarefa revisar contrato');
    await e.handle('Conclua a tarefa de ligar para o fornecedor.');
    expect(e.tasks[0].status, 'completed');
    expect(e.tasks[1].status, 'pending');
  });

  test('9. engenheiro com aviso de 15 minutos', () async {
    final (e, _, _) = await engine();
    await e.handle('Me lembre de ligar para o engenheiro amanhã às 10h; avise 15 minutos antes.');
    expect(e.tasks.single.title, 'Ligar para o engenheiro');
    expect(local(e.tasks.single.due), '2026-11-10 10:00');
    expect(e.tasks.single.reminderOffsetsMinutes, [15]);
  });

  test('datas e horas', () {
    final cases = {
      'hoje às 16h comprar pão': '2026-11-09 16:00',
      'depois de amanhã às 9:30 dentista': '2026-11-11 09:30',
      'quinta às 14h30 reunião': '2026-11-12 14:30',
      'sexta às 3 da tarde reunião': '2026-11-13 15:00',
      'amanhã às 9 da noite ligar': '2026-11-10 21:00',
      'amanhã ao meio-dia almoço': '2026-11-10 12:00',
      'amanhã às nove e meia reunião': '2026-11-10 09:30',
      'dia 15/12 às 10h reunião': '2026-12-15 10:00',
      '15 de dezembro de 2027 às 8h viagem': '2027-12-15 08:00',
      'dia 31 pagar aluguel': '2026-12-31 00:00',
      'na próxima semana revisar orçamento': '2026-11-16 00:00',
      'daqui a 30 minutos tirar o bolo': '2026-11-09 10:30',
      'às 9h ligar para o banco': '2026-11-10 09:00',
    };
    cases.forEach((cmd, exp) => expect(at(cmd), exp, reason: cmd));
  });

  test('virada de mês e de ano', () {
    final nye = DateTime(2026, 12, 31, 22, 0);
    expect(at('amanhã às 9h ligar', nye), '2027-01-01 09:00');
    expect(at('dia 5 às 8h pagar', nye), '2027-01-05 08:00');
    expect(at('03/01 às 10h reunião', nye), '2027-01-03 10:00');
    expect(at('amanhã às 8h ligar', DateTime(2026, 11, 30, 18)), '2026-12-01 08:00');
  });

  test('datas e horas inválidas são recusadas', () async {
    final (e, _, _) = await engine();
    for (final cmd in ['reunião 31/02 às 9h', 'às 25h tomar café', 'pagar 31 de abril']) {
      expect((await e.handle(cmd)).kind, 'error', reason: cmd);
    }
    expect(e.tasks, isEmpty);
  });

  test('títulos limpos', () {
    final cases = {
      'Me lembre de comprar material sexta às 9h': 'Comprar material',
      'lembre-me de pagar o boleto amanhã': 'Pagar o boleto',
      'ok jarvis, por favor, anote que preciso renovar a CNH dia 20': 'Renovar a CNH',
      'tenho que levar o carro na revisão quinta às 8h': 'Levar o carro na revisão',
      'agende almoço com o João amanhã ao meio-dia': 'Almoço com o João',
    };
    cases.forEach((cmd, exp) => expect(parse(cmd, mon()).title, exp, reason: cmd));
  });

  test('antecedências faladas', () {
    expect(parse('amanhã às 10h reunião, me avise uma hora antes', mon()).reminders, [60]);
    expect(parse('amanhã às 10h reunião, avise meia hora antes', mon()).reminders, [30]);
    expect(parse('amanhã às 10h reunião sem lembrete', mon()).reminders, <int>[]);
  });

  test('recorrência e próxima ocorrência', () async {
    final (e, c, _) = await engine();
    await e.handle('toda segunda e quarta às 7h academia');
    expect(e.tasks.single.recurrenceRule!.byDay, [1, 3]);
    expect(local(e.tasks.single.due), '2026-11-11 07:00');
    await e.handle('pagar boleto todo dia 31 às 9h');
    expect(local(e.tasks[1].due), '2026-11-30 09:00');
    c.now = DateTime(2026, 11, 30, 10);
    await e.handle('conclua pagar boleto');
    expect(local(e.tasks[1].due), '2026-12-31 09:00');
    expect(e.tasks[1].status, 'pending');
  });

  test('duplicata, desfazer e falha de gravação', () async {
    final (e, _, st) = await engine();
    await e.handle('amanhã às 15 horas me lembre de ligar para o contador');
    final r = await e.handle('amanhã às 15 horas me lembre de ligar para o contador');
    expect(r.speech, contains('já está registrada'));
    expect(e.tasks.length, 1);
    await e.handle('desfazer');
    expect(e.tasks, isEmpty);
    st.failWrites = true;
    final f = await e.handle('crie tarefa revisar contrato');
    expect(f.kind, 'error');
    expect(e.tasks, isEmpty);
  });

  test('avisos planejados para o Android', () async {
    final (e, _, _) = await engine();
    await e.handle('amanhã às 15h ligar para o contador, avise 15 minutos antes');
    await e.handle('todos os dias às 8h tomar vitamina');
    final plan = e.planNotifications();
    expect(plan.first.body, contains('Tomar vitamina'));
    expect(plan.any((p) => local(p.at) == '2026-11-10 14:45' && p.body.contains('Ligar para o contador')), isTrue);
    expect(plan.where((p) => p.body.contains('Tomar vitamina')).length, greaterThan(5));
    expect(plan.map((p) => p.id).toSet().length, plan.length);
  });

  test('dados persistem entre aberturas', () async {
    final st = MemoryStore();
    final e1 = await JarvisEngine.open(st, now: mon);
    await e1.handle('crie tarefa revisar contrato');
    final e2 = await JarvisEngine.open(st, now: mon);
    expect(e2.tasks.single.title, 'Revisar contrato');
  });
}
