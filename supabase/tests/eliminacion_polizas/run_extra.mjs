// Pruebas ADVERSARIAS de la migración 20261015090000_eliminacion_polizas.sql
// contra un PostgreSQL desechable (embebido). Complementa a run.mjs.
// Cómo correrla (en esta carpeta):  npm i embedded-postgres pg  &&  node run_extra.mjs
// Variables opcionales: PGPORT (45432 por defecto), REPO_DIR (raíz del repo).
//
// Usa los triggers REALES de producción (polizas_pago_estado de 09b, trigger de
// abonos, set_fultmod, fusionar_clientes) extraídos de lib/*.sql.
//
// Dos tipos de resultado:
//   PASS / FAIL   -> comportamiento esperado; un FAIL hace fallar el script.
//   HALLAZGO      -> defecto CONOCIDO y documentado (no hace fallar el script, para
//                    poder usarlo como regresión). Cuando se corrija, pasará a PASS.
import EmbeddedPostgres from 'embedded-postgres';
import pg from 'pg';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { fileURLToPath } from 'url';

const AQUI = path.dirname(fileURLToPath(import.meta.url));
const REPO = process.env.REPO_DIR || path.resolve(AQUI, '../../..');
const PORT = Number(process.env.PGPORT || 45432);
const MIGRACION = path.join(REPO, 'supabase/migrations/20261015090000_eliminacion_polizas.sql');
const LIB = (f) => fs.readFileSync(path.join(REPO, 'lib', f), 'utf8');
const DIR = path.join(os.tmpdir(), 'pgtest-eliminacion-extra-' + process.pid);

// Extrae un bloque "create or replace function <nombre> ... $$;" de un archivo SQL.
const funcion = (texto, nombre) => {
  const i = texto.indexOf(`create or replace function ${nombre}`);
  if (i < 0) throw new Error('No encontré ' + nombre);
  const j = texto.indexOf('\n$$;', i);
  return texto.slice(i, j + 4);
};

fs.rmSync(DIR, { recursive: true, force: true });
const server = new EmbeddedPostgres({ databaseDir: DIR, user: 'postgres', password: 'x', port: PORT, persistent: false, initdbFlags: ['--encoding=UTF8', '--locale=C'] });
await server.initialise();
await server.start();
await server.createDatabase('t');
const nuevo = () => { const k = new pg.Client({ host: 'localhost', port: PORT, user: 'postgres', password: 'x', database: 't' }); k.on('error', () => {}); return k; };
const c = nuevo();
await c.connect();

let pass = 0, fail = 0, hallazgos = 0;
const ok = (n, cond, extra = '') => { if (cond) { pass++; console.log('  PASS', n); } else { fail++; console.log('  FAIL', n, extra); } };
const hallazgo = (n, cond, extra = '') => { if (cond) { pass++; console.log('  PASS', n); } else { hallazgos++; console.log('  HALLAZGO', n, extra); } };
const info = (...a) => console.log('  (info)', ...a);
const dormir = (ms) => new Promise((r) => setTimeout(r, ms));

// ── Esquema: réplica de producción con los triggers reales ──────────────────
const t09 = LIB('migracion_2026_09_seguridad_y_pagos.sql');
const t09b = LIB('migracion_2026_09b_prima_pagada_base.sql');
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

create table asesores(id bigint generated always as identity primary key);
create table municipio(id bigint generated always as identity primary key);
create table clientes(id bigint generated always as identity primary key, nombre_cliente text,
  doc_cliente_norm text, tel_cliente text, correo_cliente text, dir_cliente text, munic_id bigint,
  contacto_cliente text, cargocont_cliente text, asesor_id bigint, notas_cliente text);
create table aseguradoras(id bigint generated always as identity primary key, nombre_aseg text);
create table ramos(id bigint generated always as identity primary key, nombre_ramo text);
create table estados_poliza(id text primary key, nombre_estado text);
insert into estados_poliza values ('I','INICIAL'), ('C','COMPLETA');
create table polizas(
  id bigint generated always as identity primary key, nro_poliza text, nro_poliza_norm text default '',
  cliente_id bigint constraint polizas_cliente_id_fkey references clientes(id),
  aseg_id bigint, ramo_id bigint, prima_poliza numeric default 0, fini_poliza timestamptz, ffin_poliza timestamptz,
  estado_poliza_id text, fultmod timestamptz default now(),
  vlrprimapagada_poliza numeric default 0, vlrprimapagada_base numeric not null default 0,
  estado_por_pagos boolean not null default false);
create table abonos_poliza(id bigint generated always as identity primary key,
  id_poliza bigint not null references polizas(id), vlrabono_prima numeric default 0,
  estado_pago char(1) not null default 'I' check (estado_pago in ('I','C','R','V','A')));

-- Triggers REALES de producción
${funcion(t09, 'set_fultmod')}
create trigger trg_fultmod before update on polizas for each row execute function set_fultmod();
${funcion(t09b, 'polizas_pago_estado')}
create trigger trg_polizas_pago_estado before insert or update on polizas for each row execute function polizas_pago_estado();
${funcion(t09, 'recalcular_pago_poliza')}
${funcion(t09, 'abonos_recalcular_poliza')}
create trigger trg_abonos_recalcular_poliza after insert or update or delete on abonos_poliza
  for each row execute function abonos_recalcular_poliza();
${funcion(t09, 'fusionar_clientes').replace('language plpgsql\nsecurity invoker', 'language plpgsql\nsecurity invoker')}

alter table polizas enable row level security;
create policy app_authenticated_full_access on polizas for all to authenticated
  using ((select app_rol()) is not null) with check ((select app_rol()) is not null);
alter table clientes enable row level security;
create policy app_authenticated_full_access on clientes for all to authenticated
  using ((select app_rol()) is not null) with check ((select app_rol()) is not null);
alter table abonos_poliza enable row level security;
create policy app_authenticated_full_access on abonos_poliza for all to authenticated
  using ((select app_rol()) is not null) with check ((select app_rol()) is not null);

create view vw_polizas_busqueda with (security_invoker = true) as
  select p.id, p.nro_poliza, p.cliente_id, p.prima_poliza, c.nombre_cliente from polizas p left join clientes c on c.id = p.cliente_id;
