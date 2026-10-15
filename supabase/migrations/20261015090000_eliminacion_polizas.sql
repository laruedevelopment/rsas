-- Eliminación de pólizas con autorización del Administrador.
--
-- Cualquier usuario activo puede MARCAR pólizas para eliminar (con motivo). Las
-- marcadas desaparecen de TODA la app (listas, búsquedas, estadísticas,
-- dashboards, duplicados) porque la base deja de mostrarlas: no es un filtro de
-- pantalla, es un permiso por fila (RLS), así que tampoco las ve nadie por la
-- API. Un Administrador revisa la bandeja y las AUTORIZA (se borran de verdad,
-- quedando una copia en el registro) o las RECHAZA (vuelven a aparecer).
--
-- Reglas que garantiza la base (no la pantalla):
--  * Nadie borra pólizas directamente por la API: el borrado solo ocurre al
--    autorizar (con copia en el registro). Antes cualquier usuario activo podía.
--  * No se marca ni se borra una póliza con pagos registrados (ni anulados):
--    primero se mueven los pagos a la póliza correcta.
--  * No se pueden registrar pagos en una póliza marcada.
--  * Máximo 500 pólizas pendientes por usuario y 200 por llamada.
--
-- Idempotente. NO borra ni cambia pólizas existentes. Se ejecuta como UNA sola
-- transacción: si algo no cuadra (por ejemplo, otra política sobre `polizas`),
-- no se aplica nada. Correr en el SQL Editor, primero en PRUEBAS y luego en
-- PRODUCCIÓN. Después publicar la app y pedir a los usuarios que recarguen.
--
-- IMPORTANTE: este archivo reemplaza la política de acceso a `polizas` y cierra
-- `polizas_eliminacion`. Si algún día se vuelve a correr el bucle de
-- "app_authenticated_full_access" de lib/migracion_2026_09_seguridad_y_pagos.sql
-- (o lib/fix_rls_seguridad.sql), esa política, más permisiva, se suma: las
-- pólizas marcadas reaparecerían y `polizas_eliminacion` quedaría abierta.
-- En ese caso volver a correr ESTE archivo.
-- Para deshacer: supabase/rollback/20261015090000_eliminacion_polizas_rollback.sql

begin;

-- ═══ A. Marca en la póliza ═════════════════════════════════════════════════
alter table polizas add column if not exists eliminada_en timestamptz;

create index if not exists idx_polizas_eliminada_en
  on polizas (eliminada_en) where eliminada_en is not null;

-- ═══ B. Registro de solicitudes (y copia de lo borrado) ════════════════════
create table if not exists polizas_eliminacion (
  id               bigint generated always as identity primary key,
  poliza_id        bigint not null,           -- sin FK: la póliza puede borrarse
  estado           text   not null default 'pendiente'
                     check (estado in ('pendiente', 'aprobada', 'rechazada')),
  -- Motivo: al menos 5 caracteres que no sean espacios, saltos ni tabs.
  motivo           text   not null
                     check (length(regexp_replace(motivo, '[\s ]', '', 'g')) >= 5
                            and length(motivo) <= 500),
  lote             uuid   not null,           -- solicitudes hechas juntas
  solicitado_por   bigint,
  solicitado_en    timestamptz not null default now(),
  resuelto_por     bigint,
  resuelto_en      timestamptz,
  nota_resolucion  text check (nota_resolucion is null or length(nota_resolucion) <= 500),
  snapshot         jsonb                      -- copia de la fila al aprobar
);

-- Una sola solicitud pendiente por póliza.
create unique index if not exists polizas_eliminacion_una_pendiente
  on polizas_eliminacion (poliza_id) where estado = 'pendiente';
create index if not exists polizas_eliminacion_estado_idx
  on polizas_eliminacion (estado, solicitado_en desc);
create index if not exists polizas_eliminacion_solicitante_idx
  on polizas_eliminacion (solicitado_por) where estado = 'pendiente';

