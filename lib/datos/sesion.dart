import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'catalogos.dart';
import 'repositorio_catalogos.dart';
import 'repositorio_dashboard.dart';
import 'repositorio_polizas.dart';

/// Usuario activo durante la sesión de la app.
class Sesion {
  Sesion._();

  static Usuario? _usuario;
  static Timer? _timerVencimiento;

  /// Permite volver al login desde cualquier pantalla cuando vence el token.
  static final navigatorKey = GlobalKey<NavigatorState>();

  /// Lo configura main(): qué hacer cuando vence la sesión.
  static VoidCallback? alVencer;

  static Usuario? get usuario => _usuario;
  static int? get usuarioId => _usuario?.id;
  static String get apodo => _usuario?.apodoUsuario ?? 'Anónimo';

  /// Roles: A = Administrador, S = (acceso a comisiones), D = Digitador.
  /// Sin sesión = sin permisos (antes se trataba como acceso completo).
  static String get rol => (_usuario?.rol ?? '').toUpperCase();
  static bool get esAdmin => rol == 'A';
  static bool get veComisiones => rol == 'A' || rol == 'S';

  static void iniciar(Usuario u, {DateTime? expira}) {
    _usuario = u;
    _timerVencimiento?.cancel();
    if (expira != null) {
      final restante =
          expira.difference(DateTime.now()) - const Duration(minutes: 1);
      _timerVencimiento = Timer(
        restante.isNegative ? Duration.zero : restante,
        () {
          cerrar();
          alVencer?.call();
        },
      );
    }
  }

  /// Olvida el usuario, vuelve el cliente a la anon key (sin esto el token
  /// quedaría pegado para la siguiente sesión) y descarta los datos en
  /// memoria — el siguiente usuario del mismo equipo no debe ver lo que
  /// cargó el anterior.
  static void cerrar() {
    _usuario = null;
    _timerVencimiento?.cancel();
    _timerVencimiento = null;
    final anon = dotenv.env['SUPABASE_ANON_KEY'];
    final db = Supabase.instance.client;
    db.rest.setAuth(anon);
    if (anon != null) db.functions.setAuth(anon);
    RepositorioPolizas.invalidarCache();
    RepositorioDashboard.invalidarCache();
    RepositorioCatalogos.limpiarCache();
  }
}
