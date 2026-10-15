// Prueba de la migración 20261015090000_eliminacion_polizas.sql contra un
// PostgreSQL desechable (embebido), con un esquema de ejemplo y los roles de
// Supabase. NO toca ninguna base real. Cómo correrla (en esta carpeta):
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
const MIGRACION = path.join(AQUI, '../../migrations/20261015090000_eliminacion_polizas.sql');
const DIR = path.join(os.tmpdir(), 'pgtest-eliminacion-' + process.pid);

fs.rmSync(DIR, { recursive: true, force: true });
const server = new EmbeddedPostgres({ databaseDir: DIR, user: 'postgres', password: 'x', port: 45432, persistent: false, initdbFlags: ['--encoding=UTF8', '--locale=C'] });
await server.initialise();
await server.start();
await server.createDatabase('t');
const c = new pg.Client({ host: 'localhost', port: 45432, user: 'postgres', password: 'x', database: 't' });
await c.connect();

let pass = 0, fail = 0;
const ok = (nombre, cond, extra = '') => {
  if (cond) { pass++; console.log('  PASS', nombre); }
  else { fail++; console.log('  FAIL', nombre, extra); }
};

// ── Esquema de ejemplo (réplica mínima de producción) ─────────────────────
await c.query(`
create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
create schema auth;
create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create extension if not exists pgcrypto;

create table usuarios(id bigint generated always as identity primary key, apodo_usuario text, rol text, estado_usuario boolean default true);
create function app_usuario_id() returns bigint language sql stable as $$
  select case when (auth.jwt() ->> 'sub') ~ '^[0-9]+$' then (auth.jwt() ->> 'sub')::bigint end; $$;
create function app_rol() returns text language sql stable security definer set search_path = public as $$
  select u.rol from usuarios u where u.id = app_usuario_id() and u.estado_usuario = true; $$;

create table clientes(id bigint generated always as identity primary key, nombre_cliente text);
create table aseguradoras(id bigint generated always as identity primary key, nombre_aseg text);
create table ramos(id bigint generated always as identity primary key, nombre_ramo text);
create table polizas(
  id bigint generated always as identity primary key, nro_poliza text, cliente_id bigint references clientes(id),
  aseg_id bigint, ramo_id bigint, prima_poliza numeric default 0, fini_poliza timestamptz, ffin_poliza timestamptz,
  estado_poliza_id text, fultmod timestamptz default now());
create table abonos_poliza(id bigint generated always as identity primary key,
  id_poliza bigint references polizas(id), vlrabono_prima numeric default 0, estado_pago text default 'I');
create function polizas_stub() returns trigger language plpgsql as $$ begin new.fultmod := now(); return new; end $$;
create trigger trg_stub before update on polizas for each row execute function polizas_stub();

alter table polizas enable row level security;
create policy app_authenticated_full_access on polizas for all to authenticated
  using ((select app_rol()) is not null) with check ((select app_rol()) is not null);

create view vw_polizas_busqueda with (security_invoker = true) as
  select p.*, c.nombre_cliente from polizas p left join clientes c on c.id = p.cliente_id;

grant usage on schema public, auth to authenticated, anon, service_role;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into usuarios(apodo_usuario, rol, estado_usuario) values
  ('ADMIN','A',true), ('DIGI','D',true), ('SUPER','S',true), ('INACTIVO','A',false), ('ADMIN2','A',true);
insert into clientes(nombre_cliente) values ('Cliente Uno'), ('Cliente Dos');
insert into aseguradoras(nombre_aseg) values ('Sura'); insert into ramos(nombre_ramo) values ('Cumplimiento');
insert into polizas(nro_poliza, cliente_id, aseg_id, ramo_id, prima_poliza)
  select 'P-'||g, 1, 1, 1, 1000*g from generate_series(1,8) g;
-- póliza 3: pago vigente; póliza 4: solo un pago anulado
insert into abonos_poliza(id_poliza, vlrabono_prima, estado_pago) values (3, 500, 'I'), (4, 300, 'A');
`);

