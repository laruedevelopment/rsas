"""
Genera el SQL para cargar las facturas y las empresas aseguradoras del software
anterior (FACTURAS.csv y EMPRESA.csv) en las tablas facturas y facturas_empresas.

Uso:
    python generar_importacion_facturas.py <carpeta_con_los_CSV> <carpeta_de_salida>

Deja en la carpeta de salida (NO en el repositorio: son datos del negocio):
    0_verificar.sql  revisa SIN CAMBIAR NADA que los códigos coincidan con la base y no se dupliquen
    1_empresas.sql   las empresas aseguradoras (por NIT), con su IVA
    2_facturas.sql   las facturas, con sus códigos originales (los que usan los abonos)
    3_cierre.sql     ajusta los consecutivos y revisa que cuadre todo

Cada archivo se pega en el SQL Editor de Supabase y se ejecuta, en orden y primero
en PRUEBAS. Los tres se pueden correr otra vez sin duplicar nada.

Reglas de la conversión:
  * Se conserva el valor a consignar (Vlrneto) tal como estaba. Si difiere de
    total − retención − ICA por la mitad del IVA, la factura queda con retención
    de IVA del 50 %.
  * Los códigos de aseguradora, intermediario y empresa que ya no existan en la
    base se dejan en blanco (NULL) en vez de fallar.
  * Si una factura viene sin fecha (la 448), se usa su fecha de registro.
  * El usuario que la creó viene vacío en el software anterior: queda en blanco.
"""
import csv
import sys
from pathlib import Path

carpeta = Path(sys.argv[1])
salida = Path(sys.argv[2])
salida.mkdir(parents=True, exist_ok=True)


def leer(nombre):
    with open(carpeta / nombre, encoding='latin-1', newline='') as f:
        return list(csv.DictReader(f))


def sql_txt(v):
    v = (v or '').strip()
    return 'null' if v == '' else "'" + v.replace("'", "''") + "'"


def sql_num(v):
    v = (v or '').strip()
    return 'null' if v == '' else repr(float(v)) if '.' in v or 'e' in v.lower() else str(int(v))


def entero(v):
    v = (v or '').strip()
    return int(float(v)) if v else 0


# ── Empresas ────────────────────────────────────────────────────────────────
empresas = leer('EMPRESA.csv')
vistos = {}
filas_emp = []
for e in empresas:
    cod = entero(e['Codigo'])
    nit = e['Nit'].strip().replace('NIT', '').strip()
    clave = ''.join(ch for ch in nit if ch.isdigit())
    if clave in vistos:
        print(f'AVISO: la empresa {cod} repite el NIT {nit} de la {vistos[clave]}; se omite.')
        continue
    vistos[clave] = cod
    filas_emp.append((cod, entero(e['Codaseg']), e['Nombre'].strip(), nit, float(e['Porciva'] or 0)))

with open(salida / '1_empresas.sql', 'w', encoding='utf-8') as f:
    f.write('-- Empresas aseguradoras del software anterior (por NIT).\n')
    f.write('-- Se puede correr otra vez: actualiza lo que ya exista con el mismo código.\n\n')
    f.write('insert into facturas_empresas (id, aseg_id, nombre, nit, iva_pct, activa)\noverriding system value\nvalues\n')
    vals = []
    for cod, aseg, nombre, nit, iva in filas_emp:
        vals.append(
            f"  ({cod}, (select id from aseguradoras where id = {aseg}), {sql_txt(nombre)}, {sql_txt(nit)}, {iva}, true)"
        )
    f.write(',\n'.join(vals))
    f.write('\non conflict (id) do update\n  set aseg_id = excluded.aseg_id, nombre = excluded.nombre, nit = excluded.nit, iva_pct = excluded.iva_pct;\n')

# ── Facturas ────────────────────────────────────────────────────────────────
facturas = leer('FACTURAS.csv')
facturas.sort(key=lambda r: entero(r['Codigo']))
codigos_empresa = {c for c, *_ in filas_emp}

columnas = (
    'id, prefijo, num_factura, fecha, aseg_id, interm_id, empresa_id, observacion, subtotal, iva_pct, iva, '
    'retefuente_pct, retefuente, ica_pct, ica, reteiva_pct, reteiva, total, neto, estado, usuario_id, fcreado, fultmod'
)

