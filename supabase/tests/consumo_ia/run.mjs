// Prueba de la migración 20261110090000_consumo_ia.sql contra un PostgreSQL
// desechable (embebido). NO toca ninguna base real. Cómo correrla (en esta carpeta):
//   npm i embedded-postgres pg
//   node run.mjs
// Debe terminar con "RESULTADO: N bien, 0 mal".
import EmbeddedPostgres from 'embedded-postgres';
import pg from 'pg';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { fileURLToPath } from 'url';
const AQUI = path.dirname(fileURLToPath(import.meta.url));
const MIGRACION = path.join(AQUI, '../../migrations/20261110090000_consumo_ia.sql');
const DIR = path.join(os.tmpdir(), 'pgtest-consumo-' + process.pid);

fs.rmSync(DIR, { recursive: true, force: true });
const server = new EmbeddedPostgres({ databaseDir: DIR, user: 'postgres', password: 'x', port: 45433, persistent: false, initdbFlags: ['--encoding=UTF8', '--locale=C'] });
await server.initialise();
await server.start();
await server.createDatabase('t');
const c = new pg.Client({ host: 'localhost', port: 45433, user: 'postgres', password: 'x', database: 't' });
await c.connect();

let pass = 0, fail = 0;
const ok = (nombre, cond, extra = '') => {
  if (cond) { pass++; console.log('  PASS', nombre); } else { fail++; console.log('  FAIL', nombre, extra); }
};

await c.query(`
create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
create schema auth;
create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create table usuarios(id bigint generated always as identity primary key, apodo_usuario text, rol text, estado_usuario boolean default true);
create function app_usuario_id() returns bigint language sql stable as $$
  select case when (auth.jwt() ->> 'sub') ~ '^[0-9]+$' then (auth.jwt() ->> 'sub')::bigint end; $$;
create function app_rol() returns text language sql stable security definer set search_path = public as $$
  select u.rol from usuarios u where u.id = app_usuario_id() and u.estado_usuario = true; $$;
create table polizas(id bigint generated always as identity primary key);
create table clientes(id bigint generated always as identity primary key);
grant usage on schema public, auth to authenticated, anon, service_role;
insert into usuarios(apodo_usuario, rol) values ('ADMIN','A'), ('DIGI','D');
`);

// La migración se corre DOS veces: debe ser repetible.
const sql = fs.readFileSync(MIGRACION, 'utf8');
await c.query(sql);
await c.query(sql);
ok('la migración corre dos veces sin error', true);

const claims = (sub) => JSON.stringify({ sub: String(sub), role: 'authenticated' });
const como = async (sub, fn, confirmar = false) => {
  await c.query('begin');
  await c.query('set local role authenticated');
  await c.query(`select set_config('request.jwt.claims', $1, true)`, [claims(sub)]);
  try {
    const r = await fn();
    await c.query(confirmar ? 'commit' : 'rollback');
    return r;
  } catch (e) {
    await c.query('rollback');
    throw e;
  }
};
const falla = async (sub, consulta) => {
  try { await como(sub, () => c.query(consulta)); return ''; } catch (e) { return String(e.message); }
};

// Datos: 2 llamadas de póliza (la segunda es reintento), 1 de reporte, en 2 días UTC.
await c.query(`
insert into consumo_ia (creado, usuario_id, funcion, modelo, tipo_archivo, tokens_entrada, tokens_cache, tokens_pensamiento, tokens_salida, reintento, estado) values
 ('2026-11-05 15:00:00+00', 2, 'extraer-poliza', 'm1', 'pdf', 1000000, 0, 0, 100000, false, 'MAX_TOKENS'),
 ('2026-11-05 15:00:05+00', 2, 'extraer-poliza', 'm1', 'pdf', 1000000, 500000, 200000, 100000, true, 'STOP'),
 ('2026-11-06 04:30:00+00', 2, 'extraer-reporte-pago', 'm1', 'xlsx', 2000000, 0, 0, 0, false, 'STOP');
`);

