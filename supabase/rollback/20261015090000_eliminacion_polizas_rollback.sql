-- Deshace supabase/migrations/20261015090000_eliminacion_polizas.sql de forma
-- SEGURA. Correr en el SQL Editor (una sola transacción).
--
-- Qué hace:
--  1. Quita las protecciones (triggers) y restaura TODAS las pólizas marcadas
--     para eliminar (reaparecen en las listas); sus solicitudes pendientes
--     quedan como "rechazada" con una nota.
--  2. Quita las funciones nuevas.
--  3. Devuelve la política de acceso anterior de `polizas` (todos los usuarios
--     activos leen/escriben) y el permiso DELETE.
-- Qué NO hace (a propósito): no borra la tabla polizas_eliminacion (guarda la
-- copia de lo que ya se eliminó) ni la columna polizas.eliminada_en (inofensiva).
--
-- ¡OJO! Después de esto vuelve a existir el borrado directo de pólizas por la
-- API para cualquier usuario activo (como antes de la función).

begin;

-- 1. Triggers fuera y pólizas marcadas de vuelta
drop trigger if exists trg_polizas_marca_eliminacion_guard on polizas;
drop trigger if exists trg_abonos_no_en_poliza_marcada on abonos_poliza;

-- Revise antes cuántas hay: select count(*) from polizas where eliminada_en is not null;
update polizas set eliminada_en = null where eliminada_en is not null;

update polizas_eliminacion
   set estado = 'rechazada', resuelto_en = now(),
       nota_resolucion = 'Reversión de la función de eliminación'
 where estado = 'pendiente';

-- 2. Funciones
drop function if exists polizas_eliminacion_solicitar(bigint[], text);
drop function if exists polizas_eliminacion_pendientes();
drop function if exists polizas_eliminacion_contar();
drop function if exists polizas_eliminacion_historial(int);
drop function if exists polizas_eliminacion_resolver(bigint[], text, text);
drop function if exists polizas_marca_eliminacion_guard();
drop function if exists abonos_no_en_poliza_marcada();

-- 3. Política anterior
drop policy if exists polizas_lectura on polizas;
drop policy if exists polizas_insercion on polizas;
drop policy if exists polizas_edicion on polizas;
drop policy if exists polizas_borrado on polizas;
drop policy if exists app_authenticated_full_access on polizas;
create policy app_authenticated_full_access on polizas for all to authenticated
  using ((select app_rol()) is not null) with check ((select app_rol()) is not null);
grant delete on polizas to authenticated;

commit;

select (select count(*) from polizas where eliminada_en is not null) as marcadas_restantes,
       (select count(*) from polizas_eliminacion) as solicitudes_conservadas;
