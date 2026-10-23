/** Syntax-checks every JS file (no extra lint dependency needed). */
import { readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';

const roots = ['src', 'scripts', 'tests'];
const files = [];
const walk = (dir) => {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p);
    else if (p.endsWith('.js')) files.push(p);
  }
};
roots.forEach(walk);
for (const f of files) execFileSync(process.execPath, ['--check', f]);
console.log(`Syntax OK: ${files.length} files`);