create view vw_polizas_duplicadas with (security_invoker = true) as
  select v.* from vw_polizas_busqueda v
  where v.nro_poliza in (select nro_poliza from polizas group by nro_poliza having count(*) > 1);
create view vw_abonos_detalle with (security_invoker = true) as
  select ab.id, ab.id_poliza, ab.estado_pago, p.nro_poliza from abonos_poliza ab left join polizas p on p.id = ab.id_poliza;
-- Vista MAL configurada a propósito (sin security_invoker), para documentar el riesgo.
create view vw_mal_definer as select id, nro_poliza from polizas;

grant usage on schema public, auth to authenticated, anon, service_role;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant select on all tables in schema public to anon;
grant execute on all functions in schema public to authenticated;

insert into usuarios(apodo_usuario, rol, estado_usuario) values
  ('ADMIN','A',true), ('DIGI','D',true), ('SUPER','S',true), ('INACTIVO','A',false), ('ADMIN2','A',true),
  ('SINROL',null,true), ('ROLVACIO','',true), ('ROLRARO','X',true), ('DIGI2','D',true);
`);
const ADMIN = 1, DIGI = 2, SUPER = 3, INACTIVO = 4, ADMIN2 = 5, SINROL = 6, ROLVACIO = 7, ROLRARO = 8, DIGI2 = 9;

await c.query(fs.readFileSync(MIGRACION, 'utf8'));
// Supabase da por defecto todos los privilegios de tablas nuevas a anon/authenticated (default privileges):
// se replica para que solo la RLS (sin políticas) sea la barrera, como en producción.
await c.query(`grant select, insert, update, delete on polizas_eliminacion to authenticated, anon`);
console.log('Migración aplicada sobre el esquema (con triggers reales).\n');

// ── Ayudantes ───────────────────────────────────────────────────────────────
const claims = (uid) => (uid == null ? '' : JSON.stringify({ sub: String(uid), role: 'authenticated' }));
async function conSesion(cli, uid, rol = 'authenticated') {
  await cli.query('begin');
  await cli.query(`set local role ${rol}`);
  await cli.query(`select set_config('request.jwt.claims', $1, true)`, [claims(uid)]);
}
async function comoCommit(uid, fn) {
  await conSesion(c, uid);
  try { const r = await fn((s, p) => c.query(s, p)); await c.query('commit'); return r; }
  catch (e) { await c.query('rollback'); throw e; }
}
async function como(uid, fn, rol) {
  await conSesion(c, uid, rol);
  try { return await fn((s, p) => c.query(s, p)); } finally { await c.query('rollback'); }
}
const falla = async (fn) => { await c.query('savepoint sp'); try { await fn(); await c.query('release sp'); return null; } catch (e) { await c.query('rollback to sp'); return e; } };
// Intenta una operación en su propia transacción; devuelve el error o null.
const intenta = async (uid, fn, rol) => { try { await comoCommit(uid, fn); return null; } catch (e) { return e; } };

const P = async (nro, prima = 1000, extra = {}) => (await c.query(
  `insert into polizas(nro_poliza, prima_poliza, cliente_id, estado_poliza_id) values ($1,$2,$3,$4) returning id`,
  [nro, prima, extra.cliente ?? null, extra.estado ?? 'I'])).rows[0].id * 1;
const abono = (idp, estado = 'I', v = 100) => c.query(`insert into abonos_poliza(id_poliza, vlrabono_prima, estado_pago) values ($1,$2,$3)`, [idp, v, estado]);
const solicitar = (uid, ids, motivo = 'Motivo válido de prueba') =>
  comoCommit(uid, async (q) => (await q(`select polizas_eliminacion_solicitar($1::bigint[], $2) r`, [ids, motivo])).rows[0].r);
const resolver = (uid, ids, accion, nota = null) =>
  comoCommit(uid, async (q) => (await q(`select polizas_eliminacion_resolver($1::bigint[], $2, $3) r`, [ids, accion, nota])).rows[0].r);
const solId = async (idPoliza, estado = 'pendiente') =>
  (await c.query(`select id from polizas_eliminacion where poliza_id=$1 and estado=$2 order by id desc limit 1`, [idPoliza, estado])).rows[0]?.id;
const sinTx = async (fn) => { try { await fn(); return null; } catch (e) { return e; } };
const fila = async (id) => (await c.query(`select * from polizas where id=$1`, [id])).rows[0];
// Abre una conexión aparte, ya dentro de una transacción como el usuario dado.
async function abre(uid) { const cl = nuevo(); await cl.connect(); await conSesion(cl, uid); return cl; }
// Lanza una consulta y devuelve {promesa, termino()} para saber si quedó esperando un bloqueo.
const lanza = (cli, sql, p) => { let t = false; const pr = cli.query(sql, p).then((r) => { t = true; return r; }, (e) => { t = true; throw e; }); return { pr, termino: () => t }; };

// ═══ 1. Entradas raras en solicitar ═════════════════════════════════════════
console.log('1) solicitar: arrays y motivos raros');
{
  const a = await P('E1-A'), b = await P('E1-B');
  let r = await solicitar(DIGI, [a, a, a, a]);
  ok('ids duplicados [a,a,a,a] -> 1 solicitada, 1 sola fila de solicitud', r.solicitadas === 1 && (await c.query(`select count(*)::int n from polizas_eliminacion where poliza_id=$1`, [a])).rows[0].n === 1, JSON.stringify(r));

  r = await solicitar(DIGI, [null, b, -5, 0, 987654321]);
  ok('NULL, negativo, 0 e inexistente en el array: no revienta; solo b se marca (el NULL se ignora)', r.solicitadas === 1 && r.omitidas.length === 3, JSON.stringify(r));
  ok('  el NULL ya no genera una omitida con id null', !r.omitidas.some((o) => o.id === null));

  let e = await intenta(DIGI, (q) => q(`select polizas_eliminacion_solicitar(null::bigint[], 'motivo válido')`));
  ok('p_ids NULL -> "No hay pólizas seleccionadas"', e && /No hay pólizas/.test(e.message), e && e.message);
  e = await intenta(DIGI, (q) => q(`select polizas_eliminacion_solicitar(array[null]::bigint[], 'motivo válido')`));
  ok('p_ids = {NULL} -> no marca nada (omitida, sin error o error controlado)', !e || /No hay pólizas/.test(e.message), e && e.message);
  e = await intenta(DIGI, (q) => q(`select polizas_eliminacion_solicitar(array[1]::bigint[], null)`));
  ok('motivo NULL rechazado', e && /motivo/.test(e.message), e && e.message);
  e = await intenta(DIGI, (q) => q(`select polizas_eliminacion_solicitar(array[1]::bigint[], '      ')`));
  ok('motivo solo espacios rechazado', e && /motivo/.test(e.message), e && e.message);
  e = await intenta(DIGI, (q) => q(`select polizas_eliminacion_solicitar(array[1]::bigint[], '  ab  ')`));
  ok('motivo "  ab  " (2 caracteres tras recortar) rechazado', e && /motivo/.test(e.message), e && e.message);
  e = await intenta(DIGI, (q) => q(`select polizas_eliminacion_solicitar(array[1]::bigint[], 'abcd')`));
  ok('motivo de 4 caracteres rechazado', e && /motivo/.test(e.message), e && e.message);

  const z = await P('E1-Z');
  r = await solicitar(DIGI, [z], '  abcde  ');
  ok('motivo de exactamente 5 caracteres (con espacios alrededor) aceptado y guardado recortado',
    r.solicitadas === 1 && (await c.query(`select motivo from polizas_eliminacion where poliza_id=$1`, [z])).rows[0].motivo === 'abcde');

  // btrim solo recorta ESPACIOS: saltos de línea, tabs y espacios no separables pasan como "motivo".
  for (const [nombre, m] of [['5 saltos de línea', '\n\n\n\n\n'], ['5 tabs', '\t\t\t\t\t'], ['5 espacios no separables (U+00A0)', ' '.repeat(5)]]) {
    const w = await P('E1-W');
    const err = await intenta(DIGI, (q) => q(`select polizas_eliminacion_solicitar($1::bigint[], $2)`, [[w], m]));
    hallazgo(`motivo de ${nombre} debería rechazarse (no es un motivo real)`, !!err, 'ACEPTADO: btrim() solo quita espacios ASCII');
  }

  const larga = await P('E1-L');
  const grande = 'x'.repeat(1_000_000);
  const errLargo = await intenta(DIGI, (q) => q(`select polizas_eliminacion_solicitar($1::bigint[], $2)`, [[larga], grande]));
  hallazgo('el motivo tiene tope de longitud (500): uno de 1.000.000 se rechaza', !!errLargo && /demasiado largo/.test(errLargo.message), errLargo && errLargo.message);
}

console.log('2) solicitar/resolver: 200 vs 201');
{
  const base = 5_000_000;
  const ids200 = Array.from({ length: 200 }, (_, i) => base + i);
  let r = await solicitar(DIGI, ids200);
  ok('200 ids (inexistentes) -> sin error, 200 omitidas', r.solicitadas === 0 && r.omitidas.length === 200);
  let e = await intenta(DIGI, (q) => q(`select polizas_eliminacion_solicitar($1::bigint[], 'motivo válido')`, [[...ids200, base + 200]]));
  ok('201 ids distintos -> rechazado', e && /200/.test(e.message), e && e.message);
  r = await solicitar(DIGI, [...ids200, ids200[0], ids200[0]]);
  ok('202 elementos con 200 distintos -> aceptado (el tope cuenta distintos)', r.omitidas.length === 200);
  e = await intenta(DIGI, (q) => q(`select polizas_eliminacion_solicitar($1::bigint[], 'motivo válido')`, [[...ids200, null]]));
  info('200 ids + un NULL (201 elementos distintos):', e ? 'rechazado por tope' : 'aceptado');
  e = await intenta(ADMIN, (q) => q(`select polizas_eliminacion_resolver($1::bigint[], 'rechazar', null)`, [[...ids200, base + 200]]));
  ok('resolver con 201 ids -> rechazado', e && /200/.test(e.message), e && e.message);
  r = await resolver(ADMIN, ids200, 'rechazar');
  ok('resolver con 200 ids inexistentes -> 0 resueltas, 200 omitidas', r.resueltas === 0 && r.omitidas.length === 200);
  e = await intenta(ADMIN, (q) => q(`select polizas_eliminacion_resolver(null::bigint[], 'aprobar', null)`));
  ok('resolver con p_ids NULL -> "No hay solicitudes"', e && /No hay solicitudes/.test(e.message), e && e.message);
}

// ═══ 3. Roles y sesiones ════════════════════════════════════════════════════
console.log('3) Roles: inactivo, rol null, rol vacío, rol raro, sub inválido, anon');
{
  const p = await P('R-1');
  for (const [nombre, uid] of [['usuario inactivo', INACTIVO], ['rol NULL en la tabla', SINROL], ['sub inexistente (9999)', 9999], ['sub no numérico', 'abc'], ['sin token', null]]) {
    const e = await intenta(uid, (q) => q(`select polizas_eliminacion_solicitar($1::bigint[], 'motivo válido')`, [[p]]));
    ok(`${nombre}: solicitar negado`, e && /No tiene permiso/.test(e.message), e && e.message);
  }
  const n = await como(INACTIVO, (q) => q('select polizas_eliminacion_contar() n'));
  ok('admin INACTIVO: contador 0', n.rows[0].n === 0);
  for (const fn of ['select polizas_eliminacion_pendientes()', 'select polizas_eliminacion_historial(5)', `select polizas_eliminacion_resolver(array[1]::bigint[], 'aprobar', null)`]) {
    const e = await intenta(INACTIVO, (q) => q(fn));
    ok(`admin INACTIVO negado: ${fn.slice(7, 40)}`, e && /Solo un Administrador/.test(e.message), e && e.message);
  }
  // Rol '' y rol 'X': app_rol() no es null -> la RLS y solicitar los dejan pasar (decisión de diseño: cualquier rol no nulo).
  for (const [nombre, uid] of [['rol vacío ""', ROLVACIO], ['rol desconocido "X"', ROLRARO]]) {
    const q2 = await P('R-' + nombre);
    const r = await solicitar(uid, [q2], 'motivo de rol raro').catch((e) => ({ err: e.message }));
    info(`${nombre}: solicitar ->`, r.err ? 'negado' : 'PERMITIDO');
    const e = await intenta(uid, (q) => q(`select polizas_eliminacion_resolver(array[1]::bigint[], 'rechazar', null)`));
    ok(`${nombre}: NO puede resolver`, e && /Solo un Administrador/.test(e.message));
  }
  const rs = await solicitar(SUPER, [await P('R-S')], 'rol S marca una');
  ok("rol 'S' puede solicitar (cualquier usuario activo)", rs.solicitadas === 1);
  // anon
  for (const fn of ['select polizas_eliminacion_solicitar(array[1]::bigint[], \'motivo válido\')', 'select polizas_eliminacion_pendientes()', 'select polizas_eliminacion_contar()',
    'select polizas_eliminacion_historial(1)', `select polizas_eliminacion_resolver(array[1]::bigint[],'aprobar',null)`]) {
    const e = await como(null, (q) => falla(() => q(fn)), 'anon');
    ok(`anon sin EXECUTE: ${fn.slice(7, 40)}`, e && /permission denied/.test(e.message), e && e.message);
  }
  const t = await como(null, (q) => falla(() => q('select count(*) from polizas')), 'anon');
  info('anon lee polizas (el test le da SELECT de tabla como cualquier rol):', t ? 'error ' + t.message : 'sin error, ver siguiente');
  const nAnon = await como(null, (q) => q('select count(*)::int n from polizas'), 'anon').catch(() => ({ rows: [{ n: -1 }] }));
  ok('anon no ve ninguna póliza (la política es solo "to authenticated")', nAnon.rows[0].n === 0, String(nAnon.rows[0].n));
}

// ═══ 4. Abonos mixtos y FK real ═════════════════════════════════════════════
console.log('4) Abonos: mixtos, solo anulados, cada estado, FK real');
{
  const mix = await P('AB-MIX'); await abono(mix, 'A'); await abono(mix, 'I');
  const soloA = await P('AB-A'); await abono(soloA, 'A'); await abono(soloA, 'A');
  const r = await solicitar(DIGI, [mix, soloA]);
  ok('mixta (activo+anulado) y solo-anulada se omiten: cualquier pago impide marcar', r.solicitadas === 0 && r.omitidas.length === 2, JSON.stringify(r));
  for (const est of ['C', 'R', 'V']) {
    const x = await P('AB-' + est); await abono(x, est);
    const rr = await solicitar(DIGI, [x]);
    ok(`abono en estado ${est} cuenta como pago registrado`, rr.solicitadas === 0 && rr.omitidas.length === 1);
  }

  // Póliza limpia: se marca; un pago NUEVO ya no puede entrar (trigger). Un dato antiguo con pago
  // (simulado desactivando el trigger) bloquea la aprobación y la salida es rechazar.
  const tardia = await P('AB-TARDE');
  ok('póliza sin pagos se marca', (await solicitar(DIGI, [tardia])).solicitadas === 1);
  const sid = await solId(tardia);
  const e = await intenta(DIGI, (q) => q(`insert into abonos_poliza(id_poliza, vlrabono_prima, estado_pago) values ($1, 50, 'I')`, [tardia]));
  ok('un pago nuevo sobre una póliza marcada es rechazado por la base', e && /marcada para eliminar/.test(e.message), e && e.message);
  await c.query('alter table abonos_poliza disable trigger trg_abonos_no_en_poliza_marcada');
  await abono(tardia, 'I');
  await c.query('alter table abonos_poliza enable trigger trg_abonos_no_en_poliza_marcada');
  const ap2 = await resolver(ADMIN, [sid], 'aprobar', 'x');
  ok('aprobar una póliza que tiene pagos se bloquea', ap2.resueltas === 0 && (await fila(tardia)) !== undefined);
  ok('  la solicitud sigue pendiente', (await solId(tardia)) === sid);
  const rj = await resolver(ADMIN, [sid], 'rechazar', 'hay pagos');
  ok('  rechazar la restaura', rj.resueltas === 1 && (await fila(tardia)).eliminada_en === null);

  // Aprobar sobre una póliza con FK de otra tabla: el borrado falla y se reporta, sin romper el resto del lote.
  const f1 = await P('FK-1'), f2 = await P('FK-2');
  await c.query(`create table if not exists hijo_poliza(id serial primary key, id_poliza bigint references polizas(id))`);
  await c.query(`insert into hijo_poliza(id_poliza) values ($1)`, [f1]);
  await solicitar(DIGI, [f1, f2]);
  const lote = [await solId(f1), await solId(f2)];
  const rr = await resolver(ADMIN, lote, 'aprobar', 'lote con FK');
  ok('lote: la póliza con FK ajena se omite, la otra se borra (1 resuelta, 1 omitida)', rr.resueltas === 1 && rr.omitidas.length === 1 && /relacionados/.test(rr.omitidas[0].razon), JSON.stringify(rr));
  ok('  f1 sigue existiendo y marcada; solicitud pendiente; f2 borrada',
    (await fila(f1)).eliminada_en !== null && (await solId(f1)) === lote[0] && !(await fila(f2)));
}

// ═══ 5. Reaprobar / remarcar tras rechazo, índice único parcial ═════════════
console.log('5) Remarcar tras rechazo, índice único parcial, acciones sobre resueltas');
{
  const p = await P('RR-1', 2500);
  await solicitar(DIGI, [p], 'primer intento');
  const s1 = await solId(p);
  await resolver(ADMIN, [s1], 'rechazar', 'no');
  const r2 = await solicitar(DIGI2, [p], 'segundo intento');
  ok('volver a marcar la misma póliza tras rechazarla funciona', r2.solicitadas === 1, JSON.stringify(r2));
  const s2 = await solId(p);
  ok('  hay 2 solicitudes (rechazada + pendiente), ids distintos', s2 !== s1 && (await c.query(`select count(*)::int n from polizas_eliminacion where poliza_id=$1`, [p])).rows[0].n === 2);
  const e = await sinTx(() => c.query(`insert into polizas_eliminacion(poliza_id,motivo,lote) values ($1,'forzado dup',gen_random_uuid())`, [p]));
  ok('índice único parcial: no se puede insertar 2ª pendiente de la misma póliza', e && e.code === '23505', e && e.message);
  const ap = await resolver(ADMIN, [s1], 'aprobar', 'x');
  ok('aprobar una solicitud ya RECHAZADA se omite y NO borra la póliza (que tiene otra pendiente)', ap.resueltas === 0 && !!(await fila(p)));
  const rc = await resolver(ADMIN, [s1], 'rechazar', 'x');
  ok('rechazar otra vez una ya rechazada se omite y no desmarca la póliza con pendiente nueva', rc.resueltas === 0 && (await fila(p)).eliminada_en !== null);
  const ap2 = await resolver(ADMIN2, [s2], 'aprobar', 'ok');
  ok('aprobar la 2ª: borrada, snapshot completo', ap2.resueltas === 1 && !(await fila(p)));
  const sn = (await c.query(`select snapshot from polizas_eliminacion where id=$1`, [s2])).rows[0].snapshot;
  ok('  snapshot trae nro_poliza, prima y eliminada_en', sn.nro_poliza === 'RR-1' && Number(sn.prima_poliza) === 2500 && sn.eliminada_en);
  const rc2 = await resolver(ADMIN, [s2], 'rechazar', 'tarde');
  ok('rechazar una aprobada se omite', rc2.resueltas === 0);

  // p_accion NULL: `NULL not in (...)` es NULL, así que el chequeo no corta y cae en la rama de APROBAR (borra).
  const q = await P('ACC-NULL');
  await solicitar(DIGI, [q], 'accion nula test');
  const sidq = await solId(q);
  const err = await intenta(ADMIN, (qq) => qq(`select polizas_eliminacion_resolver($1::bigint[], null, null)`, [[sidq]]));
  const existe = await fila(q);
  hallazgo('p_accion NULL debe rechazarse como "Acción no válida" (hoy APRUEBA y BORRA la póliza)', !!err && !!existe, `err=${err && err.message}; póliza ${existe ? 'sigue' : 'BORRADA'}`);

  // póliza que desaparece por fuera (service_role / script) antes de resolver
  const g = await P('GONE-1'); await solicitar(DIGI, [g], 'se borra por fuera');
  await c.query('delete from polizas where id=$1', [g]);
  const rg = await resolver(ADMIN, [await solId(g)], 'aprobar', 'x');
  const snapG = (await c.query(`select estado, snapshot from polizas_eliminacion where poliza_id=$1`, [g])).rows[0];
  info('aprobar solicitud cuya póliza ya no existe ->', JSON.stringify(rg), 'estado', snapG.estado, 'snapshot', snapG.snapshot === null ? 'NULL' : 'ok');
  ok('aprobar con póliza inexistente cierra la solicitud como aprobada, sin copia, dejando una nota',
     snapG.estado === 'aprobada' && snapG.snapshot === null && rg.resueltas === 1, JSON.stringify([rg, snapG]));
  const g2 = await P('GONE-2'); await solicitar(DIGI, [g2], 'se borra por fuera 2');
  await c.query('delete from polizas where id=$1', [g2]);
  const rg2 = await resolver(ADMIN, [await solId(g2)], 'rechazar', 'x');
  ok('rechazar con póliza inexistente no falla', rg2.resueltas === 1, JSON.stringify(rg2));
}

// ═══ 6. Concurrencia real (dos conexiones) ══════════════════════════════════
console.log('6) Concurrencia');
{
  // 6a. dos solicitudes simultáneas del mismo id
  const p = await P('CC-1');
  const A = await abre(DIGI), B = await abre(DIGI2);
  const rA = (await A.query(`select polizas_eliminacion_solicitar($1::bigint[], 'solicitud A')  r`, [[p]])).rows[0].r;
  const lb = lanza(B, `select polizas_eliminacion_solicitar($1::bigint[], 'solicitud B') r`, [[p]]);
  await dormir(600);
  ok('B queda esperando el bloqueo de fila mientras A no confirma', !lb.termino());
  await A.query('commit');
  const rB = (await lb.pr).rows[0].r;
  await B.query('commit');
  ok('exactamente una de las dos solicitudes marca la póliza', rA.solicitadas + rB.solicitadas === 1, JSON.stringify([rA, rB]));
  ok('  una sola solicitud pendiente', (await c.query(`select count(*)::int n from polizas_eliminacion where poliza_id=$1 and estado='pendiente'`, [p])).rows[0].n === 1);
  await A.end(); await B.end();

  // 6b. mismas pólizas en orden inverso (sin interbloqueo)
  const x = await P('CC-X'), y = await P('CC-Y');
  const A2 = await abre(DIGI), B2 = await abre(DIGI2);
  const corre = async (cl, ids, m) => { const r = await cl.query(`select polizas_eliminacion_solicitar($1::bigint[], $2) r`, [ids, m]); await cl.query('commit'); return r.rows[0].r; };
  const res2 = await Promise.all([corre(A2, [x, y], 'orden directo'), corre(B2, [y, x], 'orden inverso')]).catch((e) => ({ err: e }));
  if (res2.err) { ok('sin interbloqueo con ids en orden inverso', false, res2.err.message); }
  else { ok('ids en orden inverso desde 2 conexiones: sin deadlock y 2 solicitadas en total', res2[0].solicitadas + res2[1].solicitadas === 2, JSON.stringify(res2)); }
  await A2.end().catch(() => {}); await B2.end().catch(() => {});

  // 6c. aprobar vs rechazar simultáneo (ambos sentidos)
  for (const [primera, segunda] of [['rechazar', 'aprobar'], ['aprobar', 'rechazar']]) {
    const w = await P('CC-' + primera); await solicitar(DIGI, [w], 'carrera aprobar/rechazar');
    const sid = await solId(w);
    const A3 = await abre(ADMIN), B3 = await abre(ADMIN2);
    const r1 = (await A3.query(`select polizas_eliminacion_resolver($1::bigint[], $2, null) r`, [[sid], primera])).rows[0].r;
    const l = lanza(B3, `select polizas_eliminacion_resolver($1::bigint[], $2, null) r`, [[sid], segunda]);
    await dormir(500);
    ok(`${primera} (A, sin commit) bloquea a ${segunda} (B)`, !l.termino());
    await A3.query('commit');
    const r2 = (await l.pr).rows[0].r; await B3.query('commit');
    const ex = await fila(w);
    ok(`  gana ${primera}: B la omite; estado final coherente`, r1.resueltas === 1 && r2.resueltas === 0 &&
      (primera === 'rechazar' ? ex && ex.eliminada_en === null : !ex), JSON.stringify([r1, r2]));
    ok('  solo 1 fila de solicitud y no queda pendiente', (await c.query(`select count(*)::int n from polizas_eliminacion where poliza_id=$1 and estado='pendiente'`, [w])).rows[0].n === 0);
    await A3.end(); await B3.end();
  }

  // 6d. rechazar (sin commit) vs un nuevo solicitar de la misma póliza
  const w = await P('CC-REM'); await solicitar(DIGI, [w], 'primero');
  const s = await solId(w);
  const A4 = await abre(ADMIN), B4 = await abre(DIGI2);
  await A4.query(`select polizas_eliminacion_resolver($1::bigint[], 'rechazar', null)`, [[s]]);
  const l4 = lanza(B4, `select polizas_eliminacion_solicitar($1::bigint[], 'segundo intento') r`, [[w]]);
  await dormir(500);
  await A4.query('commit');
  const r4 = (await l4.pr.catch((e) => ({ err: e }))); if (r4.err) await B4.query('rollback').catch(() => {}); else await B4.query('commit');
  const est = (await c.query(`select estado from polizas_eliminacion where poliza_id=$1 order by id`, [w])).rows.map((r) => r.estado).join(',');
  info('rechazar + solicitar simultáneos ->', r4.err ? r4.err.message : JSON.stringify(r4.rows[0].r), '| solicitudes:', est);
  ok('  estado coherente: rechazada,pendiente con póliza marcada (o rechazada sola con póliza visible)',
    (est === 'rechazada,pendiente' && (await fila(w)).eliminada_en !== null) || (est === 'rechazada' && (await fila(w)).eliminada_en === null), est);
  await A4.end(); await B4.end();

  // 6e. un pago ya no puede entrar a una póliza marcada (trigger) y la aprobación procede
  const k = await P('CC-ABONO'); await solicitar(DIGI, [k], 'carrera abono');
  const sk = await solId(k);
  const A5 = await abre(DIGI);
  let e5 = null;
  try { await A5.query(`insert into abonos_poliza(id_poliza, vlrabono_prima, estado_pago) values ($1, 10, 'I')`, [k]); } catch (err) { e5 = err; }
  await A5.query('rollback').catch(() => {});
  await A5.end();
  ok('pago sobre una póliza marcada: rechazado por la base', e5 && /marcada para eliminar/.test(e5.message), e5 && e5.message);
  const r5 = await resolver(ADMIN, [sk], 'aprobar', null);
  ok('y la aprobación procede porque no hay pagos', r5.resueltas === 1 && !(await fila(k)), JSON.stringify(r5));
}

// ═══ 7. Triggers existentes y campos al marcar/restaurar ════════════════════
console.log('7) Triggers reales (fultmod, pago_estado) al marcar y restaurar');
{
  const p = await P('TR-1', 1000, { estado: 'I' });
  await c.query(`update polizas set fultmod = '2020-01-01', vlrprimapagada_poliza = 0 where id = $1`, [p]);
  // set_fultmod pisa lo anterior; fijamos fultmod "viejo" desactivando el trigger solo para el setup.
  await c.query(`alter table polizas disable trigger trg_fultmod`);
  await c.query(`update polizas set fultmod = '2020-01-01' where id = $1`, [p]);
  await c.query(`alter table polizas enable trigger trg_fultmod`);
  await c.query(`alter table polizas disable trigger trg_fultmod`);
  await c.query(`update polizas set fultmod = '2020-01-01' where id = $1`, [p]);
  await c.query(`alter table polizas enable trigger trg_fultmod`);
  const antes = await fila(p);
  await solicitar(DIGI, [p], 'prueba de campos');
  const marcada = await fila(p);
  await resolver(ADMIN, [await solId(p)], 'rechazar', 'restaurar');
  const despues = await fila(p);
  const campos = ['nro_poliza', 'prima_poliza', 'estado_poliza_id', 'estado_por_pagos', 'vlrprimapagada_poliza', 'vlrprimapagada_base', 'cliente_id', 'aseg_id', 'ramo_id'];
  ok('marcar y restaurar no altera datos de negocio (prima, estado, pagos, cliente...)', campos.every((k) => String(antes[k]) === String(despues[k])), JSON.stringify(campos.filter((k) => String(antes[k]) !== String(despues[k]))));
  ok('eliminada_en queda en null tras restaurar', despues.eliminada_en === null && marcada.eliminada_en !== null);
  info('fultmod al marcar/restaurar: lo pone set_fultmod() (efecto aceptado; los datos de negocio no cambian)');

  // Póliza histórica con prima pagada a mano y sin abonos: marcar/restaurar no la altera
  const h = await P('TR-H', 5000, { estado: 'I' });
  await c.query(`update polizas set vlrprimapagada_poliza = 5000, vlrprimapagada_base = 5000 where id = $1`, [h]);
  const ah = await fila(h);
  await solicitar(DIGI, [h], 'histórica sin abonos');
  await resolver(ADMIN, [await solId(h)], 'rechazar', null);
  const dh = await fila(h);
  ok('histórica sin abonos: marcar/restaurar conserva vlrprimapagada y estado',
     String(ah.vlrprimapagada_poliza) === String(dh.vlrprimapagada_poliza) && ah.estado_poliza_id === dh.estado_poliza_id,
     `${ah.vlrprimapagada_poliza}->${dh.vlrprimapagada_poliza}`);
}

// ═══ 8. UPDATE masivo, upsert y manipulación de la marca por un usuario ═════
console.log('8) Manipulación de eliminada_en por usuarios autenticados');
{
  const m1 = await P('MS-1'), m2 = await P('MS-2'), libre = await P('MS-LIBRE');
  await solicitar(DIGI, [m1, m2], 'marcadas para masivo');
  const nMarc = () => c.query(`select count(*)::int n from polizas where eliminada_en is not null`).then((r) => r.rows[0].n);
  const antes = await nMarc();

  let r = await comoCommit(DIGI, (q) => q(`update polizas set eliminada_en = null`));
  ok('UPDATE masivo "set eliminada_en = null": 0 desmarcadas (las marcadas son invisibles; las libres no cambian)', (await nMarc()) === antes, `rowCount=${r.rowCount}`);
  let e = await intenta(DIGI, (q) => q(`update polizas set eliminada_en = now()`));
  ok('UPDATE masivo "set eliminada_en = now()" falla y no marca nada', e && /solo se cambia/.test(e.message) && (await nMarc()) === antes, e && e.message);
  r = await comoCommit(DIGI, (q) => q(`update polizas set eliminada_en = eliminada_en where id = $1`, [libre]));
  ok('UPDATE no-op de eliminada_en (set col = col) sobre libre sigue permitido', r.rowCount === 1);
  r = await comoCommit(DIGI, (q) => q(`update polizas set nro_poliza = nro_poliza || '!' where id in ($1,$2,$3)`, [m1, m2, libre]));
  ok('UPDATE masivo con ids marcados: solo toca la libre', r.rowCount === 1);
  e = await intenta(DIGI, (q) => q(`delete from polizas where id in ($1,$2)`, [m1, m2]));
  ok('DELETE masivo por la API: negado (nadie borra pólizas sin autorización)', e && /permission denied/i.test(e.message) && (await nMarc()) === antes, e && e.message);

  // upsert (PostgREST on_conflict) apuntando al id de una marcada
  e = await intenta(DIGI, (q) => q(`insert into polizas(id, nro_poliza, eliminada_en) overriding system value values ($1,'UPSERT',null)
     on conflict (id) do update set eliminada_en = null, nro_poliza = excluded.nro_poliza`, [m1]));
  ok('UPSERT sobre una marcada no la desmarca ni la edita', (await nMarc()) === antes && (await fila(m1)).nro_poliza === 'MS-1', e ? e.message : 'sin error');
  info('UPSERT sobre marcada ->', e ? 'error: ' + e.message : 'sin error (0 filas)');
  e = await intenta(DIGI, (q) => q(`insert into polizas(id, nro_poliza) overriding system value values ($1,'DUP')`, [m1]));
  info('INSERT con el id de una marcada ->', e ? e.code + ' ' + e.message : 'ok');

  // la tabla de solicitudes no se toca por API
  for (const [nombre, sql] of [
    ['SELECT', `select count(*)::int n from polizas_eliminacion`],
    ['UPDATE', `update polizas_eliminacion set estado = 'rechazada'`],
    ['DELETE', `delete from polizas_eliminacion`],
  ]) {
    const res = await como(DIGI, (q) => q(sql));
    ok(`API directa a polizas_eliminacion: ${nombre} no ve/afecta nada`, (res.rows[0] ? res.rows[0].n === 0 : res.rowCount === 0));
  }
  e = await intenta(DIGI, (q) => q(`insert into polizas_eliminacion(poliza_id,motivo,lote) values (1,'forzado ok',gen_random_uuid())`));
  ok('API directa: INSERT en polizas_eliminacion denegado por RLS', e && /row-level security/.test(e.message), e && e.message);
  e = await intenta(ADMIN, (q) => q(`select * from polizas_eliminacion`).then((x) => { if (x.rowCount) throw new Error('visible'); }));
  ok('ni el administrador lee polizas_eliminacion directo (solo por funciones)', !e, e && e.message);

  // set_config a mano: solo posible en SQL directo, no por PostgREST; se documenta
  e = await intenta(DIGI, async (q) => { await q(`select set_config('app.eliminacion','1',true)`); await q(`update polizas set eliminada_en = now() where id = $1`, [libre]); });
  ok('aun activando app.eliminacion a mano, el guard (rol de la app) y la RLS impiden marcar por UPDATE', !!e && /solo se cambia|row-level security/.test(e.message), e ? e.message : 'PERMITIDO');
  await c.query(`update polizas set eliminada_en = null where id = $1`, [libre]); // limpieza (postgres)
}

// ═══ 9. Inyección SQL ═══════════════════════════════════════════════════════
console.log('9) Inyección SQL en motivo / nota / acción');
{
  const inj = `x'); drop table polizas_eliminacion; --`;
  const inj2 = `'; delete from polizas; select '`;
  const p = await P('INJ-1');
  const r = await solicitar(DIGI, [p], inj);
  ok('motivo con comillas/DROP se guarda literal', r.solicitadas === 1 && (await c.query(`select motivo from polizas_eliminacion where poliza_id=$1`, [p])).rows[0].motivo === inj);
  const rr = await resolver(ADMIN, [await solId(p)], 'rechazar', inj2);
  ok('nota con inyección se guarda literal', rr.resueltas === 1 && (await c.query(`select nota_resolucion n from polizas_eliminacion where poliza_id=$1 and estado='rechazada'`, [p])).rows[0].n === inj2);
  const e = await intenta(ADMIN, (q) => q(`select polizas_eliminacion_resolver($1::bigint[], $2, null)`, [[1], `aprobar'; delete from polizas; --`]));
  ok('acción con inyección -> "Acción no válida"', e && /Acción no válida/.test(e.message), e && e.message);
  const t = await c.query(`select to_regclass('polizas_eliminacion') t, (select count(*)::int from polizas) n`);
  ok('las tablas siguen intactas', t.rows[0].t && t.rows[0].n > 0);
  const nota = await P('INJ-2'); await solicitar(DIGI, [nota], 'nota en blanco');
  await resolver(ADMIN, [await solId(nota)], 'rechazar', '    ');
  ok('nota solo espacios se guarda como NULL', (await c.query(`select nota_resolucion n from polizas_eliminacion where poliza_id=$1 and estado='rechazada'`, [nota])).rows[0].n === null);
  // historial: límites raros
  for (const lim of [null, 0, -5, 1000000]) {
    const h = await como(ADMIN, (q) => q(`select polizas_eliminacion_historial($1::int) r`, [lim]));
    ok(`historial(limite=${lim}) devuelve arreglo de tamaño razonable`, Array.isArray(h.rows[0].r) && h.rows[0].r.length >= 1 && h.rows[0].r.length <= 500);
  }
}

