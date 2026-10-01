class PolizaPendiente {
  final int id;
  final String estado; // 'borrador' | 'pendiente_revision'
  final Map<String, dynamic> datos;
  final String? nombreArchivo;
  final String origen;
  final String? errorMsg;
  final DateTime fcreado;
  final DateTime fultmod;
  final DateTime? fdescartado;

  PolizaPendiente({
    required this.id,
    required this.estado,
    required this.datos,
    this.nombreArchivo,
    required this.origen,
    this.errorMsg,
    required this.fcreado,
    required this.fultmod,
    this.fdescartado,
  });

  factory PolizaPendiente.fromMap(Map<String, dynamic> m) => PolizaPendiente(
        id: (m['id'] as num).toInt(),
        estado: m['estado'] as String? ?? 'borrador',
        datos: (m['datos'] as Map?)?.cast<String, dynamic>() ?? {},
        nombreArchivo: m['nombre_archivo'] as String?,
        origen: m['origen'] as String? ?? 'manual',
        errorMsg: m['error_msg'] as String?,
        fcreado: DateTime.parse(m['fcreado'] as String),
        fultmod: DateTime.parse(m['fultmod'] as String),
        fdescartado: m['fdescartado'] == null
            ? null
            : DateTime.parse(m['fdescartado'] as String),
      );

  /// Número de póliza extraído por la IA o digitado en el borrador ('' si no
  /// hay).
  String get nroPoliza => (datos['nro_poliza'] ?? '').toString().trim();

  /// Días de gracia antes de borrarse sola (ver
  /// supabase/migrations/20260929090000_polizas_pendientes_descarte_temporal.sql).
  static const diasRetencion = 7;

  int? get diasParaBorrarse {
    if (fdescartado == null) return null;
    final vence = fdescartado!.add(const Duration(days: diasRetencion));
    return vence.difference(DateTime.now()).inDays.clamp(0, diasRetencion);
  }

  /// Texto corto para mostrar en la lista de pendientes: nombre del cliente
  /// o número de póliza extraído, lo que haya.
  String get resumen {
    final nombre = (datos['nombre_cliente'] ?? datos['nro_poliza'])?.toString();
    return (nombre == null || nombre.trim().isEmpty)
        ? 'Sin datos'
        : nombre.trim();
  }
}
