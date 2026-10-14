import 'dart:async';
import 'package:flutter/material.dart';
import '../../datos/catalogos.dart';
import '../../datos/repositorio_catalogos.dart';
import '../../utils/formatters.dart';
import '../pagina_polizas_de_cliente.dart';
import '../theme/app_theme.dart';
import 'form_cliente.dart';
import 'pagina_clientes_duplicados.dart';
import '../../utils/mensajes_error.dart';

class ListaClientes extends StatefulWidget {
  const ListaClientes({super.key});

  @override
  State<ListaClientes> createState() => _ListaClientesState();
}

class _ListaClientesState extends State<ListaClientes> {
  final repo = RepositorioCatalogos();

  bool cargando = true;
  bool _cargandoTodo = false;
  bool _todosLoaded = false;
  List<Cliente> items = [];

  final TextEditingController _buscarCtrl = TextEditingController();
  Timer? _debounce;

  final ScrollController _verticalCtrl = ScrollController();
  final ScrollController _horizontalCtrl = ScrollController();

  int? _sortColumnIndex;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _cargar();
    _buscarCtrl.addListener(_onBuscar);
  }

  @override
  void dispose() {
    _buscarCtrl.removeListener(_onBuscar);
    _buscarCtrl.dispose();
    _debounce?.cancel();
    _verticalCtrl.dispose();
    _horizontalCtrl.dispose();
    super.dispose();
  }

  void _onBuscar() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _cargar);
  }

  Map<int, String> _municNombre = {};

  /// Solo vale la respuesta de la última búsqueda: si una anterior (más
  /// lenta) llega después, se descarta en vez de pisar la lista.
  int _reqId = 0;

  Future<void> _cargar() async {
    final req = ++_reqId;
    setState(() { cargando = true; _todosLoaded = false; });
    try {
      final q = _buscarCtrl.text.trim();
      final futures = await Future.wait([
        q.isEmpty ? repo.listarClientes() : repo.buscarClientesCompleto(q),
        if (_municNombre.isEmpty) repo.listarMunicipios(),
      ]);

      final clientes = futures[0] as List<Cliente>;
      if (_municNombre.isEmpty && futures.length > 1) {
        final municipios = futures[1] as List<Municipio>;
        _municNombre = {for (final m in municipios) m.id: m.nombreMunic};
      }

      // Inyectar nombre de municipio en memoria
      final conMunic = clientes.map((c) {
        if (c.municId == null || c.nombreMunicipio != null) return c;
        final nombre = _municNombre[c.municId];
        if (nombre == null) return c;
        return Cliente(
          id: c.id,
          nombreCliente: c.nombreCliente,
          tipopersCliente: c.tipopersCliente,
          tipodocCliente: c.tipodocCliente,
          docCliente: c.docCliente,
          telCliente: c.telCliente,
          correoCliente: c.correoCliente,
          dirCliente: c.dirCliente,
          municId: c.municId,
          nombreMunicipio: nombre,
          notasCliente: c.notasCliente,
          contactoCliente: c.contactoCliente,
          cargocontCliente: c.cargocontCliente,
          asesorId: c.asesorId,
          estadoCliente: c.estadoCliente,
          recordarCliente: c.recordarCliente,
        );
      }).toList();

      conMunic.sort((a, b) => a.id.compareTo(b.id));

      if (!mounted || req != _reqId) return;
      if (q.isNotEmpty && clientes.length >= RepositorioCatalogos.maxResultadosBusquedaClientes) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Hay más de 500 coincidencias: se muestran las primeras 500. '
              'Escriba más letras para afinar la búsqueda.'),
        ));
      }
      setState(() {
        items = conMunic;
        _sortColumnIndex = 0;
        _sortAscending = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensajeAmigable(e))));
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }

  void _sort<T>(
    Comparable<T> Function(Cliente c) getField,
    int columnIndex,
    bool ascending,
  ) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
      items.sort((a, b) {
        final aValue = getField(a);
        final bValue = getField(b);
        return ascending
            ? Comparable.compare(aValue, bValue)
            : Comparable.compare(bValue, aValue);
      });
    });
  }

  bool _esErrorRelacion(dynamic e) {
    final s = e.toString();
    return s.contains('23503') || s.toLowerCase().contains('foreign key');
  }

  Future<void> _cargarTodos() async {
    setState(() => _cargandoTodo = true);
    try {
      final todos = await repo.listarTodosClientes();
      final conMunic = todos.map((c) {
        if (c.municId == null || c.nombreMunicipio != null) return c;
        final nombre = _municNombre[c.municId];
        if (nombre == null) return c;
        return Cliente(
          id: c.id,
          nombreCliente: c.nombreCliente,
          tipopersCliente: c.tipopersCliente,
          tipodocCliente: c.tipodocCliente,
          docCliente: c.docCliente,
          telCliente: c.telCliente,
          correoCliente: c.correoCliente,
          dirCliente: c.dirCliente,
          municId: c.municId,
          nombreMunicipio: nombre,
          notasCliente: c.notasCliente,
          contactoCliente: c.contactoCliente,
          cargocontCliente: c.cargocontCliente,
          asesorId: c.asesorId,
          estadoCliente: c.estadoCliente,
          recordarCliente: c.recordarCliente,
        );
      }).toList();
      if (!mounted) return;
      setState(() {
        items = conMunic;
        _todosLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensajeAmigable(e))));
    } finally {
      if (mounted) setState(() => _cargandoTodo = false);
    }
  }

  List<Cliente> get _filtrados => items;

  Future<void> _eliminar(Cliente c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar cliente'),
        content: Text('¿Eliminar "${c.nombreCliente}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await repo.eliminarCliente(c.id);
      await _cargar();
    } catch (e) {
      final msg = _esErrorRelacion(e)
          ? 'No se puede eliminar porque este cliente ya está relacionado con pólizas.'
          : e.toString().replaceFirst('Exception: ', '');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _abrirEditar(Cliente c) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FormCliente(cliente: c)),
    ).then((_) => _cargar());
  }

  void _verPolizas(Cliente c) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaginaPolizasDeCliente(
          clienteId: c.id,
          nombreCliente: c.nombreCliente,
        ),
      ),
    );
  }

  Widget _vistaMovil(List<Cliente> data) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
      itemCount: data.length,
      itemBuilder: (_, i) {
        final c = data[i];
        final docTxt = [
          if ((c.tipodocCliente ?? '').isNotEmpty) c.tipodocCliente!.trim(),
          if ((c.docCliente ?? '').isNotEmpty) Fmt.doc(c.docCliente),
        ].join(' ');

        final linea2 = [
          if ((c.telCliente ?? '').isNotEmpty) c.telCliente!,
          if ((c.correoCliente ?? '').isNotEmpty) c.correoCliente!,
        ].join('  ·  ');

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            isThreeLine: true,
            onTap: () => _abrirEditar(c),
            title: Text(
              c.nombreCliente,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (docTxt.isNotEmpty) Text(docTxt, style: const TextStyle(fontSize: 12)),
                if (linea2.isNotEmpty)
                  Text(linea2, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                if ((c.nombreMunicipio ?? '').isNotEmpty)
                  Text(c.nombreMunicipio!, style: const TextStyle(fontSize: 12)),
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') {
                  _abrirEditar(c);
                } else if (v == 'polizas') {
                  _verPolizas(c);
                } else {
                  _eliminar(c);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [
                    Icon(Icons.edit_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('Editar'),
                  ]),
                ),
                PopupMenuItem(
                  value: 'polizas',
                  child: Row(children: [
                    Icon(Icons.description_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('Ver pólizas'),
                  ]),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline, size: 18, color: AppTheme.danger),
                    SizedBox(width: 10),
                    Text('Eliminar', style: TextStyle(color: AppTheme.danger)),
                  ]),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Anchos de columna para la vista virtualizada
  static const _wId = 70.0;
  static const _wNombre = 220.0;
  static const _wDoc = 160.0;
  static const _wTel = 130.0;
  static const _wCorreo = 200.0;
  static const _wMunic = 180.0;
  static const _wAcciones = 130.0;

  Widget _encabezado() {
    final cs = Theme.of(context).colorScheme;
    Widget col(String label, double w, VoidCallback onTap, int idx) {
      final activo = _sortColumnIndex == idx;
      return InkWell(
        onTap: onTap,
        child: SizedBox(
          width: w,
          child: Row(children: [
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: activo ? cs.primary : null)),
            if (activo)
              Icon(
                _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 14,
                color: cs.primary,
              ),
          ]),
        ),
      );
    }

    return Container(
      color: cs.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(children: [
        col('ID', _wId, () => _sort<num>((c) => c.id, 0, _sortColumnIndex != 0 || !_sortAscending), 0),
        col('Nombre', _wNombre, () => _sort<String>((c) => c.nombreCliente.toLowerCase(), 1, _sortColumnIndex != 1 || !_sortAscending), 1),
        col('Documento', _wDoc, () => _sort<String>((c) => (c.docCliente ?? '').toLowerCase(), 2, _sortColumnIndex != 2 || !_sortAscending), 2),
        col('Teléfono', _wTel, () => _sort<String>((c) => (c.telCliente ?? '').toLowerCase(), 3, _sortColumnIndex != 3 || !_sortAscending), 3),
        col('Correo', _wCorreo, () => _sort<String>((c) => (c.correoCliente ?? '').toLowerCase(), 4, _sortColumnIndex != 4 || !_sortAscending), 4),
        col('Municipio', _wMunic, () => _sort<String>((c) => (c.nombreMunicipio ?? '').toLowerCase(), 5, _sortColumnIndex != 5 || !_sortAscending), 5),
        const SizedBox(width: _wAcciones),
      ]),
    );
  }

  Widget _filaEscritorio(Cliente c) {
    final docTxt = [
      if ((c.tipodocCliente ?? '').isNotEmpty) c.tipodocCliente!.trim(),
      if ((c.docCliente ?? '').isNotEmpty) Fmt.doc(c.docCliente),
    ].join(' ');

    return InkWell(
      onTap: () => _abrirEditar(c),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.outlineVariant)),
        ),
        child: Row(children: [
          SizedBox(width: _wId, child: Text(c.id.toString(), style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wNombre, child: Text(c.nombreCliente, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wDoc, child: Text(docTxt, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wTel, child: Text(c.telCliente ?? '', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wCorreo, child: Text(c.correoCliente ?? '', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wMunic, child: Text(c.nombreMunicipio ?? '', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          SizedBox(
            width: _wAcciones,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: 'Ver pólizas', icon: const Icon(Icons.description_outlined, size: 18), onPressed: () => _verPolizas(c)),
              IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit, size: 18), onPressed: () => _abrirEditar(c)),
              IconButton(tooltip: 'Eliminar', icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => _eliminar(c)),
            ]),
          ),
        ]),
      ),
    );
  }

  static const _totalAncho = _wId + _wNombre + _wDoc + _wTel + _wCorreo + _wMunic + _wAcciones;

  Widget _vistaEscritorio(List<Cliente> data) {
    return Scrollbar(
      controller: _horizontalCtrl,
      thumbVisibility: true,
      notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: _horizontalCtrl,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: _totalAncho + 16,
          child: Column(
            children: [
              _encabezado(),
              Expanded(
                child: Scrollbar(
                  controller: _verticalCtrl,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: _verticalCtrl,
                    itemCount: data.length,
                    itemExtent: 44,
                    itemBuilder: (_, i) => _filaEscritorio(data[i]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _filtrados;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
        actions: [
          IconButton(
            tooltip: 'Clientes duplicados',
            icon: const Icon(Icons.content_copy_outlined),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PaginaClientesDuplicados()),
              );
              _cargar();
            },
          ),
          IconButton(
            tooltip: 'Refrescar',
            icon: const Icon(Icons.refresh),
            onPressed: (cargando || _cargandoTodo) ? null : _cargar,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nuevo cliente',
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FormCliente()),
          );
          _cargar();
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: TextField(
              controller: _buscarCtrl,
              decoration: InputDecoration(
                labelText: 'Buscar (nombre, documento, teléfono, correo)',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _buscarCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar',
                        icon: const Icon(Icons.clear),
                        onPressed: () => _buscarCtrl.clear(),
                      ),
              ),
            ),
          ),
          if (cargando || _cargandoTodo) const LinearProgressIndicator(),
          if (!cargando && !_todosLoaded && items.isNotEmpty && _buscarCtrl.text.isEmpty)
            MaterialBanner(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              content: Text(
                'Mostrando los primeros ${items.length} clientes (A–Z).',
                style: const TextStyle(fontSize: 13),
              ),
              leading: const Icon(Icons.info_outline, size: 20),
              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
              actions: [
                _cargandoTodo
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton.icon(
                        icon: const Icon(Icons.download_outlined, size: 16),
                        label: const Text('Cargar todos'),
                        onPressed: _cargarTodos,
                      ),
              ],
            ),
          Expanded(
            child: cargando && items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : data.isEmpty
                    ? const Center(child: Text('No hay clientes.'))
                    : LayoutBuilder(
                        builder: (context, constraints) =>
                            constraints.maxWidth < 600
                                ? _vistaMovil(data)
                                : _vistaEscritorio(data),
                      ),
          ),
        ],
      ),
    );
  }
}
