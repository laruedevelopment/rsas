import '../../datos/poliza.dart';
import '../../datos/repositorio_dashboard.dart';

/// Cálculo puro (sin Flutter ni red) del dashboard gerencial: recibe las
/// pólizas y los pagos en memoria y devuelve agregados listos para graficar.
/// Separado de la pantalla para poder probarlo con tests.

enum Comparar { periodoAnterior, anioAnterior, ninguno }

enum Dim { aseguradora, ramo, producto, asesor, cliente }

String etiquetaDim(Dim d) => switch (d) {
      Dim.aseguradora => 'Aseguradora',
      Dim.ramo => 'Ramo',
      Dim.producto => 'Producto',
      Dim.asesor => 'Asesor',
      Dim.cliente => 'Cliente',
    };

String claveDim(Poliza p, Dim d) => switch (d) {
      Dim.aseguradora => p.nombreAseg ?? 'Sin aseguradora',
      Dim.ramo => p.nombreRamo ?? 'Sin ramo',
      Dim.producto => p.nombreProd ?? 'Sin producto',
      Dim.asesor => p.nombreAsesor ?? 'Sin asesor',
      Dim.cliente => p.nombreCliente ?? 'Sin cliente',
    };

DateTime soloDia(DateTime d) => DateTime(d.year, d.month, d.day);

/// Fecha con la que se cuenta la producción de una póliza: expedición; si no
/// hay, inicio de vigencia; si no, fecha de registro.
DateTime? fechaProduccion(Poliza p) =>
    p.fexpPoliza ??
    p.finiPoliza ??
    (p.fcreado == null ? null : soloDia(p.fcreado!.toLocal()));

int mesIdx(DateTime d) => d.year * 12 + d.month - 1;

/// Filtros globales del dashboard. Mutable: la pantalla lo copia al cambiar.
class FiltrosDash {
  DateTime desde;
  DateTime hasta;
  Comparar comparar;
  String? aseg, ramo, prod, asesor, cliente;
  bool incluirAnuladas;

  /// 0 = todas, 1 = vigentes, 2 = vencidas.
  int estado;

  FiltrosDash({
    required this.desde,
    required this.hasta,
    this.comparar = Comparar.periodoAnterior,
    this.aseg,
    this.ramo,
    this.prod,
    this.asesor,
    this.cliente,
    this.incluirAnuladas = false,
    this.estado = 0,
  });

  FiltrosDash copia() => FiltrosDash(
        desde: desde,
        hasta: hasta,
        comparar: comparar,
        aseg: aseg,
        ramo: ramo,
        prod: prod,
        asesor: asesor,
        cliente: cliente,
        incluirAnuladas: incluirAnuladas,
        estado: estado,
      );

  String? valorDe(Dim d) => switch (d) {
        Dim.aseguradora => aseg,
        Dim.ramo => ramo,
        Dim.producto => prod,
        Dim.asesor => asesor,
        Dim.cliente => cliente,
      };

  void poner(Dim d, String? v) {
    switch (d) {
      case Dim.aseguradora:
        aseg = v;
      case Dim.ramo:
        ramo = v;
      case Dim.producto:
        prod = v;
      case Dim.asesor:
        asesor = v;
      case Dim.cliente:
        cliente = v;
    }
  }

  int get nDimensiones =>
      [aseg, ramo, prod, asesor, cliente].where((e) => e != null).length;
}

class Grupo {
  final String nombre;
  int n = 0;
  num prima = 0;
  num comision = 0;
  num recaudo = 0;
  Grupo(this.nombre);
  num get ticket => n == 0 ? 0 : prima / n;
}

/// Agregados de un período (el actual o el de comparación).
class Agregado {
  final DateTime desde;
  final DateTime hasta;
  final List<Poliza> polizas;
  final int clientes;
  final num prima;
  final num comision;
  final num recaudo;
  final List<double> primaMes;
  final List<double> nMes;
  final List<double> comisionMes;
  final List<double> recaudoMes;

  const Agregado({
    required this.desde,
    required this.hasta,
    required this.polizas,
    required this.clientes,
    required this.prima,
    required this.comision,
    required this.recaudo,
    required this.primaMes,
    required this.nMes,
    required this.comisionMes,
    required this.recaudoMes,
  });

  int get n => polizas.length;
  num get ticket => n == 0 ? 0 : prima / n;
}

