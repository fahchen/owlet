import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const directory = fileURLToPath(new URL('.', import.meta.url));
const space = process.argv[2] === undefined ? null : Number(process.argv[2]);
const input = `const designDirectory = ${JSON.stringify(directory)};\n`
  + `const captureSpace = ${JSON.stringify(space)};\n`
  + readFileSync(new URL('screenshot.js', import.meta.url), 'utf8');
const result = spawnSync('ego-browser', ['nodejs'], { input, stdio: ['pipe', 'inherit', 'inherit'] });
if (result.error) throw result.error;
process.exit(result.status ?? 1);
