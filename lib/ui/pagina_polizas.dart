import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'pagina_carga_masiva_polizas.dart';
import 'pagina_catalogos.dart';
import 'pagina_estado_cuenta.dart';
import 'pagina_polizas_duplicadas.dart';
import 'pagina_polizas_pendientes.dart';
import 'pagina_eliminaciones_pendientes.dart';
import 'dialogos/eliminar_polizas.dart';
import '../utils/plurales.dart';
import '../datos/poliza.dart';
import '../datos/repositorio_polizas.dart';
import '../datos/repositorio_polizas_pendientes.dart';
import '../datos/repositorio_eliminacion.dart';
import '../datos/sesion.dart';
import '../datos/servicio_carga_masiva.dart';
import '../utils/formatters.dart';
import 'pagina_formulario_polizas.dart';
import 'theme/app_theme.dart';

class PaginaPolizas extends StatefulWidget {
  const PaginaPolizas({super.key});

  @override
  State<PaginaPolizas> createState() => _PaginaPolizasState();
}

class _PaginaPolizasState extends State<PaginaPolizas> {
  final repo = RepositorioPolizas();
  final ctrlBuscar = TextEditingController();
  final df = DateFormat('dd/MM/yyyy');
  final nf = NumberFormat.decimalPattern('es_CO');

  bool cargando = false;
  List<Poliza> polizas = [];
  int _cargados = 0;            // progreso de carga total
  bool _datosCompletos = false; // true cuando ya se cargaron todos
  String? _errorCarga;          // mensaje de error persistente para mostrar retry

  String? _filtroAseg;
  String? _filtroRamo;
  String? _filtroProd;
  String? _filtroAsesor;
  String? _filtroCliente;
  int _clienteResetKey = 0;

  // ── Cálculos memorizados ──────────────────────────────────────────────
  // Las opciones de los filtros y la lista filtrada recorren hasta ~32 mil
  // pólizas: se recalculan solo cuando cambian los datos, los filtros o el
  // orden (no en cada repintado por el contador de carga o la carga masiva).
  final Map<String, Object?> _memoCache = {};
  String _memoFirma = '';

  String get _firma => [
        identityHashCode(polizas), polizas.length, _filtroAseg, _filtroRamo,
        _filtroProd, _filtroAsesor, _filtroCliente, _sortColumnIndex, _sortAscending,
        _versionOrden,
      ].join('|');

  /// Se incrementa al reordenar en el mismo lugar (misma lista, otro orden).
  int _versionOrden = 0;

  T _memo<T>(String clave, T Function() calcular) {
    final f = _firma;
    if (f != _memoFirma) {
      _memoCache.clear();
      _memoFirma = f;
    }
    if (_memoCache.containsKey(clave)) return _memoCache[clave] as T;
    final v = calcular();
    _memoCache[clave] = v;
    return v;
  }

  /// Identificador de la última búsqueda pedida: si llega la respuesta de
  /// una anterior (más lenta), se descarta. Antes, una búsqueda escrita
  /// mientras cargaba se ignoraba y la lista no coincidía con el buscador.
  int _reqId = 0;

  bool _matchCliente(Poliza p, String q) =>
      (p.nombreCliente ?? '').toLowerCase().contains(q) ||
      // doc_cliente se guarda sin puntos — si buscan con puntos igual matchea.
      (p.docCliente ?? '').toLowerCase().contains(q.replaceAll('.', ''));

  List<String> get _opAseguradoras => _memo('_opAseguradoras', () => polizas.where((p) {
    if (_filtroRamo != null && (p.nombreRamo ?? '') != _filtroRamo) return false;
    if (_filtroProd != null && (p.nombreProd ?? '') != _filtroProd) return false;
    if (_filtroAsesor != null && (p.nombreAsesor ?? '') != _filtroAsesor) return false;
    if (_filtroCliente != null && !_matchCliente(p, _filtroCliente!.toLowerCase())) return false;
    return true;
  }).map((p) => p.nombreAseg ?? '').where((s) => s.isNotEmpty).toSet().toList()..sort());

  List<String> get _opRamos => _memo('_opRamos', () => polizas.where((p) {
    if (_filtroAseg != null && (p.nombreAseg ?? '') != _filtroAseg) return false;
    if (_filtroProd != null && (p.nombreProd ?? '') != _filtroProd) return false;
    if (_filtroAsesor != null && (p.nombreAsesor ?? '') != _filtroAsesor) return false;
    if (_filtroCliente != null && !_matchCliente(p, _filtroCliente!.toLowerCase())) return false;
    return true;
  }).map((p) => p.nombreRamo ?? '').where((s) => s.isNotEmpty).toSet().toList()..sort());

  List<String> get _opProductos => _memo('_opProductos', () => polizas.where((p) {
    if (_filtroAseg != null && (p.nombreAseg ?? '') != _filtroAseg) return false;
    if (_filtroRamo != null && (p.nombreRamo ?? '') != _filtroRamo) return false;
    if (_filtroAsesor != null && (p.nombreAsesor ?? '') != _filtroAsesor) return false;
    if (_filtroCliente != null && !_matchCliente(p, _filtroCliente!.toLowerCase())) return false;
    return true;
  }).map((p) => p.nombreProd ?? '').where((s) => s.isNotEmpty).toSet().toList()..sort());