class ClienteTop {
  final String nombre;
  final int n;
  final num prima;
  const ClienteTop(this.nombre, this.n, this.prima);
}

class FilaPoliza {
  final Poliza p;
  final num valor;
  final int dias;
  const FilaPoliza(this.p, this.valor, this.dias);
}

class Resultado {
  final FiltrosDash filtros;
  final Agregado actual;
  final Agregado? comp;
  final List<DateTime> meses;
  final Map<Dim, List<Grupo>> porDim;

  // Clientes
  final List<ClienteTop> clientesTop;
  final List<double> pareto; // % acumulado del top-N de clientes
  final double concentracionTop10;
  final int clientesNuevos;
  final int clientesRecurrentes;
  final num primaNuevos;
  final num primaRecurrentes;

  // Cartera (de lo emitido en el período)
  final num carteraSaldo;
  final num carteraPagada;
  final num carteraPrima;
  final List<MapEntry<String, num>> aging;
  final List<ClienteTop> deudores;

  // Renovaciones
  final int renBase;
  final int renRenovadas;
  final List<Grupo> renPorAseg;
  final List<Grupo> renPorAsesor; // n = base, prima = renovadas
  final List<DateTime> mesesFuturos;
  final List<double> venceN;
  final List<double> vencePrima;
  final List<FilaPoliza> porRenovar30;
  final List<FilaPoliza> sinRenovar90;
  final (int, num) vence30, vence60, vence90;
  final (int, num) sinRenovar90Tot;

  // Matriz aseguradora × ramo
  final List<String> matrizFilas;
  final List<String> matrizCols;
  final Map<String, num> matriz;

  const Resultado({
    required this.filtros,
    required this.actual,
    required this.comp,
    required this.meses,
    required this.porDim,
    required this.clientesTop,
    required this.pareto,
    required this.concentracionTop10,
    required this.clientesNuevos,
    required this.clientesRecurrentes,
    required this.primaNuevos,
    required this.primaRecurrentes,
    required this.carteraSaldo,
    required this.carteraPagada,
    required this.carteraPrima,
    required this.aging,
    required this.deudores,
    required this.renBase,
    required this.renRenovadas,
    required this.renPorAseg,
    required this.renPorAsesor,
    required this.mesesFuturos,
    required this.venceN,
    required this.vencePrima,
    required this.porRenovar30,
    required this.sinRenovar90,
    required this.vence30,
    required this.vence60,
    required this.vence90,
    required this.sinRenovar90Tot,
    required this.matrizFilas,
    required this.matrizCols,
    required this.matriz,
  });

  double? get tasaRenovacion => renBase == 0 ? null : renRenovadas / renBase;
}

class CalidadDatos {
  final int total, sinAsesor, sinRamo, sinVencimiento, sinPrima, sinCliente;
  const CalidadDatos(this.total, this.sinAsesor, this.sinRamo,
      this.sinVencimiento, this.sinPrima, this.sinCliente);
  int get problemas =>
      sinAsesor + sinRamo + sinVencimiento + sinPrima + sinCliente;
}

class MotorDash {
  final List<Poliza> polizas;
  final List<AbonoLite>? abonos;
  final DateTime hoy;

  late final Map<int, Poliza> _porId = {for (final p in polizas) p.id: p};
  late final Map<String, List<(int, DateTime)>> _renIdx =
      _indexarRenovaciones();
  late final Map<String, DateTime> _primeraFecha = _indexarPrimeraFecha();

  MotorDash(this.polizas, this.abonos, {DateTime? hoy})
      : hoy = soloDia(hoy ?? DateTime.now());

  // ── Índices ────────────────────────────────────────────────────────────

  static String claveCliente(Poliza p) =>
      p.clienteId != null ? 'c${p.clienteId}' : 'n${p.nombreCliente ?? p.id}';

  Map<String, List<(int, DateTime)>> _indexarRenovaciones() {
    final m = <String, List<(int, DateTime)>>{};
    for (final p in polizas) {
      if (p.estadoPolizaId == 'A' || p.clienteId == null) continue;
      final f = p.finiPoliza;
      if (f == null) continue;
      (m['${p.clienteId}|${p.ramoId ?? 0}'] ??= []).add((p.id, f));
    }
    return m;
  }

