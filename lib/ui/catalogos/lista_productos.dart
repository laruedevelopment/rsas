import 'package:flutter/material.dart';
import '../../datos/catalogos.dart';
import '../../datos/repositorio_catalogos.dart';
import '../theme/app_theme.dart';
import 'form_producto.dart';
import '../../utils/mensajes_error.dart';

class ListaProductos extends StatefulWidget {
  const ListaProductos({super.key});

  @override
  State<ListaProductos> createState() => _ListaProductosState();
}

class _ListaProductosState extends State<ListaProductos> {
  final repo = RepositorioCatalogos();

  bool cargando = true;
  List<Producto> items = [];

  final Map<int, String> _ramoNombreById = {};
  final Map<int, String> _asegNombreById = {};

  final TextEditingController _buscarCtrl = TextEditingController();
  String _filtro = '';

  final ScrollController _verticalCtrl = ScrollController();
  final ScrollController _horizontalCtrl = ScrollController();

  int? _sortColumnIndex;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _cargar();
    _buscarCtrl.addListener(() {
      setState(() => _filtro = _buscarCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _buscarCtrl.dispose();
    _verticalCtrl.dispose();
    _horizontalCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar({bool forzar = false}) async {
    setState(() => cargando = true);
    try {
      final res = await Future.wait([
        repo.listarProductos(forzar: forzar),
        repo.listarRamos(forzar: forzar),
        repo.listarAseguradoras(forzar: forzar),
      ]);

      final prods = res[0] as List<Producto>;
      final ramos = res[1] as List<Ramo>;
      final aseg = res[2] as List<Aseguradora>;

      _ramoNombreById
        ..clear()
        ..addEntries(ramos.map((r) => MapEntry(r.id, r.nombreRamo)));

      _asegNombreById
        ..clear()
        ..addEntries(aseg.map((a) => MapEntry(a.id, a.nombreAseg)));

      prods.sort((a, b) => a.id.compareTo(b.id));

      if (!mounted) return;
      setState(() {
        items = prods;
        _sortColumnIndex = 0;
        _sortAscending = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensajeAmigable(e))),
      );
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }

  bool _esErrorRelacion(dynamic e) {
    final s = e.toString();
    return s.contains('23503') || s.toLowerCase().contains('foreign key');
  }

  String _ramoNombre(int ramoId) => _ramoNombreById[ramoId] ?? 'Ramo desconocido';
  String _asegNombre(int asegId) => _asegNombreById[asegId] ?? 'Aseguradora desconocida';

  void _sort<T>(
    Comparable<T> Function(Producto p) getField,
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

  Future<void> _eliminar(Producto p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text('¿Eliminar "${p.nombreProd}"?'),
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
      await repo.eliminarProducto(p.id);
      await _cargar();
    } catch (e) {
      final msg = _esErrorRelacion(e)
          ? 'No se puede eliminar porque este producto ya está relacionado con pólizas.'
          : e.toString().replaceFirst('Exception: ', '');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _abrirEditar(Producto p) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FormProducto(producto: p)),
    ).then((_) => _cargar());
  }

  List<Producto> get _filtrados {
    if (_filtro.isEmpty) return items;

    return items.where((p) {
      final id = p.id.toString();
      final nombre = p.nombreProd.toLowerCase();
      final ramo = _ramoNombre(p.ramoId).toLowerCase();
      final aseg = _asegNombre(p.aseguradoraId).toLowerCase();
      final desc = (p.descProd ?? '').toLowerCase();
      final obs = (p.obsProd ?? '').toLowerCase();
      final comision = (p.comisionProd?.toString() ?? '').toLowerCase();
      final porcom = (p.porcomProd?.toString() ?? '').toLowerCase();
      final porcad = (p.porcadProd?.toString() ?? '').toLowerCase();
      final estado = p.estadoProd ? 'activo' : 'inactivo';

      return id.contains(_filtro) ||
          nombre.contains(_filtro) ||
          ramo.contains(_filtro) ||
          aseg.contains(_filtro) ||
          desc.contains(_filtro) ||
          obs.contains(_filtro) ||
          comision.contains(_filtro) ||
          porcom.contains(_filtro) ||
          porcad.contains(_filtro) ||
          estado.contains(_filtro);
    }).toList();
  }

  Widget _chip(bool activo) {
    final cs = Theme.of(context).colorScheme;
    return Chip(
      label: Text(activo ? 'Activo' : 'Inactivo'),
      visualDensity: VisualDensity.compact,
      backgroundColor:
          activo ? cs.secondaryContainer : cs.surfaceContainerHighest,
      labelStyle: TextStyle(
        fontSize: 12,
        color: activo ? cs.onSecondaryContainer : cs.onSurfaceVariant,
      ),
    );
  }

  Widget _vistaMovil(List<Producto> data) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
      itemCount: data.length,
      itemBuilder: (_, i) {
        final p = data[i];
        final ramo = _ramoNombre(p.ramoId);
        final aseg = _asegNombre(p.aseguradoraId);

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            isThreeLine: true,
            onTap: () => _abrirEditar(p),
            title: Text(
              p.nombreProd,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ramo, style: const TextStyle(fontSize: 12)),
                Text(aseg, style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
                const SizedBox(height: 6),
                _chip(p.estadoProd),
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') { _abrirEditar(p); } else { _eliminar(p); }
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

  static const _wId = 70.0;
  static const _wNombre = 220.0;
  static const _wRamo = 180.0;
  static const _wAseg = 200.0;
  static const _wComFija = 110.0;
  static const _wPorCom = 100.0;
  static const _wPorAd = 100.0;
  static const _wDesc = 200.0;
  static const _wObs = 220.0;
  static const _wEstado = 100.0;
  static const _wAcciones = 90.0;
  static const _totalAncho = _wId + _wNombre + _wRamo + _wAseg + _wComFija + _wPorCom + _wPorAd + _wDesc + _wObs + _wEstado + _wAcciones;

  Widget _encabezado() {
    final cs = Theme.of(context).colorScheme;
    Widget col(String label, double w, VoidCallback onTap, int idx) {
      final activo = _sortColumnIndex == idx;
      return InkWell(
        onTap: onTap,
        child: SizedBox(
          width: w,
          child: Row(children: [
            Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: activo ? cs.primary : null)),
            if (activo) Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 14, color: cs.primary),
          ]),
        ),
      );
    }
    return Container(
      color: cs.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(children: [
        col('ID', _wId, () => _sort<num>((p) => p.id, 0, _sortColumnIndex != 0 || !_sortAscending), 0),
        col('Producto', _wNombre, () => _sort<String>((p) => p.nombreProd.toLowerCase(), 1, _sortColumnIndex != 1 || !_sortAscending), 1),
        col('Ramo', _wRamo, () => _sort<String>((p) => _ramoNombre(p.ramoId).toLowerCase(), 2, _sortColumnIndex != 2 || !_sortAscending), 2),
        col('Aseguradora', _wAseg, () => _sort<String>((p) => _asegNombre(p.aseguradoraId).toLowerCase(), 3, _sortColumnIndex != 3 || !_sortAscending), 3),
        col('Com. fija', _wComFija, () => _sort<num>((p) => p.comisionProd ?? 0, 4, _sortColumnIndex != 4 || !_sortAscending), 4),
        col('% Com.', _wPorCom, () => _sort<num>((p) => p.porcomProd ?? 0, 5, _sortColumnIndex != 5 || !_sortAscending), 5),
        col('% Adic.', _wPorAd, () => _sort<num>((p) => p.porcadProd ?? 0, 6, _sortColumnIndex != 6 || !_sortAscending), 6),
        col('Descripción', _wDesc, () => _sort<String>((p) => (p.descProd ?? '').toLowerCase(), 7, _sortColumnIndex != 7 || !_sortAscending), 7),
        col('Observaciones', _wObs, () => _sort<String>((p) => (p.obsProd ?? '').toLowerCase(), 8, _sortColumnIndex != 8 || !_sortAscending), 8),
        col('Estado', _wEstado, () => _sort<String>((p) => p.estadoProd ? 'activo' : 'inactivo', 9, _sortColumnIndex != 9 || !_sortAscending), 9),
        const SizedBox(width: _wAcciones),
      ]),
    );
  }

  Widget _filaEscritorio(Producto p) {
    return InkWell(
      onTap: () => _abrirEditar(p),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.outlineVariant))),
        child: Row(children: [
          SizedBox(width: _wId, child: Text(p.id.toString(), style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wNombre, child: Text(p.nombreProd, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wRamo, child: Text(_ramoNombre(p.ramoId), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wAseg, child: Text(_asegNombre(p.aseguradoraId), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wComFija, child: Text(p.comisionProd?.toString() ?? '', style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wPorCom, child: Text(p.porcomProd?.toString() ?? '', style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wPorAd, child: Text(p.porcadProd?.toString() ?? '', style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wDesc, child: Text(p.descProd ?? '', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wObs, child: Text(p.obsProd ?? '', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wEstado, child: _chip(p.estadoProd)),
          SizedBox(width: _wAcciones, child: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit, size: 18), onPressed: () => _abrirEditar(p)),
            IconButton(tooltip: 'Eliminar', icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => _eliminar(p)),
          ])),
        ]),
      ),
    );
  }

  Widget _vistaEscritorio(List<Producto> data) {
    return Scrollbar(
      controller: _horizontalCtrl,
      thumbVisibility: true,
      notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: _horizontalCtrl,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: _totalAncho + 16,
          child: Column(children: [
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
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _filtrados;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Productos'),
        actions: [
          IconButton(
            tooltip: 'Refrescar',
            icon: const Icon(Icons.refresh),
            onPressed: cargando ? null : () => _cargar(forzar: true),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nuevo producto',
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FormProducto()),
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
                labelText: 'Buscar (ID, producto, ramo, aseguradora, descripción o estado)',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _filtro.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar',
                        icon: const Icon(Icons.clear),
                        onPressed: () => _buscarCtrl.clear(),
                      ),
              ),
            ),
          ),
          if (cargando) const LinearProgressIndicator(),
          Expanded(
            child: cargando
                ? const Center(child: CircularProgressIndicator())
                : data.isEmpty
                    ? const Center(child: Text('No hay productos.'))
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
