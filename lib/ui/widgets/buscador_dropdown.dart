// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import '../../utils/mensajes_error.dart';

/// Sentinel que el diálogo devuelve cuando el usuario toca "Nuevo".
const _kNuevoSolicitado = _NuevoSolicitado();

class _NuevoSolicitado {
  const _NuevoSolicitado();
}

/// Dropdown con búsqueda de texto embebida.
///
/// Parámetros opcionales:
/// - [itemSubtitle]:  texto secundario bajo el nombre.
/// - [itemFilter]:    filtro local; ignorado si se provee [itemsLoader].
/// - [itemsLoader]:   función async que recibe la query y devuelve los ítems
///                    (búsqueda server-side). Cuando se usa, [items] puede ser
///                    una lista vacía o solo el ítem seleccionado actual.
/// - [onCrear]:       callback para crear un nuevo ítem desde el diálogo.
class BuscadorDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<T> items;
  final String Function(T) itemLabel;
  final String? Function(T)? itemSubtitle;
  final bool Function(T, String)? itemFilter;
  final Future<List<T>> Function(String query)? itemsLoader;
  final ValueChanged<T?> onChanged;
  final String? Function(T?)? validator;
  final String? helperText;
  final Future<T?> Function(BuildContext)? onCrear;

  const BuscadorDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.itemSubtitle,
    this.itemFilter,
    this.itemsLoader,
    this.validator,
    this.helperText,
    this.onCrear,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      items: items
          .map(
            (e) => DropdownMenuItem<T>(
              value: e,
              child: Text(
                itemLabel(e),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Buscar',
          onPressed: () async {
            final resultado = await showDialog<Object?>(
              context: context,
              builder: (_) => _BuscadorDialog<T>(
                label: label,
                items: items,
                itemLabel: itemLabel,
                itemSubtitle: itemSubtitle,
                itemFilter: itemFilter,
                itemsLoader: itemsLoader,
                mostrarBotonNuevo: onCrear != null,
              ),
            );

            if (resultado is T) {
              onChanged(resultado);
            } else if (resultado == _kNuevoSolicitado && onCrear != null) {
              final messenger = ScaffoldMessenger.of(context);
              final futura = onCrear!(context);
              try {
                final nuevo = await futura;
                if (nuevo != null) onChanged(nuevo);
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text(mensajeAmigable(e))),
                );
              }
            }
          },
        ),
      ),
    );
  }
}

// ─── Diálogo de búsqueda ──────────────────────────────────────────────────────

class _BuscadorDialog<T> extends StatefulWidget {
  final String label;
  final List<T> items;
  final String Function(T) itemLabel;
  final String? Function(T)? itemSubtitle;
  final bool Function(T, String)? itemFilter;
  final Future<List<T>> Function(String query)? itemsLoader;
  final bool mostrarBotonNuevo;

  const _BuscadorDialog({
    required this.label,
    required this.items,
    required this.itemLabel,
    required this.mostrarBotonNuevo,
    this.itemSubtitle,
    this.itemFilter,
    this.itemsLoader,
  });

  @override
  State<_BuscadorDialog<T>> createState() => _BuscadorDialogState<T>();
}

class _BuscadorDialogState<T> extends State<_BuscadorDialog<T>> {
  final _ctrl = TextEditingController();
  List<T> _filtrados = [];
  bool _cargando = false;

  // Para debounce de búsqueda async
  DateTime _ultimaBusqueda = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    if (widget.itemsLoader != null) {
      // Carga inicial: los primeros resultados sin filtro
      _buscarAsync('');
    } else {
      _filtrados = widget.items;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _filtrar(String q) {
    if (widget.itemsLoader != null) {
      _buscarAsyncDebounced(q);
    } else {
      _filtrarLocal(q);
    }
  }

  void _filtrarLocal(String q) {
    final b = q.trim().toLowerCase();
    setState(() {
      if (b.isEmpty) {
        _filtrados = widget.items;
      } else if (widget.itemFilter != null) {
        _filtrados = widget.items.where((e) => widget.itemFilter!(e, b)).toList();
      } else {
        _filtrados = widget.items
            .where((e) => widget.itemLabel(e).toLowerCase().contains(b))
            .toList();
      }
    });
  }

  void _buscarAsyncDebounced(String q) {
    final ahora = DateTime.now();
    _ultimaBusqueda = ahora;
    Future.delayed(const Duration(milliseconds: 350), () {
      if (_ultimaBusqueda == ahora && mounted) {
        _buscarAsync(q);
      }
    });
  }

  Future<void> _buscarAsync(String q) async {
    if (!mounted) return;
    setState(() => _cargando = true);
    try {
      final res = await widget.itemsLoader!(q);
      if (!mounted) return;
      setState(() => _filtrados = res);
    } catch (_) {
      // mantiene la lista anterior
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return AlertDialog(
      title: Text('Buscar ${widget.label}'),
      contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      content: SizedBox(
        width: 520,
        height: 480,
        child: Column(
          children: [
            // ── Buscador ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                onChanged: _filtrar,
                decoration: InputDecoration(
                  hintText: 'Buscar...',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: _cargando
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
              ),
            ),
            // ── Resultados ────────────────────────────────────────────
            if (!_cargando && _filtrados.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    'Sin resultados',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _filtrados.length,
                  itemBuilder: (_, i) {
                    final item = _filtrados[i];
                    final sub = widget.itemSubtitle?.call(item);
                    return ListTile(
                      title: Text(widget.itemLabel(item)),
                      subtitle: (sub ?? '').isNotEmpty
                          ? Text(
                              sub!,
                              style: tt.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            )
                          : null,
                      onTap: () => Navigator.pop(context, item),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      // ── Acciones ──────────────────────────────────────────────────────
      actions: [
        if (widget.mostrarBotonNuevo)
          FilledButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Nuevo'),
            onPressed: () => Navigator.pop(context, _kNuevoSolicitado),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