  Map<String, DateTime> _indexarPrimeraFecha() {
    final m = <String, DateTime>{};
    for (final p in polizas) {
      if (p.estadoPolizaId == 'A') continue;
      final f = fechaProduccion(p);
      if (f == null) continue;
      final k = claveCliente(p);
      final a = m[k];
      if (a == null || f.isBefore(a)) m[k] = f;
    }
    return m;
  }

  /// ¿Existe otra póliza del mismo cliente y ramo que arranca cerca del fin
  /// de esta? Es una estimación: el sistema no guarda "renueva a".
  bool renovada(Poliza p) {
    if (p.clienteId == null || p.ffinPoliza == null) return false;
    final lista = _renIdx['${p.clienteId}|${p.ramoId ?? 0}'];
    if (lista == null) return false;
    final fin = p.ffinPoliza!;
    final lo = fin.subtract(const Duration(days: 45));
    final hi = fin.add(const Duration(days: 180));
    final ini = p.finiPoliza;
    for (final (id, f) in lista) {
      if (id == p.id) continue;
      if (ini != null && !f.isAfter(ini)) continue;
      if (!f.isBefore(lo) && !f.isAfter(hi)) return true;
    }
    return false;
  }

  // ── Filtros ────────────────────────────────────────────────────────────

  bool _pasaDims(Poliza p, FiltrosDash f) {
    if (f.aseg != null && claveDim(p, Dim.aseguradora) != f.aseg) return false;
    if (f.ramo != null && claveDim(p, Dim.ramo) != f.ramo) return false;
    if (f.prod != null && claveDim(p, Dim.producto) != f.prod) return false;
    if (f.asesor != null && claveDim(p, Dim.asesor) != f.asesor) return false;
    if (f.cliente != null && claveDim(p, Dim.cliente) != f.cliente) {
      return false;
    }
    return true;
  }

  bool _pasaPoliza(Poliza p, FiltrosDash f) {
    if (!f.incluirAnuladas && p.estadoPolizaId == 'A') return false;
    if (!_pasaDims(p, f)) return false;
    if (f.estado == 1 &&
        (p.ffinPoliza == null || p.ffinPoliza!.isBefore(hoy))) {
      return false;
    }
    if (f.estado == 2 &&
        (p.ffinPoliza == null || !p.ffinPoliza!.isBefore(hoy))) {
      return false;
    }
    return true;
  }

  static bool _enRango(DateTime? d, DateTime desde, DateTime hasta) =>
      d != null && !d.isBefore(desde) && !d.isAfter(hasta);

  /// Rango contra el que se compara [desde]–[hasta].
  static (DateTime, DateTime)? rangoComparacion(
      DateTime desde, DateTime hasta, Comparar c) {
    switch (c) {
      case Comparar.ninguno:
        return null;
      case Comparar.anioAnterior:
        return (
          DateTime(desde.year - 1, desde.month, desde.day),
          DateTime(hasta.year - 1, hasta.month, hasta.day),
        );
      case Comparar.periodoAnterior:
        final mesesCompletos = desde.day == 1 &&
            hasta.day == DateTime(hasta.year, hasta.month + 1, 0).day;
        if (mesesCompletos) {
          final n = mesIdx(hasta) - mesIdx(desde) + 1;
          return (
            DateTime(desde.year, desde.month - n, 1),
            DateTime(desde.year, desde.month, 0),
          );
        }
        final dias = hasta.difference(desde).inDays + 1;
        final h = desde.subtract(const Duration(days: 1));
        return (h.subtract(Duration(days: dias - 1)), h);
    }
  }

  // ── Cálculo principal ──────────────────────────────────────────────────