-- RLS activo y SIN políticas, y sin permisos de tabla: solo se toca por las
-- funciones de abajo (defensa en profundidad: aunque aparezca una política
-- permisiva por error, los permisos de tabla siguen cerrados).
alter table polizas_eliminacion enable row level security;
drop policy if exists app_authenticated_full_access on polizas_eliminacion;
revoke all on polizas_eliminacion from anon, authenticated;

-- ═══ C. La base oculta las marcadas (RLS) ══════════════════════════════════
alter table polizas enable row level security;

drop policy if exists app_authenticated_full_access on polizas;
drop policy if exists polizas_lectura on polizas;
drop policy if exists polizas_insercion on polizas;
drop policy if exists polizas_edicion on polizas;
drop policy if exists polizas_borrado on polizas;

-- Ver y editar solo pólizas NO marcadas. Insertar sigue igual.
create policy polizas_lectura on polizas for select to authenticated
  using ((select app_rol()) is not null and eliminada_en is null);

create policy polizas_insercion on polizas for insert to authenticated
  with check ((select app_rol()) is not null);

create policy polizas_edicion on polizas for update to authenticated
  using ((select app_rol()) is not null and eliminada_en is null)
  with check ((select app_rol()) is not null);

-- SIN política de borrado y sin permiso DELETE: nadie borra pólizas por la API.
-- El borrado ocurre únicamente en polizas_eliminacion_resolver (security
-- definer), que además guarda la copia y exige un Administrador.
revoke delete on polizas from anon, authenticated;

-- Nadie puede poner o quitar la marca directamente por la API: solo las
-- funciones de abajo (que activan app.eliminacion dentro de su transacción y se
-- ejecutan con el rol dueño, no con el del usuario de la app).
create or replace function polizas_marca_eliminacion_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if coalesce(current_setting('app.eliminacion', true), '') = '1'
     and current_user not in ('authenticated', 'anon', 'authenticator') then
    return new;
  end if;
  if (tg_op = 'INSERT' and new.eliminada_en is not null)
     or (tg_op = 'UPDATE' and new.eliminada_en is distinct from old.eliminada_en) then
    raise exception 'La marca de eliminación solo se cambia desde la función de eliminación de pólizas.'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_polizas_marca_eliminacion_guard on polizas;
create trigger trg_polizas_marca_eliminacion_guard
  before insert or update on polizas
  for each row execute function polizas_marca_eliminacion_guard();

-- ═══ D. No se registran pagos en una póliza marcada ════════════════════════
create or replace function abonos_no_en_poliza_marcada()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.id_poliza is not null
     and exists (select 1 from polizas where id = new.id_poliza and eliminada_en is not null) then
    raise exception 'La póliza fue marcada para eliminar: no se pueden registrar pagos en ella.'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_abonos_no_en_poliza_marcada on abonos_poliza;
create trigger trg_abonos_no_en_poliza_marcada
  before insert or update of id_poliza on abonos_poliza
  for each row execute function abonos_no_en_poliza_marcada();

-- ═══ E. Funciones (todas validan el rol ADENTRO) ═══════════════════════════

