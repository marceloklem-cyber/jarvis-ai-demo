// Testes do núcleo JARVIS 0.7 — executar com:  TZ=America/Sao_Paulo node --test tests/
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const C = require(path.join(__dirname, '..', 'src', 'jarvis-core.js'));

const MON = () => new Date(2026, 10, 9, 10, 0); // segunda, 09/11/2026 10:00
function memStorage(init) {
  const m = new Map(Object.entries(init || {}));
  return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, String(v)), map: m };
}
function engine(nowFn, storage) {
  let now = (nowFn || MON)();
  const st = storage || memStorage();
  const e = C.createEngine({ storage: st, now: () => now, random: () => 0 });
  e.setNow = (d) => { now = d; };
  e.storage = st;
  return e;
}
const local = (iso) => {
  const d = new Date(iso);
  const p = (n) => String(n).padStart(2, '0');
  return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) + ' ' + p(d.getHours()) + ':' + p(d.getMinutes());
};
function created(e, cmd) {
  const before = e.tasks.length;
  const r = e.handle(cmd, 'voice');
  assert.equal(e.tasks.length, before + 1, 'deveria criar tarefa: ' + cmd + ' → ' + r.speech);
  return { r, t: e.tasks[e.tasks.length - 1] };
}
function when(cmd, now) {
  const it = C.parse(cmd, now || MON());
  assert.equal(it.type, 'create', cmd + ' → ' + it.type);
  const r = C.resolveWhen(it.when, now || MON(), it.recurrence);
  return { it, r, at: r.due ? local(r.due.toISOString()) : null };
}

test('ambiente com fuso de São Paulo', () => {
  assert.equal(new Date(2026, 10, 9).getTimezoneOffset(), 180, 'execute com TZ=America/Sao_Paulo');
});

// ------------------------------------------------------- comandos do briefing
test('1. amanhã às 15 horas me lembre de ligar para o contador', () => {
  const e = engine();
  const { r, t } = created(e, 'Jarvis, amanhã às 15 horas me lembre de ligar para o contador.');
  assert.equal(t.title, 'Ligar para o contador');
  assert.equal(local(t.dueAt), '2026-11-10 15:00');
  assert.deepEqual(t.reminderOffsetsMinutes, [0]);
  assert.match(r.speech, /amanhã às 15 horas/);
});

test('2 e 3. agende reunião → pergunta antecedência → "me avise 30 minutos antes"', () => {
  const e = engine();
  const { r, t } = created(e, 'Jarvis, agende reunião com o contador amanhã às 14 horas.');
  assert.equal(t.title, 'Reunião com o contador');
  assert.equal(t.type, 'event');
  assert.equal(local(t.dueAt), '2026-11-10 14:00');
  assert.equal(r.kind, 'question');
  assert.match(r.speech, /antecedência/);
  const r2 = e.handle('Me avise 30 minutos antes.');
  assert.deepEqual(e.tasks[0].reminderOffsetsMinutes, [30]);
  assert.equal(e.tasks.length, 1);
  assert.match(r2.speech, /30 minutos antes/);
});

test('3b. "me avise 30 minutos antes" sem pergunta pendente usa a tarefa recém-criada', () => {
  const e = engine();
  e.settings.askLead = false;
  e.handle('agende reunião com o contador amanhã às 14 horas');
  assert.equal(e.pending, null);
  e.handle('me avise uma hora antes');
  assert.deepEqual(e.tasks[0].reminderOffsetsMinutes, [60]);
});

test('2b. resposta "não" mantém o aviso padrão; "sem aviso" remove', () => {
  const e = engine();
  e.handle('agende consulta no dentista sexta às 10h');
  e.handle('não');
  assert.deepEqual(e.tasks[0].reminderOffsetsMinutes, [15]);
  e.handle('agende jantar com a família sábado às 20h');
  e.handle('sem aviso');
  assert.deepEqual(e.tasks[1].reminderOffsetsMinutes, []);
});

