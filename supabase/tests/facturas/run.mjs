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
const MIGRACION2 = path.join(AQUI, '../../migrations/20261111100000_facturas_ajustes_digitador.sql');
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
const sql2 = fs.readFileSync(MIGRACION2, 'utf8');
await c.query(sql2);
await c.query(sql2);
ok('la migración de ajustes para digitador corre dos veces sin error', true);

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
await como(DIGI, () => c.query(`select facturacion_config_guardar(5, 10, 0)`), true);
ok('un digitador SÍ cambia los porcentajes', Number((await c.query(`select valor from facturacion_config where clave='iva_pct'`)).rows[0].valor) === 5);
ok('un usuario sin rol NO cambia los porcentajes', /No tiene permiso/.test(await falla(NADIE, `select facturacion_config_guardar(1,1,1)`)));
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
ok('un usuario sin rol NO puede crear empresas aseguradoras', /row-level security/.test(await falla(NADIE, `insert into facturas_empresas(aseg_id, nombre, nit) values (1, 'X', '860.009.578-6')`)));
await como(DIGI, () => c.query(`insert into facturas_empresas(aseg_id, nombre, nit, iva_pct) values (1, 'EMPRESA DIGI', '900.111.222-3', 16)`), true);
ok('un digitador SÍ crea y edita empresas', (await como(DIGI, () => c.query(`update facturas_empresas set iva_pct = 0 where nit_norm = '9001112223' returning id`), true)).rows.length === 1);
ok('un digitador NO borra empresas', (await como(DIGI, () => c.query(`delete from facturas_empresas where nit_norm = '9001112223' returning id`), true)).rows.length === 0);
await c.query(`delete from facturas_empresas where nit_norm = '9001112223'`);
await como(ADMIN, () => c.query(`insert into facturas_empresas(aseg_id, nombre, nit) values (1, 'SEGUROS DEL ESTADO S.A. (Generales)', '860.009.578-6')`), true);
ok('el administrador crea empresas y el NIT se normaliza', (await c.query(`select nit_norm from facturas_empresas`)).rows[0].nit_norm === '8600095786');
ok('el mismo NIT no se repite aunque cambie el formato', /duplicate key|unique/.test(await falla(ADMIN, `insert into facturas_empresas(aseg_id, nombre, nit) values (1, 'OTRA', '860009578-6')`)));
ok('el administrador sí puede borrar facturas', (await como(ADMIN, () => c.query(`delete from facturas where id = ${id2}`))).rowCount === 1);
const huerfana = (await como(ADMIN, () => c.query(`delete from facturas where id = ${id2} returning 1`), true)).rowCount;
const l5 = (await c.query(`select idfactura from abonos_poliza where id = 5`)).rows[0];
ok('al borrar una factura sus líneas quedan libres (idfactura nulo)', huerfana === 1 && l5.idfactura === null, JSON.stringify(l5));

// ── Retención de IVA, IVA por empresa, subtotal y prefijo vigente ──────────
const m3 = (await c.query(`select * from factura_montos(672706.04, 16, 11, 0, 50)`)).rows[0];
ok('con retención de IVA 50 %: reproduce el valor a consignar de la factura 1413 (652.524,86)',
  Number(m3.iva) === 107632.97 && Number(m3.retefuente) === 73997.66 && Number(m3.reteiva) === 53816.49 && Math.abs(Number(m3.neto) - 652524.86) < 0.011, JSON.stringify(m3));

await como(ADMIN, () => c.query(`insert into facturas_empresas(aseg_id, nombre, nit, iva_pct) values (2, 'SOLIDARIA GENERALES', '860.524.654-6', 16)`), true);
const empresaIva = (await c.query(`select id from facturas_empresas where nit_norm = '8605246546'`)).rows[0].id;
const id3 = (await como(DIGI, () => c.query(`select factura_crear(2, 1, $1, null, array[5]) id`, [empresaIva]), true)).rows[0].id;
const f3 = (await c.query(`select * from facturas where id = $1`, [id3])).rows[0];
ok('el IVA de la factura parte del de la empresa elegida (16 %)', Number(f3.iva_pct) === 16 && Number(f3.iva) === 11200, JSON.stringify(f3));

await c.query(`insert into abonos_poliza(idrep_pago, vlrcomision, estado_pago) values (2, -93750, 'C')`);
const negativa = (await c.query(`select max(id) id from abonos_poliza`)).rows[0].id;
ok('un subtotal negativo o en cero se rechaza', /mayor que cero/.test(await falla(DIGI, `select factura_crear(2, 1, null, null, array[${negativa}])`)));