  Agregado _agregar(FiltrosDash f, DateTime desde, DateTime hasta) {
    final nMeses = mesIdx(hasta) - mesIdx(desde) + 1;
    final base = mesIdx(desde);
    final primaMes = List<double>.filled(nMeses, 0);
    final nMes = List<double>.filled(nMeses, 0);
    final comMes = List<double>.filled(nMeses, 0);
    final recMes = List<double>.filled(nMeses, 0);
    final lista = <Poliza>[];
    final clientes = <String>{};
    var prima = 0.0, com = 0.0, rec = 0.0;

    for (final p in polizas) {
      if (!_pasaPoliza(p, f)) continue;
      final d = fechaProduccion(p);
      if (!_enRango(d, desde, hasta)) continue;
      lista.add(p);
      clientes.add(claveCliente(p));
      prima += p.primaPoliza;
      final i = mesIdx(d!) - base;
      primaMes[i] += p.primaPoliza;
      nMes[i] += 1;
    }
    final ab = abonos;
    if (ab != null) {
      final sinDims = f.nDimensiones == 0;
      for (final a in ab) {
        if (!_enRango(a.fecha, desde, hasta)) continue;
        final p = _porId[a.idPoliza];
        if (p == null ? !sinDims : !_pasaDims(p, f)) continue;
        final i = mesIdx(a.fecha!) - base;
        rec += a.prima;
        com += a.comision;
        recMes[i] += a.prima;
        comMes[i] += a.comision;
      }
    }
    return Agregado(
      desde: desde,
      hasta: hasta,
      polizas: lista,
      clientes: clientes.length,
      prima: prima,
      comision: com,
      recaudo: rec,
      primaMes: primaMes,
      nMes: nMes,
      comisionMes: comMes,
      recaudoMes: recMes,
    );
  }

