import 'package:flutter/foundation.dart';

import 'repositorio_catalogos.dart';
import 'repositorio_ia.dart';
import 'repositorio_polizas_pendientes.dart';

enum EstadoArchivoCarga { pendiente, procesando, ok, error }

class ItemCargaMasiva {
  final String nombre;
  final Uint8List bytes;
  final String mimeType;
  EstadoArchivoCarga estado = EstadoArchivoCarga.pendiente;
  String? error;
  bool errorRegistrado = false;
  ItemCargaMasiva({required this.nombre, required this.bytes, required this.mimeType});
}

/// Procesa la carga masiva de pólizas en segundo plano — vive fuera del
/// ciclo de vida de cualquier pantalla, así que el usuario puede navegar
/// a otras partes de la app (o cerrar la pantalla de carga) sin que el
/// lote se interrumpa. Un solo lote a la vez.
class ServicioCargaMasiva extends ChangeNotifier {
  ServicioCargaMasiva._();
  static final ServicioCargaMasiva instance = ServicioCargaMasiva._();

  final _repoIA = RepositorioIA();
  final _repoPend = RepositorioPolizasPendientes();
  final _repoCat = RepositorioCatalogos();

  List<ItemCargaMasiva> items = [];
  bool procesando = false;
  int procesados = 0;

  void agregarArchivos(List<ItemCargaMasiva> nuevos) {
    if (procesando) return;
    items = nuevos;
    procesados = 0;
    notifyListeners();
  }

  void limpiar() {
    if (procesando) return;
    items = [];
    procesados = 0;
    notifyListeners();
  }

  /// Igual que el límite de la Edge Function: evita gastar una llamada que
  /// igual va a ser rechazada.
  static const int _maxBytes = 15 * 1024 * 1024;

  bool get hayFallidos => items.any((i) => i.estado == EstadoArchivoCarga.error);

  /// Procesa los archivos pendientes o que fallaron (los que ya salieron
  /// bien no se vuelven a enviar: volver a llamar esto sirve de
  /// "Reintentar fallidos" sin gastar de nuevo en los exitosos).
  Future<void> procesarTodos() async {
    if (procesando || items.isEmpty) return;
    procesando = true;
    procesados = items.where((i) => i.estado == EstadoArchivoCarga.ok).length;
    notifyListeners();

    try {
      final catalogo = await _repoCat.catalogoProductosParaIA();
      final vistos = <String>{};

      for (final item in items) {
        if (item.estado == EstadoArchivoCarga.ok) continue;

        // El mismo archivo elegido dos veces en el lote se procesa una vez.
        final firma = '${item.bytes.length}:${Object.hashAll(item.bytes.take(4096))}:'
            '${Object.hashAll(item.bytes.skip(item.bytes.length > 4096 ? item.bytes.length - 4096 : 0))}';
        if (!vistos.add(firma)) {
          item.estado = EstadoArchivoCarga.error;
          item.error = 'Archivo repetido en este lote: se omitió.';
          procesados++;
          notifyListeners();
          continue;
        }

        item.estado = EstadoArchivoCarga.procesando;
        item.error = null;
        notifyListeners();
        try {
          if (item.bytes.length > _maxBytes) {
            throw Exception('El archivo pesa más de 15 MB. Use una versión más liviana.');
          }
          final datos = await _conReintentos(() => _repoIA.extraerPoliza(
                item.bytes,
                item.mimeType,
                catalogoProductos: catalogo,
              ));
          await _repoPend.crear(
            estado: 'pendiente_revision',
            datos: datos,
            nombreArchivo: item.nombre,
            origen: 'ia_carga_masiva',
          );
          item.estado = EstadoArchivoCarga.ok;
        } catch (e) {
          final msg = e.toString().replaceFirst('Exception: ', '');
          // Se deja registrada una vez en Pendientes, con el error a la
          // vista, en vez de perderse en silencio.
          if (!item.errorRegistrado) {
            try {
              await _repoPend.crear(
                estado: 'pendiente_revision',
                datos: const {},
                nombreArchivo: item.nombre,
                origen: 'ia_carga_masiva',
                errorMsg: msg,
              );
              item.errorRegistrado = true;
            } catch (_) {}
          }
          item.estado = EstadoArchivoCarga.error;
          item.error = msg;
        }
        procesados++;
        notifyListeners();
      }
    } catch (e) {
      // Falla antes de empezar (ej. sin conexión al traer el catálogo).
      for (final item in items) {
        if (item.estado == EstadoArchivoCarga.pendiente ||
            item.estado == EstadoArchivoCarga.procesando) {
          item.estado = EstadoArchivoCarga.error;
          item.error = 'No se pudo iniciar la carga: ${e.toString().replaceFirst('Exception: ', '')}';
        }
      }
    } finally {
      // Nunca queda trabado en "procesando" (antes, un error al traer el
      // catálogo dejaba los botones deshabilitados hasta reiniciar la app).
      procesando = false;
      notifyListeners();
    }
  }

  /// Reintenta hasta 2 veces (a los 5 y 15 segundos) los errores
  /// temporales del servicio de IA: límite de uso o servicio no disponible.
  Future<T> _conReintentos<T>(Future<T> Function() accion) async {
    const esperas = [Duration(seconds: 5), Duration(seconds: 15)];
    for (var intento = 0;; intento++) {
      try {
        return await accion();
      } catch (e) {
        final s = e.toString().toLowerCase();
        final temporal = s.contains('límite de uso') ||
            s.contains('no está disponible') ||
            s.contains('no se pudo leer este documento') ||
            s.contains('(429)') ||
            s.contains('(502)') ||
            s.contains('(503)') ||
            s.contains('(504)');
        if (!temporal || intento >= esperas.length) rethrow;
        await Future.delayed(esperas[intento]);
      }
    }
  }
}
