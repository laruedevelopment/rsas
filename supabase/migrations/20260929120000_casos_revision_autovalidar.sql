-- ═══════════════════════════════════════════════════════════════════════════
-- "Casos por revisar": cierre automático de los casos ya corregidos.
--
-- Cada vez que alguien abre la pantalla de Casos por revisar (o el menú
-- principal, para el contador), la app llama a casos_revision_revalidar().
-- Esa función mira los datos REALES de cada caso pendiente y, si la
-- situación ya no se cumple, lo marca como resuelto (con la respuesta
-- "Resuelto automáticamente…"). Nunca borra nada, nunca modifica abonos ni
-- pólizas, y nunca reabre un caso: solo pasa de Pendiente a Resuelto
-- cuando los datos lo demuestran. Se puede reabrir a mano como siempre.
--
--   COMISION_RARA    → sigue abierto mientras el abono exista y su comisión
--                      sea negativa o mayor que el abono (mismo criterio
--                      con que se crearon). Si se corrige el valor o el
--                      abono se elimina, se cierra.
--   PAGO_SIN_POLIZA  → sigue abierto mientras el abono exista y siga
--                      cargado a alguna de las pólizas del caso.
--   POSIBLE_DUPLICADO→ sigue abierto mientras al menos dos de las pólizas
--                      del caso existan con el mismo número en la misma
--                      aseguradora.
--   OTRO (y casos sin abono/pólizas para verificar) → solo a mano.
--
-- Se puede volver a correr sin problema. Correr primero en PRUEBAS y luego
-- en PRODUCCIÓN, por PASOS, en orden.
-- ═══════════════════════════════════════════════════════════════════════════


-- ── PASO 1: columna, trigger y funciones ────────────────────────────────────
alter table public.casos_revision
  add column if not exists auto_resuelto boolean not null default false;

-- Igual que antes, pero un cierre automático no se le atribuye a quien
-- tenía abierta la pantalla (usuario_resuelve queda vacío).
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
    new.usuario_resuelve := case when new.auto_resuelto then null else app_usuario_id() end;
    new.fresuelto := now();
  elsif new.estado = 'P' then
    new.usuario_resuelve := null;
    new.fresuelto := null;
    new.auto_resuelto := false;
  end if;
  return new;
end;
$$;

-- true = la situación del caso sigue sin corregirse (o no se puede
-- verificar); false = los datos demuestran que ya está corregida.
create or replace function casos_revision_sigue_abierto(c public.casos_revision)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case c.tipo
    when 'COMISION_RARA' then
      c.abono_id is null
      or exists (
        select 1 from abonos_poliza a
         where a.id = c.abono_id
           and coalesce(a.vlrabono_prima, 0) <> 0
           and coalesce(a.vlrcomision, 0) <> 0
           and a.vlrcomision / nullif(a.vlrabono_prima, 0) not between 0 and 1
      )
    when 'PAGO_SIN_POLIZA' then
      c.abono_id is null
      or cardinality(c.polizas) = 0
      or exists (
        select 1 from abonos_poliza a
         where a.id = c.abono_id
           and a.id_poliza = any (c.polizas)
      )
    when 'POSIBLE_DUPLICADO' then
      cardinality(c.polizas) < 2
      or exists (
        select 1 from polizas p
         where p.id = any (c.polizas)
         group by p.aseg_id, p.nro_poliza_norm
        having count(*) >= 2
      )
    else true
  end;
$$;

revoke all on function casos_revision_sigue_abierto(public.casos_revision) from public, anon, authenticated;

-- Cierra los casos pendientes ya corregidos. Devuelve cuántos cerró.
create or replace function casos_revision_revalidar()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  if app_rol() is null then
    return 0;
  end if;

  update casos_revision c
     set estado = 'R',
         auto_resuelto = true,
         respuesta = 'Resuelto automáticamente el '
                     || to_char(now() at time zone 'America/Bogota', 'DD/MM/YYYY HH24:MI')
                     || ': los datos ya no cumplen la situación del caso.'
   where c.estado = 'P'
     and not casos_revision_sigue_abierto(c);
  get diagnostics n = row_count;
  return n;
end;
$$;

revoke all on function casos_revision_revalidar() from public, anon;
grant execute on function casos_revision_revalidar() to authenticated;


-- ── PASO 2 (solo lectura): qué pasaría hoy ──────────────────────────────────
-- sigue_abierto = true  → el caso se queda pendiente.
-- sigue_abierto = false → los datos ya están corregidos y se cerraría solo
--                         la próxima vez que alguien abra la pantalla.
select c.id, c.tipo, c.titulo, casos_revision_sigue_abierto(c) as sigue_abierto
  from public.casos_revision c
 where c.estado = 'P'
 order by c.id;