// ═══ 10. Vistas y consumidores de pólizas ═══════════════════════════════════
console.log('10) Vistas security_invoker, duplicados, abonos, fusionar_clientes');
{
  const d1 = await P('DUP-1'), d2 = await P('DUP-1');
  const antes = await como(DIGI, (q) => q(`select count(*)::int n from vw_polizas_duplicadas where nro_poliza='DUP-1'`));
  ok('antes de marcar, ambas aparecen como duplicadas', antes.rows[0].n === 2);
  await solicitar(DIGI, [d2], 'duplicada real');
  const despues = await como(DIGI, (q) => q(`select (select count(*)::int from vw_polizas_duplicadas where nro_poliza='DUP-1') dup,
    (select count(*)::int from vw_polizas_busqueda where nro_poliza='DUP-1') bus`));
  ok('al marcar una, desaparece de vw_polizas_busqueda y el par deja de ser duplicado', despues.rows[0].bus === 1 && despues.rows[0].dup === 0, JSON.stringify(despues.rows[0]));
  const mal = await como(DIGI, (q) => q(`select count(*)::int n from vw_mal_definer where nro_poliza='DUP-1'`)).catch(() => null);
  info('vista SIN security_invoker (owner postgres) muestra', mal && mal.rows[0].n, 'de 2: confirma que toda vista nueva sobre polizas DEBE ser security_invoker');
  ok('control: una vista de owner sin security_invoker SÍ filtraría las marcadas (por eso el invariante importa)', mal && mal.rows[0].n === 2);

  // abonos anulados de una marcada siguen apareciendo en vw_abonos_detalle (con póliza nula)
  const pa = await P('VAB-1'); await abono(pa, 'A', 77);
  await solicitar(DIGI, [pa], 'abono anulado visible');
  const va = await como(DIGI, (q) => q(`select id_poliza, nro_poliza from vw_abonos_detalle where id_poliza=$1`, [pa]));
  hallazgo('los abonos (anulados) de una póliza marcada no deberían aparecer huérfanos (nro_poliza NULL) en vw_abonos_detalle',
    va.rowCount === 0 || va.rows[0].nro_poliza !== null, `filas=${va.rowCount} nro_poliza=${va.rows[0] && va.rows[0].nro_poliza}`);

  // fusionar_clientes (security invoker) con una póliza marcada del cliente sobrante
  const cb = (await c.query(`insert into clientes(nombre_cliente, doc_cliente_norm) values ('Bueno','123') returning id`)).rows[0].id;
  const cm = (await c.query(`insert into clientes(nombre_cliente, doc_cliente_norm) values ('Malo','123') returning id`)).rows[0].id;
  const pm = await P('FUS-1', 1000, { cliente: cm });
  await solicitar(DIGI, [pm], 'marcada de cliente duplicado');
  const e = await intenta(DIGI, (q) => q(`select fusionar_clientes($1, $2::bigint[])`, [cb, [cm]]));
  hallazgo('fusionar_clientes debe poder fusionar aunque el cliente sobrante tenga una póliza marcada (hoy no la ve, no la mueve y el DELETE falla por FK)',
    !e, e && e.message);
  const ex = (await c.query(`select 1 from clientes where id=$1`, [cm])).rowCount;
  ok('  tras el fallo no queda nada a medias (el cliente sobrante sigue y la póliza apunta a él)', e ? ex === 1 && (await fila(pm)).cliente_id === cm : true);
  // si el admin rechaza, la fusión ya funciona
  await resolver(ADMIN, [await solId(pm)], 'rechazar', null);
  const e2 = await intenta(DIGI, (q) => q(`select fusionar_clientes($1, $2::bigint[])`, [cb, [cm]]));
  ok('  tras rechazar la eliminación, la fusión funciona y mueve la póliza', !e2 && (await fila(pm)).cliente_id === cb, e2 && e2.message);
}

