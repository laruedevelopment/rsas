import 'package:flutter/material.dart';
import '../../datos/catalogos.dart';
import '../../datos/repositorio_catalogos.dart';
import '../theme/app_theme.dart';
import 'form_aseguradora.dart';
import '../../utils/mensajes_error.dart';

class ListaAseguradoras extends StatefulWidget {
  const ListaAseguradoras({super.key});

  @override
  State<ListaAseguradoras> createState() => _ListaAseguradorasState();
}

class _ListaAseguradorasState extends State<ListaAseguradoras> {
  final repo = RepositorioCatalogos();

  bool cargando = true;
  List<Aseguradora> items = [];

  final TextEditingController _buscarCtrl = TextEditingController();
  String _filtro = '';

  bool _soloActivas = false;

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
      final res = await repo.listarAseguradoras(soloActivas: _soloActivas, forzar: forzar);
      if (!mounted) return;

      res.sort((a, b) => a.id.compareTo(b.id));

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
    Comparable<T> Function(Aseguradora a) getField,
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

  List<Aseguradora> get _filtrados {
    Iterable<Aseguradora> data = items;

    if (_soloActivas) {
      data = data.where((a) => a.estadoAseg);
    }

    if (_filtro.isNotEmpty) {
      data = data.where((a) {
        final id = a.id.toString();
        final nombre = a.nombreAseg.toLowerCase();
        final nit = (a.nitAseg ?? '').toLowerCase();
        final clave = (a.clave ?? '').toLowerCase();
        final estado = a.estadoAseg ? 'activo' : 'inactivo';

        return id.contains(_filtro) ||
            nombre.contains(_filtro) ||
            nit.contains(_filtro) ||
            clave.contains(_filtro) ||
            estado.contains(_filtro);
      });
    }

    return data.toList();
  }

  Future<void> _eliminar(Aseguradora a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar aseguradora'),
        content: Text('¿Eliminar "${a.nombreAseg}"?'),
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
      await repo.eliminarAseguradora(a.id);
      await _cargar();
    } catch (e) {
      final msg = _esErrorRelacion(e)
          ? 'No se puede eliminar porque esta aseguradora está relacionada con productos o pólizas.'
          : e.toString().replaceFirst('Exception: ', '');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  void _abrirEditar(Aseguradora a) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FormAseguradora(aseguradora: a)),
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

  Widget _vistaMovil(List<Aseguradora> data) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
      itemCount: data.length,
      itemBuilder: (_, i) {
        final a = data[i];
        final subtitulo = [
          if ((a.clave ?? '').isNotEmpty) 'Clave: ${a.clave}',
          if ((a.nitAseg ?? '').isNotEmpty) 'NIT: ${a.nitAseg}',
        ].join('  ·  ');

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            isThreeLine: true,
            onTap: () => _abrirEditar(a),
            title: Text(
              a.nombreAseg,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subtitulo.isNotEmpty) Text(subtitulo),
                const SizedBox(height: 6),
                _chip(a.estadoAseg),
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') { _abrirEditar(a); } else { _eliminar(a); }
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
  static const _wNombre = 280.0;
  static const _wClave = 90.0;
  static const _wNit = 140.0;
  static const _wEstado = 100.0;
  static const _wAcciones = 90.0;
  static const _totalAncho = _wId + _wNombre + _wClave + _wNit + _wEstado + _wAcciones;

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
        col('ID', _wId, () => _sort<num>((a) => a.id, 0, _sortColumnIndex != 0 || !_sortAscending), 0),
        col('Nombre', _wNombre, () => _sort<String>((a) => a.nombreAseg.toLowerCase(), 1, _sortColumnIndex != 1 || !_sortAscending), 1),
        col('Clave', _wClave, () => _sort<String>((a) => (a.clave ?? '').toLowerCase(), 2, _sortColumnIndex != 2 || !_sortAscending), 2),
        col('NIT', _wNit, () => _sort<String>((a) => (a.nitAseg ?? '').toLowerCase(), 3, _sortColumnIndex != 3 || !_sortAscending), 3),
        col('Estado', _wEstado, () => _sort<String>((a) => a.estadoAseg ? 'activo' : 'inactivo', 4, _sortColumnIndex != 4 || !_sortAscending), 4),
        const SizedBox(width: _wAcciones),
      ]),
    );
  }

  Widget _filaEscritorio(Aseguradora a) {
    return InkWell(
      onTap: () => _abrirEditar(a),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.outlineVariant))),
        child: Row(children: [
          SizedBox(width: _wId, child: Text(a.id.toString(), style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wNombre, child: Text(a.nombreAseg, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wClave, child: Text(a.clave ?? '', style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wNit, child: Text(a.nitAseg ?? '', style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wEstado, child: _chip(a.estadoAseg)),
          SizedBox(width: _wAcciones, child: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit, size: 18), onPressed: () => _abrirEditar(a)),
            IconButton(tooltip: 'Eliminar', icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => _eliminar(a)),
          ])),
        ]),
      ),
    );
  }

  Widget _vistaEscritorio(List<Aseguradora> data) {
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
        title: const Text('Aseguradoras'),
        actions: [
          IconButton(
            tooltip: 'Refrescar',
            icon: const Icon(Icons.refresh),
            onPressed: cargando ? null : () => _cargar(forzar: true),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nueva aseguradora',
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FormAseguradora()),
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
                    labelText: 'Buscar (ID, nombre, NIT, clave o estado)',
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
                  contentPadding: EdgeInsets.zero,
                  value: _soloActivas,
                  onChanged: (v) async {
                    setState(() => _soloActivas = v);
                    await _cargar();
                  },
                  title: const Text('Solo activas'),
                  subtitle: Text(
                    _soloActivas
                        ? 'Mostrando solo aseguradoras activas'
                        : 'Mostrando activas e inactivas',
                  ),
                ),
              ],
            ),
          ),
          if (cargando) const LinearProgressIndicator(),
          Expanded(
            child: cargando
                ? const Center(child: CircularProgressIndicator())
                : data.isEmpty
                    ? const Center(child: Text('No hay aseguradoras.'))
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