test('4. consultas de hoje, amanhã e pendentes', () => {
  const e = engine();
  e.handle('hoje às 16h pagar fornecedor');
  e.handle('amanhã às 15 horas me lembre de ligar para o contador');
  e.handle('crie tarefa revisar contrato');
  let r = e.handle('O que tenho hoje?');
  assert.equal(r.kind, 'info');
  assert.match(r.speech, /Hoje o senhor tem 1 item: às 16 horas, Pagar fornecedor/);
  r = e.handle('O que tenho amanhã?');
  assert.match(r.speech, /Amanhã o senhor tem 1 item: às 15 horas, Ligar para o contador/);
  r = e.handle('Quais são minhas tarefas pendentes?');
  assert.match(r.speech, /3 itens/);
  assert.equal(e.tasks.length, 3, 'consultas não podem criar tarefas');
  r = e.handle('o que tenho na quarta?');
  assert.match(r.speech, /não há nada agendado/);
});

test('5. transfira minha reunião de sexta para segunda às 9 horas', () => {
  const e = engine();
  e.settings.askLead = false;
  e.handle('agende reunião com o contador sexta às 14h');
  e.handle('agende reunião de obra quinta às 10h');
  const r = e.handle('Transfira minha reunião de sexta para segunda às 9 horas.');
  const t = e.tasks.find((x) => x.title === 'Reunião com o contador');
  assert.equal(local(t.dueAt), '2026-11-16 09:00', r.speech);
  assert.equal(local(e.tasks.find((x) => x.title === 'Reunião de obra').dueAt), '2026-11-12 10:00');
});

test('5b. ambiguidade pede esclarecimento e aceita o número da opção', () => {
  const e = engine();
  e.settings.askLead = false;
  e.handle('agende reunião com o contador sexta às 14h');
  e.handle('agende reunião de obra quinta às 10h');
  const r = e.handle('transfira a reunião para terça às 11h');
  assert.equal(r.kind, 'question');
  assert.match(r.speech, /2 opções/);
  e.handle('sim'); // resposta inválida: continua perguntando, não cria tarefa
  assert.equal(e.tasks.length, 2);
  e.handle('a segunda');
  const moved = e.tasks.filter((x) => local(x.dueAt) === '2026-11-10 11:00'); // hoje é segunda → terça = amanhã
  assert.equal(moved.length, 1);
});

test('6. crie tarefa revisar contrato → pendência sem horário inventado', () => {
  const e = engine();
  const { t } = created(e, 'Crie tarefa revisar contrato.');
  assert.equal(t.title, 'Revisar contrato');
  assert.equal(t.dueAt, null);
  assert.deepEqual(t.reminderOffsetsMinutes, []);
});

test('7. todos os dias às 8 horas me apresente minhas tarefas → resumo diário', () => {
  const e = engine();
  const r = e.handle('Todos os dias às 8 horas me apresente minhas tarefas.');
  assert.equal(e.tasks.length, 0);
  assert.equal(e.settings.summary.enabled, true);
  assert.equal(e.settings.summary.time, '08:00');
  assert.match(r.speech, /Resumo diário ativado/);
  e.setNow(new Date(2026, 10, 10, 8, 5));
  assert.equal(e.summaryDue(), true);
  e.markSummary();
  assert.equal(e.summaryDue(), false);
  e.handle('desative o resumo diário');
  assert.equal(e.settings.summary.enabled, false);
});

test('8. conclua a tarefa de ligar para o fornecedor', () => {
  const e = engine();
  e.handle('me lembre de ligar para o fornecedor amanhã às 9h');
  e.handle('crie tarefa revisar contrato');
  const r = e.handle('Conclua a tarefa de ligar para o fornecedor.');
  assert.equal(e.tasks[0].status, 'completed', r.speech);
  assert.equal(e.tasks[1].status, 'pending');
  e.handle('já fiz revisar contrato');
  assert.equal(e.tasks[1].status, 'completed');
});

test('9. me lembre de ligar para o engenheiro amanhã às 10h; avise 15 minutos antes', () => {
  const e = engine();
  const { t } = created(e, 'Me lembre de ligar para o engenheiro amanhã às 10h; avise 15 minutos antes.');
  assert.equal(t.title, 'Ligar para o engenheiro');
  assert.equal(local(t.dueAt), '2026-11-10 10:00');
  assert.deepEqual(t.reminderOffsetsMinutes, [15]);
});

