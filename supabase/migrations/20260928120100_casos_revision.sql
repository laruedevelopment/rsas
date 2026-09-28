-- ═══════════════════════════════════════════════════════════════════════════
-- "Casos por revisar": bandeja de situaciones dudosas que el equipo de
-- digitación debe aclarar (un pago sin póliza, una póliza que parece
-- duplicada, una comisión que no cuadra…). Cada caso dice qué se sabe, qué
-- hay que averiguar y a qué pólizas/reporte se refiere. Quien lo aclara
-- escribe la respuesta y lo marca como resuelto; queda quién y cuándo.
--
-- La app NO corrige nada sola: el caso solo registra la decisión. Las
-- correcciones (anular una póliza, mover un pago) se hacen aparte.
--
-- Permisos: todos los usuarios ven los casos y pueden resolverlos (solo
-- pueden cambiar estado y respuesta), menos los de comisiones, que solo ven
-- Administrador y S. Crear casos: Administrador y S. Borrar: solo
-- Administrador.
--
-- Se puede volver a correr sin problema. Correr primero en PRUEBAS y luego
-- en PRODUCCIÓN, por PASOS, en orden.
-- ═══════════════════════════════════════════════════════════════════════════


-- ── PASO 1: tabla, permisos y trigger ───────────────────────────────────────
create table if not exists public.casos_revision (
  id               bigint generated always as identity primary key,
  tipo             text not null default 'OTRO'
                   check (tipo in ('PAGO_SIN_POLIZA', 'POSIBLE_DUPLICADO', 'COMISION_RARA', 'OTRO')),
  titulo           text not null,
  descripcion      text not null,          -- lo que se sabe
  pregunta         text,                   -- lo que hay que averiguar
  polizas          bigint[] not null default '{}',
  reporte_id       bigint,
  abono_id         bigint,
  estado           text not null default 'P' check (estado in ('P', 'R')),  -- Pendiente / Resuelto
  respuesta        text,
  usuario_id       bigint constraint casos_revision_usuario_id_fkey references usuarios(id),
  usuario_resuelve bigint constraint casos_revision_usuario_resuelve_fkey references usuarios(id),
  fresuelto        timestamptz,
  fcreado          timestamptz not null default now(),
  fultmod          timestamptz not null default now(),
  constraint casos_revision_respuesta_al_resolver
    check (estado = 'P' or length(btrim(coalesce(respuesta, ''))) > 0)
);

create index if not exists casos_revision_estado_idx on public.casos_revision (estado, fcreado desc);

alter table public.casos_revision enable row level security;

drop policy if exists casos_lectura    on public.casos_revision;
drop policy if exists casos_crear      on public.casos_revision;
drop policy if exists casos_resolver   on public.casos_revision;
drop policy if exists casos_borrar     on public.casos_revision;
-- Los casos de comisiones solo los ven quienes ven comisiones (A y S).
create policy casos_lectura  on public.casos_revision for select to authenticated
  using ((select app_rol()) in ('A', 'S')
         or ((select app_rol()) is not null and tipo <> 'COMISION_RARA'));
create policy casos_crear    on public.casos_revision for insert to authenticated
  with check ((select app_rol()) in ('A', 'S'));
create policy casos_resolver on public.casos_revision for update to authenticated
  using ((select app_rol()) in ('A', 'S')
         or ((select app_rol()) is not null and tipo <> 'COMISION_RARA'))
  with check ((select app_rol()) is not null);
create policy casos_borrar   on public.casos_revision for delete to authenticated
  using ((select app_rol()) = 'A');

-- anon: nada. authenticated: al editar solo puede tocar estado y respuesta.
revoke all on public.casos_revision from anon, authenticated;
grant select, insert, delete on public.casos_revision to authenticated;
grant update (estado, respuesta) on public.casos_revision to authenticated;

-- Quién creó / quién resolvió y cuándo: lo pone la base, no la app.
create or replace function casos_revision_auditoria()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    new.usuario_id := coalesce(app_usuario_id(), new.usuario_id);
    return new;
  end if;
  new.fultmod := now();
  if new.estado = 'R' and old.estado is distinct from 'R' then
    new.usuario_resuelve := app_usuario_id();
    new.fresuelto := now();
  elsif new.estado = 'P' then
    new.usuario_resuelve := null;
    new.fresuelto := null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_casos_revision_auditoria on public.casos_revision;
create trigger trg_casos_revision_auditoria
  before insert or update on public.casos_revision
  for each row execute function casos_revision_auditoria();


-- ── PASO 2: casos iniciales ─────────────────────────────────────────────────
-- Cada uno se inserta solo si no existe (se puede volver a correr).

