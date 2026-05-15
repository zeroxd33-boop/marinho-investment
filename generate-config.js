const fs = require('fs');
const path = require('path');

const url = process.env.SUPABASE_URL;
const anonKey = process.env.SUPABASE_ANON_KEY || process.env.SUPABASE_PUBLISHABLE_KEY;

if (!url || !anonKey) {
  console.error('Missing Supabase environment variables. Set SUPABASE_URL and SUPABASE_ANON_KEY in Vercel.');
  process.exit(1);
}

const config = `window.MARINHO_SUPABASE_CONFIG = ${JSON.stringify({ url, anonKey }, null, 2)};\n`;
const outputPath = path.join(__dirname, '..', 'config.js');

fs.writeFileSync(outputPath, config, 'utf8');
console.log('Generated config.js for deployment.');