// Migración real
await c.query(fs.readFileSync(MIGRACION, 'utf8'));
console.log('Migración aplicada sobre el esquema de ejemplo.\n');

// ── Ayudante: ejecutar como un usuario de la app (rol authenticated + token) ─
async function como(uid, fn) {
  await c.query('begin');
  try {
    await c.query('set local role authenticated');
    await c.query(`select set_config('request.jwt.claims', $1, true)`, [uid == null ? '' : JSON.stringify({ sub: String(uid), role: 'authenticated' })]);
    return await fn((sql, p) => c.query(sql, p));
  } finally {
    await c.query('rollback');
  }
}
async function comoCommit(uid, fn) {
  await c.query('begin');
  try {
    await c.query('set local role authenticated');
    await c.query(`select set_config('request.jwt.claims', $1, true)`, [uid == null ? '' : JSON.stringify({ sub: String(uid), role: 'authenticated' })]);
    const r = await fn((sql, p) => c.query(sql, p));
    await c.query('commit');
    return r;
  } catch (e) { await c.query('rollback'); throw e; }
}
const falla = async (fn) => { await c.query('savepoint sp'); try { await fn(); await c.query('release sp'); return null; } catch (e) { await c.query('rollback to sp'); return e; } };
const ADMIN = 1, DIGI = 2, SUPER = 3, INACTIVO = 4, ADMIN2 = 5;

console.log('1) Digitador marca pólizas (1, 2 libres; 3 con pago; 4 pago anulado; 99 no existe)');
let sol;
await comoCommit(DIGI, async (q) => {
  const r = await q(`select polizas_eliminacion_solicitar($1::bigint[], $2) as r`, [[1, 2, 3, 99], 'Duplicada de la póliza cód. 7']);
  sol = r.rows[0].r;
});
ok('solicita 2 (1 y 2)', sol.solicitadas === 2, JSON.stringify(sol));
ok('omite la 3 por pagos y la 99 inexistente', sol.omitidas.length === 2 && sol.omitidas.some(o => o.id === 3 && /pagos/.test(o.razon)) && sol.omitidas.some(o => o.id === 99));

console.log('2) Las marcadas desaparecen para todos (tabla, vista, filtros)');
for (const [nombre, uid] of [['digitador', DIGI], ['admin', ADMIN], ['rol S', SUPER]]) {
  await como(uid, async (q) => {
    const t = await q('select count(*)::int n from polizas');
    const v = await q('select count(*)::int n from vw_polizas_busqueda');
    const u = await q('select count(*)::int n from polizas where id in (1,2)');
    ok(`${nombre} ve 6 de 8 pólizas (tabla y vista), ninguna marcada`, t.rows[0].n === 6 && v.rows[0].n === 6 && u.rows[0].n === 0, `${t.rows[0].n}/${v.rows[0].n}/${u.rows[0].n}`);
  });
}
await como(DIGI, async (q) => {
  const s = await q('select count(*)::int n, coalesce(sum(prima_poliza),0)::int total from polizas');
  ok('las estadísticas (suma de prima) excluyen las marcadas: 3+4+5+6+7+8 = 33000', s.rows[0].total === 33000, JSON.stringify(s.rows[0]));
});

console.log('2b) El trabajo normal sigue funcionando (editar, crear, borrar póliza no marcada)');
await como(DIGI, async (q) => {
  const u = await q(`update polizas set prima_poliza = 9999 where id = 5`);
  ok('editar una póliza normal funciona', u.rowCount === 1);
  const i = await q(`insert into polizas(nro_poliza, prima_poliza) values ('NUEVA', 10) returning id`);
  ok('crear una póliza funciona', i.rowCount === 1);
  const r = await q(`select count(*)::int n from polizas where nro_poliza = 'NUEVA'`);
  ok('la nueva se ve', r.rows[0].n === 1);
});
for (const [nombre, uid] of [['administrador', ADMIN], ['digitador', DIGI], ['rol S', SUPER]]) {
  await como(uid, async (q) => {
    const e = await falla(() => q(`delete from polizas where id = 8`));
    ok(`${nombre} NO puede borrar una póliza directo por la API (sin autorización)`, e && /permission denied/i.test(e.message), e && e.message);
  });
}
await como(DIGI, async (q) => {
  const e = await falla(() => q(`delete from polizas where id > 0`));
  ok('borrado masivo por la API también negado', e && /permission denied/i.test(e.message), e && e.message);
});
const todas = await c.query('select count(*)::int n from polizas');
ok('ninguna póliza se borró por esos intentos', todas.rows[0].n >= 8);