// --------------------------------------------------------------- datas e horas
test('expressões de data e hora', () => {
  const cases = [
    ['hoje às 16h comprar pão', '2026-11-09 16:00'],
    ['amanhã às 9h ligar', '2026-11-10 09:00'],
    ['depois de amanhã às 9:30 dentista', '2026-11-11 09:30'],
    ['quinta às 14h30 reunião', '2026-11-12 14:30'],
    ['quinta-feira às 14 horas e 30 reunião', '2026-11-12 14:30'],
    ['sexta às 3 da tarde reunião', '2026-11-13 15:00'],
    ['amanhã às 9 da noite ligar', '2026-11-10 21:00'],
    ['amanhã ao meio-dia almoço', '2026-11-10 12:00'],
    ['amanhã à uma da tarde almoço', '2026-11-10 13:00'],
    ['amanhã às nove e meia reunião', '2026-11-10 09:30'],
    ['dia 15/12 às 10h reunião', '2026-12-15 10:00'],
    ['15 de dezembro de 2027 às 8h viagem', '2027-12-15 08:00'],
    ['dia 20 às 7h exame', '2026-11-20 07:00'],
    ['dia 31 pagar aluguel', '2026-12-31 00:00'],
    ['na segunda que vem às 8h ligar', '2026-11-16 08:00'],
    ['na próxima semana revisar orçamento', '2026-11-16 00:00'],
    ['daqui a 30 minutos tirar o bolo', '2026-11-09 10:30'],
    ['em 2 dias às 10h enviar proposta', '2026-11-11 10:00'],
    ['às 9h ligar para o banco', '2026-11-10 09:00'] // horário já passou hoje → amanhã
  ];
  for (const [cmd, exp] of cases) assert.equal(when(cmd).at, exp, cmd);
  assert.equal(when('às 9h ligar para o banco').r.rolled, true);
  assert.equal(when('sexta comprar material').r.allDay, true);
  assert.equal(when('segunda às 11h', MON()).at, '2026-11-09 11:00', 'mesmo dia da semana, horário futuro → hoje');
  assert.equal(when('segunda às 9h', MON()).at, '2026-11-16 09:00', 'mesmo dia da semana, horário passado → próxima');
});

test('datas inválidas e horários inválidos são recusados', () => {
  const e = engine();
  for (const cmd of ['reunião 31/02 às 9h', 'reunião dia 30/02', 'às 25h tomar café', 'às 10:75 ligar', 'pagar 31 de abril']) {
    const r = e.handle(cmd);
    assert.equal(r.kind, 'error', cmd + ' → ' + r.speech);
  }
  assert.equal(e.tasks.length, 0);
});

test('virada de mês e de ano', () => {
  const nye = new Date(2026, 11, 31, 22, 0);
  assert.equal(when('amanhã às 9h ligar', nye).at, '2027-01-01 09:00');
  assert.equal(when('dia 5 às 8h pagar', nye).at, '2027-01-05 08:00');
  assert.equal(when('03/01 às 10h reunião', nye).at, '2027-01-03 10:00');
  assert.equal(when('sexta às 10h reunião', nye).at, '2027-01-01 10:00');
  const eom = new Date(2026, 10, 30, 18, 0);
  assert.equal(when('amanhã às 8h ligar', eom).at, '2026-12-01 08:00');
  assert.equal(when('depois de amanhã às 8h ligar', eom).at, '2026-12-02 08:00');
});

test('data explícita já passada pede confirmação', () => {
  const e = engine();
  let r = e.handle('hoje às 8h reunião de alinhamento');
  assert.equal(r.kind, 'question');
  assert.equal(e.tasks.length, 0);
  r = e.handle('sim');
  assert.equal(local(e.tasks[0].dueAt), '2026-11-10 08:00');
});

test('compromisso sem data pergunta quando', () => {
  const e = engine();
  e.settings.askLead = false;
  let r = e.handle('agende reunião com o engenheiro');
  assert.equal(r.kind, 'question');
  assert.equal(e.tasks.length, 0);
  r = e.handle('quarta às 16h');
  assert.equal(e.tasks.length, 1);
  assert.equal(local(e.tasks[0].dueAt), '2026-11-11 16:00');
});

test('só data e hora sem descrição pergunta a tarefa', () => {
  const e = engine();
  let r = e.handle('Jarvis, amanhã às 10h');
  assert.equal(r.kind, 'question');
  r = e.handle('ligar para o despachante');
  assert.equal(e.tasks[0].title, 'Ligar para o despachante');
  assert.equal(local(e.tasks[0].dueAt), '2026-11-10 10:00');
});