-- E1. Marcar pólizas para eliminar. Cualquier usuario activo.
--     No marca las que tienen pagos registrados (se mueven antes) ni las que
--     ya están marcadas. Máximo 200 por llamada y 500 pendientes por usuario.
create or replace function polizas_eliminacion_solicitar(p_ids bigint[], p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ids bigint[];
  v_id bigint;
  v_motivo text := btrim(coalesce(p_motivo, ''), E' \t\r\n ');
  v_lote uuid := gen_random_uuid();
  v_uid bigint := app_usuario_id();
  v_ok int := 0;
  v_pendientes int;
  v_omitidas jsonb := '[]'::jsonb;
begin
  if app_rol() is null then
    raise exception 'No tiene permiso para esta acción.' using errcode = 'P0001';
  end if;
  if length(v_motivo) < 5 then
    raise exception 'Escriba el motivo de la eliminación (mínimo 5 caracteres).' using errcode = 'P0001';
  end if;
  if length(v_motivo) > 500 then
    raise exception 'El motivo es demasiado largo (máximo 500 caracteres).' using errcode = 'P0001';
  end if;
  select coalesce(array_agg(distinct x), '{}') into v_ids from unnest(coalesce(p_ids, '{}')) x where x is not null;
  if cardinality(v_ids) = 0 then
    raise exception 'No hay pólizas seleccionadas.' using errcode = 'P0001';
  end if;
  if cardinality(v_ids) > 200 then
    raise exception 'Seleccione como máximo 200 pólizas por vez.' using errcode = 'P0001';
  end if;
  select count(*) into v_pendientes from polizas_eliminacion
   where estado = 'pendiente' and solicitado_por = v_uid;
  if v_pendientes + cardinality(v_ids) > 500 then
    raise exception 'Tiene % pólizas pendientes de autorización. Espere a que un administrador las resuelva antes de enviar más.', v_pendientes
      using errcode = 'P0001';
  end if;

  foreach v_id in array v_ids loop
    perform 1 from polizas where id = v_id and eliminada_en is null for update;
    if not found then
      v_omitidas := v_omitidas || jsonb_build_object('id', v_id,
        'razon', 'No existe o ya está marcada para eliminar.');
      continue;
    end if;
    -- Mismo criterio que al autorizar: cualquier pago (incluso anulado) lo impide.
    if exists (select 1 from abonos_poliza where id_poliza = v_id) then
      v_omitidas := v_omitidas || jsonb_build_object('id', v_id,
        'razon', 'Tiene pagos registrados: primero muévalos a la póliza correcta (Editar abono → Cambiar póliza) y luego elimínela.');
      continue;
    end if;

    perform set_config('app.eliminacion', '1', true);
    update polizas set eliminada_en = now() where id = v_id;
    perform set_config('app.eliminacion', '', true);

    insert into polizas_eliminacion (poliza_id, motivo, lote, solicitado_por)
    values (v_id, v_motivo, v_lote, v_uid);
    v_ok := v_ok + 1;
  end loop;

  return jsonb_build_object('lote', v_lote, 'solicitadas', v_ok, 'omitidas', v_omitidas);
end;
$$;

-- E2. Bandeja del Administrador: solicitudes pendientes con datos de la póliza.
create or replace function polizas_eliminacion_pendientes()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if app_rol() is distinct from 'A' then
    raise exception 'Solo un Administrador puede ver las eliminaciones por autorizar.' using errcode = 'P0001';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', e.id,
      'poliza_id', e.poliza_id,
      'lote', e.lote,
      'motivo', e.motivo,
      'solicitado_en', e.solicitado_en,
      'solicitado_por', coalesce(u.apodo_usuario, '—'),
      'nro_poliza', p.nro_poliza,
      'cliente', c.nombre_cliente,
      'aseguradora', a.nombre_aseg,
      'ramo', r.nombre_ramo,
      'prima', p.prima_poliza,
      'fini', p.fini_poliza,
      'ffin', p.ffin_poliza,
      'estado_poliza', p.estado_poliza_id,
      'n_pagos', (select count(*) from abonos_poliza ab where ab.id_poliza = e.poliza_id)
    ) order by e.solicitado_en desc, e.id desc)
    from polizas_eliminacion e
    left join polizas p      on p.id = e.poliza_id
    left join clientes c     on c.id = p.cliente_id
    left join aseguradoras a on a.id = p.aseg_id
    left join ramos r        on r.id = p.ramo_id
    left join usuarios u     on u.id = e.solicitado_por
    where e.estado = 'pendiente'
  ), '[]'::jsonb);
end;
$$;

-- E3. Cuántas hay por autorizar (para el contador). Para no-administradores: 0.
create or replace function polizas_eliminacion_contar()
returns int
language sql
security definer
set search_path = public
stable
as $$
  select case when app_rol() = 'A'
              then (select count(*)::int from polizas_eliminacion where estado = 'pendiente')
              else 0 end;
$$;