console.log('3) No se puede tocar la marca ni las marcadas directamente por la API');
await como(DIGI, async (q) => {
  const u = await q(`update polizas set nro_poliza = 'HACK' where id = 1`);
  ok('update sobre una marcada afecta 0 filas', u.rowCount === 0);
  const d = await falla(() => q(`delete from polizas where id = 1`));
  ok('delete sobre una marcada es negado', d && /permission denied/i.test(d.message), d && d.message);
  const un = await q(`update polizas set eliminada_en = null where id = 1`);
  ok('"desmarcar" por la API afecta 0 filas', un.rowCount === 0);
});
await como(DIGI, async (q) => {
  const e = await falla(() => q(`update polizas set eliminada_en = now() where id = 5`));
  ok('marcar directo por la API da error', e && /solo se cambia desde la función/i.test(e.message), e && e.message);
});
await como(DIGI, async (q) => {
  const e = await falla(() => q(`insert into polizas(nro_poliza, eliminada_en) values ('X', now())`));
  ok('insertar ya marcada da error', e && /solo se cambia desde la función/i.test(e.message), e && e.message);
});
await como(DIGI, async (q) => {
  const e = await falla(() => q(`select set_config('app.eliminacion','1',true)`).then(() => q(`update polizas set eliminada_en = now() where id = 5`)));
  // OJO: un usuario podría intentar activar la variable él mismo: se documenta el resultado.
  console.log('  (info) activar app.eliminacion a mano desde SQL directo:', e ? 'bloqueado: '+e.message : 'PERMITIDO');
});

console.log('4) Funciones de administrador negadas a otros roles');
for (const [nombre, uid] of [['digitador', DIGI], ['rol S', SUPER]]) {
  await como(uid, async (q) => {
    for (const [fn, sql] of [
      ['pendientes', 'select polizas_eliminacion_pendientes()'],
      ['historial', 'select polizas_eliminacion_historial(10)'],
      ['resolver', `select polizas_eliminacion_resolver(array[1]::bigint[], 'aprobar', null)`],
    ]) {
      const e = await falla(() => q(sql));
      ok(`${nombre}: ${fn} negado`, e && /Solo un Administrador/.test(e.message), e && e.message);
    }
    const n = await q('select polizas_eliminacion_contar() n');
    ok(`${nombre}: contador devuelve 0`, n.rows[0].n === 0);
  });
}