// ------------------------------------------------------------------- títulos
test('limpeza de títulos', () => {
  const cases = [
    ['Jarvis, amanhã às 15 horas me lembre de ligar para o contador.', 'Ligar para o contador'],
    ['Me lembre de comprar material sexta às 9h', 'Comprar material'],
    ['lembre-me de pagar o boleto amanhã', 'Pagar o boleto'],
    ['ok jarvis, por favor, anote que preciso renovar a CNH dia 20', 'Renovar a CNH'],
    ['tenho que levar o carro na revisão quinta às 8h', 'Levar o carro na revisão'],
    ['crie uma tarefa para revisar o contrato da obra', 'Revisar o contrato da obra'],
    ['Nova tarefa: orçamento da estaca', 'Orçamento da estaca'],
    ['agende almoço com o João amanhã ao meio-dia', 'Almoço com o João'],
    ['ligar para o contador amanhã às 15h, me avise meia hora antes', 'Ligar para o contador']
  ];
  for (const [cmd, exp] of cases) {
    const it = C.parse(cmd, MON());
    assert.equal(it.type, 'create', cmd);
    assert.equal(it.title, exp, cmd);
  }
});

// ---------------------------------------------------------------- lembretes
test('antecedências faladas', () => {
  const cases = [
    ['amanhã às 10h reunião, me avise uma hora antes', [60]],
    ['amanhã às 10h reunião, avise meia hora antes', [30]],
    ['amanhã às 10h reunião, me lembre 1 dia antes', [1440]],
    ['amanhã às 10h reunião com lembrete de 10 minutos', [10]],
    ['amanhã às 10h reunião, avise uma hora e meia antes', [90]],
    ['amanhã às 10h reunião, me avise na hora', [0]],
    ['amanhã às 10h reunião sem lembrete', []]
  ];
  for (const [cmd, exp] of cases) assert.deepEqual(C.parse(cmd, MON()).reminders, exp, cmd);
});

test('avisos: imediato, perdido e antigo', () => {
  const e = engine();
  e.handle('hoje às 10h30 ligar para o banco, avise 15 minutos antes');
  e.setNow(new Date(2026, 10, 9, 10, 14));
  assert.equal(e.dueReminders().length, 0);
  e.setNow(new Date(2026, 10, 9, 10, 15, 30));
  let due = e.dueReminders();
  assert.equal(due.length, 1);
  assert.equal(due[0].missed, false);
  e.markNotified(due[0].task.id, due[0].key);
  assert.equal(e.dueReminders().length, 0, 'não repete o mesmo aviso');
  e.handle('amanhã às 9h pagar conta');
  e.setNow(new Date(2026, 10, 10, 11, 0));
  due = e.dueReminders();
  assert.equal(due.length, 1);
  assert.equal(due[0].missed, true);
  e.setNow(new Date(2026, 10, 12, 11, 0));
  e.markNotified(due[0].task.id, due[0].key);
  assert.equal(e.dueReminders().length, 0);
});

// ------------------------------------------------------------- recorrência
test('recorrências', () => {
  const e = engine();
  let { t } = created(e, 'todos os dias às 8h tomar vitamina');
  assert.deepEqual(t.recurrenceRule, { freq: 'daily' });
  assert.equal(local(t.dueAt), '2026-11-10 08:00');
  ({ t } = created(e, 'toda segunda e quarta às 7h academia'));
  assert.deepEqual(t.recurrenceRule, { freq: 'weekly', byDay: [1, 3] });
  assert.equal(local(t.dueAt), '2026-11-11 07:00');
  ({ t } = created(e, 'nos dias úteis às 18h conferir produção'));
  assert.deepEqual(t.recurrenceRule.byDay, [1, 2, 3, 4, 5]);
  assert.equal(local(t.dueAt), '2026-11-09 18:00');
  ({ t } = created(e, 'pagar boleto todo dia 31 às 9h'));
  assert.equal(local(t.dueAt), '2026-11-30 09:00', 'novembro não tem dia 31 → último dia');
  e.setNow(new Date(2026, 10, 30, 10, 0));
  e.handle('conclua pagar boleto');
  assert.equal(local(e.tasks[3].dueAt), '2026-12-31 09:00');
  assert.equal(e.tasks[3].status, 'pending');
});