-- E4. Historial (aprobadas y rechazadas). Solo Administrador.
create or replace function polizas_eliminacion_historial(p_limite int default 100)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if app_rol() is distinct from 'A' then
    raise exception 'Solo un Administrador puede ver el historial.' using errcode = 'P0001';
  end if;
  return coalesce((
    select jsonb_agg(t.fila order by t.orden desc)
    from (
      select e.resuelto_en as orden, jsonb_build_object(
        'id', e.id,
        'poliza_id', e.poliza_id,
        'estado', e.estado,
        'motivo', e.motivo,
        'nota', e.nota_resolucion,
        'solicitado_en', e.solicitado_en,
        'solicitado_por', coalesce(us.apodo_usuario, '—'),
        'resuelto_en', e.resuelto_en,
        'resuelto_por', coalesce(ur.apodo_usuario, '—'),
        'nro_poliza', coalesce(e.snapshot ->> 'nro_poliza', p.nro_poliza),
        'prima', coalesce((e.snapshot ->> 'prima_poliza')::numeric, p.prima_poliza)
      ) as fila
      from polizas_eliminacion e
      left join polizas p  on p.id = e.poliza_id
      left join usuarios us on us.id = e.solicitado_por
      left join usuarios ur on ur.id = e.resuelto_por
      where e.estado in ('aprobada', 'rechazada')
      order by e.resuelto_en desc nulls last
      limit greatest(1, least(coalesce(p_limite, 100), 500))
    ) t
  ), '[]'::jsonb);
end;
$$;