console.log('5) Validaciones de la solicitud');
await como(DIGI, async (q) => {
  let e = await falla(() => q(`select polizas_eliminacion_solicitar(array[5]::bigint[], 'ab')`));
  ok('motivo corto rechazado', e && /motivo/.test(e.message), e && e.message);
  e = await falla(() => q(`select polizas_eliminacion_solicitar(array[]::bigint[], 'motivo largo')`));
  ok('sin pólizas rechazado', e && /No hay pólizas/.test(e.message), e && e.message);
  e = await falla(() => q(`select polizas_eliminacion_solicitar((select array_agg(g)::bigint[] from generate_series(1,201) g), 'motivo largo')`));
  ok('más de 200 rechazado', e && /200/.test(e.message), e && e.message);
  for (const [nombre, motivo] of [['solo saltos de línea', '\n\n\n\n\n\n'], ['solo espacios no separables', '\u00a0\u00a0\u00a0\u00a0\u00a0\u00a0'], ['solo tabs', '\t\t\t\t\t\t']]) {
    const x = await falla(() => q(`select polizas_eliminacion_solicitar(array[5]::bigint[], $1)`, [motivo]));
    ok(`motivo ${nombre} rechazado`, x && /motivo/i.test(x.message), x && x.message);
  }
  e = await falla(() => q(`select polizas_eliminacion_solicitar(array[5]::bigint[], $1)`, ['x'.repeat(501)]));
  ok('motivo de más de 500 caracteres rechazado', e && /demasiado largo/.test(e.message), e && e.message);
  e = await falla(() => q(`select polizas_eliminacion_solicitar(null::bigint[], 'motivo valido')`));
  ok('lista de ids NULL rechazada', e && /No hay pólizas/.test(e.message), e && e.message);
  const r = await q(`select polizas_eliminacion_solicitar(array[1,2]::bigint[], 'otra vez') r`);
  ok('volver a marcar las ya marcadas: 0 solicitadas, 2 omitidas', r.rows[0].r.solicitadas === 0 && r.rows[0].r.omitidas.length === 2);
});
{
  let e = await como(null, (q) => falla(() => q(`select polizas_eliminacion_solicitar(array[5]::bigint[], 'sin sesión')`)));
  ok('sin sesión rechazado', e && /No tiene permiso/.test(e.message), e && e.message);
  e = await como(INACTIVO, (q) => falla(() => q(`select polizas_eliminacion_solicitar(array[5]::bigint[], 'usuario inactivo')`)));
  ok('usuario desactivado rechazado', e && /No tiene permiso/.test(e.message), e && e.message);
}

console.log('6) El administrador ve la bandeja y resuelve');
let pend;
await como(ADMIN, async (q) => {
  pend = (await q('select polizas_eliminacion_pendientes() r')).rows[0].r;
  const n = await q('select polizas_eliminacion_contar() n');
  ok('contador = 2', n.rows[0].n === 2);
});
ok('bandeja trae 2 con motivo, solicitante, cliente y n_pagos', pend.length === 2 && pend.every(x => x.motivo && x.solicitado_por === 'DIGI' && x.cliente === 'Cliente Uno' && x.n_pagos === 0), JSON.stringify(pend));
const sol1 = pend.find(x => x.poliza_id === 1).id;
const sol2 = pend.find(x => x.poliza_id === 2).id;

// póliza 4 (solo un pago anulado): ahora tampoco se marca, igual que al autorizar
await comoCommit(DIGI, async (q) => {
  const r = await q(`select polizas_eliminacion_solicitar(array[4]::bigint[], 'prueba con pago anulado') r`);
  ok('póliza con SOLO pago anulado ya no se puede marcar (mismo criterio que al autorizar)',
     r.rows[0].r.solicitadas === 0 && /pagos/.test(r.rows[0].r.omitidas[0].razon), JSON.stringify(r.rows[0].r));
});
// Póliza 9: se marca limpia y luego se le fuerza un pago por fuera (como un dato antiguo)
const ID9 = Number((await c.query(`insert into polizas(nro_poliza, prima_poliza) values ('P-9', 900) returning id`)).rows[0].id);
await comoCommit(DIGI, (q) => q(`select polizas_eliminacion_solicitar(array[${ID9}]::bigint[], 'prueba con pago tardío')`));
{
  let e = null;
  try { await c.query(`insert into abonos_poliza(id_poliza, vlrabono_prima) values (${ID9}, 10)`); } catch (err) { e = err; }
  ok('registrar un pago en una póliza marcada es rechazado por la base', e && /marcada para eliminar/.test(e.message), e && e.message);
  await c.query('alter table abonos_poliza disable trigger trg_abonos_no_en_poliza_marcada');
  await c.query(`insert into abonos_poliza(id_poliza, vlrabono_prima) values (${ID9}, 10)`);
  await c.query('alter table abonos_poliza enable trigger trg_abonos_no_en_poliza_marcada');
}
await comoCommit(ADMIN, async (q) => {
  const p9 = (await q('select polizas_eliminacion_pendientes() r')).rows[0].r.find(x => x.poliza_id === ID9);
  const r = (await q(`select polizas_eliminacion_resolver($1::bigint[], 'aprobar', 'x') r`, [[p9.id]])).rows[0].r;
  ok('aprobar póliza con pagos se bloquea y sigue pendiente', r.resueltas === 0 && r.omitidas.length === 1 && /pagos/.test(r.omitidas[0].razon), JSON.stringify(r));
  const r2 = (await q(`select polizas_eliminacion_resolver($1::bigint[], 'rechazar', 'se movieron los pagos después') r`, [[p9.id]])).rows[0].r;
  ok('la salida es rechazar (restaura la póliza)', r2.resueltas === 1);
});

