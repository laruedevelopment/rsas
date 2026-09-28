-- ═══════════════════════════════════════════════════════════════════════════
-- % de comisión de los abonos históricos.
--
-- El sistema anterior guardaba solo el valor de la comisión en pesos, no el
-- porcentaje, así que los ~20.900 abonos históricos muestran "0,0 %".
-- Aquí se calcula:  % = valor comisión ÷ abono × 100  (2 decimales).
-- Ejemplo: abono $373.950, comisión $37.395  →  10,00 %.
-- Lo mismo para la comisión adicional (porccomad desde vlrcomad).
--
-- Solo llena el porcentaje donde hoy está en 0; NO cambia ningún valor en
-- pesos, ni la prima pagada, ni la fecha de modificación de los abonos.
-- Los abonos cuyo % daría negativo o mayor a 100 % (valores que no cuadran)
-- se dejan en 0: quedan como casos en el menú "Casos por revisar"
-- (migración 20260928120100_casos_revision.sql).
--
-- Se puede volver a correr sin problema. Correr primero en PRUEBAS y luego
-- en PRODUCCIÓN, por PASOS, en orden.
-- ═══════════════════════════════════════════════════════════════════════════


-- ── PASO 0 (solo lectura): cuántos se llenan ────────────────────────────────
select
  count(*) filter (where coalesce(porccomision, 0) = 0 and coalesce(vlrabono_prima, 0) <> 0
                     and coalesce(vlrcomision, 0) <> 0
                     and vlrcomision / nullif(vlrabono_prima, 0) between 0 and 1)       as se_llenan_com,
  count(*) filter (where coalesce(porccomision, 0) = 0 and coalesce(vlrabono_prima, 0) <> 0
                     and coalesce(vlrcomision, 0) <> 0
                     and vlrcomision / nullif(vlrabono_prima, 0) not between 0 and 1)   as fuera_de_rango,
  count(*) filter (where coalesce(porccomad, 0) = 0 and coalesce(vlrabono_prima, 0) <> 0
                     and coalesce(vlrcomad, 0) <> 0
                     and vlrcomad / nullif(vlrabono_prima, 0) between 0 and 1)          as se_llenan_com_adic
from abonos_poliza;


-- ── PASO 1: cálculo ─────────────────────────────────────────────────────────
do $$
declare
  n1 bigint;
  n2 bigint;
begin
  -- Es un dato calculado, no una edición: se conserva la fecha de modificación.
  alter table abonos_poliza disable trigger trg_fultmod;

  update abonos_poliza
     set porccomision = round(vlrcomision / nullif(vlrabono_prima, 0) * 100, 2)
   where coalesce(porccomision, 0) = 0
     and coalesce(vlrabono_prima, 0) <> 0
     and coalesce(vlrcomision, 0) <> 0
     and vlrcomision / nullif(vlrabono_prima, 0) between 0 and 1;
  get diagnostics n1 = row_count;

  update abonos_poliza
     set porccomad = round(vlrcomad / nullif(vlrabono_prima, 0) * 100, 2)
   where coalesce(porccomad, 0) = 0
     and coalesce(vlrabono_prima, 0) <> 0
     and coalesce(vlrcomad, 0) <> 0
     and vlrcomad / nullif(vlrabono_prima, 0) between 0 and 1;
  get diagnostics n2 = row_count;

  alter table abonos_poliza enable trigger trg_fultmod;

  raise notice '%% comisión llenado en % abonos, %% comisión adicional en %', n1, n2;
end $$;


-- ── PASO 2 (solo lectura): verificación ─────────────────────────────────────
-- pendientes_com debe ser igual a fuera_de_rango del PASO 0 (los que no se
-- llenan a propósito).
select
  count(*) filter (where coalesce(porccomision, 0) = 0 and coalesce(vlrabono_prima, 0) <> 0
                     and coalesce(vlrcomision, 0) <> 0) as pendientes_com,
  count(*) filter (where coalesce(porccomision, 0) <> 0) as con_porcentaje
from abonos_poliza;