  Resultado calcular(FiltrosDash f) {
    final actual = _agregar(f, f.desde, f.hasta);
    final rc = rangoComparacion(f.desde, f.hasta, f.comparar);
    final comp = rc == null ? null : _agregar(f, rc.$1, rc.$2);
    final nMeses = actual.primaMes.length;
    final meses = [
      for (var i = 0; i < nMeses; i++)
        DateTime(f.desde.year, f.desde.month + i, 1)
    ];

    // Grupos por dimensión (producción del período + comisión/recaudo).
    final porDim = <Dim, List<Grupo>>{};
    for (final d in Dim.values) {
      final m = <String, Grupo>{};
      for (final p in actual.polizas) {
        final g = (m[claveDim(p, d)] ??= Grupo(claveDim(p, d)));
        g.n++;
        g.prima += p.primaPoliza;
      }
      if (abonos != null) {
        for (final a in abonos!) {
          if (!_enRango(a.fecha, f.desde, f.hasta)) continue;
          final p = _porId[a.idPoliza];
          if (p == null || !_pasaDims(p, f)) continue;
          final g = (m[claveDim(p, d)] ??= Grupo(claveDim(p, d)));
          g.comision += a.comision;
          g.recaudo += a.prima;
        }
      }
      porDim[d] = m.values.toList()..sort((a, b) => b.prima.compareTo(a.prima));
    }

    // Clientes: top, Pareto, concentración y nuevos vs recurrentes.
    final cli = <String, ClienteTopAcum>{};
    for (final p in actual.polizas) {
      final a = (cli[claveCliente(p)] ??=
          ClienteTopAcum(p.nombreCliente ?? 'Sin cliente'));
      a.n++;
      a.prima += p.primaPoliza;
    }
    final ordenados = cli.values.toList()
      ..sort((a, b) => b.prima.compareTo(a.prima));
    final totalPrima = actual.prima;
    final pareto = <double>[];
    var acum = 0.0;
    for (final c in ordenados.take(50)) {
      acum += c.prima;
      pareto.add(totalPrima == 0 ? 0 : acum / totalPrima * 100);
    }
    final top10 = ordenados.take(10).fold<double>(0, (s, c) => s + c.prima);
    var nNuevos = 0, nRec = 0;
    var pNuevos = 0.0, pRec = 0.0;
    for (final e in cli.entries) {
      final primera = _primeraFecha[e.key];
      if (primera != null && !primera.isBefore(f.desde)) {
        nNuevos++;
        pNuevos += e.value.prima;
      } else {
        nRec++;
        pRec += e.value.prima;
      }
    }

    // Cartera de lo emitido en el período.
    var cPrima = 0.0, cPagada = 0.0, cSaldo = 0.0;
    final aging = <String, num>{
      'Sin iniciar': 0,
      '0–30 días': 0,
      '31–60 días': 0,
      '61–90 días': 0,
      '91–180 días': 0,
      'Más de 180': 0,
    };
    final deud = <String, ClienteTopAcum>{};
    for (final p in actual.polizas) {
      if (p.estadoPolizaId == 'A' || p.primaPoliza <= 0) continue;
      final pagada = (p.vlrprimapagadaPoliza ?? 0).clamp(0, p.primaPoliza);
      final saldo = p.primaPoliza - pagada;
      cPrima += p.primaPoliza;
      cPagada += pagada;
      if (saldo <= 0) continue;
      cSaldo += saldo;
      final ini = p.finiPoliza ?? fechaProduccion(p) ?? hoy;
      final dias = hoy.difference(ini).inDays;
      final k = dias < 0
          ? 'Sin iniciar'
          : dias <= 30
              ? '0–30 días'
              : dias <= 60
                  ? '31–60 días'
                  : dias <= 90
                      ? '61–90 días'
                      : dias <= 180
                          ? '91–180 días'
                          : 'Más de 180';
      aging[k] = aging[k]! + saldo;
      final d = (deud[claveCliente(p)] ??=
          ClienteTopAcum(p.nombreCliente ?? 'Sin cliente'));
      d.n++;
      d.prima += saldo;
    }
    final deudores = (deud.values.toList()
          ..sort((a, b) => b.prima.compareTo(a.prima)))
        .take(10)
        .map((e) => ClienteTop(e.nombre, e.n, e.prima))
        .toList();

    // Renovaciones. Las pólizas que vencieron dentro del período (y ya
    // pasaron) son la base; cuenta cuántas tienen una póliza que las sigue.
    var renBase = 0, renOk = 0;
    final renAseg = <String, Grupo>{};
    final renAsesor = <String, Grupo>{};
    final fa = f.copia()..estado = 0;
    final sinRen = <FilaPoliza>[];
    final por30 = <FilaPoliza>[];
    final hasta30 = hoy.add(const Duration(days: 30));
    final hasta60 = hoy.add(const Duration(days: 60));
    final hasta90 = hoy.add(const Duration(days: 90));
    final desde90 = hoy.subtract(const Duration(days: 90));
    final futuros = [
      for (var i = 0; i < 12; i++) DateTime(hoy.year, hoy.month + i, 1)
    ];
    final venceN = List<double>.filled(12, 0);
    final vencePrima = List<double>.filled(12, 0);
    var v30 = 0, v60 = 0, v90 = 0;
    var p30 = 0.0, p60 = 0.0, p90 = 0.0;
    var sr = 0;
    var srPrima = 0.0;
    final mes0 = mesIdx(hoy);

    for (final p in polizas) {
      if (!_pasaPoliza(p, fa)) continue;
      final fin = p.ffinPoliza;
      if (fin == null) continue;
      if (_enRango(fin, f.desde, f.hasta) && fin.isBefore(hoy)) {
        renBase++;
        final ok = renovada(p);
        if (ok) renOk++;
        final ga = (renAseg[claveDim(p, Dim.aseguradora)] ??=
            Grupo(claveDim(p, Dim.aseguradora)));
        final gs = (renAsesor[claveDim(p, Dim.asesor)] ??=
            Grupo(claveDim(p, Dim.asesor)));
        ga.n++;
        gs.n++;
        if (ok) {
          ga.prima += 1;
          gs.prima += 1;
        }
      }
      if (!fin.isBefore(hoy)) {
        final i = mesIdx(fin) - mes0;
        if (i >= 0 && i < 12) {
          venceN[i] += 1;
          vencePrima[i] += p.primaPoliza;
        }
        final dias = fin.difference(hoy).inDays;
        if (!fin.isAfter(hasta30)) {
          v30++;
          p30 += p.primaPoliza;
          por30.add(FilaPoliza(p, p.primaPoliza, dias));
        } else if (!fin.isAfter(hasta60)) {
          v60++;
          p60 += p.primaPoliza;
        } else if (!fin.isAfter(hasta90)) {
          v90++;
          p90 += p.primaPoliza;
        }
      } else if (!fin.isBefore(desde90) && !renovada(p)) {
        sr++;
        srPrima += p.primaPoliza;
        sinRen.add(FilaPoliza(p, p.primaPoliza, hoy.difference(fin).inDays));
      }
    }
    por30.sort((a, b) => a.dias.compareTo(b.dias));
    sinRen.sort((a, b) => b.valor.compareTo(a.valor));

    // Matriz aseguradora × ramo (top 8 × top 8 por prima).
    final topAseg =
        porDim[Dim.aseguradora]!.take(8).map((g) => g.nombre).toList();
    final topRamo = porDim[Dim.ramo]!.take(8).map((g) => g.nombre).toList();
    final matriz = <String, num>{};
    for (final p in actual.polizas) {
      final a = claveDim(p, Dim.aseguradora);
      final r = claveDim(p, Dim.ramo);
      if (!topAseg.contains(a) || !topRamo.contains(r)) continue;
      matriz['$a||$r'] = (matriz['$a||$r'] ?? 0) + p.primaPoliza;
    }

    List<Grupo> ordenarRen(Map<String, Grupo> m) =>
        m.values.toList()..sort((a, b) => b.n.compareTo(a.n));

    return Resultado(
      filtros: f,
      actual: actual,
      comp: comp,
      meses: meses,
      porDim: porDim,
      clientesTop: ordenados
          .take(15)
          .map((e) => ClienteTop(e.nombre, e.n, e.prima))
          .toList(),
      pareto: pareto,
      concentracionTop10: totalPrima == 0 ? 0 : top10 / totalPrima * 100,
      clientesNuevos: nNuevos,
      clientesRecurrentes: nRec,
      primaNuevos: pNuevos,
      primaRecurrentes: pRec,
      carteraSaldo: cSaldo,
      carteraPagada: cPagada,
      carteraPrima: cPrima,
      aging: aging.entries.toList(),
      deudores: deudores,
      renBase: renBase,
      renRenovadas: renOk,
      renPorAseg: ordenarRen(renAseg),
      renPorAsesor: ordenarRen(renAsesor),
      mesesFuturos: futuros,
      venceN: venceN,
      vencePrima: vencePrima,
      porRenovar30: por30.take(40).toList(),
      sinRenovar90: sinRen.take(40).toList(),
      vence30: (v30, p30),
      vence60: (v60, p60),
      vence90: (v90, p90),
      sinRenovar90Tot: (sr, srPrima),
      matrizFilas: topAseg,
      matrizCols: topRamo,
      matriz: matriz,
    );
  }

