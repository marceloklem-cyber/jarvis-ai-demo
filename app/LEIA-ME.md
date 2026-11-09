# JARVIS AI — app Android 0.8

Fale e ele anota; pergunte "quais são meus compromissos?" e ele lê o que está pendente.
Os avisos chegam como notificação no horário, **mesmo com o app fechado e o celular bloqueado**.
Sem Firebase, sem IA paga, sem custo: tudo fica no celular.

## Como obter o APK (sem instalar nada no PC)

1. O app fica na pasta `app/` do repositório `jarvis-ai-demo`.
2. Uma vez só: em **Settings › Secrets and variables › Actions › New repository secret**, crie
   `JARVIS_KEYSTORE_B64` e `JARVIS_KEY_PASSWORD` com o conteúdo dos dois arquivos .txt entregues à parte.
   Eles garantem que cada APK novo instale por cima do anterior. Os segredos não aparecem no código nem nos registros.
3. A cada alteração em `app/`, a aba **Actions** roda "Gerar APK do JARVIS (Android)" sozinha (cerca de 8–12 minutos).
4. Quando ficar verde, abra **Releases** (lado direito da página do repositório) no celular e baixe `app-release.apk`.
5. Toque no arquivo baixado. O Android pede para permitir instalação desta fonte (uma vez). Instale.

Atualizações: cada novo envio gera um APK novo em Releases. Com os segredos configurados, ele instala **por cima**
do anterior, mantendo as tarefas. Sem os segredos, o APK sai com assinatura temporária e cada atualização exige desinstalar.

## Primeiro uso

- Permita **microfone** e **notificações** quando o app pedir.
- Toque em ⚙ › ouça as vozes com ▶ e marque a masculina que preferir; ajuste velocidade e tom.
- Samsung: Configurações › Aplicativos › JARVIS › Bateria › **Sem restrições** (evita avisos atrasados).

## O que ele entende

- "Amanhã às 15 horas me lembre de ligar para o contador"
- "Agende reunião com o contador sexta às 14h" → pergunta a antecedência → "30 minutos antes"
- "Quais são meus compromissos?" · "O que tenho hoje?" · "O que tenho amanhã?"
- "Conclua a tarefa de ligar para o fornecedor" · "Transfira a reunião para segunda às 9" · "Cancele a reunião"
- "Toda segunda e quarta às 7h academia" · "Pagar boleto todo dia 5"
- "Todos os dias às 8 horas me apresente minhas tarefas" (notificação diária; ao tocar, ele lê a agenda)
- "Desfazer"

Também dá para digitar, marcar como concluída na caixinha e apagar arrastando para a esquerda.

## Estado

| | |
|---|---|
| Núcleo (interpretação, agenda, recorrência, desfazer) | portado da versão web 0.7.2, que tem 33 testes aprovados; 18 testes em Dart rodam no GitHub antes de gerar o APK |
| App (tela, voz, notificações) | escrito para Flutter 3.24.5; **ainda não compilado** — a primeira compilação acontece no GitHub |
| Testado em aparelho real | **não** — depende da sua instalação |
| Ainda não incluído | palavra de ativação "Jarvis", sincronização com o PC, IA em nuvem, importar tarefas da versão web |

## Segurança

A chave que assina o APK fica apenas nos segredos do GitHub (e na cópia que você guardar). Não há senha, token,
chave de API ou dado pessoal no código. Guarde os dois arquivos .txt num local seguro: sem eles, um APK futuro
não conseguirá atualizar o app instalado sem desinstalá-lo.

## Estrutura

- `lib/core/jarvis_core.dart` — núcleo (sem Flutter): interpretador, agenda, avisos planejados
- `lib/services/platform.dart` — armazenamento, fala, escuta e notificações do Android
- `lib/main.dart` — telas
- `test/core_test.dart` — testes do núcleo
- `tool/patch_android.py` — permissões e assinatura aplicadas ao projeto Android gerado
- `../.github/workflows/build-apk.yml` — compilação automática
