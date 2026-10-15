import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/filtros_busqueda.dart';
import 'poliza.dart';

class RepositorioPolizas {
  final SupabaseClient _db = Supabase.instance.client;

  static const String _tabla = 'polizas';
  static const String _vista = 'vw_polizas_busqueda';

  /// Columnas que usan las listas (Pólizas, Reportes, duplicados, pólizas
  /// del cliente, revisión de reportes). La vista tiene ~57; traer solo
  /// estas reduce la descarga completa a menos de la mitad. El formulario
  /// de edición usa [obtenerPoliza], que trae todas.
  static const String _colsLista =
      'id, nro_poliza, cliente_id, asesor_id, ramo_id, producto_id, aseg_id, '
      'fexp_poliza, fini_poliza, ffin_poliza, prima_poliza, valor_poliza, '
      'vlraseg_poliza, porccom_poliza, bien_asegurado, fcreado, fultmod, '
      'estado_poliza_id, vlrprimapagada_poliza, usuario_id, '
      'nombre_cliente, doc_cliente, tipodoc_cliente, tel_cliente, '
      'nombre_asesor, nombre_ramo, nombre_prod, nombre_aseg, '
      'nombre_usuario, apodo_usuario';

  /// Filtro de búsqueda libre sobre la vista. El texto va escapado: una
  /// coma o un paréntesis en la búsqueda ya no rompe el filtro.
  String _filtroBusqueda(String b) {
    final intId = int.tryParse(b);
    final bDoc = b.replaceAll('.', '');
    return [
      if (intId != null) 'id.eq.$intId',
      ilikeContiene('nro_poliza', b),
      ilikeContiene('nombre_cliente', b),
      if (bDoc.isNotEmpty) ilikeContiene('doc_cliente', bDoc),
      ilikeContiene('nombre_asesor', b),
      ilikeContiene('nombre_ramo', b),
      ilikeContiene('nombre_prod', b),
      ilikeContiene('nombre_aseg', b),
      ilikeContiene('nombre_interm', b),
      ilikeContiene('nombre_forma_pago', b),
      ilikeContiene('nombre_formaexp', b),
      ilikeContiene('nombre_usuario', b),
      ilikeContiene('apodo_usuario', b),
      ilikeContiene('bien_asegurado', b),
      ilikeContiene('obs_poliza', b),
    ].join(',');
  }

  /// Carga rápida: devuelve los [limite] registros más recientes.
  Future<List<Poliza>> listar({
    String busqueda = '',
    int limite = 500,
  }) async {
    final b = busqueda.trim();
    dynamic query = _db.from(_vista).select(_colsLista);
    if (b.isNotEmpty) query = query.or(_filtroBusqueda(b));
    final res = await query.order('id', ascending: false).limit(limite);
    final rows = (res as List).cast<Map<String, dynamic>>();
    return rows.map(Poliza.fromMap).toList();
  }

  static const int _pageSize = 1000;

  // ── Caché de "todas las pólizas" (compartida por Pólizas y Reportes) ────
  static List<Poliza>? _cacheTodos;
  static DateTime? _cacheCargadoEn;
  static Future<List<Poliza>>? _cargaEnCurso;

  /// Pasado este tiempo se vuelve a descargar (para ver cambios de otros
  /// usuarios sin tener que presionar "Recargar").
  static const Duration vigenciaCache = Duration(minutes: 15);

  /// Cuándo se descargó la copia en memoria (para mostrarlo en pantalla).
  static DateTime? get cacheCargadoEn => _cacheCargadoEn;

  /// Saca de la copia en memoria las pólizas [ids] (marcadas para eliminar),
  /// sin volver a descargar las demás.
  static void quitarDeCache(Iterable<int> ids) {
    final fuera = ids.toSet();
    _cacheTodos?.removeWhere((p) => fuera.contains(p.id));
  }

  static void invalidarCache() {
    _cacheTodos = null;
    _cacheCargadoEn = null;
  }

  static bool get _cacheVigente =>
      _cacheTodos != null &&
      _cacheCargadoEn != null &&
      DateTime.now().difference(_cacheCargadoEn!) < vigenciaCache;

  /// Trae de nuevo solo las pólizas [ids] y las reemplaza en la caché, en
  /// vez de descartar las 32 mil y volver a bajarlas todas después de
  /// guardar una póliza o un abono.
  Future<void> refrescarEnCache(Iterable<int> ids) async {
    final lista = ids.toSet();
    final cache = _cacheTodos;
    if (lista.isEmpty || cache == null) return;
    try {
      final res = await _db
          .from(_vista)
          .select(_colsLista)
          .inFilter('id', lista.toList());
      final nuevas = {
        for (final r in (res as List).cast<Map<String, dynamic>>())
          (r['id'] as num).toInt(): Poliza.fromMap(r),
      };
      final existentes = cache.map((p) => p.id).toSet();
      _cacheTodos = [
        ...nuevas.values.where((p) => !existentes.contains(p.id)),
        for (final p in cache)
          if (!lista.contains(p.id)) p else if (nuevas[p.id] != null) nuevas[p.id]!,
      ];
    } catch (_) {
      invalidarCache();
    }
  }