n_reteiva = 0
lineas = []
for r in facturas:
    sub = float(r['Subtotal'] or 0)
    iva = float(r['Iva'] or 0)
    total = float(r['Vlrtotal'] or 0)
    rete = float(r['Retefuente'] or 0)
    ica = float(r['Ica'] or 0)
    neto = float(r['Vlrneto'] or 0)
    residuo = total - rete - ica - neto
    reteiva_pct, reteiva = 0.0, 0.0
    if iva and abs(residuo - iva / 2) < 0.5:
        reteiva_pct, reteiva = 50.0, iva / 2
        n_reteiva += 1
    emp = entero(r['Codempaseg'])
    emp_sql = f'(select id from facturas_empresas where id = {emp})' if emp in codigos_empresa else 'null'
    estado = (r['Estado'] or 'A').strip().upper()
    if estado not in ('A', 'C', 'R', 'P', 'N'):
        estado = 'A'
    registro = f"{r['Fechareg'].strip()} {r['Horareg'].strip() or '00:00'}"
    lineas.append(
        '  ('
        + ', '.join([
            str(entero(r['Codigo'])),
            str(entero(r['Prefnumfactura']) or 1),
            str(entero(r['Numfactura'])),
            sql_txt((r['Fecha'] or '').strip() or r['Fechareg']),
            f"(select id from aseguradoras where id = {entero(r['Codaseg'])})",
            f"(select id from intermediarios where id = {entero(r['Codinterm'])})",
            emp_sql,
            sql_txt(r['Observacion']),
            repr(sub), repr(float(r['Porciva'] or 0)), repr(iva),
            repr(float(r['Porcretefuente'] or 0)), repr(rete),
            repr(float(r['Porcica'] or 0)), repr(ica),
            repr(reteiva_pct), repr(reteiva),
            repr(total), repr(neto),
            sql_txt(estado), 'null',
            f"'{registro}-05'::timestamptz", f"'{registro}-05'::timestamptz",
        ])
        + ')'
    )

with open(salida / '2_facturas.sql', 'w', encoding='utf-8') as f:
    f.write('-- Facturas del software anterior, con sus códigos originales.\n')
    f.write('-- Se puede correr otra vez: actualiza las que ya existan con el mismo código.\n\n')
    # Tandas de 400 para que el editor no se ahogue con una sola instrucción enorme.
    for i in range(0, len(lineas), 400):
        f.write(f'insert into facturas ({columnas})\noverriding system value\nvalues\n')
        f.write(',\n'.join(lineas[i:i + 400]))
        f.write(
            '\non conflict (id) do update set\n'
            '  prefijo = excluded.prefijo, num_factura = excluded.num_factura, fecha = excluded.fecha,\n'
            '  aseg_id = excluded.aseg_id, interm_id = excluded.interm_id, empresa_id = excluded.empresa_id,\n'
            '  observacion = excluded.observacion, subtotal = excluded.subtotal, iva_pct = excluded.iva_pct,\n'
            '  iva = excluded.iva, retefuente_pct = excluded.retefuente_pct, retefuente = excluded.retefuente,\n'
            '  ica_pct = excluded.ica_pct, ica = excluded.ica, reteiva_pct = excluded.reteiva_pct,\n'
            '  reteiva = excluded.reteiva, total = excluded.total, neto = excluded.neto, estado = excluded.estado;\n\n'
        )

total_facturas = len(lineas)
with open(salida / '3_cierre.sql', 'w', encoding='utf-8') as f:
    f.write('-- Cierre: consecutivos y revisión. Debe devolver una sola fila, todo en "ok".\n\n')
    f.write("select setval(pg_get_serial_sequence('facturas', 'id'), (select max(id) from facturas));\n")
    f.write("select setval(pg_get_serial_sequence('facturas_empresas', 'id'), (select max(id) from facturas_empresas));\n\n")
    f.write(
        'select\n'
        f"  (select count(*) from facturas) as facturas_cargadas,  -- deben ser al menos {total_facturas}\n"
        f"  case when (select count(*) from facturas) >= {total_facturas} then 'ok' else 'REVISAR' end as cantidad,\n"
        "  (select count(*) from facturas_empresas) as empresas,\n"
        "  (select count(*) from abonos_poliza ab where ab.idfactura is not null\n"
        "      and not exists (select 1 from facturas fa where fa.id = ab.idfactura)) as abonos_con_factura_inexistente,\n"
        "  (select factura_prefijo_vigente()) as prefijo_vigente,\n"
        "  (select max(num_factura) from facturas where prefijo = (select factura_prefijo_vigente())) as ultimo_numero;\n"
    )