await comoCommit(ADMIN, async (q) => {
  const r1 = (await q(`select polizas_eliminacion_resolver($1::bigint[], 'aprobar', 'Confirmada duplicada') r`, [[sol1]])).rows[0].r;
  ok('aprobar la póliza 1: resueltas = 1', r1.resueltas === 1, JSON.stringify(r1));
  const r2 = (await q(`select polizas_eliminacion_resolver($1::bigint[], 'rechazar', 'No era duplicada') r`, [[sol2]])).rows[0].r;
  ok('rechazar la póliza 2: resueltas = 1', r2.resueltas === 1, JSON.stringify(r2));
  const r3 = (await q(`select polizas_eliminacion_resolver($1::bigint[], 'aprobar', null) r`, [[sol1]])).rows[0].r;
  ok('resolver dos veces la misma solicitud: se omite', r3.resueltas === 0 && r3.omitidas.length === 1);
  const e = await falla(() => q(`select polizas_eliminacion_resolver($1::bigint[], 'borrar_todo', null)`, [[sol1]]));
  ok('acción inválida rechazada', e && /Acción no válida/.test(e.message));
  const e2 = await falla(() => q(`select polizas_eliminacion_resolver($1::bigint[], null, null)`, [[sol1]]));
  ok('acción NULL rechazada (antes aprobaba y borraba)', e2 && /Acción no válida/.test(e2.message), e2 && e2.message);
});

const chk = await c.query(`select (select count(*)::int from polizas where id = 1) existe1,
  (select count(*)::int from polizas where id = 2 and eliminada_en is null) vuelve2,
  (select snapshot ->> 'nro_poliza' from polizas_eliminacion where id = ${sol1}) snap,
  (select estado from polizas_eliminacion where id = ${sol1}) est1,
  (select estado from polizas_eliminacion where id = ${sol2}) est2,
  (select resuelto_por from polizas_eliminacion where id = ${sol1}) por`);
const k = chk.rows[0];
ok('póliza 1 borrada de verdad', k.existe1 === 0);
ok('póliza 2 restaurada', k.vuelve2 === 1);
ok('copia (snapshot) de la 1 guardada', k.snap === 'P-1', k.snap);
ok('estados aprobada / rechazada y quién resolvió', k.est1 === 'aprobada' && k.est2 === 'rechazada' && Number(k.por) === ADMIN, JSON.stringify(k));
await como(DIGI, async (q) => {
  const n = await q('select count(*)::int n from polizas where id = 2');
  ok('el digitador vuelve a ver la póliza rechazada', n.rows[0].n === 1);
});
await como(ADMIN, async (q) => {
  const h = (await q('select polizas_eliminacion_historial(50) r')).rows[0].r;
  ok('historial trae las resueltas (aprobada con su número de póliza)', h.length >= 2 && h.some(x => x.estado === 'aprobada' && x.nro_poliza === 'P-1') && h.some(x => x.estado === 'rechazada'), JSON.stringify(h));
});

