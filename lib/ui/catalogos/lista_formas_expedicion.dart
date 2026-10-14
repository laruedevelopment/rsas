import 'package:flutter/material.dart';
import '../../datos/catalogos.dart';
import '../../datos/repositorio_catalogos.dart';
import '../theme/app_theme.dart';
import 'form_forma_expedicion.dart';
import '../../utils/mensajes_error.dart';

class ListaFormasExpedicion extends StatefulWidget {
  const ListaFormasExpedicion({super.key});

  @override
  State<ListaFormasExpedicion> createState() => _ListaFormasExpedicionState();
}

class _ListaFormasExpedicionState extends State<ListaFormasExpedicion> {
  final repo = RepositorioCatalogos();

  bool cargando = true;
  List<FormaExpedicion> items = [];

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
      final res = await repo.listarFormasExpedicion(forzar: forzar);
      if (!mounted) return;
      setState(() {
        items = res;
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

  void _sort<T>(Comparable<T> Function(FormaExpedicion f) getField, int idx, bool asc) {
    setState(() {
      _sortColumnIndex = idx;
      _sortAscending = asc;
      items.sort((a, b) {
        final av = getField(a);
        final bv = getField(b);
        return asc ? Comparable.compare(av, bv) : Comparable.compare(bv, av);
      });
    });
  }

  List<FormaExpedicion> get _filtrados {
    if (_filtro.isEmpty) return items;
    return items.where((f) =>
        f.id.toString().contains(_filtro) ||
        f.nombreFormaexp.toLowerCase().contains(_filtro)).toList();
  }

  Future<void> _eliminar(FormaExpedicion f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar forma de expedición'),
        content: Text('¿Eliminar "${f.nombreFormaexp}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
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
      await repo.eliminarFormaExpedicion(f.id);
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  void _abrirEditar(FormaExpedicion f) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => FormFormaExpedicion(forma: f)))
        .then((_) => _cargar());
  }

  // ── Escritorio ─────────────────────────────────────────────────────────────
  static const _wId = 70.0;
  static const _wNombre = 300.0;
  static const _wAcciones = 90.0;
  static const _totalAncho = _wId + _wNombre + _wAcciones;

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
        col('ID', _wId, () => _sort<num>((f) => f.id, 0, _sortColumnIndex != 0 || !_sortAscending), 0),
        col('Nombre', _wNombre, () => _sort<String>((f) => f.nombreFormaexp.toLowerCase(), 1, _sortColumnIndex != 1 || !_sortAscending), 1),
        const SizedBox(width: _wAcciones),
      ]),
    );
  }

  Widget _filaEscritorio(FormaExpedicion f) {
    return InkWell(
      onTap: () => _abrirEditar(f),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.outlineVariant))),
        child: Row(children: [
          SizedBox(width: _wId, child: Text(f.id.toString(), style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wNombre, child: Text(f.nombreFormaexp, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wAcciones, child: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit, size: 18), onPressed: () => _abrirEditar(f)),
            IconButton(tooltip: 'Eliminar', icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => _eliminar(f)),
          ])),
        ]),
      ),
    );
  }

  Widget _vistaEscritorio(List<FormaExpedicion> data) {
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

  Widget _vistaMovil(List<FormaExpedicion> data) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
      itemCount: data.length,
      itemBuilder: (_, i) {
        final f = data[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            onTap: () => _abrirEditar(f),
            leading: CircleAvatar(child: Text(f.id.toString())),
            title: Text(f.nombreFormaexp),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _abrirEditar(f)),
              IconButton(icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => _eliminar(f)),
            ]),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _filtrados;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Formas de Expedición'),
        actions: [
          IconButton(tooltip: 'Refrescar', icon: const Icon(Icons.refresh), onPressed: cargando ? null : () => _cargar(forzar: true)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nueva forma de expedición',
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const FormFormaExpedicion()));
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
                labelText: 'Buscar por ID o nombre',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _filtro.isEmpty
                    ? null
                    : IconButton(tooltip: 'Limpiar', icon: const Icon(Icons.clear), onPressed: () => _buscarCtrl.clear()),
              ),
            ),
          ),
          if (cargando) const LinearProgressIndicator(),
          Expanded(
            child: cargando
                ? const Center(child: CircularProgressIndicator())
                : data.isEmpty
                    ? const Center(child: Text('No hay formas de expedición.'))
                    : LayoutBuilder(
                        builder: (context, constraints) => constraints.maxWidth < 600
                            ? _vistaMovil(data)
                            : _vistaEscritorio(data),
                      ),
          ),
        ],
      ),
    );
  }
}