# ── Verificación previa (solo lee) ──────────────────────────────────────────
def nombres(archivo):
    return {entero(r['Codigo']): ' '.join(r['Nombre'].split()) for r in leer(archivo)}


aseg_antiguas = nombres('ASEGURADORAS.csv')
interm_antiguos = nombres('INTERMEDIARIOS.csv')
aseg_usadas = sorted({entero(r['Codaseg']) for r in facturas} | {a for _, a, *_ in filas_emp})
interm_usados = sorted({entero(r['Codinterm']) for r in facturas})
codigos_factura = sorted(entero(r['Codigo']) for r in facturas)


def valores(pares):
    return ',\n  '.join(f"({c}, {sql_txt(n)})" for c, n in pares)


with open(salida / '0_verificar.sql', 'w', encoding='utf-8') as f:
    f.write('-- VERIFICACIÓN: solo lee, no cambia nada. Correrla ANTES de los otros archivos.\n')
    f.write('-- Compara los códigos del software anterior con los que ya hay en la base.\n')
    f.write('-- Devuelve una tabla: lo que diga DIFERENTE o NO EXISTE hay que revisarlo.\n\n')
    f.write('with\n')
    f.write('aseg_ant(cod, nombre) as (values\n  ' + valores([(c, aseg_antiguas.get(c, '(sin nombre)')) for c in aseg_usadas]) + '\n),\n')
    f.write('interm_ant(cod, nombre) as (values\n  ' + valores([(c, interm_antiguos.get(c, '(sin nombre)')) for c in interm_usados]) + '\n),\n')
    f.write('fact_ant(cod) as (values\n  ' + ',\n  '.join(f'({c})' for c in codigos_factura) + '\n)\n')
    f.write(
        "select 'aseguradora' as revisar, o.cod::text as codigo, o.nombre as software_anterior, a.nombre_aseg as base_actual,\n"
        "       case when a.id is null then 'NO EXISTE'\n"
        "            when upper(btrim(a.nombre_aseg)) = upper(btrim(o.nombre)) then 'coincide'\n"
        "            else 'DIFERENTE' end as resultado\n"
        "  from aseg_ant o left join aseguradoras a on a.id = o.cod\n"
        "union all\n"
        "select 'intermediario', o.cod::text, o.nombre, i.nombre_interm,\n"
        "       case when i.id is null then 'NO EXISTE'\n"
        "            when upper(btrim(i.nombre_interm)) = upper(btrim(o.nombre)) then 'coincide'\n"
        "            else 'DIFERENTE' end\n"
        "  from interm_ant o left join intermediarios i on i.id = o.cod\n"
        "union all\n"
        "select 'facturas ya cargadas en la base (deben ser 0)', count(*)::text, '', '',\n"
        "       case when count(*) = 0 then 'coincide' else 'REVISAR: ya hay facturas' end\n"
        "  from facturas\n"
        "union all\n"
        "select 'abonos con factura que NO viene en el archivo (deben ser 0)', count(*)::text, '', '',\n"
        "       case when count(*) = 0 then 'coincide' else 'REVISAR: quedarían enlaces rotos' end\n"
        "  from abonos_poliza ab\n"
        "  where ab.idfactura is not null and ab.idfactura not in (select cod from fact_ant)\n"
        "union all\n"
        "select 'abonos enlazados a una factura', count(*)::text, count(distinct idfactura)::text || ' facturas distintas', '', 'informativo'\n"
        "  from abonos_poliza where idfactura is not null\n"
        "union all\n"
        "select 'empresas ya cargadas en la base (deben ser 0)', count(*)::text, '', '',\n"
        "       case when count(*) = 0 then 'coincide' else 'REVISAR: ya hay empresas' end\n"
        "  from facturas_empresas\n"
        "order by 1, 2;\n"
    )

print(f'Empresas: {len(filas_emp)} | Facturas: {total_facturas} | con retención de IVA 50 %: {n_reteiva}')
print(f'Archivos en: {salida}')
