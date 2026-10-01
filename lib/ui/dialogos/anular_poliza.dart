import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../datos/abono_poliza.dart';
import '../../datos/repositorio_pagos.dart';
import '../../datos/repositorio_polizas.dart';
import '../../datos/sesion.dart';
import '../../utils/formatters.dart';
import '../theme/app_theme.dart';

/// Marca una póliza como ANULADA (estado 'A') después de mostrar sus datos y,
/// para los roles que ven pagos (A y S), la lista de sus pagos con una casilla
/// por pago: los marcados pasan a estado Anulada (dejan de sumar en los
/// totales pero quedan como historial); los demás se dejan como están.
/// No borra nada. Se revierte cambiando el estado en el formulario de la póliza.
///
/// Devuelve true si algo cambió (o la póliza ya estaba anulada), para que
/// quien llama recargue su pantalla.
Future<bool> anularPolizaConPagos(BuildContext context, int id) async {
  final repoPol = RepositorioPolizas();
  final repoPagos = RepositorioPagos();

  void snack(String msg, {bool error = false}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.danger : null,
    ));
  }

  try {
    final p = await repoPol.obtenerPoliza(id);
    if (!context.mounted) return false;
    if (p == null) {
      snack('No se encontró la póliza cód. $id', error: true);
      return false;
    }
    if (p.estadoPolizaId == 'A') {
      snack('La póliza cód. $id ya está anulada.');
      return true;
    }
    // Los pagos solo los ven y editan A y S (la base los oculta a Digitador).
    final abonos = Sesion.veComisiones
        ? await repoPagos.listarAbonosPorPoliza(id)
        : <AbonoPoliza>[];
    if (!context.mounted) return false;

    final dia = DateFormat('dd/MM/yyyy');
    String textoPago(AbonoPoliza a) => 'Reporte #${a.idrepPago ?? '—'} · '
        '${a.fechaPago != null ? dia.format(a.fechaPago!) : 'sin fecha'} · '
        'Abono \$ ${Fmt.money(a.vlrabonoprima)}';

    final aAnular = await showDialog<Set<int>>(
      context: context,
      builder: (ctx) {
        final marcados = <int>{};
        return StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            title: const Text('Anular póliza'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Póliza cód. $id · ${p.nroPoliza ?? '—'}\n'
                    '${p.nombreCliente ?? ''}\n'
                    'Prima: \$ ${Fmt.money(p.primaPoliza)}\n\n'
                    'Se marca como ANULADA; no se borra nada. Se puede '
                    'revertir cambiando el estado desde el formulario de '
                    'la póliza.',
                  ),
                  if (abonos.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Pagos de esta póliza (${abonos.length}). Marque los '
                      'que también quiere anular (dejan de sumar en los '
                      'totales, pero quedan como historial). Los que no '
                      'marque se dejan como están.',
                      style: TextStyle(
                          fontSize: 13, color: AppTheme.inkSoft, height: 1.35),
                    ),
                    const SizedBox(height: 6),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final a in abonos)
                              if (a.estadoPago == 'A')
                                ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.block, size: 18),
                                  title: Text(textoPago(a)),
                                  subtitle: const Text('Ya está anulado'),
                                )
                              else
                                CheckboxListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  value: marcados.contains(a.id),
                                  onChanged: (v) => setD(() {
                                    if (v == true) {
                                      marcados.add(a.id);
                                    } else {
                                      marcados.remove(a.id);
                                    }
                                  }),
                                  title: Text(textoPago(a)),
                                  subtitle: Text(
                                      'Comisión \$ ${Fmt.money(a.vlrcomision)} · '
                                      '${labelEstadoPago(a.estadoPago)}'),
                                ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
              FilledButton(
                  style:
                      FilledButton.styleFrom(backgroundColor: AppTheme.danger),
                  onPressed: () => Navigator.pop(ctx, Set<int>.of(marcados)),
                  child: const Text('Anular póliza')),
            ],
          ),
        );
      },
    );
    if (aAnular == null) return false;

    await repoPol.actualizarPoliza(id, {'estado_poliza_id': 'A'});
    var fallidos = 0;
    for (final abonoId in aAnular) {
      try {
        await repoPagos.actualizarAbono(abonoId, {'estado_pago': 'A'});
      } catch (_) {
        fallidos++;
      }
    }
    if (aAnular.isNotEmpty) await repoPol.refrescarEnCache([id]);
    final hechos = aAnular.length - fallidos;
    snack(
      'Póliza anulada'
      '${hechos > 0 ? ' y $hechos pago(s) anulado(s)' : ''}'
      '${fallidos > 0 ? '. $fallidos pago(s) no se pudieron anular: revíselos en Editar abono' : ''}',
      error: fallidos > 0,
    );
    return true;
  } catch (e) {
    snack('Error: $e', error: true);
    return false;
  }
}