  /// Trae todas las pólizas (o todas las que coinciden con [busqueda]).
  /// Sin búsqueda usa la copia en memoria mientras esté vigente, salvo que
  /// [forzar] sea true (botón "Recargar"). Si otra pantalla ya está
  /// descargando, espera esa misma descarga en vez de empezar otra.
  Future<List<Poliza>> listarTodos({
    String busqueda = '',
    bool forzar = false,
    void Function(int cargados)? onProgreso,
  }) async {
    final b = busqueda.trim();
    if (b.isNotEmpty) return _descargarTodas(b, onProgreso);

    if (!forzar && _cacheVigente) {
      onProgreso?.call(_cacheTodos!.length);
      return List.of(_cacheTodos!);
    }
    final enCurso = _cargaEnCurso;
    if (enCurso != null && !forzar) return List.of(await enCurso);

    final carga = _descargarTodas('', onProgreso);
    _cargaEnCurso = carga;
    try {
      final todas = await carga;
      _cacheTodos = todas;
      _cacheCargadoEn = DateTime.now();
      return List.of(todas);
    } finally {
      if (identical(_cargaEnCurso, carga)) _cargaEnCurso = null;
    }
  }

  /// Pagina por id (keyset): exacto aunque entren pólizas nuevas mientras
  /// carga. Antes se paginaba con OFFSET ordenando por fecha de creación
  /// (que se repite), y se podían saltar o repetir filas.
  Future<List<Poliza>> _descargarTodas(
    String b,
    void Function(int cargados)? onProgreso,
  ) async {
    final List<Poliza> todos = [];
    int? ultimoId;

    while (true) {
      dynamic query = _db.from(_vista).select(_colsLista);
      if (b.isNotEmpty) query = query.or(_filtroBusqueda(b));
      if (ultimoId != null) query = query.lt('id', ultimoId);

      final res = await query.order('id', ascending: false).limit(_pageSize);
      final rows = (res as List).cast<Map<String, dynamic>>();
      todos.addAll(rows.map(Poliza.fromMap));

      onProgreso?.call(todos.length);
      // Cede el hilo para que la UI pueda repintar el contador
      await Future.delayed(Duration.zero);

      if (rows.length < _pageSize) break;
      ultimoId = todos.last.id;
    }
    return todos;
  }

  /// Solo las pólizas cuyo nro_poliza está repetido (ver
  /// vw_polizas_duplicadas, lib/fix_vista_polizas_duplicadas.sql) — el
  /// filtro corre en la base, no trae todo el catálogo al cliente.
  Future<List<Poliza>> listarDuplicados() async {
    final res = await _db.from('vw_polizas_duplicadas').select(_colsLista);
    final rows = (res as List).cast<Map<String, dynamic>>();
    return rows.map(Poliza.fromMap).toList();
  }

  /// Pólizas cuyo número contiene [fragmento] — solo en nro_poliza, no en
  /// el resto de columnas como [listar]. Trae de más a propósito: el filtro
  /// fino (segmento exacto + anexo) lo hace matching_reporte_pago.dart.
  Future<List<Poliza>> listarPorNroContiene(String fragmento, {int limite = 200}) async {
    final f = normalizarAlfanumerico(fragmento);
    if (f.isEmpty) return [];
    final res = await _db
        .from(_vista)
        .select(_colsLista)
        .ilike('nro_poliza', '%$f%')
        .order('id', ascending: false)
        .limit(limite);
    return (res as List).cast<Map<String, dynamic>>().map(Poliza.fromMap).toList();
  }

  /// Todas las pólizas de un cliente puntual — usado por el botón "Ver
  /// pólizas" en el catálogo de Clientes. Consulta directa por cliente_id
  /// (indexado), no depende de la caché de listarTodos().
  Future<List<Poliza>> listarPorCliente(int clienteId) async {
    final res = await _db
        .from(_vista)
        .select(_colsLista)
        .eq('cliente_id', clienteId)
        .order('fcreado', ascending: false);
    final rows = (res as List).cast<Map<String, dynamic>>();
    return rows.map(Poliza.fromMap).toList();
  }

  /// Póliza completa (todas las columnas y los nombres de cliente, ramo,
  /// producto, etc. — desde la vista).
  Future<Poliza?> obtenerPoliza(int id) async {
    final res = await _db
        .from(_vista)
        .select()
        .eq('id', id)
        .maybeSingle();

    if (res == null) return null;
    return Poliza.fromMap(res as Map<String, dynamic>);
  }

