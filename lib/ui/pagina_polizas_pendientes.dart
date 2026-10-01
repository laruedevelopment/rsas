import 'package:flutter/material.dart';

import '../datos/poliza_pendiente.dart';
import '../datos/repositorio_polizas_pendientes.dart';
import '../utils/filtros_busqueda.dart';
import 'pagina_formulario_polizas.dart';
import 'theme/app_layout.dart';
import 'theme/app_theme.dart';

/// Bandeja de trabajo: pólizas en "Borrador" (guardadas a medio llenar) o
/// "Pendiente de revisión" (predigitadas por IA, todavía sin revisar), más
/// una pestaña de "Descartados" — al descartar una ya no se borra de una
/// vez, queda ahí para restaurar durante unos días por si fue un error.
/// Ninguna tiene id real todavía — ver lib/fix_polizas_pendientes.sql.
class PaginaPolizasPendientes extends StatefulWidget {
  const PaginaPolizasPendientes({super.key});

  @override
  State<PaginaPolizasPendientes> createState() =>
      _PaginaPolizasPendientesState();
}

class _PaginaPolizasPendientesState extends State<PaginaPolizasPendientes> {
  final _repo = RepositorioPolizasPendientes();
  bool _cargando = true;
  String? _error;
  List<PolizaPendiente> _items = [];
  List<PolizaPendiente> _descartados = [];
  bool _verDescartados = false;