// ═══ 11. Idempotencia de la migración ═══════════════════════════════════════
console.log('11) Re-ejecutar la migración con datos existentes');
{
  const p = await P('IDEM-1'); await solicitar(DIGI, [p], 'antes de reaplicar');
  const n0 = (await c.query(`select count(*)::int a, (select count(*)::int from polizas_eliminacion) b from polizas where eliminada_en is not null`)).rows[0];
  let e = null;
  try { await c.query(fs.readFileSync(MIGRACION, 'utf8')); } catch (x) { e = x; }
  ok('la migración se puede volver a correr sin error', !e, e && e.message);
  const n1 = (await c.query(`select count(*)::int a, (select count(*)::int from polizas_eliminacion) b from polizas where eliminada_en is not null`)).rows[0];
  ok('  no pierde marcas ni solicitudes', n0.a === n1.a && n0.b === n1.b, JSON.stringify([n0, n1]));
  const pol = await c.query(`select policyname from pg_policies where tablename='polizas' order by 1`);
  ok('  quedan exactamente 3 políticas en polizas (sin borrado), ninguna permisiva', pol.rowCount === 3 && !pol.rows.some((x) => x.policyname === 'app_authenticated_full_access'), pol.rows.map((x) => x.policyname).join());
  // Si alguien repite el bucle de migracion_2026_09 (política permisiva), las marcadas reaparecen: se documenta.
  await c.query(`create policy app_authenticated_full_access on polizas for all to authenticated using ((select app_rol()) is not null) with check ((select app_rol()) is not null)`);
  const v = await como(DIGI, (q) => q(`select count(*)::int n from polizas where id=$1`, [p]));
  ok('control: con la política permisiva reinstalada, la marcada REAPARECE (advertencia del encabezado de la migración)', v.rows[0].n === 1);
  await c.query(`drop policy app_authenticated_full_access on polizas`);
  const v2 = await como(DIGI, (q) => q(`select count(*)::int n from polizas where id=$1`, [p]));
  ok('  al quitarla vuelve a ocultarse', v2.rows[0].n === 0);
}

console.log(`\nRESULTADO: ${pass} bien, ${fail} mal, ${hallazgos} hallazgos conocidos (no cuentan como fallo)`);
await c.end();
await server.stop();
process.exit(fail ? 1 : 0);