console.log('7) Dos administradores / concurrencia de la misma solicitud');
{
  await comoCommit(DIGI, (q) => q(`select polizas_eliminacion_solicitar(array[7,8]::bigint[], 'prueba concurrencia') `));
  const ids = (await c.query(`select id from polizas_eliminacion where estado='pendiente' and poliza_id in (7,8)`)).rows.map(r => r.id);
  const c2 = new pg.Client({ host: 'localhost', port: 45432, user: 'postgres', password: 'x', database: 't' });
  await c2.connect();
  const run = async (cli, uid) => {
    await cli.query('begin'); await cli.query('set local role authenticated');
    await cli.query(`select set_config('request.jwt.claims', $1, true)`, [JSON.stringify({ sub: String(uid), role: 'authenticated' })]);
    const r = (await cli.query(`select polizas_eliminacion_resolver($1::bigint[], 'aprobar', 'x') r`, [ids])).rows[0].r;
    await cli.query('commit'); return r;
  };
  const [a, b] = await Promise.all([run(c, ADMIN), run(c2, ADMIN2)]);
  ok('aprobadas una sola vez entre los dos administradores (2 en total)', a.resueltas + b.resueltas === 2, JSON.stringify([a, b]));
  const n = await c.query(`select count(*)::int n from polizas where id in (7,8)`);
  ok('pólizas 7 y 8 borradas', n.rows[0].n === 0);
  await c2.end();
}

console.log('8) Tope de 500 pendientes por usuario y guarda de políticas');
{
  await c.query(`insert into polizas(nro_poliza, prima_poliza) select 'T-'||g, 1 from generate_series(1,520) g`);
  const ids = (await c.query(`select id from polizas where nro_poliza like 'T-%' order by id`)).rows.map(r => r.id);
  for (let i = 0; i < 500; i += 200) {
    await comoCommit(SUPER, (q) => q(`select polizas_eliminacion_solicitar($1::bigint[], 'carga de prueba')`, [ids.slice(i, Math.min(i + 200, 500))]));
  }
  const e = await como(SUPER, (q) => falla(() => q(`select polizas_eliminacion_solicitar($1::bigint[], 'una más')`, [ids.slice(500, 501)])));
  ok('la póliza 501 pendiente del mismo usuario se rechaza', e && /pendientes de autorización/.test(e.message), e && e.message);
  const otro = await comoCommit(DIGI, (q) => q(`select polizas_eliminacion_solicitar($1::bigint[], 'otro usuario') r`, [ids.slice(500, 502)]));
  ok('otro usuario no queda afectado por el tope', otro.rows[0].r.solicitadas === 2);
}
{
  const p = await c.query(`select count(*)::int n, count(*) filter (where cmd = 'DELETE')::int d from pg_policies where tablename = 'polizas'`);
  ok('polizas queda con 3 políticas y ninguna de borrado', p.rows[0].n === 3 && p.rows[0].d === 0, JSON.stringify(p.rows[0]));
  // Si alguien deja una política permisiva extra, la migración completa se aborta (nada se aplica)
  await c.query(`create policy extra_permisiva on polizas for select to authenticated using (true)`);
  const mig = fs.readFileSync(MIGRACION, 'utf8');
  let e = null;
  try { await c.query(mig); } catch (err) { e = err; }
  await c.query('rollback').catch(() => {});
  await c.query(`drop policy extra_permisiva on polizas`);
  ok('con una política extra la migración se aborta y lo explica', e && /políticas adicionales/.test(e.message), e && e.message);
  await c.query(mig); // vuelve a correr limpia: idempotente
  ok('la migración es idempotente (se puede volver a correr)', true);
}
{
  const g = await c.query(`select has_table_privilege('authenticated','polizas_eliminacion','select') s, has_table_privilege('authenticated','polizas','delete') d`);
  ok('authenticated no tiene permisos de tabla sobre polizas_eliminacion ni DELETE en polizas', g.rows[0].s === false && g.rows[0].d === false, JSON.stringify(g.rows[0]));
}

console.log(`\nRESULTADO: ${pass} bien, ${fail} mal`);
await c.end();
await server.stop();
process.exit(fail ? 1 : 0);
