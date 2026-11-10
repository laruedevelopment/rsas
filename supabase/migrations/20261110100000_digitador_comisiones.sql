-- ═══════════════════════════════════════════════════════════════════════════
-- El Digitador (D) también puede registrar reportes de comisiones y abonos.
--
-- Hasta ahora estas tablas se podían LEER con cualquier rol, pero solo
-- ESCRIBIR con A (Administrador) y S. Al abrir el módulo de Reportes de
-- Comisiones al Digitador, guardar un reporte fallaba con "No tiene permiso
-- para realizar esta acción". Esta migración deja escribir también a D.
--
-- Qué NO cambia: sigue sin poder borrar nada que antes no pudiera (el borrado
-- de pólizas, de casos y de clientes tiene sus propias reglas), y los casos de
-- comisiones raras siguen visibles solo para A y S.
--
-- Se puede volver a correr sin problema. Correr primero en PRUEBAS.
-- Para revertir: volver a poner ('A', 'S') en la política app_escritura.
-- ═══════════════════════════════════════════════════════════════════════════

do $$
declare
  t text;
begin
  foreach t in array array['reportes_pago', 'abonos_poliza', 'ia_aprendizaje_intermediario_reporte']
  loop
    if to_regclass('public.' || t) is null then continue; end if;
    execute format('drop policy if exists app_escritura on public.%I;', t);
    execute format(
      'create policy app_escritura on public.%I for all to authenticated '
      'using ((select app_rol()) in (''A'', ''S'', ''D'')) '
      'with check ((select app_rol()) in (''A'', ''S'', ''D''));', t);
  end loop;
end $$;

-- Verificación: debe listar las tres tablas con A, S y D.
select tablename, policyname, qual
  from pg_policies
 where schemaname = 'public'
   and tablename in ('reportes_pago', 'abonos_poliza', 'ia_aprendizaje_intermediario_reporte')
   and policyname = 'app_escritura'
 order by tablename;