const resumen = (sub = 1) => como(sub, async () => (await c.query(`select consumo_ia_resumen('2026-11-01','2026-11-30') as j`)).rows[0].j);
const r = await resumen();
ok('el admin recibe filas agrupadas', Array.isArray(r) && r.length === 2, JSON.stringify(r));
const pol = r.filter((x) => x.funcion === 'extraer-poliza');
const lecturas = pol.reduce((s, x) => s + Number(x.lecturas), 0);
const llamadas = pol.reduce((s, x) => s + Number(x.llamadas), 0);
ok('las lecturas no cuentan reintentos', lecturas === 1 && llamadas === 2, `${lecturas}/${llamadas}`);
// Precio de referencia: 0.30 / 0.03 / 2.50 por millón.
// Fila 1: 1M*0.30 + 0.1M*2.50 = 0.55
// Fila 2: 0.5M*0.30 + 0.5M*0.03 + (0.1M+0.2M)*2.50 = 0.15 + 0.015 + 0.75 = 0.915
const costoPol = pol.reduce((s, x) => s + Number(x.costo_usd), 0);
ok('costo estimado de pólizas = 1.465', Math.abs(costoPol - 1.465) < 1e-6, String(costoPol));
const rep = r.find((x) => x.funcion === 'extraer-reporte-pago');
ok('el día se cuenta en hora de Colombia (04:30 UTC del 6 = 5 de nov)', rep.dia === '2026-11-05', rep.dia);
ok('costo del reporte = 0.60', Math.abs(Number(rep.costo_usd) - 0.6) < 1e-6, String(rep.costo_usd));
ok('muestra el apodo del usuario', pol[0].usuario === 'DIGI', pol[0].usuario);

// Un precio propio del modelo tiene prioridad sobre el 'default'.
await como(1, () => c.query(`select consumo_ia_guardar_config(4200, 'm1', 1, 0, 1)`), true);
const r2 = await resumen();
const cfg = await como(1, async () => (await c.query(`select consumo_ia_config() as j`)).rows[0].j);
const rep2 = r2.find((x) => x.funcion === 'extraer-reporte-pago');
ok('el precio propio del modelo tiene prioridad', Math.abs(Number(rep2.costo_usd) - 2.0) < 1e-6, String(rep2.costo_usd));
ok('la TRM y los precios se guardan', Number(cfg.trm) === 4200 && cfg.precios.length === 2, JSON.stringify(cfg));

// Permisos.
const soloAdmin = /Solo un Administrador/;
ok('un digitador NO puede ver el resumen', soloAdmin.test(await falla(2, `select consumo_ia_resumen('2026-11-01','2026-11-30')`)));
ok('un digitador NO puede ver los precios', soloAdmin.test(await falla(2, `select consumo_ia_config()`)));
ok('un digitador NO puede cambiar precios', soloAdmin.test(await falla(2, `select consumo_ia_guardar_config(4000,'x',1,1,1)`)));
ok('un digitador NO puede ver el uso de la base', soloAdmin.test(await falla(2, `select consumo_servicios()`)));
ok('nadie con sesión lee la tabla directo', /permission denied/.test(await falla(1, `select * from consumo_ia`)));
ok('nadie con sesión escribe la tabla directo', /permission denied/.test(await falla(1, `insert into consumo_ia (funcion, modelo, estado) values ('x','y','z')`)));
ok('precios inválidos se rechazan', /positivos/.test(await falla(1, `select consumo_ia_guardar_config(0,'x',1,1,1)`)));

const s = await como(1, async () => (await c.query(`select consumo_servicios() as j`)).rows[0].j);
ok('el uso de la base devuelve el tamaño', Number(s.db_bytes) > 0 && Number(s.storage_bytes) === 0, JSON.stringify(s));

// La service role sí puede insertar (como las Edge Functions).
await c.query('begin');
await c.query('set local role service_role');
await c.query(`insert into consumo_ia (funcion, modelo, estado) values ('extraer-poliza','m1','STOP')`);
await c.query('rollback');
ok('la service role puede registrar consumo', true);

console.log(`\nRESULTADO: ${pass} bien, ${fail} mal`);
await c.end();
await server.stop();
process.exit(fail ? 1 : 0);