  // ── Metas ──────────────────────────────────────────────────────────────

  /// Real mes a mes (12 posiciones) de un año, para toda la agencia o un
  /// asesor ([asesorId]). Devuelve claves prima, polizas, comision, recaudo.
  Map<String, List<double>> realesAnio(int anio, {int? asesorId}) {
    final r = {
      'prima': List<double>.filled(12, 0),
      'polizas': List<double>.filled(12, 0),
      'comision': List<double>.filled(12, 0),
      'recaudo': List<double>.filled(12, 0),
    };
    for (final p in polizas) {
      if (p.estadoPolizaId == 'A') continue;
      if (asesorId != null && p.asesorId != asesorId) continue;
      final d = fechaProduccion(p);
      if (d == null || d.year != anio) continue;
      r['prima']![d.month - 1] += p.primaPoliza;
      r['polizas']![d.month - 1] += 1;
    }
    final ab = abonos;
    if (ab != null) {
      for (final a in ab) {
        final d = a.fecha;
        if (d == null || d.year != anio) continue;
        if (asesorId != null && _porId[a.idPoliza]?.asesorId != asesorId) {
          continue;
        }
        r['comision']![d.month - 1] += a.comision;
        r['recaudo']![d.month - 1] += a.prima;
      }
    }
    return r;
  }

  // ── Calidad de datos ───────────────────────────────────────────────────

  CalidadDatos calidad() {
    var t = 0, sa = 0, sr = 0, sv = 0, sp = 0, sc = 0;
    for (final p in polizas) {
      if (p.estadoPolizaId == 'A') continue;
      t++;
      if (p.asesorId == null) sa++;
      if (p.ramoId == null) sr++;
      if (p.ffinPoliza == null) sv++;
      if (p.primaPoliza <= 0) sp++;
      if (p.clienteId == null) sc++;
    }
    return CalidadDatos(t, sa, sr, sv, sp, sc);
  }

  /// Rango (mín, máx) de fechas de producción: para el preset "Todo".
  (DateTime, DateTime)? rangoTotal() {
    DateTime? lo, hi;
    for (final p in polizas) {
      final d = fechaProduccion(p);
      if (d == null) continue;
      if (lo == null || d.isBefore(lo)) lo = d;
      if (hi == null || d.isAfter(hi)) hi = d;
    }
    return lo == null ? null : (lo, hi!);
  }
}

class ClienteTopAcum {
  final String nombre;
  int n = 0;
  num prima = 0;
  ClienteTopAcum(this.nombre);
}