insert into public.casos_revision (tipo, titulo, descripcion, pregunta, polizas, reporte_id, abono_id)
select 'PAGO_SIN_POLIZA',
       'Pago de $373.950 cargado a la póliza 400-49-994000000228-0',
       'En el reporte #1418 de SOLIDARIA (10/06/2020) hay un pago del 29/05/2020 por $373.950 '
       || 'cargado a la póliza 400-49-994000000228-0 (cód. 21506, LILI PATRICIA SERRANO MANTILLA, '
       || 'SOLIARRIENDO, vigencia 01/09/2019 – 01/09/2020). Esa póliza tiene prima de $281.731 y ya '
       || 'se pagó completa el 04/09/2019 (reporte #1339). El pago de 2020 dice que la prima era '
       || '$373.950, y ninguna póliza registrada tiene esa prima.',
       'Revisar el reporte de SOLIDARIA del 10/06/2020: ¿a qué póliza corresponde este pago? '
       || 'Si es de una póliza que no se registró (anexo, modificación o renovación), registrarla y '
       || 'anotar aquí su número. Si fue un pago errado, anotarlo. IMPORTANTE: no mover el pago a otra '
       || 'póliza sin avisar al administrador (la 21506 tiene un ajuste interno que hay que corregir).',
       '{21506}', 1418, 18925
 where not exists (select 1 from public.casos_revision where abono_id = 18925 and tipo = 'PAGO_SIN_POLIZA');

insert into public.casos_revision (tipo, titulo, descripcion, pregunta, polizas)
select 'POSIBLE_DUPLICADO',
       'Póliza 0969019-9 registrada dos veces',
       'Las pólizas cód. 237 y cód. 332 tienen el mismo número (0969019-9), el mismo cliente, el '
       || 'mismo vehículo (TLO5496) y la misma vigencia (11/06/2009 – 19/05/2010), pero primas '
       || 'distintas: $1.889.754 (cód. 237) y $1.771.373 (cód. 332). Las dos tienen un pago '
       || 'registrado (reportes #20 y #321). La 237 tiene la nota "RENOVACION POLIZA, HOY 12 JULIO '
       || 'HICE CORRECCION…".',
       '¿Son la misma póliza? Si sí, indicar cuál es la correcta (la otra se anula) y si la '
       || 'comisión se cobró dos veces. Si no, explicar en qué se diferencian.',
       '{237,332}'
 where not exists (select 1 from public.casos_revision
                    where tipo = 'POSIBLE_DUPLICADO' and polizas @> '{237,332}');

-- Abonos cuya comisión es negativa o mayor que el abono (el % no se pudo
-- calcular, ver 20260928120000_porcentaje_comision_historico.sql).
insert into public.casos_revision (tipo, titulo, descripcion, pregunta, polizas, reporte_id, abono_id)
select 'COMISION_RARA',
       'Comisión que no cuadra en la póliza ' || coalesce(p.nro_poliza, a.id_poliza::text),
       'En el reporte #' || a.idrep_pago
       || coalesce(' (' || to_char(r.fecha_rep, 'DD/MM/YYYY') || ')', '')
       || ' la póliza ' || coalesce(p.nro_poliza, '') || ' (cód. ' || a.id_poliza || ') tiene un abono de $'
       || replace(to_char(a.vlrabono_prima, 'FM999,999,999,990'), ',', '.')
       || ' con una comisión de $'
       || replace(to_char(a.vlrcomision, 'FM999,999,999,990'), ',', '.')
       || ' (' || replace(to_char(round(a.vlrcomision / nullif(a.vlrabono_prima, 0) * 100, 2), 'FM999999990.00'), '.', ',')
       || ' %). Una comisión no debería ser negativa ni mayor que el abono.',
       'Revisar el reporte de la aseguradora: ¿el abono y la comisión están bien digitados? '
       || 'Anotar los valores correctos.',
       array[a.id_poliza], a.idrep_pago, a.id
  from abonos_poliza a
  left join polizas p on p.id = a.id_poliza
  left join reportes_pago r on r.id = a.idrep_pago
 where coalesce(a.porccomision, 0) = 0
   and coalesce(a.vlrabono_prima, 0) <> 0
   and coalesce(a.vlrcomision, 0) <> 0
   and a.vlrcomision / nullif(a.vlrabono_prima, 0) not between 0 and 1
   and not exists (select 1 from public.casos_revision c
                    where c.abono_id = a.id and c.tipo = 'COMISION_RARA');


-- ── PASO 3 (solo lectura): verificación ─────────────────────────────────────
select tipo, estado, count(*) as casos
  from public.casos_revision
 group by tipo, estado
 order by tipo;
