import 'package:supabase_flutter/supabase_flutter.dart';

import 'repositorio_polizas.dart';

/// Póliza que no se pudo marcar/resolver, con la razón en español.
class Omitida {
  final int id;
  final String razon;
  const Omitida(this.id, this.razon);

  factory Omitida.fromMap(Map<String, dynamic> m) =>
      Omitida((m['id'] as num).toInt(), (m['razon'] ?? '').toString());
}

class ResultadoEliminacion {
  /// Pólizas marcadas (solicitar) o solicitudes resueltas (resolver).
  final int hechas;
  final List<Omitida> omitidas;
  const ResultadoEliminacion(this.hechas, this.omitidas);

  factory ResultadoEliminacion.fromMap(Map<String, dynamic> m) =>
      ResultadoEliminacion(
        ((m['solicitadas'] ?? m['resueltas'] ?? 0) as num).toInt(),
        ((m['omitidas'] as List?) ?? const [])
            .map((e) => Omitida.fromMap((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

DateTime? _fecha(dynamic v) {
  final d = v == null ? null : DateTime.tryParse(v.toString());
  return d?.toLocal();
}

num? _num(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}');

/// Solicitud de eliminación pendiente de autorizar (vista del Administrador).
class SolicitudEliminacion {
  final int id;
  final int polizaId;
  final String lote;
  final String motivo;
  final DateTime? solicitadoEn;
  final String solicitadoPor;
  final String? nroPoliza;
  final String? cliente;
  final String? aseguradora;
  final String? ramo;
  final num? prima;
  final DateTime? fini;
  final DateTime? ffin;
  final int nPagos;

  const SolicitudEliminacion({
    required this.id,
    required this.polizaId,
    required this.lote,
    required this.motivo,
    required this.solicitadoEn,
    required this.solicitadoPor,
    this.nroPoliza,
    this.cliente,
    this.aseguradora,
    this.ramo,
    this.prima,
    this.fini,
    this.ffin,
    this.nPagos = 0,
  });

  factory SolicitudEliminacion.fromMap(Map<String, dynamic> m) =>
      SolicitudEliminacion(
        id: (m['id'] as num).toInt(),
        polizaId: (m['poliza_id'] as num).toInt(),
        lote: (m['lote'] ?? '').toString(),
        motivo: (m['motivo'] ?? '').toString(),
        solicitadoEn: _fecha(m['solicitado_en']),
        solicitadoPor: (m['solicitado_por'] ?? '—').toString(),
        nroPoliza: m['nro_poliza']?.toString(),
        cliente: m['cliente']?.toString(),
        aseguradora: m['aseguradora']?.toString(),
        ramo: m['ramo']?.toString(),
        prima: _num(m['prima']),
        fini: _fecha(m['fini']),
        ffin: _fecha(m['ffin']),
        nPagos: ((m['n_pagos'] ?? 0) as num).toInt(),
      );
}

/// Solicitud ya resuelta (historial).
class HistorialEliminacion {
  final int id;
  final int polizaId;
  final String estado; // aprobada | rechazada
  final String motivo;
  final String? nota;
  final DateTime? solicitadoEn;
  final String solicitadoPor;
  final DateTime? resueltoEn;
  final String resueltoPor;
  final String? nroPoliza;
  final num? prima;

  const HistorialEliminacion({
    required this.id,
    required this.polizaId,
    required this.estado,
    required this.motivo,
    this.nota,
    this.solicitadoEn,
    required this.solicitadoPor,
    this.resueltoEn,
    required this.resueltoPor,
    this.nroPoliza,
    this.prima,
  });

  bool get aprobada => estado == 'aprobada';

  factory HistorialEliminacion.fromMap(Map<String, dynamic> m) =>
      HistorialEliminacion(
        id: (m['id'] as num).toInt(),
        polizaId: (m['poliza_id'] as num).toInt(),
        estado: (m['estado'] ?? '').toString(),
        motivo: (m['motivo'] ?? '').toString(),
        nota: m['nota']?.toString(),
        solicitadoEn: _fecha(m['solicitado_en']),
        solicitadoPor: (m['solicitado_por'] ?? '—').toString(),
        resueltoEn: _fecha(m['resuelto_en']),
        resueltoPor: (m['resuelto_por'] ?? '—').toString(),
        nroPoliza: m['nro_poliza']?.toString(),
        prima: _num(m['prima']),
      );
}

/// Eliminación de pólizas con autorización del Administrador. Toda la lógica y
/// los permisos viven en la base (ver supabase/migrations/20261015090000_*):
/// la app solo llama funciones y no puede saltarse las validaciones.
class RepositorioEliminacion {
  final SupabaseClient _db = Supabase.instance.client;

  /// Marca pólizas para eliminar (cualquier usuario). Las marcadas
  /// desaparecen de las listas; esta llamada también las saca de la caché.
  Future<ResultadoEliminacion> solicitar(List<int> ids, String motivo) async {
    final res = await _db.rpc('polizas_eliminacion_solicitar',
        params: {'p_ids': ids, 'p_motivo': motivo});
    final r =
        ResultadoEliminacion.fromMap((res as Map).cast<String, dynamic>());
    final omitidas = r.omitidas.map((o) => o.id).toSet();
    RepositorioPolizas.quitarDeCache(ids.where((i) => !omitidas.contains(i)));
    return r;
  }

  Future<List<SolicitudEliminacion>> pendientes() async {
    final res = await _db.rpc('polizas_eliminacion_pendientes');
    return (res as List)
        .map((e) =>
            SolicitudEliminacion.fromMap((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<List<HistorialEliminacion>> historial({int limite = 100}) async {
    final res = await _db
        .rpc('polizas_eliminacion_historial', params: {'p_limite': limite});
    return (res as List)
        .map((e) =>
            HistorialEliminacion.fromMap((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// [aprobar] true = borrar de verdad; false = rechazar y restaurar.
  /// [ids] son ids de solicitud, no de póliza. Solo Administrador.
  Future<ResultadoEliminacion> resolver(List<int> ids,
      {required bool aprobar, String? nota}) async {
    final res = await _db.rpc('polizas_eliminacion_resolver', params: {
      'p_ids': ids,
      'p_accion': aprobar ? 'aprobar' : 'rechazar',
      'p_nota': nota,
    });
    // Aprobadas o restauradas: la lista de pólizas cambió en cualquier caso.
    RepositorioPolizas.invalidarCache();
    return ResultadoEliminacion.fromMap((res as Map).cast<String, dynamic>());
  }

  /// Cuántas hay por autorizar (0 si el usuario no es Administrador).
  Future<int> contarPendientes() async {
    final res = await _db.rpc('polizas_eliminacion_contar');
    return (res as num?)?.toInt() ?? 0;
  }
}
