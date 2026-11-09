// Gera index.html (arquivo único para o GitHub Pages) embutindo src/jarvis-core.js no template.
// Uso: node build.js
'use strict';
const fs = require('fs');
const path = require('path');
const root = __dirname;
const core = fs.readFileSync(path.join(root, 'src', 'jarvis-core.js'), 'utf8').trim();
const tpl = fs.readFileSync(path.join(root, 'src', 'index.template.html'), 'utf8');
if (!tpl.includes('/*@@JARVIS_CORE@@*/')) throw new Error('Marcador do núcleo ausente no template');
if (core.includes('</script')) throw new Error('O núcleo não pode conter </script>');
const out = tpl.replace('/*@@JARVIS_CORE@@*/', () => core);
fs.writeFileSync(path.join(root, '..', 'index.html'), out);
console.log('index.html gerado: ' + out.length + ' bytes');