  List<String> get _opAsesores => _memo('_opAsesores', () => polizas.where((p) {
    if (_filtroAseg != null && (p.nombreAseg ?? '') != _filtroAseg) return false;
    if (_filtroRamo != null && (p.nombreRamo ?? '') != _filtroRamo) return false;
    if (_filtroProd != null && (p.nombreProd ?? '') != _filtroProd) return false;
    if (_filtroCliente != null && !_matchCliente(p, _filtroCliente!.toLowerCase())) return false;
    return true;
  }).map((p) => p.nombreAsesor ?? '').where((s) => s.isNotEmpty).toSet().toList()..sort());

  List<String> get _opClientes => _memo('_opClientes', () => polizas.where((p) {
    if (_filtroAseg != null && (p.nombreAseg ?? '') != _filtroAseg) return false;
    if (_filtroRamo != null && (p.nombreRamo ?? '') != _filtroRamo) return false;
    if (_filtroProd != null && (p.nombreProd ?? '') != _filtroProd) return false;
    if (_filtroAsesor != null && (p.nombreAsesor ?? '') != _filtroAsesor) return false;
    return true;
  }).map((p) => p.nombreCliente ?? '').where((s) => s.isNotEmpty).toSet().toList()..sort());

  List<Poliza> get _polizasFiltradas => _memo('filtradas', () => polizas.where((p) {
    if (_filtroAseg != null && (p.nombreAseg ?? '') != _filtroAseg) return false;
    if (_filtroRamo != null && (p.nombreRamo ?? '') != _filtroRamo) return false;
    if (_filtroProd != null && (p.nombreProd ?? '') != _filtroProd) return false;
    if (_filtroAsesor != null && (p.nombreAsesor ?? '') != _filtroAsesor) return false;
    if (_filtroCliente != null && !_matchCliente(p, _filtroCliente!.toLowerCase())) return false;
    return true;
  }).toList());

  void _setFiltro(void Function() setter) {
    setState(setter);
    final hayFiltro = _filtroAseg != null || _filtroRamo != null ||
        _filtroProd != null || _filtroAsesor != null ||
        (_filtroCliente != null && _filtroCliente!.isNotEmpty);
    if (hayFiltro && !_datosCompletos && !cargando) _cargarTodo();
  }

  // Columnas:
  // 0  Cód.          1  Nro Póliza    2  Bien Asegurado
  // 3  Cliente        4  Aseguradora   5  Ramo/Prod
  // 6  F. Ini.        7  F. Venc.      8  Prima
  // 9  Valor         10  F. Exp.      11  Asesor
  // 12 F. Registro   13  Usuario      14  (acciones)
  int _sortColumnIndex = 0;
  bool _sortAscending = false;

  Timer? debounce;
  Timer? _clienteDebounce;

  final ScrollController _verticalCtrl = ScrollController();
  final ScrollController _horizontalCtrl = ScrollController();

  final _repoPend = RepositorioPolizasPendientes();
  int _pendientesCount = 0;
  final _servicioCarga = ServicioCargaMasiva.instance;

  // ── Selección para eliminar ───────────────────────────────────────────
  bool _modoSeleccion = false;
  final Set<int> _sel = {};
  int _eliminacionesPendientes = 0; // solo Administrador
  static const int _maxSeleccion = 200;

  @override
  void initState() {
    super.initState();
    _cargar();
    _cargarPendientesCount();
    _cargarEliminacionesCount();
    _servicioCarga.addListener(_onCambioCargaMasiva);
  }

  bool _procesandoAntes = false;
  void _onCambioCargaMasiva() {
    if (!mounted) return;
    setState(() {});
    // Se acaba de terminar un lote — refresca el contador solo, sin
    // obligar al usuario a volver a la pantalla de carga masiva.
    if (_procesandoAntes && !_servicioCarga.procesando) {
      _cargarPendientesCount();
    }
    _procesandoAntes = _servicioCarga.procesando;
  }

  Future<void> _cargarPendientesCount() async {
    try {
      final n = await _repoPend.contar();
      if (mounted) setState(() => _pendientesCount = n);
    } catch (_) {}
  }

  Future<void> _cargarEliminacionesCount() async {
    if (!Sesion.esAdmin) return;
    try {
      final n = await RepositorioEliminacion().contarPendientes();
      if (mounted) setState(() => _eliminacionesPendientes = n);
    } catch (_) {}
  }

