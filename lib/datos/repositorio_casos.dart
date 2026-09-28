import 'package:supabase_flutter/supabase_flutter.dart';

/// Caso dudoso que el equipo debe aclarar (pago sin póliza, posible
/// duplicado, comisión que no cuadra…). Ver
/// supabase/migrations/20260928120100_casos_revision.sql.
class CasoRevision {
  final int id;
  final String tipo;
  final String titulo;
  final String descripcion;
  final String? pregunta;
  final List<int> polizas;
  final int? reporteId;
  final String estado; // P = pendiente, R = resuelto
  final String? respuesta;
  final String? resueltoPor;
  final DateTime? fresuelto;
  final DateTime? fcreado;

  CasoRevision({
    required this.id,
    required this.tipo,
    required this.titulo,
    required this.descripcion,
    this.pregunta,
    this.polizas = const [],
    this.reporteId,
    required this.estado,
    this.respuesta,
    this.resueltoPor,
    this.fresuelto,
    this.fcreado,
  });

  bool get resuelto => estado == 'R';

  String get nombreTipo => switch (tipo) {
        'PAGO_SIN_POLIZA' => 'Pago sin póliza',
        'POSIBLE_DUPLICADO' => 'Posible duplicado',
        'COMISION_RARA' => 'Comisión que no cuadra',
        _ => 'Otro',
      };

  factory CasoRevision.fromMap(Map<String, dynamic> m) {
    DateTime? fecha(dynamic v) =>
        v == null ? null : DateTime.tryParse('$v')?.toLocal();
    final quien = m['resuelve'];
    return CasoRevision(
      id: (m['id'] as num).toInt(),
      tipo: '${m['tipo'] ?? 'OTRO'}',
      titulo: '${m['titulo'] ?? ''}',
      descripcion: '${m['descripcion'] ?? ''}',
      pregunta: m['pregunta'] as String?,
      polizas: ((m['polizas'] as List?) ?? const [])
          .map((e) => (e as num).toInt())
          .toList(),
      reporteId: (m['reporte_id'] as num?)?.toInt(),
      estado: '${m['estado'] ?? 'P'}',
      respuesta: m['respuesta'] as String?,
      resueltoPor: quien is Map ? quien['apodo_usuario'] as String? : null,
      fresuelto: fecha(m['fresuelto']),
      fcreado: fecha(m['fcreado']),
    );
  }
}

class RepositorioCasos {
  final SupabaseClient _db = Supabase.instance.client;
  static const String _tabla = 'casos_revision';
  static const String _cols =
      'id, tipo, titulo, descripcion, pregunta, polizas, reporte_id, estado, '
      'respuesta, fresuelto, fcreado, '
      'resuelve:usuarios!casos_revision_usuario_resuelve_fkey(apodo_usuario)';

  Future<List<CasoRevision>> listar({required String estado}) async {
    final res = await _db.from(_tabla).select(_cols).eq('estado', estado).order(
        estado == 'R' ? 'fresuelto' : 'fcreado',
        ascending: estado != 'R');
    return (res as List)
        .cast<Map<String, dynamic>>()
        .map(CasoRevision.fromMap)
        .toList();
  }

  Future<int> contarPendientes() async {
    final res = await _db.from(_tabla).select('id').eq('estado', 'P');
    return (res as List).length;
  }

  /// Quién y cuándo lo pone la base (trigger).
  Future<void> resolver(int id, String respuesta) async {
    await _db
        .from(_tabla)
        .update({'estado': 'R', 'respuesta': respuesta.trim()}).eq('id', id);
  }

  Future<void> reabrir(int id) async {
    await _db.from(_tabla).update({'estado': 'P'}).eq('id', id);
  }
}
