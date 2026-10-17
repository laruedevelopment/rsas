import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento_polizas/datos/poliza_pendiente.dart';

Map<String, dynamic> base() => {
      'id': 747,
      'estado': 'pendiente_revision',
      'datos': {'nro_poliza': 'B-100082313-3', 'nombre_cliente': 'Cliente'},
      'nombre_archivo': 'poliza cump 3.pdf',
      'origen': 'ia_carga_masiva',
      'fcreado': '2026-10-17T16:08:00+00:00',
      'fultmod': '2026-10-17T16:08:00+00:00',
    };

void main() {
  test('lee quién la subió (usuario_id)', () {
    final p = PolizaPendiente.fromMap({...base(), 'usuario_id': 5});
    expect(p.usuarioId, 5);
    expect(p.id, 747);
  });

  test('datos antiguos sin usuario no fallan', () {
    expect(PolizaPendiente.fromMap(base()).usuarioId, isNull);
    expect(PolizaPendiente.fromMap({...base(), 'usuario_id': null}).usuarioId, isNull);
  });
}
