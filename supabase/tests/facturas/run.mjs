// Prueba de la migración 20261111090000_facturas.sql contra un PostgreSQL
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
const MIGRACION = path.join(AQUI, '../../migrations/20261111090000_facturas.sql');
const DIR = path.join(os.tmpdir(), 'pgtest-facturas-' + process.pid);

fs.rmSync(DIR, { recursive: true, force: true });
const server = new EmbeddedPostgres({ databaseDir: DIR, user: 'postgres', password: 'x', port: 45434, persistent: false, initdbFlags: ['--encoding=UTF8', '--locale=C'] });
await server.initialise();
await server.start();
await server.createDatabase('t');
const c = new pg.Client({ host: 'localhost', port: 45434, user: 'postgres', password: 'x', database: 't' });
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
create table aseguradoras(id bigint generated always as identity primary key, nombre_aseg text);
create table intermediarios(id bigint generated always as identity primary key, nombre_interm text);
create table reportes_pago(id bigint generated always as identity primary key, aseg_id bigint references aseguradoras(id), interm_id bigint);
create table abonos_poliza(id bigint generated always as identity primary key,
  idrep_pago bigint references reportes_pago(id), vlrcomision numeric default 0, vlrcomad numeric default 0,
  idfactura bigint, num_factura text, estado_pago char(1) default 'I');
grant usage on schema public, auth to authenticated, anon, service_role;
grant select, update on abonos_poliza to authenticated;
insert into usuarios(apodo_usuario, rol) values ('ADMIN','A'), ('DIGI','D'), ('SUPER','S'), ('NADIE', null);
insert into aseguradoras(nombre_aseg) values ('ESTADO'), ('SOLIDARIA');
insert into intermediarios(nombre_interm) values ('LUZ STELLA');
insert into reportes_pago(aseg_id, interm_id) values (1, 1), (2, 1);
-- 4 líneas de ESTADO (la 4 anulada), 1 de SOLIDARIA, 1 con factura vieja (sin cabecera cargada).
insert into abonos_poliza(idrep_pago, vlrcomision, vlrcomad, estado_pago, idfactura, num_factura) values
  (1, 100000, 0, 'C', null, 'REC-1'), (1, 250000.5, 10000, 'C', null, 'REC-2'), (1, 50000, 0, 'R', null, 'REC-3'),
  (1, 999, 0, 'A', null, null), (2, 70000, 0, 'C', null, null), (1, 5000, 0, 'C', 777, '1413');
