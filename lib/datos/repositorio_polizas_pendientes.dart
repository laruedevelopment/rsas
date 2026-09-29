import 'package:supabase_flutter/supabase_flutter.dart';
import 'poliza_pendiente.dart';
import 'sesion.dart';

/// Bandeja de trabajo de pólizas que todavía no tienen id definitivo — ver
/// lib/fix_polizas_pendientes.sql para el porqué de "borrador" vs
/// "pendiente_revision".
class RepositorioPolizasPendientes {
  final SupabaseClient _db = Supabase.instance.client;
  static const String _tabla = 'polizas_pendientes';

  /// [incluirDescartados]: true trae solo las descartadas (para la pestaña
  /// "Descartados"); false (por defecto) trae solo las activas.
  Future<List<PolizaPendiente>> listar({
    String? estado,
    bool incluirDescartados = false,
  }) async {
    dynamic q = _db.from(_tabla).select();
    q = incluirDescartados
        ? q.not('fdescartado', 'is', null)
        : q.filter('fdescartado', 'is', null);
    if (estado != null) q = q.eq('estado', estado);
    final res = await q.order('fcreado', ascending: false);
    final rows = (res as List).cast<Map<String, dynamic>>();
    return rows.map(PolizaPendiente.fromMap).toList();
  }

  Future<int> contar({String? estado}) async {
    dynamic q = _db.from(_tabla).select('id').filter('fdescartado', 'is', null);
    if (estado != null) q = q.eq('estado', estado);
    final res = await q;
    return (res as List).length;
  }

  Future<int> crear({
    required String estado,
    required Map<String, dynamic> datos,
    String? nombreArchivo,
    String origen = 'manual',
    String? errorMsg,
  }) async {
    final res = await _db
        .from(_tabla)
        .insert({
          'estado': estado,
          'datos': datos,
          'nombre_archivo': nombreArchivo,
          'origen': origen,
          'error_msg': errorMsg,
          'usuario_id': Sesion.usuarioId,
        })
        .select('id')
        .single();
    return (res['id'] as num).toInt();
  }

  Future<void> actualizar(
    int id, {
    String? estado,
    Map<String, dynamic>? datos,
  }) async {
    final cambios = <String, dynamic>{
      'fultmod': DateTime.now().toIso8601String(),
    };
    if (estado != null) cambios['estado'] = estado;
    if (datos != null) cambios['datos'] = datos;
    await _db.from(_tabla).update(cambios).eq('id', id);
  }

  /// Ya no borra de una vez: marca la fila como descartada y se puede
  /// restaurar durante [PolizaPendiente.diasRetencion] días (ver
  /// [restaurar] y [purgarVencidos]).
  Future<void> descartar(int id) async {
    await _db
        .from(_tabla)
        .update({'fdescartado': DateTime.now().toIso8601String()}).eq('id', id);
  }

  Future<void> restaurar(int id) async {
    await _db.from(_tabla).update({'fdescartado': null}).eq('id', id);
  }

  /// Borrado real e inmediato — solo para cuando la fila ya cumplió su
  /// función (se guardó como póliza real, ver pagina_formulario_polizas.dart)
  /// y no para el botón "Descartar" de la pantalla (ese usa [descartar]).
  Future<void> eliminar(int id) async {
    await _db.from(_tabla).delete().eq('id', id);
  }

  /// Borra de verdad las que llevan descartadas más de
  /// [PolizaPendiente.diasRetencion] días. Se llama sola al abrir la
  /// pantalla de Pendientes — no depende de un cron en la base.
  Future<void> purgarVencidos() async {
    final limite = DateTime.now()
        .subtract(const Duration(days: PolizaPendiente.diasRetencion))
        .toIso8601String();
    await _db.from(_tabla).delete().lt('fdescartado', limite);
  }
}