// ------------------------------------------------------- outras intenções
test('cancelar, adiar, ajustar aviso, marcar como feita', () => {
  const e = engine();
  e.settings.askLead = false;
  e.handle('agende reunião com o contador amanhã às 14h');
  e.handle('adie a reunião em 1 hora');
  assert.equal(local(e.tasks[0].dueAt), '2026-11-10 15:00');
  e.handle('passe a reunião para as 16h30');
  assert.equal(local(e.tasks[0].dueAt), '2026-11-10 16:30', 'só horário mantém a data');
  e.handle('mude a reunião para quinta');
  assert.equal(local(e.tasks[0].dueAt), '2026-11-12 16:30', 'só data mantém o horário');
  e.handle('mude o aviso da reunião para 1 hora antes');
  assert.deepEqual(e.tasks[0].reminderOffsetsMinutes, [60]);
  e.handle('crie tarefa revisar contrato');
  e.handle('marque como feita a tarefa revisar contrato');
  assert.equal(e.tasks[1].status, 'completed');
  e.handle('cancele a reunião com o contador');
  assert.equal(e.tasks[0].status, 'cancelled');
  const r = e.handle('conclua a tarefa de comprar cimento');
  assert.equal(r.kind, 'error');
});

test('"passe na farmácia" é tarefa, não transferência', () => {
  const e = engine();
  const { t } = created(e, 'passe na farmácia amanhã às 18h');
  assert.equal(t.title, 'Passe na farmácia');
});

test('duplicatas por reconhecimento repetido não são criadas', () => {
  const e = engine();
  e.handle('amanhã às 15 horas me lembre de ligar para o contador');
  const r = e.handle('amanhã às 15 horas me lembre de ligar para o contador');
  assert.equal(e.tasks.length, 1);
  assert.equal(r.kind, 'info');
  assert.match(r.speech, /já está registrada/);
});

test('desfazer restaura o estado anterior', () => {
  const e = engine();
  e.handle('crie tarefa revisar contrato');
  e.handle('conclua revisar contrato');
  assert.equal(e.tasks[0].status, 'completed');
  e.handle('desfazer');
  assert.equal(e.tasks[0].status, 'pending');
  e.handle('desfazer');
  assert.equal(e.tasks.length, 0);
  assert.match(e.handle('desfazer').speech, /Não há nada/);
});

test('falha de gravação não confirma nem altera', () => {
  const st = memStorage();
  const e = engine(MON, st);
  st.setItem = () => { throw new Error('QuotaExceeded'); };
  const r = e.handle('crie tarefa revisar contrato');
  assert.equal(r.kind, 'error');
  assert.equal(e.tasks.length, 0);
  assert.doesNotMatch(r.speech, /Registrado|Anotado/);
});

test('utilidades: hora, data, ajuda, só "Jarvis"', () => {
  const e = engine();
  assert.match(e.handle('que horas são?').speech, /São 10 horas/);
  assert.match(e.handle('que dia é hoje?').speech, /segunda-feira, 9 de novembro de 2026/);
  assert.equal(e.handle('ajuda').kind, 'info');
  assert.equal(e.handle('Jarvis').kind, 'question');
  assert.equal(e.tasks.length, 0);
});

// ------------------------------------------------------- migração e dados
test('migra tarefas da 0.3–0.6 (jarvis-demo-v03) sem apagar a chave antiga', () => {
  const legacy = [
    { id: 'a1', title: 'Ligar contador', date: new Date(2026, 10, 10, 15, 0).toISOString(), reminder: 15, done: false },
    { id: 'a2', title: 'Revisar contrato', date: null, reminder: 15, done: false },
    { id: 'a3', title: 'Pagar luz', date: new Date(2026, 9, 1, 9, 0).toISOString(), reminder: 0, done: true },
    { id: 'a4', title: 'Antiga', date: new Date(2026, 9, 2, 9, 0).toISOString(), reminder: 5, done: false }
  ];
  const raw = JSON.stringify(legacy);
  const st = memStorage({ 'jarvis-demo-v03': raw, 'jarvis-voice': 'Microsoft Daniel' });
  const e = engine(MON, st);
  assert.equal(e.status.migrated, 4);
  assert.equal(e.status.saved, true);
  assert.equal(st.getItem('jarvis-demo-v03'), raw, 'backup original intacto');
  assert.equal(e.tasks[0].title, 'Ligar contador');
  assert.deepEqual(e.tasks[0].reminderOffsetsMinutes, [15]);
  assert.equal(e.tasks[1].dueAt, null);
  assert.deepEqual(e.tasks[1].reminderOffsetsMinutes, []);
  assert.equal(e.tasks[2].status, 'completed');
  assert.equal(e.dueReminders().length, 0, 'avisos antigos não disparam em massa');
  assert.equal(e.settings.voiceURI, 'Microsoft Daniel');
  const e2 = engine(MON, st); // segunda abertura lê a chave nova
  assert.equal(e2.status.migrated, 0);
  assert.equal(e2.tasks.length, 4);
});

