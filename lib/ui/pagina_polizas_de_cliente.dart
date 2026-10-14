import 'package:flutter/material.dart';

import '../datos/poliza.dart';
import '../datos/repositorio_polizas.dart';
import '../utils/formatters.dart';
import 'pagina_formulario_polizas.dart';
import 'theme/app_layout.dart';
import 'theme/app_theme.dart';
import '../utils/mensajes_error.dart';

/// Todas las pólizas de un cliente puntual — se abre desde el botón "Ver
/// pólizas" en el catálogo de Clientes.
class PaginaPolizasDeCliente extends StatefulWidget {
  final int clienteId;
  final String nombreCliente;
  const PaginaPolizasDeCliente({
    super.key,
    required this.clienteId,
    required this.nombreCliente,
  });

  @override
  State<PaginaPolizasDeCliente> createState() =>
      _PaginaPolizasDeClienteState();
}

class _PaginaPolizasDeClienteState extends State<PaginaPolizasDeCliente> {
  final _repo = RepositorioPolizas();
  bool _cargando = true;
  String? _error;
  List<Poliza> _polizas = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = null; });
    try {
      final res = await _repo.listarPorCliente(widget.clienteId);
      if (!mounted) return;
      setState(() => _polizas = res);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeAmigable(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _abrir(Poliza p) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PaginaFormularioPolizas(poliza: p)),
    );
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Pólizas de ${widget.nombreCliente}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar',
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(_error ?? '',
                      style: TextStyle(color: AppTheme.danger)))
              : _polizas.isEmpty
                  ? const Center(
                      child: Text('Este cliente no tiene pólizas registradas.'))
                  : AppLayout.centered(ListView(
                      padding: AppLayout.pagePadding,
                      children: [
                        Text('${_polizas.length} póliza(s)',
                            style: TextStyle(color: cs.onSurfaceVariant)),
                        const SizedBox(height: 12),
                        for (final p in _polizas) ...[
                          _fila(p),
                          const SizedBox(height: 8),
                        ],
                      ],
                    )),
    );
  }

  Widget _fila(Poliza p) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        title: Text(p.nroPoliza ?? '(sin número)'),
        subtitle: Text(
          '${p.nombreAseg ?? '—'} · ${p.nombreRamo ?? '—'}'
          '${(p.bienAsegurado ?? '').isNotEmpty ? ' · ${p.bienAsegurado}' : ''}\n'
          'Prima: \$ ${Fmt.money(p.primaPoliza)} · Vence: ${_fecha(p.ffinPoliza)}',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: () => _abrir(p),
      ),
    );
  }

  String _fecha(DateTime? d) {
    if (d == null) return '—';
    final l = d.toLocal();
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(l.day)}/${dos(l.month)}/${l.year}';
  }
}