  void _toggleSel(int id) => setState(() {
        if (!_sel.remove(id)) {
          if (_sel.length >= _maxSeleccion) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Máximo 200 pólizas por vez.')));
            return;
          }
          _sel.add(id);
        }
      });

  void _salirSeleccion() => setState(() {
        _modoSeleccion = false;
        _sel.clear();
      });

  /// Selecciona (hasta 200) las pólizas que hoy se ven con los filtros.
  void _seleccionarVisibles(List<Poliza> visibles) => setState(() {
        final ids = visibles.take(_maxSeleccion).map((p) => p.id);
        _sel
          ..clear()
          ..addAll(ids);
        if (visibles.length > _maxSeleccion) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Se seleccionaron las primeras 200 (máximo por vez).')));
        }
      });

  /// Las seleccionadas que se ven con la búsqueda y los filtros de ahora: el
  /// diálogo y el contador solo usan estas, nunca pólizas que quedaron ocultas.
  List<Poliza> get _elegidasVisibles =>
      _polizasFiltradas.where((p) => _sel.contains(p.id)).toList();

  /// Elimina (marca) [lista] o, si es null, las seleccionadas que se ven. Una
  /// sola confirmación para todas.
  Future<void> _eliminar([List<Poliza>? lista]) async {
    final elegidas = lista ?? _elegidasVisibles;
    if (elegidas.isEmpty) return;
    final cambio = await mostrarDialogoEliminarPolizas(context, elegidas);
    if (!mounted) return;
    if (cambio) {
      setState(() {
        if (lista == null) {
          // Eliminación del grupo seleccionado: se sale del modo selección.
          _modoSeleccion = false;
          _sel.clear();
        } else {
          // Papelera de una fila: no se pierde el resto de la selección.
          _sel.removeAll(elegidas.map((p) => p.id));
        }
      });
      // La caché ya no tiene las marcadas: recargar es instantáneo.
      _datosCompletos ? _cargarTodo() : _cargar();
      _cargarEliminacionesCount();
    }
  }

  @override
  void dispose() {
    ctrlBuscar.dispose();
    debounce?.cancel();
    _clienteDebounce?.cancel();
    _verticalCtrl.dispose();
    _horizontalCtrl.dispose();
    _servicioCarga.removeListener(_onCambioCargaMasiva);
    super.dispose();
  }

  /// Carga inicial rápida: 500 más recientes.
  static const int _limiteRapido = 500;

  Future<void> _cargar() async {
    final busqueda = ctrlBuscar.text.trim();
    final req = ++_reqId;
    if (mounted) setState(() { cargando = true; _datosCompletos = false; _errorCarga = null; });
    try {
      final data = await repo.listar(busqueda: busqueda, limite: _limiteRapido)
          .timeout(const Duration(seconds: 30));
      if (!mounted || req != _reqId) return;
      setState(() {
        polizas = data;
        // Si cupo todo, ya son todos los resultados (antes una búsqueda de
        // 12 pólizas decía "mostrando las 12 más recientes").
        _datosCompletos = data.length < _limiteRapido;
        _aplicarOrden();
      });
    } catch (e) {
      if (mounted && req == _reqId) setState(() => _errorCarga = _mensajeError(e));
    } finally {
      if (mounted && req == _reqId) setState(() => cargando = false);
    }
  }

  /// Carga completa paginada: trae todos los registros de a 1.000.
  Future<void> _cargarTodo({bool forzar = false}) async {
    final req = ++_reqId;
    if (mounted) setState(() { cargando = true; _cargados = 0; _errorCarga = null; });
    final busqueda = ctrlBuscar.text.trim();
    try {
      final data = await repo.listarTodos(
        busqueda: busqueda,
        forzar: forzar,
        onProgreso: (n) {
          if (mounted && req == _reqId) setState(() => _cargados = n);
        },
      ).timeout(const Duration(minutes: 3));
      if (!mounted || req != _reqId) return;
      setState(() {
        polizas = data;
        _datosCompletos = true;
        _aplicarOrden();
      });
    } catch (e) {
      if (mounted && req == _reqId) setState(() => _errorCarga = _mensajeError(e));
    } finally {
      if (mounted && req == _reqId) setState(() => cargando = false);
    }
  }

  String _mensajeError(Object e) {
    final s = e.toString();
    if (e is TimeoutException ||
        s.contains('57014') ||
        s.contains('timeout') ||
        s.contains('canceling') ||
        s.contains('TimeoutException')) {
      return 'La consulta tardó demasiado.\nVerifique su conexión e intente de nuevo.';
    }
    if (s.contains('network') ||
        s.contains('connection') ||
        s.contains('SocketException') ||
        s.contains('Failed host')) {
      return 'Sin conexión a internet.\nVerifique su red e intente de nuevo.';
    }
    return 'Error al cargar pólizas.\nIntente de nuevo.';
  }

  void _aplicarOrden() {
    _versionOrden++;
    polizas.sort((a, b) {
      final int cmp;
      switch (_sortColumnIndex) {
        case 0:
          cmp = a.id.compareTo(b.id);
        case 1:
          cmp = (a.nroPoliza ?? '').compareTo(b.nroPoliza ?? '');
        case 2:
          cmp = (a.bienAsegurado ?? '').toLowerCase().compareTo(
                (b.bienAsegurado ?? '').toLowerCase(),
              );
        case 3:
          cmp = (a.nombreCliente ?? '').toLowerCase().compareTo(
                (b.nombreCliente ?? '').toLowerCase(),
              );
        case 4:
          cmp = (a.nombreAseg ?? '').toLowerCase().compareTo(
                (b.nombreAseg ?? '').toLowerCase(),
              );
        case 5:
          cmp = (a.nombreRamo ?? '').toLowerCase().compareTo(
                (b.nombreRamo ?? '').toLowerCase(),
              );
        case 6:
          final da = a.finiPoliza ?? DateTime(9999);
          final db = b.finiPoliza ?? DateTime(9999);
          cmp = da.compareTo(db);
        case 7:
          final da = a.ffinPoliza ?? DateTime(9999);
          final db = b.ffinPoliza ?? DateTime(9999);
          cmp = da.compareTo(db);
        case 8:
          cmp = a.primaPoliza.compareTo(b.primaPoliza);
        case 9:
          cmp = a.valorPoliza.compareTo(b.valorPoliza);
        case 10:
          final da = a.fexpPoliza ?? DateTime(9999);
          final db = b.fexpPoliza ?? DateTime(9999);
          cmp = da.compareTo(db);
        case 11:
          cmp = (a.nombreAsesor ?? '').toLowerCase().compareTo(
                (b.nombreAsesor ?? '').toLowerCase(),
              );
        case 12:
          final da = a.fcreado ?? DateTime(9999);
          final db = b.fcreado ?? DateTime(9999);
          cmp = da.compareTo(db);
        case 15:
          cmp = (a.apodoUsuario ?? '').toLowerCase().compareTo(
                (b.apodoUsuario ?? '').toLowerCase(),
              );
        default:
          cmp = a.id.compareTo(b.id);
      }
      return _sortAscending ? cmp : -cmp;
    });
  }

  void _sort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
      _aplicarOrden();
    });
  }

  void _onBuscarChanged(String _) {
    debounce?.cancel();
    debounce = Timer(
      const Duration(milliseconds: 400),
      () => _cargar(),
    );
  }

  Widget _filtroAuto({
    required String label,
    required String? value,
    required List<String> opciones,
    required ValueChanged<String?> onChanged,
    bool textSearch = false,
    int resetKey = 0,
  }) {
    final cs = Theme.of(context).colorScheme;
    // textSearch: clave estable durante escritura, solo cambia al limpiar (resetKey)
    // exacto: ObjectKey(value) recrea el widget cuando el valor cambia externamente
    final key = textSearch ? ValueKey('$label-$resetKey') : ObjectKey(value);
    return SizedBox(
      width: 210,
      child: Autocomplete<String>(
        key: key,
        initialValue: TextEditingValue(text: value ?? ''),
        optionsBuilder: (tv) {
          final q = tv.text.toLowerCase().trim();
          if (q.isEmpty) return opciones;
          return opciones.where((o) => o.toLowerCase().contains(q));
        },
        optionsViewBuilder: (ctx, onSelected, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260, maxWidth: 280),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (_, i) {
                  final o = options.elementAt(i);
                  return ListTile(
                    dense: true,
                    selected: o == value,
                    title: Text(o, style: const TextStyle(fontSize: 13)),
                    onTap: () => onSelected(o),
                  );
                },
              ),
            ),
          ),
        ),
        onSelected: (sel) => onChanged(sel.isEmpty ? null : sel),
        fieldViewBuilder: (ctx, ctrl, focusNode, _) => TextFormField(
          controller: ctrl,
          focusNode: focusNode,
          style: const TextStyle(fontSize: 13),
          onChanged: (t) {
            if (textSearch) {
              // Filtro de cliente recorre toda la lista en memoria en cada
              // cambio — se espera una pausa al tipear para no recalcularlo
              // en cada tecla.
              _clienteDebounce?.cancel();
              _clienteDebounce = Timer(const Duration(milliseconds: 250),
                  () => onChanged(t.isNotEmpty ? t : null));
            } else {
              if (t.isEmpty && value != null) onChanged(null);
            }
          },
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            filled: true,
            fillColor: cs.surface,
            prefixIcon: const Icon(Icons.search, size: 16),
            suffixIcon: value != null
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      ctrl.clear();
                      setState(() => onChanged(null));
                    },
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _vistaError() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 64, color: cs.error.withOpacity(0.7)),
            const SizedBox(height: 20),
            Text(
              _errorCarga!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtFecha(DateTime? fecha) {
    if (fecha == null) return '—';
    return df.format(fecha);
  }

  String _fmtFechaHora(DateTime? fecha) {
    if (fecha == null) return '—';
    return DateFormat('dd/MM/yyyy HH:mm').format(fecha.toLocal());
  }

  String _fmtNum(num? valor) {
    if (valor == null || valor == 0) return '—';
    return '\$${nf.format(valor.round())}';
  }

  Future<void> _nuevaPoliza() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PaginaFormularioPolizas()),
    );
    if (!mounted) return;
    // La caché ya tiene la póliza guardada (se refresca solo esa fila), así
    // que recargar "todo" no vuelve a descargar las 32 mil.
    _datosCompletos ? _cargarTodo() : _cargar();
    _cargarPendientesCount();
  }

  void _abrirEditar(Poliza p) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaginaFormularioPolizas(poliza: p),
      ),
    );
    if (!mounted) return;
    _datosCompletos ? _cargarTodo() : _cargar();
  }

  Widget _vistaMovil(List<Poliza> data) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
      itemCount: data.length,
      itemBuilder: (_, i) {
        final p = data[i];

        final marcada = _sel.contains(p.id);
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: marcada ? AppTheme.navy.withOpacity(0.08) : null,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _modoSeleccion ? () => _toggleSel(p.id) : () => _abrirEditar(p),
            onLongPress: _modoSeleccion
                ? null
                : () => setState(() {
                      _modoSeleccion = true;
                      _sel.add(p.id);
                    }),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (_modoSeleccion)
                        Checkbox(
                          value: marcada,
                          visualDensity: VisualDensity.compact,
                          onChanged: (_) => _toggleSel(p.id),
                        ),
                      Expanded(
                        child: Text(
                          p.nroPoliza ?? 'Sin número',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Text(
                        'Cód. ${p.id}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      if (!_modoSeleccion)
                        IconButton(
                          tooltip: 'Eliminar (la autoriza un administrador)',
                          icon: const Icon(Icons.delete_outline, size: 22),
                          color: AppTheme.danger,
                          onPressed: () => _eliminar([p]),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.nombreCliente ?? '—',
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (p.clienteId != null)
                        SizedBox(
                          width: 38,
                          child: Text('#${p.clienteId}',
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.clip,
                              softWrap: false,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Theme.of(context).colorScheme.outline)),
                        ),
                    ],
                  ),
                  if ((p.docCliente ?? '').isNotEmpty)
                    Text(
                      '${(p.tipodocCliente ?? '').isNotEmpty ? '${p.tipodocCliente} ' : ''}${Fmt.doc(p.docCliente)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  if ((p.bienAsegurado ?? '').isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.shield_outlined,
                            size: 12,
                            color: Theme.of(context).colorScheme.outline),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            p.bienAsegurado!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if ((p.nombreAseg ?? '').isNotEmpty)
                        _etiqueta(p.nombreAseg!),
                      if ((p.nombreRamo ?? '').isNotEmpty)
                        _etiqueta(p.nombreRamo!),
                      if ((p.nombreAsesor ?? '').isNotEmpty)
                        _etiqueta(p.nombreAsesor!, icono: Icons.person_outline),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Fechas
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      _infoFecha(Icons.edit_calendar_outlined, 'Exp.', p.fexpPoliza),
                      _infoFecha(Icons.play_circle_outline, 'Ini.', p.finiPoliza),
                      _infoFecha(Icons.event_outlined, 'Vence', p.ffinPoliza),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Prima: ${_fmtNum(p.primaPoliza)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if ((p.apodoUsuario ?? '').isNotEmpty)
                        _etiqueta(p.apodoUsuario!, icono: Icons.person_pin_outlined),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _infoFecha(IconData icono, String label, DateTime? fecha) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 13, color: cs.outline),
        const SizedBox(width: 3),
        Text(
          '$label: ${_fmtFecha(fecha)}',
          style: TextStyle(fontSize: 12, color: cs.outline),
        ),
      ],
    );
  }

  Widget _etiqueta(String texto, {IconData? icono}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 11, color: cs.onSurfaceVariant),
            const SizedBox(width: 3),
          ],
          Text(
            texto,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // Anchos columnas escritorio
  static const _wCod = 60.0;
  static const _wNro = 180.0;
  static const _wBien = 160.0;
  static const _wCliente = 190.0;
  static const _wAseg = 150.0;
  static const _wRamo = 140.0;
  static const _wAsesor = 62.0;
  static const _wFecha = 80.0;
  static const _wPrima = 80.0;
  static const _wValor = 80.0;
  static const _wFCreado = 138.0;
  static const _wUsuario = 50.0;
  static const _wAcciones = 124.0;
  static const _wSel = 44.0;
  static const _totalAncho = _wCod + _wNro + _wBien + _wCliente + _wAseg +
      _wRamo + _wAsesor + _wFecha * 3 + _wPrima + _wValor + 12 +
      _wFCreado + _wUsuario + _wAcciones;

  Widget _encabezadoPolizas() {
    final cs = Theme.of(context).colorScheme;
    Widget col(String label, double w, int idx, {bool num = false}) {
      final activo = _sortColumnIndex == idx;
      return InkWell(
        onTap: () => _sort(idx, _sortColumnIndex != idx || !_sortAscending),
        child: SizedBox(
          width: w,
          child: Row(
            mainAxisAlignment: num ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Flexible(
                child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: activo ? cs.primary : null)),
              ),
              if (activo) Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 13, color: cs.primary),
            ],
          ),
        ),
      );
    }
    return Container(
      color: cs.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(children: [
        if (_modoSeleccion)
          SizedBox(
            width: _wSel,
            child: Checkbox(
              tristate: true,
              value: _elegidasVisibles.isEmpty
                  ? false
                  : (_elegidasVisibles.length >=
                          _polizasFiltradas.length.clamp(0, _maxSeleccion)
                      ? true
                      : null),
              onChanged: (_) {
                if (_elegidasVisibles.isEmpty) {
                  _seleccionarVisibles(_polizasFiltradas);
                } else {
                  setState(_sel.clear);
                }
              },
            ),
          ),
        col('Cód.', _wCod, 0, num: true),
        col('Nro Póliza', _wNro, 1),
        col('Bien Asegurado', _wBien, 2),
        col('Cliente', _wCliente, 3),
        col('Aseguradora', _wAseg, 4),
        col('Ramo / Producto', _wRamo, 5),
        col('F. Ini.', _wFecha, 6),
        col('F. Venc.', _wFecha, 7),
        col('V. Prima', _wPrima, 8, num: true),
        col('V. Total', _wValor, 9, num: true),
        const SizedBox(width: 12),
        col('F. Exp.', _wFecha, 10),
        col('Asesor', _wAsesor, 11),
        col('F. Registro / Ult Mod', _wFCreado, 12),
        col('Usuario', _wUsuario, 15),
        const SizedBox(width: _wAcciones),
      ]),
    );
  }

  Widget _filaPoliza(Poliza p) {
    final marcada = _sel.contains(p.id);
    return InkWell(
      onTap: _modoSeleccion ? () => _toggleSel(p.id) : () => _abrirEditar(p),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: marcada ? AppTheme.navy.withOpacity(0.08) : null,
          border: const Border(bottom: BorderSide(color: AppTheme.outlineVariant)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          if (_modoSeleccion)
            SizedBox(
              width: _wSel,
              child: Semantics(
                label: 'Seleccionar la póliza ${p.nroPoliza ?? p.id}',
                child: Checkbox(value: marcada, onChanged: (_) => _toggleSel(p.id)),
              ),
            ),
          SizedBox(width: _wCod, child: Text(p.id.toString(), style: const TextStyle(fontSize: 12), textAlign: TextAlign.right)),
          const SizedBox(width: 8),
          SizedBox(
            width: _wNro - 8,
            child: Tooltip(
              message: p.nroPoliza ?? '—',
              child: Text(p.nroPoliza ?? '—', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            ),
          ),
          SizedBox(
            width: _wBien,
            child: Tooltip(
              message: [
                p.bienAsegurado ?? '—',
                if (p.vlrasegPoliza != null && p.vlrasegPoliza! > 0) _fmtNum(p.vlrasegPoliza),
              ].join('\n'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(p.bienAsegurado ?? '—', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                if (p.vlrasegPoliza != null && p.vlrasegPoliza! > 0)
                  Text(_fmtNum(p.vlrasegPoliza), style: const TextStyle(fontSize: 11, color: AppTheme.inkSoft), overflow: TextOverflow.ellipsis),
              ]),
            ),
          ),
          SizedBox(
            width: _wCliente,
            child: Tooltip(
              message: [
                p.nombreCliente ?? '—',
                if (p.clienteId != null) 'Código: ${p.clienteId}',
                if ((p.docCliente ?? '').isNotEmpty)
                  '${(p.tipodocCliente ?? '').isNotEmpty ? '${p.tipodocCliente} ' : ''}${Fmt.doc(p.docCliente)}',
              ].join('\n'),
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Row(children: [
                  Expanded(
                    child: Text(p.nombreCliente ?? '—', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                  ),
                  if (p.clienteId != null) ...[
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 30,
                      child: Text('#${p.clienteId}',
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.outline)),
                    ),
                  ],
                ]),
                if ((p.docCliente ?? '').isNotEmpty)
                  Text(
                    '${(p.tipodocCliente ?? '').isNotEmpty ? '${p.tipodocCliente} ' : ''}${Fmt.doc(p.docCliente)}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.inkSoft),
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
            ),
          ),
          SizedBox(
            width: _wAseg,
            child: Tooltip(
              message: p.nombreAseg ?? '—',
              child: Text(p.nombreAseg ?? '—', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            ),
          ),
          SizedBox(
            width: _wRamo,
            child: Tooltip(
              message: [
                p.nombreRamo ?? '—',
                if ((p.nombreProd ?? '').isNotEmpty) p.nombreProd!,
              ].join('\n'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(p.nombreRamo ?? '—', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                if ((p.nombreProd ?? '').isNotEmpty)
                  Text(p.nombreProd!, style: const TextStyle(fontSize: 11, color: AppTheme.inkSoft), overflow: TextOverflow.ellipsis),
              ]),
            ),
          ),
          SizedBox(width: _wFecha, child: Tooltip(message: _fmtFecha(p.finiPoliza), child: Text(_fmtFecha(p.finiPoliza), style: const TextStyle(fontSize: 12)))),
          SizedBox(width: _wFecha, child: Tooltip(message: _fmtFecha(p.ffinPoliza), child: Text(_fmtFecha(p.ffinPoliza), style: const TextStyle(fontSize: 12)))),
          SizedBox(width: _wPrima, child: Tooltip(message: _fmtNum(p.primaPoliza), child: Text(_fmtNum(p.primaPoliza), style: const TextStyle(fontSize: 12), textAlign: TextAlign.right))),
          SizedBox(width: _wValor, child: Tooltip(message: _fmtNum(p.valorPoliza), child: Text(_fmtNum(p.valorPoliza), style: const TextStyle(fontSize: 12), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis))),
          const SizedBox(width: 12),
          SizedBox(width: _wFecha, child: Tooltip(message: _fmtFecha(p.fexpPoliza), child: Text(_fmtFecha(p.fexpPoliza), style: const TextStyle(fontSize: 12)))),
          SizedBox(
            width: _wAsesor,
            child: Tooltip(
              message: p.nombreAsesor ?? '—',
              child: Text(p.nombreAsesor ?? '—', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            ),
          ),
          SizedBox(
            width: _wFCreado,
            child: Tooltip(
              message: [
                _fmtFechaHora(p.fcreado),
                if (p.fultmod != null) _fmtFechaHora(p.fultmod),
              ].join('\n'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(_fmtFechaHora(p.fcreado), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                if (p.fultmod != null)
                  Text(_fmtFechaHora(p.fultmod), style: const TextStyle(fontSize: 10, color: AppTheme.inkSoft), overflow: TextOverflow.ellipsis),
              ]),
            ),
          ),
          SizedBox(
            width: _wUsuario,
            child: Tooltip(
              message: p.apodoUsuario ?? '—',
              child: Text(p.apodoUsuario ?? '—', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            ),
          ),
          SizedBox(
            width: _wAcciones,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Editar',
                icon: const Icon(Icons.edit, size: 18),
                onPressed: () => _abrirEditar(p),
              ),
              IconButton(
                tooltip: 'Eliminar (la autoriza un administrador)',
                icon: const Icon(Icons.delete_outline, size: 18),
                color: AppTheme.danger,
                onPressed: () => _eliminar([p]),
              ),
              IconButton(
                tooltip: 'Ver pagos',
                icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                color: const Color(0xFF6A1B9A),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PaginaEstadoCuenta.poliza(idPoliza: p.id),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _vistaEscritorio(List<Poliza> data) {
    return Scrollbar(
      controller: _horizontalCtrl,
      thumbVisibility: true,
      notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: _horizontalCtrl,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: _totalAncho + 16 + (_modoSeleccion ? _wSel : 0),
          child: Column(children: [
            _encabezadoPolizas(),
            Expanded(
              child: Scrollbar(
                controller: _verticalCtrl,
                thumbVisibility: true,
                child: ListView.builder(
                  controller: _verticalCtrl,
                  itemCount: data.length,
                  itemExtent: 48,
                  itemBuilder: (_, i) => _filaPoliza(data[i]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // En pantallas angostas (móvil) las acciones secundarias van a un menú.
    final angosto = MediaQuery.sizeOf(context).width < 640;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, alt: true): _nuevaPoliza,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_modoSeleccion) _salirSeleccion();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
      appBar: AppBar(
        title: const Text('Pólizas'),
        actions: [
          IconButton(
            tooltip: 'Nueva póliza (Alt+N)',
            icon: const Icon(Icons.add),
            onPressed: _nuevaPoliza,
          ),
          angosto
              ? IconButton(
                  tooltip: _modoSeleccion
                      ? 'Salir de la selección'
                      : 'Seleccionar varias pólizas para eliminar',
                  icon: Icon(_modoSeleccion ? Icons.close : Icons.checklist_rtl),
                  onPressed: () => _modoSeleccion
                      ? _salirSeleccion()
                      : setState(() => _modoSeleccion = true),
                )
              : TextButton.icon(
                  onPressed: () => _modoSeleccion
                      ? _salirSeleccion()
                      : setState(() => _modoSeleccion = true),
                  icon: Icon(_modoSeleccion ? Icons.close : Icons.checklist_rtl, size: 18),
                  label: Text(_modoSeleccion ? 'Salir de la selección' : 'Eliminar varias'),
                ),
          if (Sesion.esAdmin)
            IconButton(
              tooltip: 'Eliminaciones por autorizar',
              icon: Badge(
                label: Text('$_eliminacionesPendientes'),
                isLabelVisible: _eliminacionesPendientes > 0,
                child: const Icon(Icons.delete_sweep_outlined),
              ),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const PaginaEliminacionesPendientes()),
                );
                if (!mounted) return;
                _cargarEliminacionesCount();
                _datosCompletos ? _cargarTodo() : _cargar();
              },
            ),
          if (!angosto)
          IconButton(
            tooltip: 'Recargar lista',
            icon: const Icon(Icons.refresh),
            onPressed: cargando ? null : () => _datosCompletos ? _cargarTodo(forzar: true) : _cargar(),
          ),
          if (!angosto)
          IconButton(
            icon: const Icon(Icons.content_copy_outlined),
            tooltip: 'Pólizas con número repetido',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PaginaPolizasDuplicadas()),
            ),
          ),
          if (_servicioCarga.procesando)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PaginaCargaMasivaPolizas()),
                ),
                icon: const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                label: Text(
                    'Cargando ${_servicioCarga.procesados}/${_servicioCarga.items.length}'),
              ),
            ),
          if (!angosto)
          IconButton(
            icon: const Icon(Icons.upload_file_outlined),
            tooltip: 'Carga masiva de pólizas (PDF/imagen con IA)',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PaginaCargaMasivaPolizas()),
              );
              _cargarPendientesCount();
            },
          ),
          IconButton(
            icon: Badge(
              label: Text('$_pendientesCount'),
              isLabelVisible: _pendientesCount > 0,
              child: const Icon(Icons.pending_actions_outlined),
            ),
            tooltip: 'Pólizas pendientes (borrador / por revisar)',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PaginaPolizasPendientes()),
              );
              if (!mounted) return;
              _cargarPendientesCount();
              // Si desde ahí se guardó una póliza real, la caché ya la tiene
              // (se refresca solo esa fila): no hace falta bajar todo otra vez.
              _datosCompletos ? _cargarTodo() : _cargar();
            },
          ),
          if (!angosto)
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Catálogos',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PaginaCatalogos()),
            ),
          ),
          if (angosto)
            PopupMenuButton<String>(
              tooltip: 'Más opciones',
              onSelected: (v) async {
                switch (v) {
                  case 'recargar':
                    if (!cargando) {
                      _datosCompletos ? _cargarTodo(forzar: true) : _cargar();
                    }
                  case 'duplicadas':
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const PaginaPolizasDuplicadas()));
                  case 'masiva':
                    await Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const PaginaCargaMasivaPolizas()));
                    _cargarPendientesCount();
                  case 'catalogos':
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const PaginaCatalogos()));
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'recargar', child: Text('Recargar lista')),
                PopupMenuItem(value: 'duplicadas', child: Text('Pólizas con número repetido')),
                PopupMenuItem(value: 'masiva', child: Text('Carga masiva (PDF/imagen con IA)')),
                PopupMenuItem(value: 'catalogos', child: Text('Catálogos')),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: TextField(
              controller: ctrlBuscar,
              onChanged: _onBuscarChanged,
              decoration: const InputDecoration(
                labelText:
                    'Buscar por ID, nro. póliza, cliente, documento, aseguradora, ramo, asesor…',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _filtroAuto(
                  label: 'Cliente',
                  value: _filtroCliente,
                  opciones: _opClientes,
                  textSearch: true,
                  resetKey: _clienteResetKey,
                  onChanged: (v) => _setFiltro(() => _filtroCliente = v),
                ),
                _filtroAuto(
                  label: 'Aseguradora',
                  value: _filtroAseg,
                  opciones: _opAseguradoras,
                  onChanged: (v) => _setFiltro(() => _filtroAseg = v),
                ),
                _filtroAuto(
                  label: 'Ramo',
                  value: _filtroRamo,
                  opciones: _opRamos,
                  onChanged: (v) => _setFiltro(() => _filtroRamo = v),
                ),
                _filtroAuto(
                  label: 'Producto',
                  value: _filtroProd,
                  opciones: _opProductos,
                  onChanged: (v) => _setFiltro(() => _filtroProd = v),
                ),
                _filtroAuto(
                  label: 'Asesor',
                  value: _filtroAsesor,
                  opciones: _opAsesores,
                  onChanged: (v) => _setFiltro(() => _filtroAsesor = v),
                ),
                if (_filtroAseg != null || _filtroRamo != null ||
                    _filtroProd != null || _filtroAsesor != null ||
                    _filtroCliente != null)
                  TextButton.icon(
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('Limpiar', style: TextStyle(fontSize: 13)),
                    onPressed: () => setState(() {
                      _filtroAseg = null;
                      _filtroRamo = null;
                      _filtroProd = null;
                      _filtroAsesor = null;
                      _filtroCliente = null;
                      _clienteResetKey++;
                    }),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Row(
              children: [
                Icon(Icons.keyboard_outlined, size: 14, color: AppTheme.inkSoft),
                const SizedBox(width: 6),
                Text(
                  'Presiona Alt+N para crear una nueva póliza',
                  style: TextStyle(fontSize: 12, color: AppTheme.inkSoft),
                ),
              ],
            ),
          ),
          if (_modoSeleccion)
            Container(
              width: double.infinity,
              color: AppTheme.navy.withOpacity(0.06),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _elegidasVisibles.isEmpty
                        ? 'Toque las pólizas que quiere eliminar'
                        : '${plural(_elegidasVisibles.length, 'póliza seleccionada', 'pólizas seleccionadas')}'
                            '${_sel.length > _elegidasVisibles.length ? ' (${_sel.length - _elegidasVisibles.length} más quedaron ocultas por el filtro y no se incluyen)' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextButton(
                    onPressed: _polizasFiltradas.isEmpty
                        ? null
                        : () => _seleccionarVisibles(_polizasFiltradas),
                    child: Text(_polizasFiltradas.length > _maxSeleccion
                        ? 'Seleccionar las primeras $_maxSeleccion de ${_polizasFiltradas.length}'
                        : 'Seleccionar todas las visibles (${_polizasFiltradas.length})'),
                  ),
                  if (_sel.isNotEmpty)
                    TextButton(
                        onPressed: () => setState(_sel.clear),
                        child: const Text('Quitar selección')),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
                    onPressed: _elegidasVisibles.isEmpty ? null : () => _eliminar(),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text('Eliminar (${_elegidasVisibles.length})'),
                  ),
                  TextButton(onPressed: _salirSeleccion, child: const Text('Cancelar')),
                ],
              ),
            ),
          if (cargando) ...[
            const LinearProgressIndicator(),
            if (_cargados > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Text(
                  'Cargando... ${_cargados.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} pólizas',
                  style: TextStyle(fontSize: 12, color: AppTheme.inkSoft),
                ),
              ),
          ],
          if (!cargando && !_datosCompletos && polizas.isNotEmpty)
            MaterialBanner(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              content: Text(
                'Mostrando las ${polizas.length} pólizas más recientes.',
                style: const TextStyle(fontSize: 13),
              ),
              leading: const Icon(Icons.info_outline, size: 20),
              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
              actions: [
                TextButton.icon(
                  icon: const Icon(Icons.download_outlined, size: 16),
                  label: const Text('Cargar todas'),
                  onPressed: _cargarTodo,
                ),
              ],
            ),
          Expanded(
            child: cargando && polizas.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _errorCarga != null && polizas.isEmpty
                    ? _vistaError()
                    : polizas.isEmpty
                        ? const Center(child: Text('No se encontraron pólizas'))
                        : LayoutBuilder(
                        builder: (context, constraints) {
                          final data = _polizasFiltradas;
                          if (data.isEmpty) {
                            return const Center(
                              child: Text('Ninguna póliza coincide con los filtros'),
                            );
                          }
                          return constraints.maxWidth < 600
                              ? _vistaMovil(data)
                              : _vistaEscritorio(data);
                        },
                      ),
          ),
        ],
      ),
        ),
      ),
    );
  }
}
