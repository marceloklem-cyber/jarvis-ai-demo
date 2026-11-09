// Teste de ponta a ponta no Chrome headless (Playwright).
// Uso: TZ=America/Sao_Paulo node tests/browser.test.js   (serve a pasta em http://127.0.0.1:8765)
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const ROOT = path.join(__dirname, '..', '..');
const SHOTS = process.env.SHOTS || path.join(ROOT, 'tests', 'screens');
fs.mkdirSync(SHOTS, { recursive: true });
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript' };
const server = http.createServer((req, res) => {
  const p = path.join(ROOT, decodeURIComponent(req.url.split('?')[0]).replace(/^\/$/, '/index.html'));
  if (!p.startsWith(ROOT) || !fs.existsSync(p)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'Content-Type': TYPES[path.extname(p)] || 'application/octet-stream' });
  fs.createReadStream(p).pipe(res);
});

// Simula vozes e reconhecimento (o Chrome headless não tem áudio).
const MOCKS = `
  window.__spoken = [];
  window.__srScript = [];
  const VOICES = [
    { name: 'Microsoft Francisca Online (Natural) - Portuguese (Brazil)', lang: 'pt-BR', voiceURI: 'francisca', localService: false },
    { name: 'Google português do Brasil', lang: 'pt-BR', voiceURI: 'google-ptbr', localService: false },
    { name: 'Google UK English Female', lang: 'en-GB', voiceURI: 'uk-female', localService: false },
    { name: 'Microsoft Antonio Online (Natural) - Portuguese (Brazil)', lang: 'pt-BR', voiceURI: 'antonio', localService: false }
  ];
  window.SpeechSynthesisUtterance = class { constructor(t) { this.text = t; } };
  Object.defineProperty(window, 'speechSynthesis', { configurable: true, value: {
    getVoices: () => VOICES, cancel() {}, addEventListener() {},
    speak(u) { window.__spoken.push({ text: u.text, voice: u.voice && u.voice.voiceURI, rate: u.rate, pitch: u.pitch });
      setTimeout(() => { u.onstart && u.onstart(); u.onend && u.onend(); }, 5); }
  }});
  window.SpeechRecognition = class {
    start() {
      const step = window.__srScript.shift() || { error: 'no-speech' };
      setTimeout(() => {
        this.onstart && this.onstart();
        if (step.error) { this.onerror && this.onerror({ error: step.error }); }
        else {
          const r = [{ transcript: step.text }]; r.isFinal = true;
          this.onresult && this.onresult({ resultIndex: 0, results: [r] });
        }
        this.onend && this.onend();
      }, 20);
    }
    stop() {} abort() {}
  };
`;

const results = [];
function check(name, cond, info) { results.push({ name, ok: !!cond, info }); console.log((cond ? '  ok   ' : '  FALHA ') + name + (info && !cond ? ' → ' + info : '')); }

