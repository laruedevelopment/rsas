// Prueba de supabase/functions/_shared/json_parcial.ts. Se compila con esbuild y se ejecuta en node:
//   node json_parcial.test.mjs
import { execFileSync } from 'child_process';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { fileURLToPath, pathToFileURL } from 'url';

const aqui = path.dirname(fileURLToPath(import.meta.url));
const fuente = path.join(aqui, '../../functions/_shared/json_parcial.ts');
const salida = path.join(os.tmpdir(), 'json_parcial_' + process.pid + '.mjs');
execFileSync('npx', ['-y', 'esbuild', fuente, '--format=esm', `--outfile=${salida}`, '--log-level=error'], { stdio: 'inherit', shell: true });
const { rescatarJsonTruncado } = await import(pathToFileURL(salida).href);

let mal = 0;
const ok = (n, c, x = '') => { console.log(c ? '  PASS' : '  FAIL', n, c ? '' : x); if (!c) mal++; };

ok('JSON completo se devuelve igual', rescatarJsonTruncado('{"a":1,"b":"x"}')?.b === 'x');
const cortado = '{"nro_poliza":"B-100","nombre_cliente":"ACME, S.A.","prima":1268456,"bien_asegurado":"CONTRATO No. 7500000750 CUYO OBJETO ES ' + 'texto repetido '.repeat(50);
const r = rescatarJsonTruncado(cortado);
ok('rescata los campos terminados cuando se corta el último', r && r.nro_poliza === 'B-100' && r.prima === 1268456 && r.nombre_cliente === 'ACME, S.A.' && !('bien_asegurado' in r), JSON.stringify(r));
ok('una coma dentro de un texto no engaña', rescatarJsonTruncado('{"a":"uno, dos, tres","b":2,"c":"cort')?.a === 'uno, dos, tres');
ok('comillas escapadas dentro del texto', rescatarJsonTruncado('{"a":"di \\"hola\\", y","b":2,"c":"cor')?.b === 2);
ok('sin nada rescatable devuelve null', rescatarJsonTruncado('{"a":"corta') === null);
ok('texto que no es JSON devuelve null', rescatarJsonTruncado('hola') === null && rescatarJsonTruncado('') === null);
console.log(mal ? `\n${mal} FALLAS` : '\nTodo bien');
fs.rmSync(salida, { force: true });
process.exit(mal ? 1 : 0);