  // Orden y filtro de la lista: por fecha (la de descarte en "Descartados",
  // la de guardado en "Activos"), por código o por número de póliza, cada
  // uno ascendente o descendente por separado.
  String _ordenPor = 'fecha'; // 'fecha' | 'cod' | 'nro'
  bool _ascendente = false;
  final _ctrlFiltro = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _ctrlFiltro.dispose();
    super.dispose();
  }

  /// Aplica el filtro de texto (código, número de póliza, nombre de archivo o
  /// cliente) y el orden elegido.
  List<PolizaPendiente> _filtrarYOrdenar(
    List<PolizaPendiente> lista, {
    required bool descartadas,
  }) {
    final q = _ctrlFiltro.text.trim();
    final qNorm = normalizarAlfanumerico(q);
    final qTexto = q.toUpperCase();
    final res = q.isEmpty
        ? List<PolizaPendiente>.of(lista)
        : lista.where((p) {
            return p.id.toString().contains(q.replaceFirst('#', '')) ||
                (qNorm.isNotEmpty &&
                    normalizarAlfanumerico(p.nroPoliza).contains(qNorm)) ||
                (p.nombreArchivo ?? '').toUpperCase().contains(qTexto) ||
                p.resumen.toUpperCase().contains(qTexto);
          }).toList();

    int cmp(PolizaPendiente a, PolizaPendiente b) {
      switch (_ordenPor) {
        case 'cod':
          return a.id.compareTo(b.id);
        case 'nro':
          // Las que no tienen número quedan siempre al final.
          if (a.nroPoliza.isEmpty != b.nroPoliza.isEmpty) {
            return a.nroPoliza.isEmpty ? 1 : -1;
          }
          return a.nroPoliza.toUpperCase().compareTo(b.nroPoliza.toUpperCase());
        default:
          final da = descartadas ? a.fdescartado : a.fcreado;
          final db = descartadas ? b.fdescartado : b.fcreado;
          return (da ?? DateTime(1970)).compareTo(db ?? DateTime(1970));
      }
    }

    res.sort((a, b) {
      if (_ordenPor == 'nro' && a.nroPoliza.isEmpty != b.nroPoliza.isEmpty) {
        return cmp(a, b);
      }
      final c = cmp(a, b);
      return _ascendente ? c : -c;
    });
    return res;
  }

  Widget _barraOrden() {
    Widget criterio(String id, String etiqueta) {
      final activo = _ordenPor == id;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          selected: activo,
          label: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(etiqueta),
            if (activo) ...[
              const SizedBox(width: 4),
              Icon(_ascendente ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 14),
            ],
          ]),
          // Tocar el criterio activo invierte el sentido; tocar otro lo
          // elige (más reciente / mayor primero).
          onSelected: (_) => setState(() {
            if (activo) {
              _ascendente = !_ascendente;
            } else {
              _ordenPor = id;
              _ascendente = false;
            }
          }),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctrlFiltro,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText:
                  'Buscar por código, número de póliza, archivo o cliente…',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: _ctrlFiltro.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(_ctrlFiltro.clear),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Ordenar por: ',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              criterio('fecha',
                  _verDescartados ? 'Fecha de descarte' : 'Fecha de guardado'),
              criterio('cod', 'Código'),
              criterio('nro', 'Nº póliza'),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      // Purga las que ya cumplieron el plazo antes de listar — así la
      // pestaña "Descartados" no acumula filas vencidas indefinidamente.
      await _repo.purgarVencidos();
      final items = await _repo.listar();
      final descartados = await _repo.listar(incluirDescartados: true);
      if (!mounted) return;
      setState(() {
        _items = items;
        _descartados = descartados;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _abrir(PolizaPendiente p) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaginaFormularioPolizas(polizaPendiente: p),
      ),
    );
    _cargar();
  }

  Future<void> _descartar(PolizaPendiente p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descartar'),
        content: Text(
          '¿Descartar "${p.resumen}"? Queda ${PolizaPendiente.diasRetencion} '
          'días en "Descartados" por si hay que recuperarla; pasado ese '
          'tiempo se borra sola.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Descartar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.descartar(p.id);
      _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _restaurar(PolizaPendiente p) async {
    try {
      await _repo.restaurar(p.id);
      _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final borradores = _filtrarYOrdenar(
      _items.where((p) => p.estado == 'borrador').toList(),
      descartadas: false,
    );
    final pendientes = _filtrarYOrdenar(
      _items.where((p) => p.estado == 'pendiente_revision').toList(),
      descartadas: false,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pólizas pendientes'),
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
                  child: Text('Error: $_error',
                      style: TextStyle(color: AppTheme.danger)))
              : AppLayout.centered(Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                      child: Row(
                        children: [
                          FilterChip(
                            label: const Text('Activos'),
                            selected: !_verDescartados,
                            onSelected: (_) =>
                                setState(() => _verDescartados = false),
                          ),
                          const SizedBox(width: 6),
                          FilterChip(
                            label: Text('Descartados (${_descartados.length})'),
                            selected: _verDescartados,
                            onSelected: (_) =>
                                setState(() => _verDescartados = true),
                          ),
                        ],
                      ),
                    ),
                    _barraOrden(),
                    Expanded(
                      child: _verDescartados
                          ? _listaDescartados()
                          : _listaActivos(pendientes, borradores, cs),
                    ),
                  ],
                )),
    );
  }

  Widget _listaActivos(
    List<PolizaPendiente> pendientes,
    List<PolizaPendiente> borradores,
    ColorScheme cs,
  ) {
    if (pendientes.isEmpty && borradores.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 52, color: AppTheme.green),
            const SizedBox(height: 12),
            const Text('No hay pólizas pendientes.'),
          ],
        ),
      );
    }
    return ListView(
      padding: AppLayout.pagePadding,
      children: [
        if (pendientes.isNotEmpty) ...[
          Text('Pendientes de revisión (${pendientes.length})',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          for (final p in pendientes) ...[
            _fila(p),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 16),
        ],
        if (borradores.isNotEmpty) ...[
          Text('Borradores (${borradores.length})',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          for (final p in borradores) ...[
            _fila(p),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  Widget _listaDescartados() {
    if (_descartados.isEmpty) {
      return const Center(child: Text('No hay pólizas descartadas.'));
    }
    return ListView(
      padding: AppLayout.pagePadding,
      children: [
        for (final p in _filtrarYOrdenar(_descartados, descartadas: true)) ...[
          _fila(p, descartada: true),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _fila(PolizaPendiente p, {bool descartada = false}) {
    final cs = Theme.of(context).colorScheme;
    final esPendiente = p.estado == 'pendiente_revision';
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: descartada
              ? cs.surfaceContainerHighest
              : esPendiente
                  ? AppTheme.warningContainer
                  : cs.surfaceContainerHighest,
          child: Icon(
            descartada
                ? Icons.delete_outline
                : esPendiente
                    ? Icons.auto_awesome_outlined
                    : Icons.description_outlined,
            color: esPendiente && !descartada
                ? AppTheme.onWarningContainer
                : cs.onSurfaceVariant,
            size: 20,
          ),
        ),
        title: Text(p.resumen),
        subtitle: Text([
          'Cód. ${p.id}',
          if (p.nroPoliza.isNotEmpty) 'Póliza ${p.nroPoliza}',
          if ((p.nombreArchivo ?? '').isNotEmpty) p.nombreArchivo!,
          if (p.errorMsg != null) 'Error: ${p.errorMsg}',
          if (descartada && p.fdescartado != null)
            'Descartado el ${_fecha(p.fdescartado!)} '
                '(se borra en ${p.diasParaBorrarse ?? 0} día(s))'
          else
            'Guardado el ${_fecha(p.fcreado)}',
        ].join(' · ')),
        trailing: descartada
            ? TextButton(
                onPressed: () => _restaurar(p),
                child: const Text('Restaurar'),
              )
            : IconButton(
                icon: Icon(Icons.delete_outline, color: cs.error),
                tooltip: 'Descartar',
                onPressed: () => _descartar(p),
              ),
        onTap: descartada ? null : () => _abrir(p),
      ),
    );
  }

  String _fecha(DateTime d) {
    final l = d.toLocal();
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(l.day)}/${dos(l.month)}/${l.year} ${dos(l.hour)}:${dos(l.minute)}';
  }
}