(async () => {
  await new Promise((r) => server.listen(8765, '127.0.0.1', r));
  const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', args: ['--no-sandbox'] });
  const errors = [];
  const ctx = await browser.newContext({ locale: 'pt-BR', timezoneId: 'America/Sao_Paulo', viewport: { width: 1280, height: 900 } });
  await ctx.addInitScript(MOCKS);
  const page = await ctx.newPage();
  page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
  page.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); });

  // 1. dados da 0.6 (chave jarvis-demo-v03) + voz feminina escolhida antes
  await page.goto('http://127.0.0.1:8765/');
  await page.evaluate(() => {
    localStorage.clear();
    const d = new Date(); d.setDate(d.getDate() + 1); d.setHours(15, 0, 0, 0);
    localStorage.setItem('jarvis-demo-v03', JSON.stringify([
      { id: 'old1', title: 'Ligar para o contador (0.6)', date: d.toISOString(), reminder: 15, done: false },
      { id: 'old2', title: 'Revisar contrato (0.6)', date: null, reminder: 15, done: false },
      { id: 'old3', title: 'Tarefa concluída (0.6)', date: null, reminder: -1, done: true }
    ]));
  });
  await page.reload();
  await page.waitForTimeout(600);
  console.log('Migração e carregamento');
  check('versão 0.7 no título, cabeçalho e rodapé', (await page.title()).includes('0.7'));
  check('nenhum texto "0.4" visível', !(await page.locator('body').innerText()).includes('0.4'));
  check('banner de migração exibido', /Importei 3 tarefa/.test(await page.locator('#banner').textContent()));
  check('3 tarefas migradas, 2 pendentes', (await page.locator('#sOpen').textContent()) === '2' && (await page.locator('#sDone').textContent()) === '1');
  check('chave antiga preservada', await page.evaluate(() => JSON.parse(localStorage.getItem('jarvis-demo-v03')).length === 3));

  console.log('Voz');
  const opts = await page.locator('#voiceChoice option').allTextContents();
  check('vozes em inglês ocultas por padrão', opts.length === 3 && !opts.some((o) => /English/.test(o)), opts.join(' | '));
  check('voz masculina selecionada automaticamente (Antonio)', (await page.locator('#voiceChoice').inputValue()) === 'antonio');
  check('rótulos de gênero estimado', opts.some((o) => /masculina provável/.test(o)) && opts.some((o) => /feminina provável/.test(o)));
  await page.locator('#voicePanel summary').click();
  await page.locator('#preview').click();
  await page.waitForTimeout(200);
  let spoken = await page.evaluate(() => window.__spoken.slice(-1)[0]);
  check('prévia usa a voz escolhida com tom e velocidade', spoken && spoken.voice === 'antonio' && Math.abs(spoken.pitch - 0.9) < 1e-9 && Math.abs(spoken.rate - 0.92) < 1e-9, JSON.stringify(spoken));
  await page.locator('#pitch').fill('0.8');
  await page.locator('#pitch').dispatchEvent('change');
  await page.locator('#voiceChoice').selectOption('francisca');
  check('guia de voz aparece ao escolher voz feminina', await page.locator('#voiceGuide').isVisible());
  await page.locator('#voiceChoice').selectOption('antonio');
  await page.reload();
  await page.waitForTimeout(500);
  check('voz e tom persistem após recarregar', (await page.locator('#voiceChoice').inputValue()) === 'antonio' && (await page.locator('#pitch').inputValue()) === '0.8');

  console.log('Comandos por texto');
  const cmd = async (t) => { await page.fill('#command', t); await page.press('#command', 'Enter'); await page.waitForTimeout(150); return page.locator('#reply').textContent(); };
  let r = await cmd('Jarvis, agende reunião com o contador amanhã às 14 horas');
  check('cria compromisso e pergunta antecedência', /Reunião com o contador, amanhã às 14 horas.*Deseja outra antecedência/.test(r), r);
  r = await cmd('Me avise 30 minutos antes');
  check('vincula a antecedência ao compromisso', /Aviso 30 minutos antes de Reunião com o contador/.test(r), r);
  r = await cmd('O que tenho amanhã?');
  check('consulta lê os itens de amanhã', /Amanhã o senhor tem 2 itens: às 14 horas, Reunião com o contador; e às 15 horas, Ligar para o contador \(0\.6\)/.test(r), r);
  check('consulta muda o filtro para Amanhã', (await page.locator('[data-filter="tomorrow"]').getAttribute('aria-pressed')) === 'true');
  r = await cmd('Conclua revisar contrato');
  check('conclui tarefa migrada', /Concluída|concluída/.test(r) && (await page.locator('#sDone').textContent()) === '2', r);
  check('toast com Desfazer', await page.locator('#toastUndo').isVisible());
  await page.locator('#toastUndo').click();
  await page.waitForTimeout(150);
  check('desfazer pelo botão reabre a tarefa', (await page.locator('#sDone').textContent()) === '1');
  r = await cmd('reunião 31/02 às 9h');
  check('data inválida recusada', /Data inválida/.test(r), r);
  const n0 = await page.evaluate(() => window.__jarvis.tasks.length);
  await cmd('amanhã às 10h me lembre de ligar para o engenheiro');
  await cmd('amanhã às 10h me lembre de ligar para o engenheiro');
  check('sem duplicata em repetição', (await page.evaluate(() => window.__jarvis.tasks.length)) === n0 + 1);

  console.log('Microfone (simulado)');
  await page.evaluate(() => { window.__srScript.push({ text: 'Jarvis, crie tarefa comprar cimento' }); });
  await page.locator('#mic').click();
  await page.waitForTimeout(400);
  check('comando falado cria a tarefa', await page.evaluate(() => window.__jarvis.tasks.some((t) => t.title === 'Comprar cimento')));
  check('transcrição exibida', /comprar cimento/i.test(await page.locator('#heard').textContent()));
  spoken = await page.evaluate(() => window.__spoken.map((s) => s.text).join(' '));
  check('resposta falada com a voz escolhida', /Comprar cimento/.test(spoken) && (await page.evaluate(() => window.__spoken.slice(-1)[0].voice)) === 'antonio');
  await page.evaluate(() => { window.__srScript.push({ text: 'agende visita na obra' }, { text: 'sexta às 9h' }); });
  await page.locator('#mic').click();
  await page.waitForTimeout(900);
  check('pergunta reabre o microfone e a resposta completa o agendamento', await page.evaluate(() => window.__jarvis.tasks.some((t) => t.title === 'Visita na obra' && t.dueAt)));
  await page.evaluate(() => { window.__jarvis.clearPending(); window.__srScript.push({ error: 'not-allowed' }); });
  await page.locator('#mic').click();
  await page.waitForTimeout(300);
  check('erro de permissão com instrução específica', /Permissão de microfone negada/.test(await page.locator('#state').textContent()) && /Permitir/.test(await page.locator('#micHelp').textContent()));
  await page.keyboard.press('Alt+j');
  await page.waitForTimeout(300);
  check('atalho Alt+J aciona o microfone', /Não ouvi nada/.test(await page.locator('#state').textContent()));

  console.log('Formulário, edição, lembretes');
  await page.locator('#manualPanel summary').click();
  await page.fill('#mTitle', 'Tarefa manual de teste');
  await page.locator('#manualForm button[type=submit]').click();
  await page.waitForTimeout(150);
  check('tarefa manual salva', await page.evaluate(() => window.__jarvis.tasks.some((t) => t.title === 'Tarefa manual de teste')));
  await page.locator('[data-filter="all"]').click();
  const editBtn = page.locator('.task', { hasText: 'Tarefa manual de teste' }).locator('button', { hasText: 'Editar' });
  await editBtn.click();
  await page.fill('#eTitle', 'Tarefa manual editada');
  await page.locator('#editForm button[value=save]').click();
  await page.waitForTimeout(150);
  check('edição pelo diálogo', await page.evaluate(() => window.__jarvis.tasks.some((t) => t.title === 'Tarefa manual editada')));
  await page.evaluate(() => {
    const d = new Date(Date.now() + 15 * 60000 - 5000); // arredondado ao minuto → aviso já vencido há 5–65 s
    const hh = d.getHours(), mm = String(d.getMinutes()).padStart(2, '0');
    window.__jarvis.handle('hoje às ' + hh + ':' + mm + ' ligar para o banco, avise 15 minutos antes');
    window.__spoken.length = 0;
  });
  await page.evaluate(() => document.dispatchEvent(new Event('visibilitychange')));
  await page.waitForTimeout(1200);
  const remind = await page.evaluate(() => window.__spoken.map((s) => s.text).join(' '));
  check('lembrete falado com a página aberta', /Lembrete, senhor: Ligar para o banco/.test(remind), remind);

  console.log('Layout');
  await page.screenshot({ path: path.join(SHOTS, 'desktop.png'), fullPage: true });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForTimeout(200);
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  check('sem rolagem horizontal no celular (390 px)', overflow <= 0, 'excesso ' + overflow + ' px');
  check('painel de voz dentro do layout principal', await page.evaluate(() => !!document.querySelector('main #voicePanel')));
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({ path: path.join(SHOTS, 'mobile.png'), fullPage: true });

  console.log('Arquivo local (file://)');
  const p2 = await ctx.newPage();
  p2.on('pageerror', (e) => errors.push('file pageerror: ' + e.message));
  await p2.goto('file://' + path.join(ROOT, 'index.html'));
  await p2.locator('#mic').click();
  await p2.waitForTimeout(200);
  check('aviso claro ao abrir como arquivo', /aberta como arquivo/.test(await p2.locator('#state').textContent()));

  check('nenhum erro de JavaScript', errors.length === 0, errors.join(' | '));
  await browser.close();
  server.close();
  const fail = results.filter((x) => !x.ok).length;
  console.log('\n' + (results.length - fail) + '/' + results.length + ' verificações aprovadas');
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error(e); server.close(); process.exit(1); });
