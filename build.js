#!/usr/bin/env node
/* Inlines www/style.css and www/game.js into a single self-contained
   index.html at the project root. A one-file build works when opened
   directly as a local file (including Android's content:// URIs, which
   can't resolve relative <link>/<script> paths). */
const fs = require('fs');
const path = require('path');

const www = path.join(__dirname, 'www');
let html = fs.readFileSync(path.join(www, 'index.html'), 'utf8');
const css = fs.readFileSync(path.join(www, 'style.css'), 'utf8');
const js  = fs.readFileSync(path.join(www, 'game.js'), 'utf8');

// Drop PWA hooks (manifest link + service-worker registration): a single
// self-contained file has no sibling files to reference.
html = html.replace(/\s*<!-- pwa:start -->[\s\S]*?<!-- pwa:end -->/g, '');

html = html.replace(/\s*<link rel="stylesheet" href="style\.css" \/>/,
  '\n  <style>\n' + css + '\n  </style>');
html = html.replace(/\s*<script src="game\.js"><\/script>/,
  '\n  <script>\n' + js + '\n  </script>');

fs.writeFileSync(path.join(__dirname, 'index.html'), html);
console.log('Built index.html (' + html.length + ' bytes) from www/');
