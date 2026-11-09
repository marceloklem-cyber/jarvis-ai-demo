# JARVIS AI

Assistente pessoal por voz, em português — uso exclusivamente pessoal.

| Pasta | O que é |
|---|---|
| `index.html`, `sw.js` | Versão web 0.7.2 (GitHub Pages) |
| `app/` | App Android 0.8 (Flutter) — o APK é gerado automaticamente em **Actions › Releases** |
| `web-src/` | Código-fonte e testes da versão web (`node web-src/build.js` gera o `index.html`) |
| `.github/workflows/build-apk.yml` | Compilação automática do APK sempre que `app/` muda |

Instruções do app: `app/LEIA-ME.md`. Instruções da versão web: `web-src/LEIA-ME_0.7.md`.