await c.query(`insert into facturas(prefijo, num_factura, fecha, aseg_id, estado) values (2, 2730, '2031-01-01', 1, 'A')`);
ok('el prefijo vigente es el de la última factura', (await como(DIGI, () => c.query(`select factura_prefijo_vigente() p`))).rows[0].p === 2);
ok('el siguiente número sigue esa serie (2731)', (await como(DIGI, () => c.query(`select factura_siguiente_numero() n`))).rows[0].n === 2731);
await c.query(`update abonos_poliza set vlrcomision = 80000 where id = ${negativa}`);
const id4 = (await como(DIGI, () => c.query(`select factura_crear(2, 1, null, null, array[${negativa}], null, 16, 10, 0, 50) id`), true)).rows[0].id;
const f4 = (await c.query(`select * from facturas where id = $1`, [id4])).rows[0];
ok('la factura nueva queda en el prefijo 2, número 2731', f4.prefijo === 2 && f4.num_factura === 2731, JSON.stringify(f4));
ok('guarda la retención de IVA y descuenta del valor a consignar', Number(f4.reteiva_pct) === 50 && Number(f4.reteiva) === 6400 && Number(f4.neto) === 80000 + 12800 - 8000 - 6400, JSON.stringify(f4));

// ── Quitar y agregar líneas ────────────────────────────────────────────────
ok('el modo "solo monto" no queda activo después de crear una factura',
  ((await c.query(`select current_setting('app.solo_monto', true) v`)).rows[0].v ?? '') === '');
// Factura id4 (aseg 2, línea negativa->80000). Se crea una línea libre más de la aseguradora 2.
await c.query(`insert into abonos_poliza(idrep_pago, vlrcomision, estado_pago) values (2, 20000, 'C')`);
const libreA = (await c.query(`select max(id) id from abonos_poliza`)).rows[0].id;
await c.query(`insert into abonos_poliza(idrep_pago, vlrcomision, estado_pago) values (1, 5000, 'C')`);
const libreOtra = (await c.query(`select max(id) id from abonos_poliza`)).rows[0].id; // aseguradora 1
ok('no deja agregar una línea de otra aseguradora', /otra aseguradora/.test(await falla(DIGI, `select factura_agregar_lineas(${id4}, array[${libreOtra}])`)));
const agregadas = (await como(DIGI, () => c.query(`select factura_agregar_lineas(${id4}, array[${libreA}]) n`), true)).rows[0].n;
const f4b = (await c.query(`select subtotal from facturas where id = ${id4}`)).rows[0];
ok('agregar líneas las enlaza y vuelve a sumar el subtotal', agregadas === 1 && Number(f4b.subtotal) === 100000, JSON.stringify(f4b));
ok('no deja agregar una línea que ya está en una factura', /ya está en otra factura/.test(await falla(DIGI, `select factura_agregar_lineas(${id4}, array[${libreA}])`)));
const quitadas = (await como(DIGI, () => c.query(`select factura_quitar_lineas(${id4}, array[${libreA}]) n`), true)).rows[0].n;
const f4c = (await c.query(`select subtotal from facturas where id = ${id4}`)).rows[0];
const libre = (await c.query(`select idfactura from abonos_poliza where id = ${libreA}`)).rows[0];
ok('quitar líneas las deja libres y vuelve a sumar', quitadas === 1 && libre.idfactura === null && Number(f4c.subtotal) === 80000, JSON.stringify([f4c, libre]));
ok('quitar una línea que no está en la factura se rechaza', /ya no están en la factura/.test(await falla(DIGI, `select factura_quitar_lineas(${id4}, array[${libreA}])`)));
await c.query(`update facturas set estado = 'N' where id = ${id4}`);
ok('una factura anulada no admite agregar ni quitar líneas', /pagada o anulada/.test(await falla(DIGI, `select factura_agregar_lineas(${id4}, array[${libreA}])`)) && /pagada o anulada/.test(await falla(DIGI, `select factura_quitar_lineas(${id4}, array[${libreA}])`)));
ok('un usuario sin rol no puede agregar líneas', /No tiene permiso/.test(await falla(NADIE, `select factura_agregar_lineas(${id4}, array[${libreA}])`)));
ok('el modo "solo monto" tampoco queda activo después de quitar o agregar',
  ((await c.query(`select current_setting('app.solo_monto', true) v`)).rows[0].v ?? '') === '');

console.log(`\nRESULTADO: ${pass} bien, ${fail} mal`);
await c.end();
await server.stop();
process.exit(fail ? 1 : 0);
