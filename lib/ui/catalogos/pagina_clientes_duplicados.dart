import 'package:flutter/material.dart';

import '../../datos/catalogos.dart';
import '../../datos/repositorio_catalogos.dart';
import '../../utils/formatters.dart';
import '../pagina_polizas_de_cliente.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import 'form_cliente.dart';
import '../../utils/mensajes_error.dart';

/// Agrupa los clientes con el mismo tipo+número de documento — nunca se
/// borra ni se fusiona nada solo, el usuario elige a mano cuál conservar.
class PaginaClientesDuplicados extends StatefulWidget {
  const PaginaClientesDuplicados({super.key});

  @override
  State<PaginaClientesDuplicados> createState() =>
      _PaginaClientesDuplicadosState();
}

class _PaginaClientesDuplicadosState extends State<PaginaClientesDuplicados> {
  final _repo = RepositorioCatalogos();
  bool _cargando = true;
  bool _fusionando = false;
  String? _error;
  List<List<Cliente>> _grupos = [];
  final Set<String> _expandidos = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = null; });
    try {
      final todos = await _repo.listarClientesDuplicados();
      final porClave = <String, List<Cliente>>{};
      for (final c in todos) {
        final clave = '${c.tipodocCliente ?? ''}|${c.docCliente ?? ''}';
        porClave.putIfAbsent(clave, () => []).add(c);
      }
      final grupos = porClave.values.where((g) => g.length > 1).toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      if (!mounted) return;
      setState(() => _grupos = grupos);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeAmigable(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _verPolizas(Cliente c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaginaPolizasDeCliente(
          clienteId: c.id,
          nombreCliente: c.nombreCliente,
        ),
      ),
    );
  }

  Future<void> _editar(Cliente c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FormCliente(cliente: c)),
    );
    _cargar();
  }

  Future<void> _fusionar(List<Cliente> grupo, Cliente conservar) async {
    final sobrantes = grupo.where((c) => c.id != conservar.id).toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fusionar clientes'),
        content: Text(
          'Se van a mover todas las pólizas de:\n'
          '${sobrantes.map((c) => '• #${c.id} ${c.nombreCliente}').join('\n')}\n\n'
          'hacia "#${conservar.id} ${conservar.nombreCliente}", y los clientes '
          'de arriba se van a eliminar. Esto no se puede deshacer.\n\n'
          '¿Confirma?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, fusionar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _fusionando = true);
    try {
      await _repo.fusionarClientes(conservar.id, sobrantes.map((c) => c.id).toList());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clientes fusionados.')),
      );
      _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(mensajeAmigable(e, accion: 'Error al fusionar'))));
      }
    } finally {
      if (mounted) setState(() => _fusionando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes duplicados'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar',
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: Stack(
        children: [
          _cargando
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Text(_error ?? '',
                          style: TextStyle(color: AppTheme.danger)))
                  : _grupos.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_outline,
                                  size: 52, color: AppTheme.green),
                              const SizedBox(height: 12),
                              const Text('No hay clientes duplicados.'),
                            ],
                          ),
                        )
                      : AppLayout.centered(ListView(
                          padding: AppLayout.pagePadding,
                          children: [
                            Text(
                              '${_grupos.length} grupo(s) con el mismo tipo y número de documento. '
                              'Dos clientes con el mismo número pero distinto tipo de documento '
                              '(ej. una CC y un NIT) no cuentan acá — eso sí puede pasar.',
                              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                            ),
                            const SizedBox(height: 16),
                            for (final grupo in _grupos) ...[
                              _grupoCard(grupo),
                              const SizedBox(height: 10),
                            ],
                          ],
                        )),
          if (_fusionando)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _grupoCard(List<Cliente> grupo) {
    final cs = Theme.of(context).colorScheme;
    final clave = '${grupo.first.tipodocCliente ?? ''}|${grupo.first.docCliente ?? ''}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: ExpansionTile(
          key: PageStorageKey(clave),
          initiallyExpanded: _expandidos.contains(clave),
          onExpansionChanged: (abierto) {
            if (abierto) {
              _expandidos.add(clave);
            } else {
              _expandidos.remove(clave);
            }
          },
          title: Text(
            '${grupo.first.tipodocCliente ?? ''} ${Fmt.doc(grupo.first.docCliente)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text('${grupo.length} clientes con este documento'),
          leading: CircleAvatar(
            backgroundColor: AppTheme.warningContainer,
            child: Text('${grupo.length}',
                style: TextStyle(
                    color: AppTheme.onWarningContainer,
                    fontWeight: FontWeight.bold)),
          ),
          children: grupo.map((c) {
            return ListTile(
              dense: true,
              title: Text('#${c.id} — ${c.nombreCliente}'),
              subtitle: Text(
                [
                  if ((c.telCliente ?? '').isNotEmpty) c.telCliente!,
                  if ((c.correoCliente ?? '').isNotEmpty) c.correoCliente!,
                ].join(' · '),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'ver') {
                    _verPolizas(c);
                  } else if (v == 'editar') {
                    _editar(c);
                  } else if (v == 'fusionar') {
                    _fusionar(grupo, c);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'ver', child: Text('Ver pólizas')),
                  PopupMenuItem(value: 'editar', child: Text('Editar')),
                  PopupMenuItem(
                    value: 'fusionar',
                    child: Text('Conservar este y fusionar los demás'),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
