import 'package:flutter/material.dart';
import '../../datos/catalogos.dart';
import '../../datos/repositorio_catalogos.dart';
import '../../datos/sesion.dart';
import '../theme/app_theme.dart';
import 'form_usuario.dart';
import '../../utils/mensajes_error.dart';

class ListaUsuarios extends StatefulWidget {
  const ListaUsuarios({super.key});

  @override
  State<ListaUsuarios> createState() => _ListaUsuariosState();
}

class _ListaUsuariosState extends State<ListaUsuarios> {
  final repo = RepositorioCatalogos();

  bool cargando = true;
  List<Usuario> items = [];

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

  Future<void> _cargar() async {
    setState(() => cargando = true);
    try {
      final res = await repo.listarUsuarios(soloActivos: _soloActivos);
      res.sort((a, b) => a.id.compareTo(b.id));
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

  void _sort<T>(Comparable<T> Function(Usuario u) getField, int idx, bool asc) {
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

  List<Usuario> get _filtrados {
    Iterable<Usuario> data = items;
    if (_soloActivos) data = data.where((u) => u.estadoUsuario);
    if (_filtro.isNotEmpty) {
      data = data.where((u) =>
          u.id.toString().contains(_filtro) ||
          u.apodoUsuario.toLowerCase().contains(_filtro) ||
          u.nombreUsuario.toLowerCase().contains(_filtro) ||
          u.rol.toLowerCase().contains(_filtro));
    }
    return data.toList();
  }

  String _etiquetaRol(String rol) {
    switch (rol.toUpperCase()) {
      case 'A': return 'Administrador';
      case 'D': return 'Digitador';
      default: return rol;
    }
  }

  Future<void> _eliminar(Usuario u) async {
    if (u.id == Sesion.usuarioId) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No puede eliminar su propio usuario.'),
      ));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar usuario'),
        content: Text('¿Eliminar "${u.apodoUsuario}"?'),
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
      await repo.eliminarUsuario(u.id);
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  void _abrirEditar(Usuario u) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => FormUsuario(usuario: u)))
        .then((_) => _cargar());
  }

  Widget _chip(bool activo) {
    final cs = Theme.of(context).colorScheme;
    return Chip(
      label: Text(activo ? 'Activo' : 'Inactivo'),
      visualDensity: VisualDensity.compact,
      backgroundColor: activo ? cs.secondaryContainer : cs.surfaceContainerHighest,
      labelStyle: TextStyle(
        fontSize: 12,
        color: activo ? cs.onSecondaryContainer : cs.onSurfaceVariant,
      ),
    );
  }

  // ── Escritorio ────────────────────────────────────────────────────────────
  static const _wId = 60.0;
  static const _wApodo = 140.0;
  static const _wNombre = 220.0;
  static const _wRol = 130.0;
  static const _wEstado = 100.0;
  static const _wAcciones = 90.0;
  static const _totalAncho = _wId + _wApodo + _wNombre + _wRol + _wEstado + _wAcciones;

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
        col('ID', _wId, () => _sort<num>((u) => u.id, 0, _sortColumnIndex != 0 || !_sortAscending), 0),
        col('Usuario', _wApodo, () => _sort<String>((u) => u.apodoUsuario.toLowerCase(), 1, _sortColumnIndex != 1 || !_sortAscending), 1),
        col('Nombre', _wNombre, () => _sort<String>((u) => u.nombreUsuario.toLowerCase(), 2, _sortColumnIndex != 2 || !_sortAscending), 2),
        col('Rol', _wRol, () => _sort<String>((u) => u.rol.toLowerCase(), 3, _sortColumnIndex != 3 || !_sortAscending), 3),
        col('Estado', _wEstado, () => _sort<String>((u) => u.estadoUsuario ? 'a' : 'b', 4, _sortColumnIndex != 4 || !_sortAscending), 4),
        const SizedBox(width: _wAcciones),
      ]),
    );
  }

  Widget _filaEscritorio(Usuario u) {
    return InkWell(
      onTap: () => _abrirEditar(u),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.outlineVariant))),
        child: Row(children: [
          SizedBox(width: _wId, child: Text(u.id.toString(), style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wApodo, child: Text(u.apodoUsuario, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          SizedBox(width: _wNombre, child: Text(u.nombreUsuario, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wRol, child: Text(_etiquetaRol(u.rol), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          SizedBox(width: _wEstado, child: _chip(u.estadoUsuario)),
          SizedBox(width: _wAcciones, child: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit, size: 18), onPressed: () => _abrirEditar(u)),
            IconButton(tooltip: 'Eliminar', icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => _eliminar(u)),
          ])),
        ]),
      ),
    );
  }

  Widget _vistaEscritorio(List<Usuario> data) {
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

  Widget _vistaMovil(List<Usuario> data) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
      itemCount: data.length,
      itemBuilder: (_, i) {
        final u = data[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            onTap: () => _abrirEditar(u),
            leading: CircleAvatar(child: Text(u.apodoUsuario.isNotEmpty ? u.apodoUsuario[0].toUpperCase() : '?')),
            title: Text(u.apodoUsuario, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${u.nombreUsuario}  ·  ${_etiquetaRol(u.rol)}'),
            trailing: _chip(u.estadoUsuario),
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
        title: const Text('Usuarios'),
        actions: [
          IconButton(tooltip: 'Refrescar', icon: const Icon(Icons.refresh), onPressed: cargando ? null : _cargar),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nuevo usuario',
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const FormUsuario()));
          _cargar();
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Column(children: [
              TextField(
                controller: _buscarCtrl,
                decoration: InputDecoration(
                  labelText: 'Buscar (ID, usuario, nombre, rol)',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _filtro.isEmpty
                      ? null
                      : IconButton(tooltip: 'Limpiar', icon: const Icon(Icons.clear), onPressed: () => _buscarCtrl.clear()),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _soloActivos,
                onChanged: (v) async { setState(() => _soloActivos = v); await _cargar(); },
                title: const Text('Solo activos'),
                subtitle: Text(_soloActivos ? 'Mostrando solo activos' : 'Mostrando todos'),
              ),
            ]),
          ),
          if (cargando) const LinearProgressIndicator(),
          Expanded(
            child: cargando
                ? const Center(child: CircularProgressIndicator())
                : data.isEmpty
                    ? const Center(child: Text('No hay usuarios.'))
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