test('chave nova corrompida é preservada em backup e não sobrescrita silenciosamente', () => {
  const st = memStorage({ 'jarvis-ai-v07-tasks': '{quebrado' });
  const e = engine(MON, st);
  assert.equal(e.status.loadError, 'corrupt');
  assert.ok([...st.map.keys()].some((k) => k.startsWith('jarvis-ai-v07-tasks-corrompido-')));
});

test('exportar e importar backup', () => {
  const e = engine();
  e.handle('crie tarefa revisar contrato');
  const json = e.exportData();
  const e2 = engine();
  const r = e2.importData(json);
  assert.equal(r.kind, 'ok');
  assert.equal(e2.tasks[0].title, 'Revisar contrato');
  assert.equal(e2.importData('não é json').kind, 'error');
});

// ---------------------------------------------------------------- vozes
test('classificação de vozes (bug "Female" da 0.6 corrigido)', () => {
  const g = (name, lang) => C.classifyVoice({ name, lang, voiceURI: name }).gender;
  assert.equal(g('Google UK English Female', 'en-GB'), 'f');
  assert.equal(g('Google UK English Male', 'en-GB'), 'm');
  assert.equal(g('Microsoft Antonio Online (Natural) - Portuguese (Brazil)', 'pt-BR'), 'm');
  assert.equal(g('Microsoft Daniel - Portuguese (Brazil)', 'pt-BR'), 'm');
  assert.equal(g('Microsoft Francisca Online (Natural) - Portuguese (Brazil)', 'pt-BR'), 'f');
  assert.equal(g('Microsoft Maria - Portuguese (Brazil)', 'pt-BR'), 'f');
  assert.equal(g('Microsoft Thalita Multilingual Online (Natural) - Portuguese (Brazil)', 'pt-BR'), 'f');
  assert.equal(g('Microsoft Duarte Online (Natural) - Portuguese (Portugal)', 'pt-PT'), 'm');
  assert.equal(g('Luciana', 'pt-BR'), 'f');
  assert.equal(g('Google português do Brasil', 'pt-BR'), '?');
  const voices = [
    { name: 'Microsoft Francisca Online (Natural) - Portuguese (Brazil)', lang: 'pt-BR' },
    { name: 'Google português do Brasil', lang: 'pt-BR' },
    { name: 'Google UK English Female', lang: 'en-GB' },
    { name: 'Microsoft Daniel - Portuguese (Brazil)', lang: 'pt-BR' },
    { name: 'Microsoft Antonio Online (Natural) - Portuguese (Brazil)', lang: 'pt-BR' }
  ];
  const ranked = C.rankVoices(voices, false).map((x) => x.voice.name);
  assert.match(ranked[0], /Antonio/);
  assert.match(ranked[1], /Daniel/);
  assert.ok(!ranked.some((n) => /English/.test(n)), 'vozes em inglês ficam ocultas por padrão');
  assert.equal(C.rankVoices(voices, true).length, 5);
});

test('núcleo embutido no index.html é idêntico ao src (build)', () => {
  const fs = require('fs');
  const html = path.join(__dirname, '..', '..', 'index.html');
  if (!fs.existsSync(html)) return;
  const src = fs.readFileSync(path.join(__dirname, '..', 'src', 'jarvis-core.js'), 'utf8');
  assert.ok(fs.readFileSync(html, 'utf8').includes(src.trim()), 'rode: node build.js');
});
