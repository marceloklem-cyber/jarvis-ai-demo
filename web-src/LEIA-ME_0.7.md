# JARVIS AI — Demo web 0.7

Versão web pessoal (GitHub Pages). **Não é o aplicativo nativo**: lembretes e resumo só funcionam com a página aberta.

## Como publicar no GitHub Pages (sem excluir nada)

1. Abra https://github.com/marceloklem-cyber/jarvis-ai-demo
2. Clique em **Add file › Upload files** e arraste **`index.html`** e **`sw.js`** juntos.
   O GitHub substitui o `index.html` existente — não é preciso apagar antes.
3. Em "Commit changes", escreva `JARVIS 0.7` e confirme.
4. Aguarde 1–2 minutos (aba **Actions** mostra o deploy) e abra
   https://marceloklem-cyber.github.io/jarvis-ai-demo/ — o cabeçalho deve dizer **DEMO 0.7**.
   Se ainda aparecer 0.6, recarregue forçando (no celular: feche a aba e abra de novo).

As tarefas gravadas nas versões 0.3–0.6 (chave `jarvis-demo-v03`) são importadas automaticamente na
primeira abertura, **no mesmo navegador e aparelho** onde foram criadas. A chave antiga não é apagada.

## Voz masculina

- **Windows**: use o **Microsoft Edge** — ele oferece a voz neural masculina "Antonio" (precisa de internet).
  No Chrome, a voz masculina local costuma ser a "Microsoft Daniel" (instalável em Configurações › Hora e idioma › Fala).
- **Android (Samsung)**: o Chrome usa a voz do sistema. Configurações › Gerenciamento geral › Idioma ›
  Conversão de texto em voz › mecanismo "Serviços de voz do Google" › engrenagem › Instalar dados de voz ›
  Português (Brasil) › escolha uma variante masculina. O caminho exato varia por modelo.
- A página escolhe sozinha a melhor voz masculina em português que encontrar e mostra um guia quando não há nenhuma.
  O gênero é estimado pelo nome da voz (o navegador não informa) — confirme pela prévia.

## O que mudou da 0.6 para a 0.7

| Área | 0.6 | 0.7 |
|---|---|---|
| Versão exibida | título 0.6, tela "0.4" | 0.7 em todos os lugares |
| Painel de voz | fora do layout, após o rodapé | dentro da página, recolhível |
| Escolha da voz | regra `male` casava com "Female" | classificação corrigida, só português, masculina primeiro |
| Velocidade/tom | não eram salvos | salvos; rótulos coerentes |
| Consultas | "O que tenho amanhã?" criava tarefa | lê os itens de hoje/amanhã/semana/dia/pendentes/atrasadas |
| Títulos | "amanhã às 15 horas me lembre de…" | "Ligar para o contador" (bug do `\b` com acentos corrigido) |
| Concluir / transferir / cancelar / adiar por voz | criavam tarefas | funcionam, com pedido de esclarecimento na ambiguidade |
| Antecedência | só no mesmo comando | pergunta ao agendar compromissos; "me avise 30 minutos antes" vale para a última tarefa |
| Recorrência | não havia | diária, dias úteis, dias da semana, mensal (dia fixo) |
| Resumo diário | não havia | "Todos os dias às 8 horas me apresente minhas tarefas" |
| Datas inválidas | 31/02 virava 03/03 | recusadas; data passada pede confirmação |
| Sem horário | inventava 9h | dia inteiro, sem aviso inventado |
| Duplicatas / desfazer | não havia | bloqueio de duplicatas, "desfazer" por voz e botão |
| Gravação | confirmava sem verificar | confirma só após ler de volta do armazenamento |
| Microfone | mensagem genérica de "arquivo local" | mensagem e instrução por tipo de erro, transcrição ao vivo, Alt+J |
| Notificações | permissão nunca era pedida | botão de ativação; Android via `sw.js` |
| Dados | só no navegador | + exportar/importar backup JSON |

## O que foi testado (e como)

- `tests/core.test.js` — **33 testes** do núcleo (Node, fuso America/Sao_Paulo): os 9 comandos do briefing,
  hoje/amanhã/depois de amanhã, dias da semana, 9h/9:30/14 horas/"nove e meia"/"3 da tarde"/meio-dia,
  datas explícitas e por extenso, datas e horas inválidas, virada de mês e de ano, recorrências (inclui dia 31
  em mês de 30 dias), ambiguidade, duplicatas, desfazer, falha de gravação, migração da 0.6, backup e vozes.
- `tests/browser.test.js` — **33 verificações** no Chrome headless com voz e microfone **simulados**
  (migração real via localStorage, comandos, fala, erros de microfone, edição, lembrete, layout 390 px, `file://`).

**Não testado em aparelho real**: som das vozes, reconhecimento real no Samsung e no Windows, notificações
reais. Esses dependem do seu teste após publicar (roteiro abaixo).

## Roteiro rápido de teste após publicar

1. Abra o site no Chrome do Samsung e no Edge do PC. Confira "DEMO 0.7" e o aviso de tarefas importadas.
2. Voz e personalidade › Ouvir prévia. Se soar feminina, siga o guia exibido.
3. Toque no círculo e diga: "Jarvis, agende reunião com o contador amanhã às 14 horas" → responda "trinta minutos antes".
4. "O que tenho amanhã?" · "Transfira a reunião para quinta às 10" · "Conclua a reunião" · "Desfazer".
5. Lembretes, resumo e dados › Ativar notificações. Crie "daqui a 2 minutos testar aviso" e espere com a página aberta.

## Limitações conhecidas da versão web

- Avisos e resumo **só com a página aberta** (sem garantia com navegador fechado ou tela bloqueada).
- Dados por navegador/aparelho, sem sincronização (virá com o Firebase, em projeto separado).
- Sem palavra de ativação contínua "Jarvis" — exige módulo nativo.
- O interpretador é por regras: frases muito diferentes dos padrões podem não ser entendidas; nesse caso ele pergunta ou recusa, não inventa.

## Desenvolvimento

`src/jarvis-core.js` (núcleo sem DOM) + `src/index.template.html` (interface) → `node build.js` gera o `index.html`.
Testes: `TZ=America/Sao_Paulo node --test tests/core.test.js` e `TZ=America/Sao_Paulo node tests/browser.test.js` (requer Playwright e Chrome).
