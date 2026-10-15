import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento_polizas/datos/poliza.dart';
import 'package:seguimiento_polizas/datos/repositorio_eliminacion.dart';
import 'package:seguimiento_polizas/ui/dialogos/eliminar_polizas.dart';
import 'package:seguimiento_polizas/utils/mensajes_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Poliza pol(int id, {String? nro, String? cliente}) => Poliza(
      id: id,
      primaPoliza: 1000 * id,
      valorPoliza: 0,
      nroPoliza: nro ?? 'P-$id',
      nombreCliente: cliente ?? 'Cliente $id',
      nombreAseg: 'Sura',
    );

/// Abre el diálogo desde un botón y deja registrado lo que se envió.
Future<void> abrir(
  WidgetTester t,
  List<Poliza> polizas, {
  required EnviarEliminacion enviar,
  void Function(bool)? alTerminar,
}) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => Center(
          child: ElevatedButton(
            onPressed: () async {
              final r = await mostrarDialogoEliminarPolizas(ctx, polizas,
                  enviar: enviar);
              alTerminar?.call(r);
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('abrir'));
  await t.pumpAndSettle();
}

Finder get botonMarcar => find
    .ancestor(
      of: find.textContaining('para eliminar'),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    )
    .first;

bool habilitado(WidgetTester t) =>
    t.widget<FilledButton>(botonMarcar).onPressed != null;

void main() {
  group('Diálogo de eliminar pólizas', () {
    testWidgets(
        'el botón empieza deshabilitado y exige motivo y la palabra ELIMINAR',
        (t) async {
      await abrir(t, [pol(1)],
          enviar: (_, __) async => const ResultadoEliminacion(1, []));
      expect(habilitado(t), isFalse);

      await t.enterText(
          find.widgetWithText(TextField, 'Motivo (obligatorio)'), 'dup');
      await t.enterText(
          find.widgetWithText(TextField, 'Para confirmar, escriba ELIMINAR'),
          'ELIMINAR');
      await t.pump();
      expect(habilitado(t), isFalse,
          reason: 'motivo de 3 caracteres no alcanza');

      await t.enterText(find.widgetWithText(TextField, 'Motivo (obligatorio)'),
          'Duplicada de la 1234');
      await t.enterText(
          find.widgetWithText(TextField, 'Para confirmar, escriba ELIMINAR'),
          'eliminar ya');
      await t.pump();
      expect(habilitado(t), isFalse, reason: 'la frase no coincide');

      await t.enterText(
          find.widgetWithText(TextField, 'Para confirmar, escriba ELIMINAR'),
          ' eliminar ');
      await t.pump();
      expect(habilitado(t), isTrue,
          reason: 'sin importar mayúsculas ni espacios');
    });

    testWidgets(
        'varias pólizas: una sola confirmación, lista todas y envía todos los ids',
        (t) async {
      List<int>? ids;
      String? motivo;
      bool? cambio;
      await abrir(
        t,
        [pol(10), pol(11), pol(12)],
        enviar: (i, m) async {
          ids = i;
          motivo = m;
          return const ResultadoEliminacion(3, []);
        },
        alTerminar: (r) => cambio = r,
      );
      expect(find.text('Eliminar 3 pólizas'), findsOneWidget);
      for (final n in ['P-10', 'P-11', 'P-12']) {
        expect(find.textContaining(n), findsOneWidget);
      }
      await t.enterText(find.widgetWithText(TextField, 'Motivo (obligatorio)'),
          '  Repetidas por error  ');
      await t.enterText(
          find.widgetWithText(TextField, 'Para confirmar, escriba ELIMINAR'),
          'ELIMINAR');
      await t.pump();
      await t.tap(botonMarcar);
      await t.pumpAndSettle();

      expect(ids, [10, 11, 12]);
      expect(motivo, 'Repetidas por error',
          reason: 'el motivo se envía sin espacios sobrantes');
      expect(cambio, isTrue);
      expect(find.textContaining('3 pólizas marcadas'), findsOneWidget);
    });

    testWidgets('si algunas no se pueden marcar, se explica por qué',
        (t) async {
      bool? cambio;
      await abrir(
        t,
        [pol(1), pol(3, nro: 'CON-PAGOS')],
        enviar: (_, __) async => const ResultadoEliminacion(
            1, [Omitida(3, 'Tiene pagos registrados: muévalos antes.')]),
        alTerminar: (r) => cambio = r,
      );
      await t.enterText(
          find.widgetWithText(TextField, 'Motivo (obligatorio)'), 'Duplicadas');
      await t.enterText(
          find.widgetWithText(TextField, 'Para confirmar, escriba ELIMINAR'),
          'ELIMINAR');
      await t.pump();
      await t.tap(botonMarcar);
      await t.pumpAndSettle();

      expect(find.textContaining('Se marcaron 1; 1 no se pudieron marcar'),
          findsOneWidget);
      expect(find.textContaining('CON-PAGOS'), findsOneWidget);
      expect(find.textContaining('Tiene pagos registrados'), findsOneWidget);
      await t.tap(find.text('Entendido'));
      await t.pumpAndSettle();
      expect(cambio, isTrue);
    });

    testWidgets(
        'un error del servidor se muestra en español y no cierra el diálogo',
        (t) async {
      await abrir(
        t,
        [pol(1)],
        enviar: (_, __) async => throw const PostgrestException(
            message: 'No tiene permiso para esta acción.', code: 'P0001'),
      );
      await t.enterText(
          find.widgetWithText(TextField, 'Motivo (obligatorio)'), 'Duplicada');
      await t.enterText(
          find.widgetWithText(TextField, 'Para confirmar, escriba ELIMINAR'),
          'ELIMINAR');
      await t.pump();
      await t.tap(botonMarcar);
      await t.pumpAndSettle();
      expect(find.textContaining('No tiene permiso para esta acción.'),
          findsOneWidget);
      expect(find.text('Eliminar póliza'), findsOneWidget,
          reason: 'sigue abierto para reintentar');
      expect(habilitado(t), isTrue);
    });

    testWidgets('cancelar no envía nada', (t) async {
      var llamadas = 0;
      bool? cambio;
      await abrir(
        t,
        [pol(1)],
        enviar: (_, __) async {
          llamadas++;
          return const ResultadoEliminacion(1, []);
        },
        alTerminar: (r) => cambio = r,
      );
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(llamadas, 0);
      expect(cambio, isFalse);
    });
  });

  group('Modelos de la eliminación', () {
    test('ResultadoEliminacion lee solicitadas, resueltas y omitidas', () {
      final a = ResultadoEliminacion.fromMap({
        'solicitadas': 2,
        'omitidas': [
          {'id': 3, 'razon': 'Tiene pagos'}
        ],
      });
      expect(a.hechas, 2);
      expect(a.omitidas.single.id, 3);
      expect(
          ResultadoEliminacion.fromMap({'resueltas': 5, 'omitidas': []}).hechas,
          5);
      expect(ResultadoEliminacion.fromMap({}).hechas, 0);
    });

    test('SolicitudEliminacion tolera nulos y números como texto', () {
      final s = SolicitudEliminacion.fromMap({
        'id': 7,
        'poliza_id': 99,
        'lote': 'abc',
        'motivo': 'Duplicada',
        'solicitado_en': '2026-10-15T15:30:00+00:00',
        'solicitado_por': 'DIGI',
        'nro_poliza': null,
        'prima': '1500000.50',
        'n_pagos': 2,
      });
      expect(s.polizaId, 99);
      expect(s.nroPoliza, isNull);
      expect(s.prima, 1500000.5);
      expect(s.nPagos, 2);
      expect(s.solicitadoEn, isNotNull);
    });

    test('HistorialEliminacion distingue aprobada de rechazada', () {
      final h = HistorialEliminacion.fromMap({
        'id': 1,
        'poliza_id': 2,
        'estado': 'aprobada',
        'motivo': 'x',
        'solicitado_por': 'A',
        'resuelto_por': 'B',
      });
      expect(h.aprobada, isTrue);
    });
  });

  group('Mensajes de error de la base', () {
    test('los mensajes de las funciones (P0001) pasan tal cual', () {
      expect(
        mensajeAmigable(const PostgrestException(
            message:
                'Solo un Administrador puede ver las eliminaciones por autorizar.',
            code: 'P0001')),
        'Solo un Administrador puede ver las eliminaciones por autorizar.',
      );
    });
  });
}
