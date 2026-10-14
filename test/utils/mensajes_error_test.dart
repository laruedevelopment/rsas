import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento_polizas/utils/mensajes_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('llave foránea → mensaje de "en uso", sin texto técnico', () {
    final m = mensajeAmigable(
        const PostgrestException(message: 'violates foreign key constraint', code: '23503'),
        accion: 'No se pudo eliminar');
    expect(m, startsWith('No se pudo eliminar. '));
    expect(m, contains('en uso'));
    expect(m.toLowerCase(), isNot(contains('postgrest')));
  });

  test('duplicado, permisos y sesión', () {
    expect(mensajeAmigable(const PostgrestException(message: 'x', code: '23505')),
        contains('Ya existe'));
    expect(mensajeAmigable(const PostgrestException(message: 'x', code: '42501')),
        contains('permiso'));
    expect(mensajeAmigable(const PostgrestException(message: 'JWT expired', code: 'PGRST301')),
        contains('sesión venció'));
  });

  test('red y tiempo', () {
    expect(mensajeAmigable(Exception('SocketException: Failed host lookup')),
        contains('Sin conexión'));
    expect(mensajeAmigable(TimeoutException('x')), contains('tardó demasiado'));
  });

  test('excepciones propias de la app pasan sin prefijo', () {
    expect(mensajeAmigable(Exception('El archivo pesa más de 15 MB.'), accion: 'Error al importar'),
        'Error al importar. El archivo pesa más de 15 MB.');
  });

  test('error desconocido → genérico', () {
    expect(mensajeAmigable(StateError('boom')), contains('error inesperado'));
  });
}
