import 'package:supabase_flutter/supabase_flutter.dart';

import 'meta.dart';

/// Pago mínimo que necesita el dashboard (sin los datos de póliza/cliente:
/// esos se cruzan en memoria con la lista de pólizas).
class AbonoLite {
  final int idPoliza;
  final DateTime? fecha;
  final num prima;
  final num comision;
  const AbonoLite({
    required this.idPoliza,
    required this.fecha,
    required this.prima,
    required this.comision,
  });
}

class RepositorioDashboard {
  final SupabaseClient _db = Supabase.instance.client;

  static const int _pagina = 1000;
  static List<AbonoLite>? _cacheAbonos;
  static DateTime? _cacheEn;
  static const Duration _vigencia = Duration(minutes: 15);

  static void invalidarCache() {
    _cacheAbonos = null;
    _cacheEn = null;
  }

  static num _num(dynamic v) =>
      v is num ? v : (num.tryParse(v?.toString() ?? '') ?? 0);

  /// Mismo criterio que Poliza: se conserva el día calendario guardado.
  static DateTime? _dia(dynamic v) {
    final d = v == null ? null : DateTime.tryParse(v.toString());
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }

  /// Pagos no anulados (los anulados no suman en ningún total de la app).
  /// Pagina por id (keyset). Solo roles A y S: la base lo permite a todos,
  /// pero la pantalla los muestra únicamente a quien ve comisiones.
  Future<List<AbonoLite>> listarAbonos({
    bool forzar = false,
    void Function(int cargados)? onProgreso,
  }) async {
    final c = _cacheAbonos;
    if (!forzar &&
        c != null &&
        _cacheEn != null &&
        DateTime.now().difference(_cacheEn!) < _vigencia) {
      onProgreso?.call(c.length);
      return c;
    }
    final out = <AbonoLite>[];
    int? ultimo;
    while (true) {
      dynamic q = _db
          .from('abonos_poliza')
          .select(
              'id, id_poliza, fecha_pago, vlrabono_prima, vlrcomision, vlrcomad')
          .neq('estado_pago', 'A');
      if (ultimo != null) q = q.lt('id', ultimo);
      final res = await q.order('id', ascending: false).limit(_pagina);
      final rows = (res as List).cast<Map<String, dynamic>>();
      for (final r in rows) {
        out.add(AbonoLite(
          idPoliza: (r['id_poliza'] as num).toInt(),
          fecha: _dia(r['fecha_pago']),
          prima: _num(r['vlrabono_prima']),
          comision: _num(r['vlrcomision']) + _num(r['vlrcomad']),
        ));
      }
      onProgreso?.call(out.length);
      if (rows.length < _pagina) break;
      ultimo = (rows.last['id'] as num).toInt();
    }
    _cacheAbonos = out;
    _cacheEn = DateTime.now();
    return out;
  }

  // ── Metas ──────────────────────────────────────────────────────────────

  Future<List<Meta>> listarMetas(int anio) async {
    final res = await _db.from('metas_comerciales').select().eq('anio', anio);
    return (res as List)
        .cast<Map<String, dynamic>>()
        .map(Meta.fromMap)
        .toList();
  }

  Future<void> guardarMetas(List<Meta> metas) async {
    if (metas.isEmpty) return;
    await _db.from('metas_comerciales').upsert(
        metas.map((m) => m.toMap()).toList(),
        onConflict: 'anio,mes,indicador,asesor_id');
  }
}