-- E5. Autorizar (se borran de verdad, con copia) o rechazar (reaparecen).
--     p_ids son ids de SOLICITUD (polizas_eliminacion.id). Solo Administrador.
create or replace function polizas_eliminacion_resolver(p_ids bigint[], p_accion text, p_nota text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid bigint := app_usuario_id();
  v_nota text := left(nullif(btrim(coalesce(p_nota, ''), E' \t\r\n '), ''), 500);
  v_ids bigint[];
  v_sol polizas_eliminacion%rowtype;
  v_pol polizas%rowtype;
  v_ok int := 0;
  v_borradas int;
  v_omitidas jsonb := '[]'::jsonb;
  v_id bigint;
begin
  if app_rol() is distinct from 'A' then
    raise exception 'Solo un Administrador puede autorizar o rechazar eliminaciones.' using errcode = 'P0001';
  end if;
  if p_accion is null or p_accion not in ('aprobar', 'rechazar') then
    raise exception 'Acción no válida.' using errcode = 'P0001';
  end if;
  select coalesce(array_agg(distinct x), '{}') into v_ids from unnest(coalesce(p_ids, '{}')) x where x is not null;
  if cardinality(v_ids) = 0 then
    raise exception 'No hay solicitudes seleccionadas.' using errcode = 'P0001';
  end if;
  if cardinality(v_ids) > 200 then
    raise exception 'Seleccione como máximo 200 solicitudes por vez.' using errcode = 'P0001';
  end if;

  foreach v_id in array v_ids loop
    select * into v_sol from polizas_eliminacion where id = v_id and estado = 'pendiente' for update;
    if not found then
      v_omitidas := v_omitidas || jsonb_build_object('id', v_id, 'razon', 'La solicitud ya fue resuelta o no existe.');
      continue;
    end if;

    if p_accion = 'rechazar' then
      perform set_config('app.eliminacion', '1', true);
      update polizas set eliminada_en = null where id = v_sol.poliza_id;
      perform set_config('app.eliminacion', '', true);
      update polizas_eliminacion
         set estado = 'rechazada', resuelto_por = v_uid, resuelto_en = now(), nota_resolucion = v_nota
       where id = v_sol.id;
      v_ok := v_ok + 1;
      continue;
    end if;

    -- aprobar. Se bloquea la póliza antes de mirar los pagos (un pago que
    -- entre a la vez no se cuela entre la revisión y el borrado).
    select * into v_pol from polizas where id = v_sol.poliza_id for update;
    if not found then
      -- Ya no existe (se borró por otro medio): se cierra la solicitud sin copia.
      update polizas_eliminacion
         set estado = 'aprobada', resuelto_por = v_uid, resuelto_en = now(),
             nota_resolucion = coalesce(v_nota || ' · ', '') || 'La póliza ya no existía al autorizar.'
       where id = v_sol.id;
      v_ok := v_ok + 1;
      continue;
    end if;
    if exists (select 1 from abonos_poliza where id_poliza = v_sol.poliza_id) then
      v_omitidas := v_omitidas || jsonb_build_object('id', v_id,
        'razon', 'Tiene pagos registrados (aunque estén anulados): primero hay que moverlos a la póliza correcta, o rechazar la solicitud para restaurarla.');
      continue;
    end if;
    begin
      delete from polizas where id = v_sol.poliza_id;
      get diagnostics v_borradas = row_count;
      if v_borradas <> 1 then
        raise exception 'No se borró ninguna fila';
      end if;
      update polizas_eliminacion
         set estado = 'aprobada', resuelto_por = v_uid, resuelto_en = now(),
             nota_resolucion = v_nota, snapshot = to_jsonb(v_pol)
       where id = v_sol.id;
      v_ok := v_ok + 1;
    exception when others then
      raise warning 'polizas_eliminacion_resolver: póliza % no se pudo borrar (%: %)', v_sol.poliza_id, sqlstate, sqlerrm;
      v_omitidas := v_omitidas || jsonb_build_object('id', v_id,
        'razon', 'No se pudo borrar: la póliza tiene datos relacionados. Avise a soporte.');
    end;
  end loop;

  return jsonb_build_object('resueltas', v_ok, 'omitidas', v_omitidas);
end;
$$;

-- ═══ F. Permisos de ejecución ══════════════════════════════════════════════
revoke all on function polizas_eliminacion_solicitar(bigint[], text) from public, anon;
revoke all on function polizas_eliminacion_pendientes() from public, anon;
revoke all on function polizas_eliminacion_contar() from public, anon;
revoke all on function polizas_eliminacion_historial(int) from public, anon;
revoke all on function polizas_eliminacion_resolver(bigint[], text, text) from public, anon;
revoke all on function abonos_no_en_poliza_marcada() from public, anon, authenticated;
grant execute on function polizas_eliminacion_solicitar(bigint[], text) to authenticated;
grant execute on function polizas_eliminacion_pendientes() to authenticated;
grant execute on function polizas_eliminacion_contar() to authenticated;
grant execute on function polizas_eliminacion_historial(int) to authenticated;
grant execute on function polizas_eliminacion_resolver(bigint[], text, text) to authenticated;

-- ═══ G. Guarda: si hay otras políticas sobre estas tablas, NO se aplica nada ═
-- (una política permisiva extra dejaría ver las pólizas marcadas). Si falla,
-- la transacción completa se deshace; revise las políticas que muestra el
-- error y avise antes de continuar.
do $$
declare
  v_extra text;
begin
  select string_agg(policyname, ', ') into v_extra
    from pg_policies
   where schemaname = 'public' and tablename = 'polizas'
     and policyname not in ('polizas_lectura', 'polizas_insercion', 'polizas_edicion');
  if v_extra is not null then
    raise exception 'La tabla polizas tiene políticas adicionales (%): revíselas antes de aplicar esta migración.', v_extra;
  end if;
  select string_agg(policyname, ', ') into v_extra
    from pg_policies where schemaname = 'public' and tablename = 'polizas_eliminacion';
  if v_extra is not null then
    raise exception 'polizas_eliminacion no debe tener políticas (%).', v_extra;
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.polizas'::regclass) then
    raise exception 'La seguridad por fila (RLS) no quedó activa en polizas.';
  end if;
end $$;

commit;

-- ═══ Verificación ══════════════════════════════════════════════════════════
-- Debe devolver: 0 marcadas, 5 funciones, rls_activa = true, 3 políticas
-- (lectura, inserción, edición) y 0 de borrado.
select (select count(*) from polizas where eliminada_en is not null) as marcadas,
       (select count(*) from pg_proc where proname like 'polizas_eliminacion_%'
          and pronamespace = 'public'::regnamespace) as funciones,
       (select relrowsecurity from pg_class where oid = 'public.polizas'::regclass) as rls_activa,
       (select count(*) from pg_policies where schemaname = 'public' and tablename = 'polizas') as politicas_polizas,
       (select count(*) from pg_policies where schemaname = 'public' and tablename = 'polizas'
          and cmd = 'DELETE') as politicas_borrado;
