import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Texto para el usuario a partir de cualquier error: nunca muestra
/// "PostgrestException(...)" ni trazas. El detalle técnico queda en la
/// consola (debugPrint) para quien depure.
///
/// [accion] es lo que se intentaba ("No se pudo guardar la póliza"); el
/// resultado es "<accion>. <causa y qué hacer>".
String mensajeAmigable(Object e, {String? accion}) {
  debugPrint('Error${accion != null ? ' ($accion)' : ''}: $e');
  final causa = _causa(e);
  if (accion == null || accion.trim().isEmpty) return causa;
  final a = accion.trim().replaceAll(RegExp(r'[.:]+$'), '');
  return '$a. $causa';
}

String _causa(Object e) {
  if (e is TimeoutException) {
    return 'La operación tardó demasiado. Verifique su conexión e intente de nuevo.';
  }
  if (e is PostgrestException) {
    final code = e.code ?? '';
    // Mensajes propios de las funciones de la base (raise exception ... P0001):
    // ya vienen en español y dicen qué pasó.
    if (code == 'P0001' && e.message.trim().isNotEmpty) return e.message.trim();
    final msg = '${e.message} ${e.details ?? ''}'.toLowerCase();
    if (code == '23503' || msg.contains('foreign key')) {
      return 'Está en uso por otros registros (por ejemplo pólizas, incluso pólizas marcadas para '
          'eliminar que aún esperan autorización), así que no se puede eliminar o cambiar.';
    }
    if (code == '23505' || msg.contains('duplicate key')) {
      return 'Ya existe un registro con esos datos.';
    }
    if (code == '23502') return 'Falta un dato obligatorio.';
    if (code == '42501' || msg.contains('row-level security')) {
      return 'No tiene permiso para realizar esta acción.';
    }
    if (code == 'PGRST301' || msg.contains('jwt')) {
      return 'Su sesión venció. Cierre sesión e ingrese de nuevo.';
    }
    if (code == '57014' || msg.contains('statement timeout')) {
      return 'La consulta tardó demasiado. Intente de nuevo en un momento.';
    }
    return 'No se pudo completar. Intente de nuevo; si sigue fallando, avise al administrador.';
  }
  final s = e.toString();
  final l = s.toLowerCase();
  if (l.contains('socketexception') ||
      l.contains('failed host') ||
      l.contains('failed to fetch') ||
      l.contains('clientexception') ||
      l.contains('network')) {
    return 'Sin conexión a internet. Verifique su red e intente de nuevo.';
  }
  if (l.contains('timeout') || l.contains('tardó demasiado')) {
    return 'La operación tardó demasiado. Intente de nuevo.';
  }
  // Excepciones propias de la app (Exception('texto en español')): se
  // muestran tal cual, sin el prefijo "Exception: ".
  if (e is Exception && s.startsWith('Exception: ')) {
    return s.substring('Exception: '.length).trim();
  }
  if (e is String && e.isNotEmpty) return e;
  return 'Ocurrió un error inesperado. Intente de nuevo.';
}