`);

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
const falla = async (sub, consulta, params = []) => {
  try { await como(sub, () => c.query(consulta, params)); return ''; } catch (e) { return String(e.message); }
};
const ADMIN = 1, DIGI = 2, SUPER = 3, NADIE = 4;

// ── Montos ────────────────────────────────────────────────────────────────
const m1 = (await c.query(`select * from factura_montos(453182.99, 0, 10, 0)`)).rows[0];
ok('Valor a consignar de la captura: 453.182,99 − 10 % = 407.864,69', Number(m1.neto) === 407864.69 && Number(m1.retefuente) === 45318.3 && Number(m1.total) === 453182.99, JSON.stringify(m1));
const m2 = (await c.query(`select * from factura_montos(672706.04, 16, 10, 1)`)).rows[0];
ok('con IVA 16 %: total = subtotal + IVA; neto = total − retención − ICA',
  Number(m2.iva) === 107632.97 && Number(m2.total) === 780339.01 && Number(m2.neto) === 780339.01 - 67270.6 - 6727.06, JSON.stringify(m2));

// ── Configuración ─────────────────────────────────────────────────────────
const cfg = (await c.query(`select clave, valor from facturacion_config order by clave`)).rows;
ok('porcentajes iniciales: IVA 0, retención 10, ICA 0', cfg.length === 3 && cfg.find((x) => x.clave === 'retefuente_pct').valor == 10);
await como(ADMIN, () => c.query(`select facturacion_config_guardar(19, 11, 0.5)`), true);
ok('el administrador cambia los porcentajes por defecto', Number((await c.query(`select valor from facturacion_config where clave='iva_pct'`)).rows[0].valor) === 19);
ok('un digitador NO cambia los porcentajes', /Solo un Administrador/.test(await falla(DIGI, `select facturacion_config_guardar(1,1,1)`)));
ok('porcentajes fuera de rango se rechazan', /entre 0 y 100/.test(await falla(ADMIN, `select facturacion_config_guardar(101,1,1)`)));
ok('el digitador puede LEER los porcentajes', (await como(DIGI, () => c.query(`select * from facturacion_config`))).rows.length === 3);
await como(ADMIN, () => c.query(`select facturacion_config_guardar(0, 10, 0)`), true);

// ── Crear factura ─────────────────────────────────────────────────────────
ok('el siguiente número parte en 1', (await como(DIGI, () => c.query(`select factura_siguiente_numero(1) n`))).rows[0].n === 1);
const id1 = (await como(DIGI, () => c.query(`select factura_crear(1, 1, null, '2026-11-10', array[1,2,3], 'prueba') id`), true)).rows[0].id;
const f1 = (await c.query(`select * from facturas where id = $1`, [id1])).rows[0];
// subtotal = 100000 + (250000.5 + 10000) + 50000 = 410000.5
ok('subtotal = suma de comisiones y comisión adicional', Number(f1.subtotal) === 410000.5, String(f1.subtotal));
ok('usa los porcentajes por defecto (0 / 10 / 0)', Number(f1.iva_pct) === 0 && Number(f1.retefuente_pct) === 10 && Number(f1.retefuente) === 41000.05, JSON.stringify(f1));
ok('neto = total − retención', Number(f1.neto) === 369000.45, String(f1.neto));
ok('queda Abierta, con prefijo 1 y número 1 y el usuario que la creó', f1.estado === 'A' && f1.prefijo === 1 && f1.num_factura === 1 && Number(f1.usuario_id) === DIGI);
const lineas = (await c.query(`select id, idfactura, num_factura from abonos_poliza order by id`)).rows;
ok('las líneas elegidas quedan enlazadas', lineas.slice(0, 3).every((l) => Number(l.idfactura) === Number(id1)));
ok('el recibo de la aseguradora (num_factura) NO se toca', lineas[0].num_factura === 'REC-1' && lineas[5].num_factura === '1413');
ok('el siguiente número sube a 2', (await como(DIGI, () => c.query(`select factura_siguiente_numero(1) n`))).rows[0].n === 2);

ok('líneas de otra aseguradora se rechazan', /misma aseguradora/.test(await falla(DIGI, `select factura_crear(1, 1, null, null, array[5])`)));
ok('un usuario sin rol NO puede crear facturas', /No tiene permiso/.test(await falla(NADIE, `select factura_crear(1, 1, null, null, array[5])`)));

// Porcentajes propios en una factura.
const id2 = (await como(SUPER, () => c.query(`select factura_crear(2, 1, null, null, array[5], null, 16, 0, 2) id`), true)).rows[0].id;
const f2 = (await c.query(`select * from facturas where id = $1`, [id2])).rows[0];
ok('porcentajes propios: IVA 16 %, sin retención, ICA 2 %', Number(f2.iva) === 11200 && Number(f2.retefuente) === 0 && Number(f2.ica) === 1400 && Number(f2.neto) === 70000 + 11200 - 1400, JSON.stringify(f2));
ok('el segundo prefijo/consecutivo es el 2', f2.num_factura === 2);

// Validaciones.
const solo = /Elija al menos una línea/;
ok('sin líneas se rechaza', solo.test(await falla(DIGI, `select factura_crear(1, 1, null, null, array[]::bigint[])`)));
ok('una línea ya facturada no entra en otra factura', /ya están en otra factura/.test(await falla(DIGI, `select factura_crear(1, 1, null, null, array[1])`)));
ok('una línea con factura vieja tampoco', /ya están en otra factura/.test(await falla(DIGI, `select factura_crear(1, 1, null, null, array[6])`)));
ok('una línea anulada se rechaza', /anulada/.test(await falla(DIGI, `select factura_crear(1, 1, null, null, array[4])`)));

// ── Recalcular ────────────────────────────────────────────────────────────
await c.query(`update abonos_poliza set vlrcomision = 200000 where id = 1`);
await como(DIGI, () => c.query(`select factura_recalcular($1)`, [id1]), true);
const f1b = (await c.query(`select subtotal, neto from facturas where id = $1`, [id1])).rows[0];
ok('recalcular vuelve a sumar las líneas', Number(f1b.subtotal) === 510000.5 && Number(f1b.neto) === 459000.45, JSON.stringify(f1b));
await c.query(`update facturas set estado = 'P' where id = $1`, [id1]);
ok('una factura pagada no se recalcula', /pagada o anulada/.test(await falla(DIGI, `select factura_recalcular(${id1})`)));

// ── Permisos ──────────────────────────────────────────────────────────────
ok('un digitador puede leer facturas', (await como(DIGI, () => c.query(`select * from facturas`))).rows.length === 2);
ok('un usuario sin rol no ve facturas', (await como(NADIE, () => c.query(`select * from facturas`))).rows.length === 0);
ok('un digitador NO puede borrar facturas', (await como(DIGI, () => c.query(`delete from facturas where id = ${id2}`))).rowCount === 0);
ok('un digitador NO puede crear empresas aseguradoras', /row-level security/.test(await falla(DIGI, `insert into facturas_empresas(aseg_id, nombre, nit) values (1, 'X', '860.009.578-6')`)));
await como(ADMIN, () => c.query(`insert into facturas_empresas(aseg_id, nombre, nit) values (1, 'SEGUROS DEL ESTADO S.A. (Generales)', '860.009.578-6')`), true);
ok('el administrador crea empresas y el NIT se normaliza', (await c.query(`select nit_norm from facturas_empresas`)).rows[0].nit_norm === '8600095786');
ok('el mismo NIT no se repite aunque cambie el formato', /duplicate key|unique/.test(await falla(ADMIN, `insert into facturas_empresas(aseg_id, nombre, nit) values (1, 'OTRA', '860009578-6')`)));
ok('el administrador sí puede borrar facturas', (await como(ADMIN, () => c.query(`delete from facturas where id = ${id2}`))).rowCount === 1);
const huerfana = (await como(ADMIN, () => c.query(`delete from facturas where id = ${id2} returning 1`), true)).rowCount;
const l5 = (await c.query(`select idfactura from abonos_poliza where id = 5`)).rows[0];
ok('al borrar una factura sus líneas quedan libres (idfactura nulo)', huerfana === 1 && l5.idfactura === null, JSON.stringify(l5));

console.log(`\nRESULTADO: ${pass} bien, ${fail} mal`);
await c.end();
await server.stop();
process.exit(fail ? 1 : 0);