  /// Compara ignorando espacios/separadores (via la columna generada
  /// nro_poliza_norm, ver lib/fix_nro_poliza_normalizado.sql) — "1 0987 2"
  /// y "109872" se consideran el mismo número. Solo dentro de la misma
  /// aseguradora: dos aseguradoras distintas pueden usar el mismo número.
  Future<bool> existeNroPoliza(String nroPoliza, {int? excluirId, int? aseguradoraId}) async {
    final normalizado = normalizarNroPoliza(nroPoliza);
    if (normalizado.isEmpty) return false;

    dynamic query =
        _db.from(_tabla).select('id').eq('nro_poliza_norm', normalizado);
    if (aseguradoraId != null) query = query.eq('aseg_id', aseguradoraId);

    if (excluirId != null) {
      query = query.neq('id', excluirId);
    }

    // .limit(1) en vez de .maybeSingle(): hoy hay grupos con más de un
    // duplicado ya existentes (ver PaginaPolizasDuplicadas), y
    // .maybeSingle() falla si la consulta devuelve más de una fila.
    final res = await query.limit(1);
    return (res as List).isNotEmpty;
  }

  /// Ignora espacios/guiones/separadores — "1-0987-2" y "1 0987 2" y
  /// "109872" se consideran el mismo número. Pública para que otras
  /// pantallas (ej. la de pólizas duplicadas) agrupen con el mismo
  /// criterio exacto que usa la comparación de duplicados al guardar.
  static String normalizarNroPoliza(String s) => normalizarAlfanumerico(s);

  /// Crea la póliza y devuelve el id real asignado por la base — recién
  /// ahí se sabe con certeza cuál es (dos personas digitando a la vez no
  /// pueden chocar: Postgres asigna el id de forma atómica).
  Future<int> crearPoliza(Map<String, dynamic> data) async {
    final res = await _db
        .from(_tabla)
        .insert(_limpiarMapa(data))
        .select('id')
        .single();
    final id = (res['id'] as num).toInt();
    await refrescarEnCache([id]);
    return id;
  }

  Future<void> actualizarPoliza(int id, Map<String, dynamic> data) async {
    final filas = await _db
        .from(_tabla)
        .update({
          ..._limpiarMapa(data),
          'fultmod': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .select('id');
    // Cero filas = la póliza ya no es visible (la marcaron para eliminar o la
    // borraron): no se debe dar por guardado un cambio que no se aplicó.
    if ((filas as List).isEmpty) {
      throw Exception('La póliza ya no está disponible: fue marcada para '
          'eliminar o borrada por otra persona. Recargue la lista.');
    }
    await refrescarEnCache([id]);
  }

  Future<void> eliminarPoliza(int id) async {
    await _db.from(_tabla).delete().eq('id', id);
    _cacheTodos?.removeWhere((p) => p.id == id);
  }

  Map<String, dynamic> _limpiarMapa(Map<String, dynamic> data) {
    final limpio = <String, dynamic>{};

    for (final entry in data.entries) {
      final key = entry.key;
      dynamic value = entry.value;

      if (value is String) {
        value = value.trim();
        if (value.isEmpty) value = null;
      }

      // Formato acordado para nro_poliza: segmentos unidos con guion, nunca
      // con espacios — si se tipeó o importó con espacios, se normaliza
      // sola al guardar en vez de dejar los dos formatos mezclados en la
      // base.
      if (key == 'nro_poliza' && value is String) {
        value = value.replaceAll(RegExp(r'\s+'), '-');
      }

      if (_camposEnterosNullable.contains(key)) {
        if (value == 0 || value == '0') {
          value = null;
        } else if (value is String) {
          value = int.tryParse(value);
        }
      }

      if (_camposNumericos.contains(key)) {
        if (value is String) {
          final txt = value.replaceAll(',', '.').trim();
          value = txt.isEmpty ? null : num.tryParse(txt);
        }
      }

      limpio[key] = value;
    }

    return limpio;
  }

  static const Set<String> _camposEnterosNullable = {
    'cliente_id',
    'asesor_id',
    'ramo_id',
    'producto_id',
    'intermediario_id',
    'agencia_id',
    'forma_pago_id',
    'asesor2_id',
    'asesor3_id',
    'asesorad_id',
    'agenciaad_id',
    'formaexp_id',
    'aseg_id',
    'usuario_id',
  };

  static const Set<String> _camposNumericos = {
    'prima_poliza',
    'valor_poliza',
    'vlraseg_poliza',
    'porccom_poliza',
    'vlrbasecom_poliza',
    'porcom_agencia',
    'vlrcom_poliza',
    'vlrcomfija_poliza',
    'porcomadic_poliza',
    'vlrcomadic_poliza',
    'porcom_asesor1',
    'vlrprimapagada_poliza',
    'porcom_asesor2',
    'porcom_asesor3',
    'porcom_asesorad',
    'porcom_agenciaad',
  };
}
