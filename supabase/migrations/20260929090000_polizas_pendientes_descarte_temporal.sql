-- ═══════════════════════════════════════════════════════════════════════════
-- "Descartar" en Pólizas pendientes deja de borrar de una vez para siempre.
--
-- Hasta ahora, el botón de basurero en la bandeja de Pendientes hacía un
-- DELETE inmediato e irreversible. El 2026-09-29 se detectó que ~30
-- pólizas cargadas por IA el viernes 26 desaparecieron sin que nadie las
-- hubiera revisado ni guardado -- lo más probable es que alguien las haya
-- descartado por error pensando que eran duplicadas, sin forma de
-- recuperarlas (esta tabla no tiene historial ni el proyecto tiene backups).
--
-- A partir de ahora "Descartar" solo marca fdescartado = now(). La fila se
-- deja de mostrar en la bandeja, pero se puede restaurar durante 7 días
-- desde una pestaña "Descartados". Pasado ese plazo, se borra sola (la app
-- purga los vencidos cada vez que abre la pantalla de Pendientes -- no
-- depende de pg_cron).
--
-- Se puede volver a correr sin problema. Correr primero en PRUEBAS y luego
-- en PRODUCCIÓN.
-- ═══════════════════════════════════════════════════════════════════════════

alter table public.polizas_pendientes
  add column if not exists fdescartado timestamptz;

create index if not exists polizas_pendientes_fdescartado_idx
  on public.polizas_pendientes (fdescartado);
