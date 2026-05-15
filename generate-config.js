const fs = require('fs');
const path = require('path');

const root = __dirname;
const dist = path.join(root, 'dist');
const url = process.env.SUPABASE_URL;
const anonKey = process.env.SUPABASE_ANON_KEY || process.env.SUPABASE_PUBLISHABLE_KEY;

if (!url || !anonKey) {
  console.error('Missing Supabase environment variables. Set SUPABASE_URL and SUPABASE_ANON_KEY in Vercel.');
  process.exit(1);
}

fs.rmSync(dist, { recursive: true, force: true });
fs.mkdirSync(dist, { recursive: true });

for (const file of ['index.html', 'dashboard.html', 'admin.html']) {
  fs.copyFileSync(path.join(root, file), path.join(dist, file));
}

const config = `window.MARINHO_SUPABASE_CONFIG = ${JSON.stringify({ url, anonKey }, null, 2)};\n`;
fs.writeFileSync(path.join(dist, 'config.js'), config, 'utf8');

console.log('Generated static deployment in dist/.');