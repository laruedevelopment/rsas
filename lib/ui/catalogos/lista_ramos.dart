import 'package:flutter/material.dart';
import '../../datos/catalogos.dart';
import '../../datos/repositorio_catalogos.dart';
import '../theme/app_theme.dart';
import 'form_ramo.dart';
import '../../utils/mensajes_error.dart';

class ListaRamos extends StatefulWidget {
  const ListaRamos({super.key});

  @override
  State<ListaRamos> createState() => _ListaRamosState();
}

class _ListaRamosState extends State<ListaRamos> {
  final repo = RepositorioCatalogos();

  bool cargando = true;
  List<Ramo> items = [];

  final TextEditingController _buscarCtrl = TextEditingController();
  String _filtro = '';

  bool _soloActivos = true;

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
      final res = await repo.listarRamos(soloActivos: _soloActivos, forzar: forzar);

      res.sort((a, b) => a.id.compareTo(b.id));

      if (!mounted) return;
      setState(() {
        items = res;
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

  void _sort<T>(
    Comparable<T> Function(Ramo r) getField,
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

  List<Ramo> get _filtrados {
    Iterable<Ramo> data = items;

    if (_soloActivos) {
      data = data.where((r) => r.estadoRamo);
    }

    if (_filtro.isNotEmpty) {
      data = data.where((r) {
        final id = r.id.toString();
        final nombre = r.nombreRamo.toLowerCase();
        final obs = (r.obsRamo ?? '').toLowerCase();
        final porcom = r.porcomBaseRamo.toString().toLowerCase();
        final estado = r.estadoRamo ? 'activo' : 'inactivo';

        return id.contains(_filtro) ||
            nombre.contains(_filtro) ||
            obs.contains(_filtro) ||
            porcom.contains(_filtro) ||
            estado.contains(_filtro);
      });
    }

    return data.toList();
  }

  Future<void> _eliminar(Ramo r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar ramo'),
        content: Text('¿Eliminar "${r.nombreRamo}"?'),
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
      await repo.eliminarRamo(r.id);
      await _cargar();
    } catch (e) {
      final msg = _esErrorRelacion(e)
          ? 'No se puede eliminar porque este ramo está relacionado con productos o pólizas.'
          : e.toString().replaceFirst('Exception: ', '');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  void _abrirEditar(Ramo r) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FormRamo(ramo: r)),
    ).then((_) => _cargar());
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

  Widget _vistaMovil(List<Ramo> data) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
      itemCount: data.length,
      itemBuilder: (_, i) {
        final r = data[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            isThreeLine: true,
            onTap: () => _abrirEditar(r),
            title: Text(
              r.nombreRamo,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('% Base comisión: ${r.porcomBaseRamo}'),
                if ((r.obsRamo ?? '').isNotEmpty)
                  Text(
                    r.obsRamo!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                const SizedBox(height: 6),
                _chip(r.estadoRamo),
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') { _abrirEditar(r); } else { _eliminar(r); }
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
  static const _wPorc = 90.0;
  static const _wObs = 280.0;
  static const _wEstado = 100.0;
  static const _wAcciones = 90.0;
  static const _totalAncho = _wId + _wNombre + _wPorc + _wObs + _wEstado + _wAcciones;

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
        col('ID', _wId, () => _sort<num>((r) => r.id, 0, _sortColumnIndex != 0 || !_sortAscending), 0),
        col('Nombre', _wNombre, () => _sort<String>((r) => r.nombreRamo.toLowerCase(), 1, _sortColumnIndex != 1 || !_sortAscending), 1),
        col('% Base', _wPorc, () => _sort<num>((r) => r.porcomBaseRamo, 2, _sortColumnIndex != 2 || !_sortAscending), 2),
        col('Observaciones', _wObs, () => _sort<String>((r) => (r.obsRamo ?? '').toLowerCase(), 3, _sortColumnIndex != 3 || !_sortAscending), 3),
        col('Estado', _wEstado, () => _sort<String>((r) => r.estadoRamo ? 'activo' : 'inactivo', 4, _sortColumnIndex != 4 || !_sortAscending), 4),
        const SizedBox(width: _wAcciones),
      ]),
    );
  }

  Widget _filaEscritorio(Ramo r) {
    return InkWell(
      onTap: () => _abrirEditar(r),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.outlineVariant))),
        child: Row(children: [
          SizedBox(width: _wId, child: Text(r.id.toString(), style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wNombre, child: Text(r.nombreRamo, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wPorc, child: Text(r.porcomBaseRamo.toString(), style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wObs, child: Text(r.obsRamo ?? '', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wEstado, child: _chip(r.estadoRamo)),
          SizedBox(width: _wAcciones, child: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit, size: 18), onPressed: () => _abrirEditar(r)),
            IconButton(tooltip: 'Eliminar', icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => _eliminar(r)),
          ])),
        ]),
      ),
    );
  }

  Widget _vistaEscritorio(List<Ramo> data) {
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
        title: const Text('Ramos'),
        actions: [
          IconButton(
            tooltip: 'Refrescar',
            icon: const Icon(Icons.refresh),
            onPressed: cargando ? null : () => _cargar(forzar: true),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nuevo ramo',
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FormRamo()),
          );
          _cargar();
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Column(
              children: [
                TextField(
                  controller: _buscarCtrl,
                  decoration: InputDecoration(
                    labelText: 'Buscar (ID, nombre, observaciones, % base o estado)',
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
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _soloActivos,
                  onChanged: (v) async {
                    setState(() => _soloActivos = v);
                    await _cargar();
                  },
                  title: const Text('Solo activos'),
                  subtitle: Text(
                    _soloActivos ? 'Mostrando solo ramos activos' : 'Mostrando todos',
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          if (cargando) const LinearProgressIndicator(),
          Expanded(
            child: cargando
                ? const Center(child: CircularProgressIndicator())
                : data.isEmpty
                    ? const Center(child: Text('No hay ramos.'))
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
