import 'package:flutter/material.dart';
import '../../datos/catalogos.dart';
import '../../datos/repositorio_catalogos.dart';
import '../theme/app_theme.dart';
import 'form_asesor.dart';
import '../../utils/mensajes_error.dart';

class ListaAsesores extends StatefulWidget {
  const ListaAsesores({super.key});

  @override
  State<ListaAsesores> createState() => _ListaAsesoresState();
}

class _ListaAsesoresState extends State<ListaAsesores> {
  final repo = RepositorioCatalogos();

  bool cargando = true;
  List<Asesor> items = [];

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
      final res = await repo.listarAsesores(soloActivos: _soloActivos, forzar: forzar);
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

  void _sort<T>(
    Comparable<T> Function(Asesor a) getField,
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

  List<Asesor> get _filtrados {
    Iterable<Asesor> data = items;
    if (_soloActivos) {
      data = data.where((a) => a.estadoAsesor);
    }
    if (_filtro.isNotEmpty) {
      data = data.where((a) {
        final id = a.id.toString();
        final nombre = a.nombreAsesor.toLowerCase();
        final doc = (a.docAsesor ?? '').toLowerCase();
        final tel = (a.telAsesor ?? '').toLowerCase();
        final correo = (a.correoAsesor ?? '').toLowerCase();
        final estado = a.estadoAsesor ? 'activo' : 'inactivo';
        return id.contains(_filtro) ||
            nombre.contains(_filtro) ||
            doc.contains(_filtro) ||
            tel.contains(_filtro) ||
            correo.contains(_filtro) ||
            estado.contains(_filtro);
      });
    }
    return data.toList();
  }

  Future<void> _eliminar(Asesor a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar asesor'),
        content: Text('¿Eliminar "${a.nombreAsesor}"?'),
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
      await repo.eliminarAsesor(a.id);
      await _cargar();
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _abrirEditar(Asesor a) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FormAsesor(asesor: a)),
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

  Widget _vistaMovil(List<Asesor> data) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
      itemCount: data.length,
      itemBuilder: (_, i) {
        final a = data[i];
        final docTxt =
            '${a.tipodocAsesor ?? ''} ${a.docAsesor ?? ''}'.trim();
        final detalles = [
          if (docTxt.isNotEmpty) docTxt,
          if ((a.telAsesor ?? '').isNotEmpty) a.telAsesor!,
          if ((a.correoAsesor ?? '').isNotEmpty) a.correoAsesor!,
          if (a.porccomAsesor != null) '% Comisión: ${a.porccomAsesor}',
        ].join('  ·  ');

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            isThreeLine: true,
            onTap: () => _abrirEditar(a),
            title: Text(
              a.nombreAsesor,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (detalles.isNotEmpty)
                  Text(
                    detalles,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                const SizedBox(height: 6),
                _chip(a.estadoAsesor),
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
  static const _wNombre = 200.0;
  static const _wDoc = 160.0;
  static const _wTel = 130.0;
  static const _wCorreo = 200.0;
  static const _wPorc = 80.0;
  static const _wEstado = 100.0;
  static const _wAcciones = 90.0;
  static const _totalAncho = _wId + _wNombre + _wDoc + _wTel + _wCorreo + _wPorc + _wEstado + _wAcciones;

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
        col('Nombre', _wNombre, () => _sort<String>((a) => a.nombreAsesor.toLowerCase(), 1, _sortColumnIndex != 1 || !_sortAscending), 1),
        col('Documento', _wDoc, () => _sort<String>((a) => (a.docAsesor ?? '').toLowerCase(), 2, _sortColumnIndex != 2 || !_sortAscending), 2),
        col('Teléfono', _wTel, () => _sort<String>((a) => (a.telAsesor ?? '').toLowerCase(), 3, _sortColumnIndex != 3 || !_sortAscending), 3),
        col('Correo', _wCorreo, () => _sort<String>((a) => (a.correoAsesor ?? '').toLowerCase(), 4, _sortColumnIndex != 4 || !_sortAscending), 4),
        col('%', _wPorc, () => _sort<num>((a) => a.porccomAsesor ?? 0, 5, _sortColumnIndex != 5 || !_sortAscending), 5),
        col('Estado', _wEstado, () => _sort<String>((a) => a.estadoAsesor ? 'activo' : 'inactivo', 6, _sortColumnIndex != 6 || !_sortAscending), 6),
        const SizedBox(width: _wAcciones),
      ]),
    );
  }

  Widget _filaEscritorio(Asesor a) {
    final docTxt = '${a.tipodocAsesor ?? ''} ${a.docAsesor ?? ''}'.trim();
    return InkWell(
      onTap: () => _abrirEditar(a),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.outlineVariant))),
        child: Row(children: [
          SizedBox(width: _wId, child: Text(a.id.toString(), style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wNombre, child: Text(a.nombreAsesor, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wDoc, child: Text(docTxt, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wTel, child: Text(a.telAsesor ?? '', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wCorreo, child: Text(a.correoAsesor ?? '', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wPorc, child: Text(a.porccomAsesor?.toString() ?? '', style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wEstado, child: _chip(a.estadoAsesor)),
          SizedBox(width: _wAcciones, child: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit, size: 18), onPressed: () => _abrirEditar(a)),
            IconButton(tooltip: 'Eliminar', icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => _eliminar(a)),
          ])),
        ]),
      ),
    );
  }

  Widget _vistaEscritorio(List<Asesor> data) {
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
        title: const Text('Asesores'),
        actions: [
          IconButton(
            tooltip: 'Refrescar',
            icon: const Icon(Icons.refresh),
            onPressed: cargando ? null : () => _cargar(forzar: true),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nuevo asesor',
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FormAsesor()),
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
                    labelText: 'Buscar (ID, nombre, doc, tel, correo o estado)',
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
                  value: _soloActivos,
                  onChanged: (v) async {
                    setState(() => _soloActivos = v);
                    await _cargar();
                  },
                  title: const Text('Solo activos'),
                  subtitle: Text(
                    _soloActivos
                        ? 'Mostrando solo asesores activos'
                        : 'Mostrando todos',
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
                    ? const Center(child: Text('No hay asesores.'))
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
