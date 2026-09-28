// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../datos/repositorio_catalogos.dart';
import '../datos/repositorio_ia.dart';
import '../datos/repositorio_polizas.dart';
import '../datos/repositorio_polizas_pendientes.dart';
import '../datos/catalogos.dart';
import '../datos/poliza.dart';
import '../datos/poliza_pendiente.dart';
import '../datos/sesion.dart';
import '../utils/filtros_busqueda.dart';
import '../utils/formatters.dart';
import 'catalogos/form_cliente.dart';
import 'theme/app_layout.dart';
import 'theme/app_theme.dart';
import 'widgets/buscador_dropdown.dart';
import 'widgets/section_card.dart';
import 'widgets/selector_fecha.dart';
import '../utils/numeros_co.dart';

extension FirstWhereOrNullExt<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}

class FormaPagoLite {
  final int id;
  final String nombre;
  final bool activo;

  FormaPagoLite({
    required this.id,
    required this.nombre,
    this.activo = true,
  });

  factory FormaPagoLite.fromMap(Map<String, dynamic> m) => FormaPagoLite(
        id: (m['id'] as num).toInt(),
        nombre: (m['nombre_forma_pago'] ?? '') as String,
        activo: m['estado_forma_pago'] != false,
      );
}

class EstadoPolizaLite {
  final String id;
  final String nombre;
  final bool activo;

  EstadoPolizaLite({
    required this.id,
    required this.nombre,
    this.activo = true,
  });

  factory EstadoPolizaLite.fromMap(Map<String, dynamic> m) => EstadoPolizaLite(
        id: (m['id'] ?? '').toString(),
        nombre: (m['nombre_estado'] ?? '') as String,
        activo: m['estado_activo'] != false,
      );
}

class IntermediarioLite {
  final int id;
  final String nombre;
  final bool activo;

  IntermediarioLite({
    required this.id,
    required this.nombre,
    this.activo = true,
  });

  factory IntermediarioLite.fromMap(Map<String, dynamic> m) =>
      IntermediarioLite(
        id: (m['id'] as num).toInt(),
        nombre: (m['nombre_interm'] ?? '') as String,
        activo: m['estado_interm'] != false,
      );
}

class FormaExpLite {
  final int id;
  final String nombre;

  FormaExpLite({required this.id, required this.nombre});

  factory FormaExpLite.fromMap(Map<String, dynamic> m) => FormaExpLite(
        id: (m['id'] as num).toInt(),
        nombre: (m['nombre_formaexp'] ?? '') as String,
      );
}

class PaginaFormularioPolizas extends StatefulWidget {
  final Poliza? poliza;

  /// Póliza en borrador o predigitada por IA que se está retomando — ver
  /// lib/fix_polizas_pendientes.sql. No se usa junto con [poliza].
  final PolizaPendiente? polizaPendiente;
  const PaginaFormularioPolizas({super.key, this.poliza, this.polizaPendiente});

  @override
  State<PaginaFormularioPolizas> createState() =>
      _PaginaFormularioPolizasState();
}

class _PaginaFormularioPolizasState extends State<PaginaFormularioPolizas> {
  final _formKey = GlobalKey<FormState>();

  final _repoCat = RepositorioCatalogos();
  final _repoPol = RepositorioPolizas();
  final _repoIA = RepositorioIA();
  final _repoPend = RepositorioPolizasPendientes();
  final _db = Supabase.instance.client;

  bool _cargando = true;
  bool _guardando = false;
  bool _guardandoBorrador = false;
  bool _importando = false;

  final _idCtrl = TextEditingController();
  final _nroCtrl = TextEditingController();
  String? _nroPolizaOriginal;

  final _fExpCtrl = TextEditingController();
  final _fIniCtrl = TextEditingController();
  final _fFinCtrl = TextEditingController();

  final _bienCtrl = TextEditingController();
  final _vlrAsegCtrl = TextEditingController();
  final _primaCtrl = TextEditingController();
  final _valorPolizaCtrl = TextEditingController();
  final _vlrBaseComCtrl = TextEditingController();
  final _porcComCtrl = TextEditingController();
  final _porcomAgenciaCtrl = TextEditingController();
  final _vlrComCtrl = TextEditingController();
  final _vlrComFijaCtrl = TextEditingController();
  final _porcomAdicCtrl = TextEditingController();
  final _vlrComAdicCtrl = TextEditingController();
  final _comDistribCtrl = TextEditingController();
  final _comAdicDistribCtrl = TextEditingController();
  final _porcomAsesor1Ctrl = TextEditingController();
  final _porcomAsesor2Ctrl = TextEditingController();
  final _porcomAsesor3Ctrl = TextEditingController();
  final _porcomAsesoradCtrl = TextEditingController();
  final _porcomAgenciaadCtrl = TextEditingController();
  final _vlrPrimaPagadaCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();

  Cliente? cliente;
  Aseguradora? aseguradora;
  Ramo? ramo;
  Producto? producto;

  IntermediarioLite? intermediario;

  Asesor? asesor1;
  Asesor? agencia;
  Asesor? asesor2;
  Asesor? asesor3;
  Asesor? asesorAd;
  Asesor? agenciaAd;

  FormaPagoLite? formaPago;
  EstadoPolizaLite? estadoPoliza;

  DateTime? fExp;
  DateTime? fIni;
  DateTime? fFin;

  List<Cliente> clientes = [];
  List<Asesor> asesores = [];
  List<Aseguradora> aseguradoras = [];
  List<Ramo> ramos = [];

  /// Ramos que tienen al menos un producto activo bajo la aseguradora
  /// elegida — igual que Producto se reduce por Ramo+Aseguradora, Ramo se
  /// reduce por Aseguradora (los ramos no tienen aseguradora propia, se
  /// derivan de los productos). Sin aseguradora elegida, muestra todos.
  List<Ramo> ramosDisponibles = [];
  List<Producto> productos = [];

  /// Todos los productos activos (de cualquier aseguradora/ramo) — sirve
  /// para derivar qué ramos tiene cada aseguradora sin ir a la red.
  List<Producto> _todosProductos = [];

  // Aprendizaje de correcciones IA (ver ia_aprendizaje_producto): si el
  // producto que terminó eligiendo el usuario al guardar es distinto del
  // que había sugerido la importación por IA, se registra la corrección.
  int? _productoSugeridoPorIA;
  String? _textoProductoParaAprendizaje;
  int? _aseguradoraIdEnSugerenciaIA;

  // Aprendizaje del rol de cliente (ver ia_aprendizaje_rol_cliente): qué
  // candidato (Tomador/Asegurado/Beneficiario) dio el match automático,
  // para reforzarlo si el usuario lo confirma tal cual al guardar.
  int? _clienteIdSugeridoPorIA;
  String? _rolClienteSugeridoPorIA;
  int? _aseguradoraIdEnSugerenciaCliente;
  List<FormaPagoLite> formasPago = [];
  List<EstadoPolizaLite> estadosPoliza = [];
  List<IntermediarioLite> intermediarios = [];
  List<FormaExpLite> formasExp = [];
  FormaExpLite? formaExp;

  bool get esEdicion => widget.poliza != null;

  @override
  void initState() {
    super.initState();
    _inicializar();
    // Rebuild en tiempo real para los valores calculados por asesor
    for (final ctrl in [
      _comDistribCtrl,
      _comAdicDistribCtrl,
      _porcomAsesor1Ctrl,
      _porcomAsesor2Ctrl,
      _porcomAsesor3Ctrl,
      _porcomAsesoradCtrl,
      _porcomAgenciaCtrl,
      _porcomAgenciaadCtrl,
    ]) {
      ctrl.addListener(_onComDistribChanged);
    }
  }

  void _onComDistribChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _nroCtrl.dispose();
    _fExpCtrl.dispose();
    _fIniCtrl.dispose();
    _fFinCtrl.dispose();
    _bienCtrl.dispose();
    _vlrAsegCtrl.dispose();
    _primaCtrl.dispose();
    _valorPolizaCtrl.dispose();
    _vlrBaseComCtrl.dispose();
    _porcComCtrl.dispose();
    _porcomAgenciaCtrl.dispose();
    _vlrComCtrl.dispose();
    _vlrComFijaCtrl.dispose();
    _porcomAdicCtrl.dispose();
    _vlrComAdicCtrl.dispose();
    _comDistribCtrl.dispose();
    _comAdicDistribCtrl.dispose();
    _porcomAsesor1Ctrl.dispose();
    _porcomAsesor2Ctrl.dispose();
    _porcomAsesor3Ctrl.dispose();
    _porcomAsesoradCtrl.dispose();
    _porcomAgenciaadCtrl.dispose();
    _vlrPrimaPagadaCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  String _formatearFecha(DateTime d) =>
      "${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}";

  String _soloFecha(String v) {
    final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length <= 2) return digits;
    if (digits.length <= 4) {
      return '${digits.substring(0, 2)}-${digits.substring(2)}';
    }
    // Con 5 a 7 dígitos el año todavía está incompleto (antes se cortaba
    // en la posición 8 y la app lanzaba un error en cada tecla).
    final fin = digits.length < 8 ? digits.length : 8;
    return '${digits.substring(0, 2)}-${digits.substring(2, 4)}-${digits.substring(4, fin)}';
  }

  DateTime? _parseFecha(String v) {
    try {
      final p = v.split('-');
      if (p.length != 3) return null;

      final d = int.parse(p[0]);
      final m = int.parse(p[1]);
      final y = int.parse(p[2]);

      if (y < 1900 || y > 2100) return null;

      final dt = DateTime(y, m, d);
      if (dt.day != d || dt.month != m || dt.year != y) return null;

      return dt;
    } catch (_) {
      return null;
    }
  }

  DateTime _addOneYearSafe(DateTime d) {
    final y = d.year + 1;
    final m = d.month;
    final day = d.day;

    final candidate = DateTime(y, m, day);
    if (candidate.month == m) return candidate;

    return DateTime(y, m + 1, 0);
  }

  // Parser compartido: "12.5" es 12,5 (antes se borraban todos los puntos
  // y quedaba 125).
  num? _parseNumero(String s) => parseNumCO(s);

  String _fmtMoney(num? n) => formatearNumCO(n);
  // Hasta 5 decimales: antes un 33,333% guardado se mostraba 33,33 y al
  // volver a guardar quedaba redondeado.
  String _fmtNum(num? n) => formatearNumCO(n, maxDecimales: 5);

  void _formatearMoney(TextEditingController ctrl) {
    final n = _parseNumero(ctrl.text);
    if (n == null) return;
    ctrl.text = _fmtMoney(n);
  }

  void _formatearNum(TextEditingController ctrl) {
    final n = _parseNumero(ctrl.text);
    if (n == null) return;
    ctrl.text = _fmtNum(n);
  }

  void _aplicarDefaultsDesdeRamo() {
    if (ramo == null) return;
    _recalcularBaseCom();
  }

  /// Ramos que tienen al menos un producto activo bajo [aseg] — sin
  /// aseguradora elegida, muestra todos. Siempre incluye el ramo ya
  /// seleccionado (si hay), para no ocultar una selección válida por datos
  /// de catálogo inconsistentes.
  /// [mantenerActual] preserva el Ramo ya seleccionado en la lista aunque
  /// no tenga productos bajo la aseguradora dada — sirve para no perder el
  /// dato al CARGAR una póliza ya guardada (edición, borrador, IA), pero
  /// NO debe usarse cuando el usuario cambia de Aseguradora a mano: ahí el
  /// Ramo/Producto de la aseguradora anterior no pertenecen a la nueva y
  /// tienen que limpiarse de verdad, no quedar "colados" en la lista.
  List<Ramo> _calcularRamosDisponibles(Aseguradora? aseg,
      {bool mantenerActual = true}) {
    if (aseg == null) return ramos;
    final idsConProducto = _todosProductos
        .where((p) => p.aseguradoraId == aseg.id)
        .map((p) => p.ramoId)
        .toSet();
    if (mantenerActual && ramo != null) idsConProducto.add(ramo!.id);
    final filtrados =
        ramos.where((r) => idsConProducto.contains(r.id)).toList();
    // Si la aseguradora todavía no tiene ningún producto cargado, no
    // bloqueamos el formulario con un dropdown vacío — mostramos todos.
    return filtrados.isEmpty ? ramos : filtrados;
  }

  void _aplicarDefaultsDesdeProducto() {
    if (producto == null) return;

    if (producto!.porcomProd != null) {
      _porcComCtrl.text = _fmtNum(producto!.porcomProd);
    }

    if (producto!.porcadProd != null) {
      _porcomAdicCtrl.text = _fmtNum(producto!.porcadProd);
    }

    _recalcularComision();
  }

  void _recalcularBaseCom() {
    final prima = _parseNumero(_primaCtrl.text) ?? 0;
    _vlrBaseComCtrl.text = _fmtMoney(prima);
    _recalcularComision();
  }

  void _recalcularComision() {
    final vlrBase = _parseNumero(_vlrBaseComCtrl.text) ?? 0;
    final porc = _parseNumero(_porcComCtrl.text) ?? 0;
    final calculado = vlrBase * (porc / 100);
    _vlrComCtrl.text = _fmtMoney(calculado);
    // Sugerir Com a distrib = Vlr Com + Com Fija (solo si el usuario no lo ha editado)
    final comFija = _parseNumero(_vlrComFijaCtrl.text) ?? 0;
    _comDistribCtrl.text = _fmtMoney(calculado + comFija);
  }

  /// Valor que le corresponde a un participante según Com a distrib y su %.
  num _vlrParticipante(
      TextEditingController porcCtrl, TextEditingController baseCtrl) {
    final base = _parseNumero(baseCtrl.text) ?? 0;
    final porc = _parseNumero(porcCtrl.text) ?? 0;
    return base * (porc / 100);
  }

  int? _idValido(int? v) {
    if (v == null || v <= 0) return null;
    return v;
  }

  // Todos, activos e inactivos: al editar una póliza con una forma de pago,
  // estado o intermediario ya desactivado, el valor se conserva (antes se
  // borraba al guardar o bloqueaba el guardado). Los dropdowns muestran
  // solo los activos más el que ya tenga la póliza.
  List<FormaPagoLite> _todasFormasPago = [];
  List<EstadoPolizaLite> _todosEstados = [];
  List<IntermediarioLite> _todosIntermediarios = [];

  Future<void> _cargarCatalogosExtra() async {
    final results = await Future.wait([
      _db
          .from('formas_pago')
          .select()
          .order('nombre_forma_pago', ascending: true),
      _db
          .from('estados_poliza')
          .select()
          .order('nombre_estado', ascending: true),
      _db
          .from('intermediarios')
          .select()
          .order('nombre_interm', ascending: true),
      _db.from('formaexp').select().order('nombre_formaexp', ascending: true),
    ]);

    _todasFormasPago = (results[0] as List)
        .cast<Map<String, dynamic>>()
        .map(FormaPagoLite.fromMap)
        .toList();
    _todosEstados = (results[1] as List)
        .cast<Map<String, dynamic>>()
        .map(EstadoPolizaLite.fromMap)
        .toList();
    _todosIntermediarios = (results[2] as List)
        .cast<Map<String, dynamic>>()
        .map(IntermediarioLite.fromMap)
        .toList();
    formasPago = _todasFormasPago.where((x) => x.activo).toList();
    estadosPoliza = _todosEstados.where((x) => x.activo).toList();
    intermediarios = _todosIntermediarios.where((x) => x.activo).toList();
    formasExp = (results[3] as List)
        .cast<Map<String, dynamic>>()
        .map(FormaExpLite.fromMap)
        .toList();
  }

  /// Después de cargar una póliza: si su valor está inactivo, se agrega a
  /// la lista del dropdown para que siga visible y se guarde igual.
  void _incluirInactivosSeleccionados() {
    if (formaPago != null && !formasPago.any((x) => x.id == formaPago!.id)) {
      formasPago = [...formasPago, formaPago!];
    }
    if (estadoPoliza != null &&
        !estadosPoliza.any((x) => x.id == estadoPoliza!.id)) {
      estadosPoliza = [...estadosPoliza, estadoPoliza!];
    }
    if (intermediario != null &&
        !intermediarios.any((x) => x.id == intermediario!.id)) {
      intermediarios = [...intermediarios, intermediario!];
    }
  }

  Future<Asesor?> _asegurarAsesor(int? id) async {
    if (id == null) return null;

    final existente = asesores.firstWhereOrNull((a) => a.id == id);
    if (existente != null) return existente;

    final nuevo = await _repoCat.obtenerAsesor(id);
    if (nuevo != null) {
      asesores = [...asesores, nuevo]
        ..sort((a, b) => a.nombreAsesor.compareTo(b.nombreAsesor));
    }

    return nuevo;
  }

  Future<Cliente?> _asegurarCliente(int? id) async {
    if (id == null) return null;

    final existente = clientes.firstWhereOrNull((c) => c.id == id);
    if (existente != null) return existente;

    final nuevo = await _repoCat.obtenerCliente(id);
    if (nuevo != null) {
      clientes = [...clientes, nuevo]
        ..sort((a, b) => a.nombreCliente.compareTo(b.nombreCliente));
    }

    return nuevo;
  }

  /// Abre el mismo formulario de edición de clientes que usa el catálogo,
  /// pero sin salir de la póliza — al volver, refresca este cliente con lo
  /// que se haya guardado (no reutiliza la instancia vieja en caché).
  Future<void> _editarClienteActual() async {
    if (cliente == null) return;
    final id = await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => FormCliente(cliente: cliente)),
    );
    if (id == null || !mounted) return;
    final actualizado = await _repoCat.obtenerCliente(id);
    if (actualizado == null || !mounted) return;
    setState(() {
      clientes = [
        for (final c in clientes)
          if (c.id != id) c,
        actualizado,
      ]..sort((a, b) => a.nombreCliente.compareTo(b.nombreCliente));
      cliente = actualizado;
    });
  }

  Future<void> _inicializar() async {
    await _cargar();
    final pp = widget.polizaPendiente;
    if (pp != null && pp.estado == 'pendiente_revision' && mounted) {
      final completados = await _aplicarDatosExtraidos(pp.datos);
      if (!mounted) return;
      _toast(completados > 0
          ? 'Póliza predigitada: revise los $completados campo(s) antes de guardar.'
          : 'No se pudo aplicar la información predigitada; complétela a mano.');
    }
  }

  Future<void> _cargar() async {
    try {
      final results = await Future.wait([
        _repoCat.listarAsesores(soloActivos: true),
        _repoCat.listarAseguradoras(soloActivas: true),
        _repoCat.listarRamos(soloActivos: true),
        _repoCat.listarProductos(soloActivos: true),
        _cargarCatalogosExtra(),
      ]);

      asesores = results[0] as List<Asesor>;
      aseguradoras = results[1] as List<Aseguradora>;
      ramos = results[2] as List<Ramo>;
      ramosDisponibles = ramos;
      _todosProductos = results[3] as List<Producto>;
      final allProductosActivos = _todosProductos;

      if (esEdicion) {
        final p =
            await _repoPol.obtenerPoliza(widget.poliza!.id) ?? widget.poliza!;

        _idCtrl.text = p.id.toString();
        _nroCtrl.text = p.nroPoliza ?? '';
        _nroPolizaOriginal = p.nroPoliza ?? '';
        _asegOriginalId = p.asegId;

        _bienCtrl.text = p.bienAsegurado ?? '';
        _vlrAsegCtrl.text = _fmtMoney(p.vlrasegPoliza);
        _primaCtrl.text = _fmtMoney(p.primaPoliza);
        _valorPolizaCtrl.text = _fmtMoney(p.valorPoliza);
        _vlrBaseComCtrl.text = _fmtMoney(p.vlrbasecomPoliza);
        _porcComCtrl.text = _fmtNum(p.porccomPoliza);
        _porcomAgenciaCtrl.text = _fmtNum(p.porcomAgencia);
        _vlrComCtrl.text = _fmtMoney(p.vlrcomPoliza);
        _vlrComFijaCtrl.text = _fmtMoney(p.vlrcomfijaPoliza);
        final comDistrib = (p.vlrcomPoliza ?? 0) + (p.vlrcomfijaPoliza ?? 0);
        _comDistribCtrl.text = _fmtMoney(comDistrib);
        _comAdicDistribCtrl.text = _fmtMoney(p.vlrcomadicPoliza);
        _porcomAdicCtrl.text = _fmtNum(p.porcomadicPoliza);
        _vlrComAdicCtrl.text = _fmtMoney(p.vlrcomadicPoliza);
        _porcomAsesor1Ctrl.text = _fmtNum(p.porcomAsesor1);
        _porcomAsesor2Ctrl.text = _fmtNum(p.porcomAsesor2);
        _porcomAsesor3Ctrl.text = _fmtNum(p.porcomAsesor3);
        _porcomAsesoradCtrl.text = _fmtNum(p.porcomAsesorad);
        _porcomAgenciaadCtrl.text = _fmtNum(p.porcomAgenciaad);
        _vlrPrimaPagadaCtrl.text = _fmtMoney(p.vlrprimapagadaPoliza);
        _obsCtrl.text = p.obsPoliza ?? '';

        fExp = p.fexpPoliza;
        fIni = p.finiPoliza;
        fFin = p.ffinPoliza;

        _fExpCtrl.text = fExp == null ? '' : _formatearFecha(fExp!);
        _fIniCtrl.text = fIni == null ? '' : _formatearFecha(fIni!);
        _fFinCtrl.text = fFin == null ? '' : _formatearFecha(fFin!);

        cliente = await _asegurarCliente(p.clienteId);
        intermediario = _todosIntermediarios
            .firstWhereOrNull((x) => x.id == p.intermediarioId);
        formaExp = formasExp.firstWhereOrNull((x) => x.id == p.formaexpId);

        asesor1 = await _asegurarAsesor(p.asesorId);
        asesor2 = await _asegurarAsesor(p.asesor2Id);
        asesor3 = await _asegurarAsesor(p.asesor3Id);
        asesorAd = await _asegurarAsesor(p.asesoradId);
        agencia = await _asegurarAsesor(p.agenciaId);
        agenciaAd = await _asegurarAsesor(p.agenciaadId);

        Producto? prod =
            allProductosActivos.firstWhereOrNull((x) => x.id == p.productoId);
        if (prod == null && p.productoId != null) {
          prod = await _repoCat.obtenerProducto(p.productoId!);
        }
        producto = prod;

        ramo = ramos.firstWhereOrNull((x) => x.id == p.ramoId);
        if (ramo == null && p.ramoId != null) {
          final sel = await _repoCat.obtenerRamo(p.ramoId!);
          if (sel != null) {
            ramos = [...ramos, sel]
              ..sort((a, b) => a.nombreRamo.compareTo(b.nombreRamo));
            ramo = ramos.firstWhereOrNull((x) => x.id == p.ramoId);
          }
        }

        if (p.asegId != null) {
          aseguradora = aseguradoras.firstWhereOrNull((a) => a.id == p.asegId);
          if (aseguradora == null) {
            final sel = await _repoCat.obtenerAseguradora(p.asegId!);
            if (sel != null) {
              aseguradoras = [...aseguradoras, sel]
                ..sort((a, b) => a.nombreAseg.compareTo(b.nombreAseg));
              aseguradora =
                  aseguradoras.firstWhereOrNull((a) => a.id == p.asegId);
            }
          }
        } else if (producto != null) {
          final asegId = producto!.aseguradoraId;
          aseguradora = aseguradoras.firstWhereOrNull((a) => a.id == asegId);
        }

        formaPago =
            _todasFormasPago.firstWhereOrNull((x) => x.id == p.formaPagoId);
        estadoPoliza =
            _todosEstados.firstWhereOrNull((x) => x.id == p.estadoPolizaId);
        _estadoOriginalId = p.estadoPolizaId;
        _primaPagadaOriginal = _parseNumero(_vlrPrimaPagadaCtrl.text);
        _incluirInactivosSeleccionados();
      } else {
        estadoPoliza = estadosPoliza.firstWhereOrNull((e) => e.id == 'I');
        formaPago = formasPago.firstWhereOrNull(
          (f) => f.nombre.toUpperCase().contains('CONTADO'),
        );
        formaExp = formasExp.firstWhereOrNull(
          (f) => f.nombre.toUpperCase().contains('STELLA'),
        );
        intermediario = intermediarios.firstWhereOrNull(
          (i) => i.nombre.toUpperCase().contains('STELLA'),
        );

        // Asesor 1 casi siempre es Luz Stella Serrano Mantilla con el 100%
        // de la comisión — se predigita para no tener que llenarlo a mano
        // cada vez, pero sigue siendo editable.
        asesor1 = asesores.firstWhereOrNull(
          (a) => a.nombreAsesor.toUpperCase().contains('LUZ STELLA SERRANO'),
        );
        if (asesor1 != null) _porcomAsesor1Ctrl.text = _fmtNum(100);

        // El código real se asigna solo al guardar (ver _guardar) — mostrar
        // acá un preview del "siguiente id" es justo lo que causaba que dos
        // personas digitando a la vez anotaran un código que después no
        // coincidía con el real.

        // Retomando un borrador guardado a medio llenar — pisa los defaults
        // de arriba con lo que ya se había digitado. La predigitada por IA
        // ('pendiente_revision') se aplica en _inicializar() reusando el
        // mismo matcheo por nombre que la importación manual de PDF.
        if (widget.polizaPendiente?.estado == 'borrador') {
          await _aplicarBorrador(widget.polizaPendiente!.datos);
        }
      }

      ramosDisponibles = _calcularRamosDisponibles(aseguradora);

      if (!mounted) return;
      setState(() => _cargando = false);

      await _refrescarProductos();
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      _toast('Error cargando catálogos: $e');
    }
  }

  static int? _intJson(dynamic v) =>
      v == null ? null : (v is int ? v : int.tryParse(v.toString()));
  static num? _numJson(dynamic v) =>
      v == null ? null : (v is num ? v : num.tryParse(v.toString()));
  static DateTime? _dateJson(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  /// Repuebla el formulario con el mapa que guardó "Guardar borrador" — es
  /// el mismo shape que arma _guardar() antes de insertar (ids reales, ya
  /// elegidos por el usuario), no el de la extracción por IA.
  Future<void> _aplicarBorrador(Map<String, dynamic> datos) async {
    _nroCtrl.text = (datos['nro_poliza'] as String?) ?? '';
    _bienCtrl.text = (datos['bien_asegurado'] as String?) ?? '';
    _vlrAsegCtrl.text = _fmtMoney(_numJson(datos['vlraseg_poliza']));
    _primaCtrl.text = _fmtMoney(_numJson(datos['prima_poliza']));
    _valorPolizaCtrl.text = _fmtMoney(_numJson(datos['valor_poliza']));
    _vlrBaseComCtrl.text = _fmtMoney(_numJson(datos['vlrbasecom_poliza']));
    _porcComCtrl.text = _fmtNum(_numJson(datos['porccom_poliza']));
    _porcomAgenciaCtrl.text = _fmtNum(_numJson(datos['porcom_agencia']));
    _vlrComCtrl.text = _fmtMoney(_numJson(datos['vlrcom_poliza']));
    _vlrComFijaCtrl.text = _fmtMoney(_numJson(datos['vlrcomfija_poliza']));
    final comDistrib = (_numJson(datos['vlrcom_poliza']) ?? 0) +
        (_numJson(datos['vlrcomfija_poliza']) ?? 0);
    _comDistribCtrl.text = _fmtMoney(comDistrib);
    _comAdicDistribCtrl.text = _fmtMoney(_numJson(datos['vlrcomadic_poliza']));
    _porcomAdicCtrl.text = _fmtNum(_numJson(datos['porcomadic_poliza']));
    _vlrComAdicCtrl.text = _fmtMoney(_numJson(datos['vlrcomadic_poliza']));
    _porcomAsesor1Ctrl.text = _fmtNum(_numJson(datos['porcom_asesor1']));
    _porcomAsesor2Ctrl.text = _fmtNum(_numJson(datos['porcom_asesor2']));
    _porcomAsesor3Ctrl.text = _fmtNum(_numJson(datos['porcom_asesor3']));
    _porcomAsesoradCtrl.text = _fmtNum(_numJson(datos['porcom_asesorad']));
    _porcomAgenciaadCtrl.text = _fmtNum(_numJson(datos['porcom_agenciaad']));
    _vlrPrimaPagadaCtrl.text =
        _fmtMoney(_numJson(datos['vlrprimapagada_poliza']));
    _obsCtrl.text = (datos['obs_poliza'] as String?) ?? '';

    fExp = _dateJson(datos['fexp_poliza']);
    fIni = _dateJson(datos['fini_poliza']);
    fFin = _dateJson(datos['ffin_poliza']);
    _fExpCtrl.text = fExp == null ? '' : _formatearFecha(fExp!);
    _fIniCtrl.text = fIni == null ? '' : _formatearFecha(fIni!);
    _fFinCtrl.text = fFin == null ? '' : _formatearFecha(fFin!);

    cliente = await _asegurarCliente(_intJson(datos['cliente_id']));
    intermediario = intermediarios
        .firstWhereOrNull((x) => x.id == _intJson(datos['intermediario_id']));
    formaExp = formasExp
        .firstWhereOrNull((x) => x.id == _intJson(datos['formaexp_id']));

    asesor1 = await _asegurarAsesor(_intJson(datos['asesor_id']));
    asesor2 = await _asegurarAsesor(_intJson(datos['asesor2_id']));
    asesor3 = await _asegurarAsesor(_intJson(datos['asesor3_id']));
    asesorAd = await _asegurarAsesor(_intJson(datos['asesorad_id']));
    agencia = await _asegurarAsesor(_intJson(datos['agencia_id']));
    agenciaAd = await _asegurarAsesor(_intJson(datos['agenciaad_id']));

    final productoId = _intJson(datos['producto_id']);
    Producto? prod =
        _todosProductos.firstWhereOrNull((x) => x.id == productoId);
    if (prod == null && productoId != null) {
      prod = await _repoCat.obtenerProducto(productoId);
    }
    producto = prod;

    final ramoId = _intJson(datos['ramo_id']);
    ramo = ramos.firstWhereOrNull((x) => x.id == ramoId);
    if (ramo == null && ramoId != null) {
      final sel = await _repoCat.obtenerRamo(ramoId);
      if (sel != null) {
        ramos = [...ramos, sel]
          ..sort((a, b) => a.nombreRamo.compareTo(b.nombreRamo));
        ramo = ramos.firstWhereOrNull((x) => x.id == ramoId);
      }
    }

    final asegId = _intJson(datos['aseg_id']);
    if (asegId != null) {
      aseguradora = aseguradoras.firstWhereOrNull((a) => a.id == asegId);
      if (aseguradora == null) {
        final sel = await _repoCat.obtenerAseguradora(asegId);
        if (sel != null) {
          aseguradoras = [...aseguradoras, sel]
            ..sort((a, b) => a.nombreAseg.compareTo(b.nombreAseg));
          aseguradora = aseguradoras.firstWhereOrNull((a) => a.id == asegId);
        }
      }
    } else if (producto != null) {
      aseguradora =
          aseguradoras.firstWhereOrNull((a) => a.id == producto!.aseguradoraId);
    }

    final formaPagoId = _intJson(datos['forma_pago_id']);
    if (formaPagoId != null) {
      formaPago = _todasFormasPago.firstWhereOrNull((x) => x.id == formaPagoId);
    }
    final estadoId = datos['estado_poliza_id'] as String?;
    if (estadoId != null) {
      estadoPoliza = _todosEstados.firstWhereOrNull((x) => x.id == estadoId);
    }
    _incluirInactivosSeleccionados();
  }

  Future<void> _refrescarProductos() async {
    if (ramo == null || aseguradora == null) {
      if (!mounted) return;
      setState(() {
        productos = [];
        producto = null;
      });
      return;
    }

    try {
      final res = await _repoCat.listarProductos(
        ramoId: ramo!.id,
        aseguradoraId: aseguradora!.id,
        soloActivos: true,
      );

      if (!mounted) return;

      setState(() {
        productos = res;

        final currentId = producto?.id;
        if (currentId == null) {
          producto = null;
          return;
        }

        final match = productos.firstWhereOrNull((p) => p.id == currentId);
        if (match != null) {
          producto = match;
        } else if (producto!.ramoId == ramo!.id &&
            producto!.aseguradoraId == aseguradora!.id) {
          // Producto ya desactivado pero es el de esta póliza: se conserva
          // (antes se borraba y había que cambiar el dato histórico).
          productos = [...productos, producto!];
        } else {
          producto = null;
        }
      });
    } catch (e) {
      _toast('Error cargando productos: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  // ── Importar desde PDF/imagen (IA) ──────────────────────────────────────

  Future<void> _importarDesdeArchivo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    _nombreArchivoImportado = file.name;
    final bytes = file.bytes;
    final ext = (file.extension ?? '').toLowerCase();
    final mimeType = switch (ext) {
      'pdf' => 'application/pdf',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => null,
    };
    if (bytes == null || mimeType == null) {
      _toast('No se pudo leer el archivo. Use PDF, JPG, PNG o WEBP.');
      return;
    }

    setState(() => _importando = true);
    try {
      // Ya cacheado (RepositorioCatalogos._cache), no pega dos veces a la red.
      final catalogo = await _repoCat.catalogoProductosParaIA();
      final datos = await _repoIA.extraerPoliza(bytes, mimeType,
          catalogoProductos: catalogo);
      if (!mounted) return;
      final completados = await _aplicarDatosExtraidos(datos);
      final huboCliente = cliente != null;
      String avisoCliente = '';
      if (!huboCliente) {
        // Cliente nuevo, ningún documento matcheó — si para esta
        // aseguradora ya se confirmó antes que el cliente real suele venir
        // de un rol puntual (Tomador/Asegurado/Beneficiario), se sugiere
        // ese nombre en vez de siempre asumir el Tomador.
        var rolSugerido = 'tomador';
        if (aseguradora != null) {
          final preferido = await _repoCat.rolClientePreferido(aseguradora!.id);
          if (preferido != null) rolSugerido = preferido;
        }
        final (nombreSugerido, docSugerido) = switch (rolSugerido) {
          'asegurado' => (datos['nombre_asegurado'], datos['doc_asegurado']),
          'beneficiario' => (
              datos['nombre_beneficiario'],
              datos['doc_beneficiario']
            ),
          _ => (datos['nombre_cliente'], datos['doc_cliente']),
        };
        avisoCliente = ' Cliente extraído: "${nombreSugerido ?? '—'}" '
            '(doc "${docSugerido ?? '—'}") — no se encontró en la base, '
            'búsquelo a mano.';
      }
      _toast(completados > 0
          ? 'Se completaron $completados campo(s) automáticamente. Revise antes de guardar.$avisoCliente'
          : 'No se pudo identificar ningún dato en el documento.');
    } catch (e) {
      _toast('Error al importar: $e');
    } finally {
      if (mounted) setState(() => _importando = false);
    }
  }

  Future<int> _aplicarDatosExtraidos(Map<String, dynamic> datos) async {
    int completados = 0;
    // Una importación nueva descarta lo sugerido por la anterior.
    _productoSugeridoPorIA = null;
    _textoProductoParaAprendizaje = null;
    _aseguradoraIdEnSugerenciaIA = null;
    _clienteIdSugeridoPorIA = null;
    _rolClienteSugeridoPorIA = null;
    _aseguradoraIdEnSugerenciaCliente = null;

    String? texto(String key) {
      final v = datos[key];
      return (v is String && v.trim().isNotEmpty) ? v.trim() : null;
    }

    num? numero(String key) {
      final v = datos[key];
      return v is num ? v : null;
    }

    // Se calcula antes del await de cliente porque el aprendizaje de rol
    // necesita saber la aseguradora — es síncrono, no hace falta esperar.
    final matchAsegPrevio = _matchPorNombre(
        aseguradoras, (a) => a.nombreAseg, texto('nombre_aseguradora'));

    // La búsqueda de cliente pega al servidor — se resuelve antes del
    // setState para no mezclar await con la actualización de estado.
    final (matchCliente, rolMatcheado) = await _buscarClienteExtraido([
      ('tomador', texto('nombre_cliente'), texto('doc_cliente')),
      ('asegurado', texto('nombre_asegurado'), texto('doc_asegurado')),
      ('beneficiario', texto('nombre_beneficiario'), texto('doc_beneficiario')),
    ]);
    if (matchCliente != null &&
        rolMatcheado != null &&
        matchAsegPrevio != null) {
      _clienteIdSugeridoPorIA = matchCliente.id;
      _rolClienteSugeridoPorIA = rolMatcheado;
      _aseguradoraIdEnSugerenciaCliente = matchAsegPrevio.id;
    }

    setState(() {
      final nro = texto('nro_poliza');
      if (nro != null) {
        _nroCtrl.text = nro;
        completados++;
      }

      final matchAseg = matchAsegPrevio;
      if (matchAseg != null) {
        aseguradora = matchAseg;
        ramosDisponibles = _calcularRamosDisponibles(aseguradora);
        completados++;
      }

      if (matchCliente != null) {
        cliente = matchCliente;
        completados++;
      }

      final dIni = _parseFechaISO(datos['fecha_inicio']);
      if (dIni != null) {
        fIni = dIni;
        _fIniCtrl.text = _formatearFecha(dIni);
        completados++;
      }
      final dFin = _parseFechaISO(datos['fecha_fin']);
      if (dFin != null) {
        fFin = dFin;
        _fFinCtrl.text = _formatearFecha(dFin);
        completados++;
      }
      final dExp = _parseFechaISO(datos['fecha_expedicion']);
      if (dExp != null) {
        fExp = dExp;
        _fExpCtrl.text = _formatearFecha(dExp);
        completados++;
      }

      final prima = numero('prima');
      if (prima != null) {
        _primaCtrl.text = _fmtMoney(prima);
        // Igual que si se escribiera a mano: dispara el recálculo en
        // cascada de Vlr. Base Com. y Vlr. Com. (ver _recalcularBaseCom).
        _recalcularBaseCom();
        completados++;
      }
      final vlrAseg = numero('valor_asegurado');
      if (vlrAseg != null) {
        _vlrAsegCtrl.text = _fmtMoney(vlrAseg);
        completados++;
      }
      final valorPoliza = numero('valor_poliza');
      if (valorPoliza != null) {
        _valorPolizaCtrl.text = _fmtMoney(valorPoliza);
        completados++;
      }

      final bien = texto('bien_asegurado');
      if (bien != null) {
        _bienCtrl.text = bien;
        completados++;
      }
    });

    // Ramo y Producto: cada Producto ya pertenece a un Ramo fijo en el
    // catálogo, así que primero se intenta matchear el Producto (suele
    // aparecer más literal en el documento — título de la póliza, tipo de
    // plan — que un "Ramo" que casi nunca se escribe como texto) contra
    // los productos de la aseguradora ya detectada, y el Ramo se DERIVA de
    // ahí. Si no matchea ningún producto, se cae al intento viejo de
    // matchear el ramo por nombre directo.
    if (aseguradora != null) {
      final candidatosProd = _todosProductos
          .where((p) => p.aseguradoraId == aseguradora!.id)
          .toList();
      final textoProd = texto('nombre_producto') ?? texto('nombre_ramo') ?? '';
      final textoProdNorm = _normalizarTexto(textoProd);

      // Aprendizaje: si antes alguien ya corrigió a mano lo que la IA
      // sugería para este mismo texto de esta aseguradora, se usa
      // directamente esa corrección en vez de volver a adivinar.
      Producto? matchAprendido;
      if (textoProdNorm.isNotEmpty) {
        try {
          final prodIdAprendido = await _repoCat.buscarProductoAprendido(
              aseguradora!.id, textoProdNorm);
          if (prodIdAprendido != null) {
            matchAprendido =
                candidatosProd.firstWhereOrNull((p) => p.id == prodIdAprendido);
          }
        } catch (_) {}
      }

      final matchProd = matchAprendido ??
          _matchPorNombre(
              candidatosProd, (p) => p.nombreProd, texto('nombre_producto')) ??
          _matchPorNombre(
              candidatosProd, (p) => p.nombreProd, texto('nombre_ramo'));

      // Se guarda el texto aunque no haya coincidencia: si el usuario elige
      // el producto a mano, esa elección también se aprende.
      if (textoProdNorm.isNotEmpty) {
        _productoSugeridoPorIA = matchProd?.id;
        _textoProductoParaAprendizaje = textoProdNorm;
        _aseguradoraIdEnSugerenciaIA = aseguradora!.id;
      }

      if (matchProd != null && mounted) {
        final matchRamoDerivado =
            ramos.firstWhereOrNull((r) => r.id == matchProd.ramoId);
        setState(() {
          if (matchRamoDerivado != null) {
            ramo = matchRamoDerivado;
            ramosDisponibles = _calcularRamosDisponibles(aseguradora);
            completados++;
          }
          // Instancia provisoria (viene de _todosProductos, cargada al
          // abrir el formulario) — _refrescarProductos() la reemplaza por
          // la instancia real de la lista recién traída para ese ramo,
          // usando el id. Si no se hace así, el dropdown de Producto
          // revienta: su value quedaría siendo un objeto que no es ==
          // (por identidad) a ninguno de los items de la lista nueva.
          producto = matchProd;
        });
        await _refrescarProductos();
        if (mounted && producto != null) {
          setState(() {
            // Igual que al elegir el producto a mano: aplica su % de
            // comisión por defecto y recalcula Vlr. Com.
            _aplicarDefaultsDesdeProducto();
          });
          completados++;
        }
      } else {
        final matchRamo =
            _matchPorNombre(ramos, (r) => r.nombreRamo, texto('nombre_ramo'));
        if (matchRamo != null && mounted) {
          setState(() {
            ramo = matchRamo;
            ramosDisponibles = _calcularRamosDisponibles(aseguradora);
          });
          completados++;
          await _refrescarProductos();
          final matchProd2 = _matchPorNombre(
              productos, (p) => p.nombreProd, texto('nombre_producto'));
          if (matchProd2 != null && mounted) {
            setState(() {
              producto = matchProd2;
              _aplicarDefaultsDesdeProducto();
            });
            completados++;
          }
        }
      }
    }

    return completados;
  }

  /// [candidatos] va en orden de prioridad (Tomador, Asegurado, Beneficiario)
  /// pero la prioridad real es del DOCUMENTO: se prueba cada uno contra la
  /// base y gana el primero que ya exista como cliente real — sin importar
  /// qué rol le haya puesto la aseguradora en el PDF, porque puede que el
  /// cliente de la correduría figure como Asegurado en vez de Tomador según
  /// cómo esté armado ese producto. Solo si NINGÚN documento matchea se cae
  /// al nombre del primer candidato (el Tomador) como sugerencia.
  /// [candidatos] va con su rol ('tomador'/'asegurado'/'beneficiario') para
  /// poder registrar después, si el usuario confirma este cliente al
  /// guardar, cuál rol resultó ser el correcto para esta aseguradora (ver
  /// ia_aprendizaje_rol_cliente). Devuelve el cliente encontrado y el rol
  /// que dio el match, o (null, null) si no encontró nada.
  Future<(Cliente?, String?)> _buscarClienteExtraido(
      List<(String rol, String? nombre, String? doc)> candidatos) async {
    try {
      for (final (rol, _, doc) in candidatos) {
        final docLimpio =
            (doc ?? '').replaceAll(RegExp(r'[^0-9A-Za-z]'), '').toUpperCase();
        if (docLimpio.isEmpty) continue;
        // Match exacto contra doc_cliente_norm (solo dígitos/letras, sin
        // puntos ni guión — ver fix_doc_cliente_normalizado.sql).
        final match = await _repoCat.buscarClientePorDocExacto(docLimpio);
        if (match != null) return (match, rol);
      }
      final primero = candidatos.isNotEmpty ? candidatos.first : null;
      final nombre = primero?.$2;
      if (nombre != null && nombre.isNotEmpty) {
        // El documento puede traer el nombre en otro orden que la base
        // ("APELLIDOS, NOMBRE" vs "Nombre Apellidos") — un ilike de la
        // cadena completa no encontraría nada, así que buscamos por la
        // palabra más significativa (la más larga) y comparamos después
        // por conjunto de palabras, sin importar el orden.
        final palabras = _palabras(_normalizarTexto(nombre)).toList()
          ..sort((a, b) => b.length.compareTo(a.length));
        if (palabras.isEmpty) return (null, null);
        final res = await _repoCat.buscarClientes(palabras.first, limit: 20);
        final matchNombre =
            _matchPorNombre(res, (c) => c.nombreCliente, nombre);
        return (matchNombre, matchNombre != null ? primero!.$1 : null);
      }
    } catch (_) {
      // Si falla la búsqueda, se deja para que el usuario elija a mano.
    }
    return (null, null);
  }

  T? _matchPorNombre<T>(
      List<T> lista, String Function(T) nombre, String? candidato) {
    if (candidato == null || candidato.trim().isEmpty) return null;
    final norm = _normalizarTexto(candidato);
    for (final item in lista) {
      if (_normalizarTexto(nombre(item)) == norm) return item;
    }
    for (final item in lista) {
      final n = _normalizarTexto(nombre(item));
      if (n.isNotEmpty && (n.contains(norm) || norm.contains(n))) return item;
    }
    // Mismo conjunto de palabras aunque el orden difiera (ej: nombre del
    // documento en "APELLIDOS, NOMBRE" contra "Nombre Apellidos" en la
    // base) — uno de los dos debe contener todas las palabras del otro.
    final palabrasCandidato = _palabras(norm);
    if (palabrasCandidato.length >= 2) {
      for (final item in lista) {
        final palabrasItem = _palabras(_normalizarTexto(nombre(item)));
        if (palabrasItem.isEmpty) continue;
        if (palabrasCandidato.difference(palabrasItem).isEmpty ||
            palabrasItem.difference(palabrasCandidato).isEmpty) {
          return item;
        }
      }
    }
    return null;
  }

  Set<String> _palabras(String s) => s
      .replaceAll(',', ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.length > 1)
      .toSet();

  /// Ignora espacios/separadores, igual que RepositorioPolizas.existeNroPoliza
  /// — se usa para detectar si el usuario realmente cambió el número (y no
  /// solo el espaciado) y así evitar re-chequear duplicados preexistentes
  /// contra pólizas que ya se guardaron así antes de este fix.
  /// Aseguradora con la que se cargó la póliza: si cambia, se vuelve a
  /// revisar el número repetido (la unicidad es por aseguradora).
  int? _asegOriginalId;

  String _normalizarNroLocal(String s) =>
      s.replaceAll(RegExp(r'[^0-9A-Za-z]'), '').toUpperCase();

  String _normalizarTexto(String s) {
    var r = s.trim().toUpperCase();
    const acentos = {
      'Á': 'A',
      'É': 'E',
      'Í': 'I',
      'Ó': 'O',
      'Ú': 'U',
      'Ñ': 'N',
    };
    acentos.forEach((k, v) => r = r.replaceAll(k, v));
    return r;
  }

  DateTime? _parseFechaISO(dynamic v) {
    if (v is! String || v.trim().isEmpty) return null;
    try {
      final d = DateTime.parse(v.trim());
      return DateTime(d.year, d.month, d.day);
    } catch (_) {
      return null;
    }
  }

  Widget _campo(
    String l,
    TextEditingController c, {
    bool req = false,
    bool num = false,
    bool money = false,
    int maxDec = 2,
    int lines = 1,
    bool readOnly = false,
    String? helper,
    VoidCallback? onEditingComplete,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: c,
      maxLines: lines,
      readOnly: readOnly,
      keyboardType: num
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : null,
      inputFormatters: (num && !readOnly && lines == 1)
          ? [NumeroCOInputFormatter(maxDecimales: maxDec)]
          : null,
      validator: req
          ? (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null
          : null,
      onEditingComplete: onEditingComplete,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: l,
        helperText: helper,
        prefixText: money ? '\$ ' : null,
        border: const OutlineInputBorder(),
      ),
    );
  }

  /// F. Fin = F. Inicio + 1 año, solo si F. Fin está vacía o la había
  /// puesto este mismo cálculo (antes pisaba una F. Fin ya digitada o
  /// guardada al corregir la F. Inicio).
  bool _finAutomatica = false;

  void _sugerirFin(DateTime inicio) {
    if (fFin != null && !_finAutomatica) return;
    final fin = _addOneYearSafe(inicio);
    fFin = fin;
    _fFinCtrl.text = _formatearFecha(fin);
    _finAutomatica = true;
  }

  Widget _fechaCampo(
    String label,
    TextEditingController ctrl,
    DateTime? fecha,
    void Function(DateTime?) setFecha, {
    bool autoFin = false,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      onChanged: (v) {
        final f = _soloFecha(v);
        ctrl.value = TextEditingValue(
          text: f,
          selection: TextSelection.collapsed(offset: f.length),
        );

        if (f.isEmpty) {
          // Borrar el campo borra la fecha (antes quedaba la anterior y se
          // guardaba sin que el usuario la viera).
          setState(() {
            setFecha(null);
            if (identical(ctrl, _fFinCtrl)) _finAutomatica = false;
          });
          return;
        }
        final parsed = _parseFecha(f);
        if (parsed != null) {
          setState(() {
            setFecha(parsed);
            if (identical(ctrl, _fFinCtrl)) _finAutomatica = false;
            if (autoFin) _sugerirFin(parsed);
          });
        }
      },
      validator: (v) {
        final s = (v ?? '').trim();
        final esFin = identical(ctrl, _fFinCtrl);

        if (s.isEmpty) return esFin ? 'Requerido' : null;

        final parsed = _parseFecha(s);
        if (parsed == null) return 'Fecha inválida';

        if (esFin && fIni != null && parsed.isBefore(fIni!)) {
          return 'Fin < Inicio';
        }
        return null;
      },
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: 'dd-mm-aaaa',
        border: const OutlineInputBorder(),
        suffixIconConstraints:
            const BoxConstraints(minWidth: 36, minHeight: 24),
        suffixIcon: IconButton(
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.calendar_month, size: 18),
          onPressed: () async {
            final sel = await mostrarSelectorFecha(
              context,
              inicial: fecha,
              primera: DateTime(2000),
              ultima: DateTime(2100),
            );
            if (sel != null) {
              setState(() {
                ctrl.text = _formatearFecha(sel);
                setFecha(sel);
                if (identical(ctrl, _fFinCtrl)) _finAutomatica = false;
                if (autoFin) _sugerirFin(sel);
              });
            }
          },
        ),
      ),
    );
  }

  Future<void> _guardar() async {
    if (_guardando) return;

    FocusScope.of(context).unfocus();

    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    // Campos obligatorios según la base de datos
    if (cliente == null) {
      _toast('El campo Cliente es obligatorio.');
      return;
    }
    if (aseguradora == null) {
      _toast('El campo Aseguradora es obligatorio.');
      return;
    }
    if (ramo == null) {
      _toast('El campo Ramo es obligatorio.');
      return;
    }
    if (producto == null) {
      _toast('El campo Producto es obligatorio.');
      return;
    }
    if (asesor1 == null) {
      _toast('El campo Asesor es obligatorio.');
      return;
    }
    if (fFin == null) {
      _toast('La Fecha fin es obligatoria.');
      return;
    }
    if (Sesion.usuarioId == null) {
      _toast('No hay un usuario activo en sesión.');
      return;
    }

    if (fIni != null && fFin!.isBefore(fIni!)) {
      _toast('La fecha fin no puede ser anterior a la fecha inicio.');
      return;
    }

    // Validar que la suma de % de comisiones principales no supere 100%
    final porcAsesor1 = _parseNumero(_porcomAsesor1Ctrl.text) ?? 0;
    final porcAsesor2 = _parseNumero(_porcomAsesor2Ctrl.text) ?? 0;
    final porcAsesor3 = _parseNumero(_porcomAsesor3Ctrl.text) ?? 0;
    final porcAgencia = _parseNumero(_porcomAgenciaCtrl.text) ?? 0;
    final totalPorcPrincipal =
        porcAsesor1 + porcAsesor2 + porcAsesor3 + porcAgencia;
    if (totalPorcPrincipal > 100 + 1e-6) {
      _toast(
          'La suma de % de comisiones (Asesor 1 + 2 + 3 + Agencia) es ${totalPorcPrincipal.toStringAsFixed(2)}% y supera el 100%.');
      return;
    }

    // Validar que la suma de % adicionales no supere 100%
    final porcAsesorad = _parseNumero(_porcomAsesoradCtrl.text) ?? 0;
    final porcAgenciaad = _parseNumero(_porcomAgenciaadCtrl.text) ?? 0;
    final totalPorcAdic = porcAsesorad + porcAgenciaad;
    if (totalPorcAdic > 100 + 1e-6) {
      _toast(
          'La suma de % adicionales (Asesor adic. + Agencia adic.) es ${totalPorcAdic.toStringAsFixed(2)}% y supera el 100%.');
      return;
    }

    // Validar que Com a distrib no supere Vlr Com + Com Fija
    final vlrCom = _parseNumero(_vlrComCtrl.text) ?? 0;
    final comFija = _parseNumero(_vlrComFijaCtrl.text) ?? 0;
    final comDistrib = _parseNumero(_comDistribCtrl.text) ?? 0;
    final maxComDistrib = vlrCom + comFija;
    if (comDistrib > maxComDistrib + 0.005) {
      _toast(
          'La Com. a distribuir (\$ ${Fmt.money(comDistrib, dec: 2)}) no puede ser mayor a '
          'Vlr Com + Com Fija (\$ ${Fmt.money(maxComDistrib, dec: 2)}).');
      return;
    }

    setState(() => _guardando = true);

    try {
      final nroPolizaTrim = formatearNroPoliza(_nroCtrl.text);
      final nroPolizaCambio = !esEdicion ||
          _normalizarNroLocal(nroPolizaTrim) !=
              _normalizarNroLocal(_nroPolizaOriginal ?? '') ||
          aseguradora?.id != _asegOriginalId;
      if (nroPolizaTrim.isNotEmpty && nroPolizaCambio) {
        final existeNro = await _repoPol.existeNroPoliza(
          nroPolizaTrim,
          excluirId: esEdicion ? widget.poliza!.id : null,
          aseguradoraId: aseguradora?.id,
        );
        if (existeNro) {
          _toast(
              'Ya existe una póliza de ${aseguradora?.nombreAseg ?? 'esta aseguradora'} '
              'con el número "$nroPolizaTrim".');
          return;
        }
      }

      final data = _mapaActual();
      int? idReal;

      if (esEdicion) {
        final originalId = widget.poliza!.id;
        // Al editar no se modifica quién la creó originalmente.
        data.remove('usuario_id');
        if (estadoPoliza?.id == _estadoOriginalId)
          data.remove('estado_poliza_id');
        if (data['vlrprimapagada_poliza'] == _primaPagadaOriginal) {
          data.remove('vlrprimapagada_poliza');
        }
        await _repoPol.actualizarPoliza(originalId, data);
      } else {
        idReal = await _repoPol.crearPoliza(data);
      }

      _registrarAprendizajeIA();

      // Si se venía retomando un borrador o una predigitada por IA, ya
      // quedó guardada como póliza real — la bandeja de pendientes no la
      // necesita más. Si esto falla no pasa nada grave, queda una fila
      // huérfana que se puede borrar a mano desde "Pendientes".
      if (widget.polizaPendiente != null) {
        try {
          await _repoPend.eliminar(widget.polizaPendiente!.id);
        } catch (_) {}
      }

      if (!mounted) return;
      if (idReal != null) {
        await _mostrarConfirmacionGuardado(idReal);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _toast('Error guardando: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// Aprendizaje de la importación con IA, solo con la póliza ya guardada
  /// (antes se registraba antes de guardar y un reintento por error contaba
  /// doble). No bloquea: si falla, simplemente no se aprende esta vez.
  void _registrarAprendizajeIA() {
    // El usuario dejó un producto distinto al sugerido — o eligió uno
    // cuando la IA no encontró ninguno — para este texto de la aseguradora.
    if (_textoProductoParaAprendizaje != null &&
        producto != null &&
        producto!.id != _productoSugeridoPorIA &&
        aseguradora?.id == _aseguradoraIdEnSugerenciaIA) {
      unawaited(_repoCat.registrarAprendizajeProducto(
        _aseguradoraIdEnSugerenciaIA!,
        _textoProductoParaAprendizaje!,
        producto!.id,
      ));
    }

    // El cliente confirmado sigue siendo el que matcheó automáticamente por
    // un rol puntual (Tomador/Asegurado/Beneficiario): refuerza ese rol.
    if (_clienteIdSugeridoPorIA != null &&
        _rolClienteSugeridoPorIA != null &&
        _aseguradoraIdEnSugerenciaCliente != null &&
        cliente?.id == _clienteIdSugeridoPorIA &&
        aseguradora?.id == _aseguradoraIdEnSugerenciaCliente) {
      unawaited(_repoCat.reforzarAprendizajeRolCliente(
        _aseguradoraIdEnSugerenciaCliente!,
        _rolClienteSugeridoPorIA!,
      ));
    }

    _productoSugeridoPorIA = null;
    _textoProductoParaAprendizaje = null;
    _aseguradoraIdEnSugerenciaIA = null;
    _clienteIdSugeridoPorIA = null;
    _rolClienteSugeridoPorIA = null;
    _aseguradoraIdEnSugerenciaCliente = null;
  }

  /// Recién acá se conoce el código real de la póliza — antes de guardar
  /// no se muestra ningún preview a propósito, porque con varias personas
  /// digitando a la vez el "siguiente id" que verían podía no coincidir
  /// con el que terminaba quedando.
  /// Archivo del que salió la póliza (importado a mano o de la carga
  /// masiva): se usa para sugerir el nombre "código - archivo original".
  String? _nombreArchivoImportado;

  Future<void> _mostrarConfirmacionGuardado(int idReal) async {
    final archivo =
        _nombreArchivoImportado ?? widget.polizaPendiente?.nombreArchivo;
    final nombreSugerido = archivo == null ? null : '$idReal - $archivo';

    Future<void> copiar(BuildContext ctx, String texto, String aviso) async {
      await Clipboard.setData(ClipboardData(text: texto));
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text(aviso),
          duration: const Duration(seconds: 2),
        ));
      }
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Póliza guardada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Código: $idReal',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(height: 12),
            Text(
                'Nro. Póliza: ${_nroCtrl.text.trim().isEmpty ? '—' : _nroCtrl.text.trim()}'),
            Text('Cliente: ${cliente?.nombreCliente ?? '—'}'),
            Text('Aseguradora: ${aseguradora?.nombreAseg ?? '—'}'),
            Text('Prima: \$ ${_primaCtrl.text}'),
            if (nombreSugerido != null) ...[
              const SizedBox(height: 12),
              const Text('Nombre sugerido para el archivo:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              Text(nombreSugerido, style: const TextStyle(fontSize: 12)),
            ],
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => copiar(ctx, '$idReal', 'Código $idReal copiado'),
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copiar código'),
          ),
          if (nombreSugerido != null)
            TextButton.icon(
              onPressed: () =>
                  copiar(ctx, nombreSugerido, 'Nombre del archivo copiado'),
              icon: const Icon(Icons.drive_file_rename_outline, size: 16),
              label: const Text('Copiar nombre de archivo'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Listo'),
          ),
        ],
      ),
    );
  }

  /// Mismo shape que arma _guardar() para insertar/actualizar en `polizas`
  /// — se reusa para el snapshot que se guarda en un borrador.
  Map<String, dynamic> _mapaActual() {
    return <String, dynamic>{
      'nro_poliza': _nroCtrl.text.trim().isEmpty
          ? null
          : formatearNroPoliza(_nroCtrl.text),
      'cliente_id': _idValido(cliente?.id),
      'asesor_id': _idValido(asesor1?.id),
      'intermediario_id': _idValido(intermediario?.id),
      'ramo_id': _idValido(ramo?.id),
      'producto_id': _idValido(producto?.id),
      'fexp_poliza': fExp?.toIso8601String(),
      'fini_poliza': fIni?.toIso8601String(),
      'ffin_poliza': fFin?.toIso8601String(),
      'prima_poliza': _parseNumero(_primaCtrl.text) ?? 0,
      'valor_poliza': _parseNumero(_valorPolizaCtrl.text) ?? 0,
      'vlraseg_poliza': _parseNumero(_vlrAsegCtrl.text),
      'vlrbasecom_poliza': _parseNumero(_vlrBaseComCtrl.text),
      'porccom_poliza': _parseNumero(_porcComCtrl.text),
      'porcom_agencia': _parseNumero(_porcomAgenciaCtrl.text),
      'vlrcom_poliza': _parseNumero(_vlrComCtrl.text),
      'vlrcomfija_poliza': _parseNumero(_vlrComFijaCtrl.text),
      'porcomadic_poliza': _parseNumero(_porcomAdicCtrl.text),
      'vlrcomadic_poliza': _parseNumero(_vlrComAdicCtrl.text),
      'porcom_asesor1': _parseNumero(_porcomAsesor1Ctrl.text),
      'agencia_id': _idValido(agencia?.id),
      'forma_pago_id': _idValido(formaPago?.id),
      'estado_poliza_id': estadoPoliza?.id,
      'vlrprimapagada_poliza': _parseNumero(_vlrPrimaPagadaCtrl.text),
      'asesor2_id': _idValido(asesor2?.id),
      'porcom_asesor2': _parseNumero(_porcomAsesor2Ctrl.text),
      'asesor3_id': _idValido(asesor3?.id),
      'porcom_asesor3': _parseNumero(_porcomAsesor3Ctrl.text),
      'asesorad_id': _idValido(asesorAd?.id),
      'porcom_asesorad': _parseNumero(_porcomAsesoradCtrl.text),
      'agenciaad_id': _idValido(agenciaAd?.id),
      'porcom_agenciaad': _parseNumero(_porcomAgenciaadCtrl.text),
      'bien_asegurado':
          _bienCtrl.text.trim().isEmpty ? null : _bienCtrl.text.trim(),
      'obs_poliza': _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),
      'formaexp_id': _idValido(formaExp?.id),
      'aseg_id': _idValido(aseguradora?.id),
      'usuario_id': Sesion.usuarioId,
    };
  }

  /// A diferencia de "Guardar", esto no exige ningún campo obligatorio —
  /// guarda lo que haya en ese momento para retomarlo después.
  Future<void> _guardarBorrador() async {
    if (_guardando || _guardandoBorrador) return;
    setState(() => _guardandoBorrador = true);
    try {
      final datos = _mapaActual();
      final idExistente = widget.polizaPendiente?.id;
      if (idExistente != null) {
        await _repoPend.actualizar(idExistente,
            estado: 'borrador', datos: datos);
      } else {
        await _repoPend.crear(
            estado: 'borrador', datos: datos, origen: 'manual');
      }
      if (!mounted) return;
      _toast('Guardado como borrador.');
      Navigator.pop(context, true);
    } catch (e) {
      _toast('Error guardando el borrador: $e');
    } finally {
      if (mounted) setState(() => _guardandoBorrador = false);
    }
  }

  Widget _filaAsesor(
    String label,
    Asesor? value,
    void Function(Asesor?) onChanged,
    TextEditingController? porcCtrl,
    TextEditingController baseCtrl, {
    bool req = false,
  }) {
    final vlr = porcCtrl != null ? _vlrParticipante(porcCtrl, baseCtrl) : 0;
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: BuscadorDropdown<Asesor>(
            label: req ? '$label *' : label,
            value: value,
            items: asesores,
            itemLabel: (a) => a.nombreAsesor,
            onChanged: onChanged,
            validator:
                req ? (x) => x == null ? 'Requerido' : null : (_) => null,
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 120,
          child: porcCtrl != null
              ? _campo('% Comisión', porcCtrl,
                  num: true,
                  maxDec: 5,
                  onEditingComplete: () => _formatearNum(porcCtrl))
              : const SizedBox.shrink(),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 150,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Vlr. Comisión',
              prefixText: '\$ ',
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: cs.surfaceContainerHighest.withOpacity(0.4),
            ),
            child: Text(
              porcCtrl != null ? _fmtMoney(vlr) : '—',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: vlr > 0 ? cs.primary : cs.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Estado con el que se cargó la póliza. Al editar, el estado solo se
  /// envía si el usuario lo cambió: así no pisa un COMPLETA que la base
  /// puso por pagos mientras el formulario estaba abierto.
  String? _estadoOriginalId;

  /// Prima pagada con la que se cargó la póliza (ya parseada del campo). Igual
  /// que el estado: solo se envía si el usuario la cambió, para no pisar los
  /// abonos que la base sumó mientras el formulario estaba abierto.
  num? _primaPagadaOriginal;

  Widget _selectorEstado() {
    if (estadosPoliza.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: estadosPoliza.map((e) {
        final selected = estadoPoliza?.id == e.id;
        return ChoiceChip(
          label: Text(e.nombre),
          selected: selected,
          onSelected: (_) => setState(() => estadoPoliza = e),
        );
      }).toList(),
    );
  }

  Widget _seccion(String titulo, List<Widget> campos) {
    return SectionCard(titulo: titulo, children: campos);
  }

  Widget _fila3(Widget a, Widget b, Widget c) {
    final w = MediaQuery.of(context).size.width;
    if (w < 900) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          a,
          const SizedBox(height: 12),
          b,
          const SizedBox(height: 12),
          c,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        const SizedBox(width: 16),
        Expanded(child: b),
        const SizedBox(width: 16),
        Expanded(child: c),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(esEdicion ? 'Editar póliza' : 'Nueva póliza'),
        actions: [
          if (!esEdicion && _importando)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (!esEdicion && !_importando)
            TextButton.icon(
              onPressed: _importarDesdeArchivo,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Importar desde PDF/imagen'),
            ),
          if (!esEdicion && _guardandoBorrador)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (!esEdicion)
            TextButton.icon(
              onPressed: _guardando ? null : _guardarBorrador,
              icon: const Icon(Icons.description_outlined),
              label: const Text('Guardar borrador'),
            ),
          if (_guardando)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton.icon(
              onPressed: _guardandoBorrador ? null : _guardar,
              icon: const Icon(Icons.save),
              label: const Text('Guardar'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: AppLayout.pagePadding,
              // Mantiene construidos todos los campos: un ListView normal
              // desmonta los que salen de la pantalla y el validate() de
              // "Guardar" (botón de abajo) no revisaba los de arriba.
              cacheExtent: 100000,
              children: [
                // ── Fila 1: Código · Nro Póliza · Fechas ─────────────────────
                _seccion('Identificación y Vigencia', [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 130,
                      child: _campo('Código', _idCtrl,
                          num: true,
                          readOnly: true,
                          helper: esEdicion ? 'Auto' : 'Al guardar'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: _campo('Número de Póliza', _nroCtrl),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _fechaCampo(
                          'F. Inicio', _fIniCtrl, fIni, (d) => fIni = d,
                          autoFin: true),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _fechaCampo(
                          'F. Fin *', _fFinCtrl, fFin, (d) => fFin = d),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _fechaCampo(
                          'F. Expedición', _fExpCtrl, fExp, (d) => fExp = d),
                    ),
                  ]),
                ]),

                // ── Fila 2: Aseguradora · Ramo ────────────────────────────────
                _seccion('Aseguradora y Ramo', [
                  // Aseguradora | Ramo | % Base Com (read-only)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      flex: 3,
                      child: BuscadorDropdown<Aseguradora>(
                        label: 'Aseguradora *',
                        value: aseguradora,
                        items: aseguradoras,
                        itemLabel: (a) => a.nombreAseg,
                        onChanged: (v) async {
                          setState(() {
                            aseguradora = v;
                            // mantenerActual: false — el Ramo/Producto de la
                            // aseguradora anterior no pertenecen a esta, no
                            // hay que preservarlos en la lista.
                            ramosDisponibles = _calcularRamosDisponibles(v,
                                mantenerActual: false);
                            if (ramo != null &&
                                !ramosDisponibles
                                    .any((r) => r.id == ramo!.id)) {
                              ramo = null;
                            }
                            producto = null;
                          });
                          await _refrescarProductos();
                        },
                        validator: (x) => x == null ? 'Requerido' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: BuscadorDropdown<Ramo>(
                        label: 'Ramo *',
                        value: ramo,
                        items: ramosDisponibles,
                        itemLabel: (r) => r.nombreRamo,
                        onChanged: (v) async {
                          setState(() {
                            ramo = v;
                            producto = null;
                            if (ramo != null) _aplicarDefaultsDesdeRamo();
                          });
                          await _refrescarProductos();
                        },
                        validator: (x) => x == null ? 'Requerido' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 130,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: '% Base Com.',
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: AppTheme.surfaceContainerHighest,
                        ),
                        child: Text(
                          ramo != null ? ramo!.porcomBaseRamo.toString() : '—',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  // Producto | Forma de pago | Forma Exp
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      flex: 3,
                      child: BuscadorDropdown<Producto>(
                        label: 'Producto *',
                        value: producto,
                        items: productos,
                        itemLabel: (p) => p.nombreProd,
                        onChanged: (v) {
                          setState(() {
                            producto = v;
                            if (producto != null)
                              _aplicarDefaultsDesdeProducto();
                          });
                        },
                        validator: (x) => x == null ? 'Requerido' : null,
                        helperText: (ramo == null || aseguradora == null)
                            ? 'Selecciona Aseguradora y Ramo primero'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: BuscadorDropdown<FormaPagoLite>(
                        label: 'Forma de Pago *',
                        value: formaPago,
                        items: formasPago,
                        itemLabel: (f) => f.nombre,
                        onChanged: (v) => setState(() => formaPago = v),
                        validator: (x) => x == null ? 'Requerido' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: BuscadorDropdown<FormaExpLite>(
                        label: 'Forma Exp.',
                        value: formaExp,
                        items: formasExp,
                        itemLabel: (f) => f.nombre,
                        onChanged: (v) => setState(() => formaExp = v),
                        validator: (_) => null,
                      ),
                    ),
                  ]),
                ]),

                // ── Cliente ───────────────────────────────────────────────────
                _seccion('Cliente', [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: BuscadorDropdown<Cliente>(
                          label: 'Cliente *',
                          value: cliente,
                          items: cliente != null ? [cliente!] : [],
                          itemLabel: (c) => c.nombreCliente,
                          itemSubtitle: (c) {
                            final partes = [
                              if ((c.tipodocCliente ?? '').isNotEmpty)
                                c.tipodocCliente!,
                              if ((c.docCliente ?? '').isNotEmpty)
                                Fmt.doc(c.docCliente),
                            ];
                            return partes.isEmpty ? null : partes.join(' ');
                          },
                          itemsLoader: (q) => _repoCat.buscarClientes(q),
                          onChanged: (v) => setState(() => cliente = v),
                          validator: (x) => x == null ? 'Requerido' : null,
                          onCrear: (ctx) async {
                            final nuevoId = await Navigator.of(ctx).push<int>(
                              MaterialPageRoute(
                                  builder: (_) => const FormCliente()),
                            );
                            if (nuevoId != null)
                              return await _asegurarCliente(nuevoId);
                            return null;
                          },
                        ),
                      ),
                      if (cliente != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Editar datos de este cliente',
                          onPressed: _editarClienteActual,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  _fila3(
                    _campo('Bien Asegurado / Identificación *', _bienCtrl,
                        req: true),
                    _campo('Vlr. Asegurado', _vlrAsegCtrl,
                        num: true,
                        money: true,
                        onEditingComplete: () => _formatearMoney(_vlrAsegCtrl)),
                    BuscadorDropdown<IntermediarioLite>(
                      label: 'Intermediario',
                      value: intermediario,
                      items: intermediarios,
                      itemLabel: (a) => a.nombre,
                      onChanged: (v) => setState(() => intermediario = v),
                      validator: (_) => null,
                    ),
                  ),
                ]),

                // ── Valores ───────────────────────────────────────────────────
                _seccion('Valores', [
                  _fila3(
                    _campo('Vlr. Prima', _primaCtrl,
                        num: true,
                        money: true,
                        helper: 'Ej: 1.500.000,00',
                        onEditingComplete: () {
                          _formatearMoney(_primaCtrl);
                          _recalcularBaseCom();
                        },
                        onChanged: (_) => _recalcularBaseCom()),
                    _campo('Vlr. Total', _valorPolizaCtrl,
                        num: true,
                        money: true,
                        onEditingComplete: () =>
                            _formatearMoney(_valorPolizaCtrl)),
                    _campo('Vlr. Base Com.', _vlrBaseComCtrl,
                        num: true,
                        money: true,
                        helper: 'Automático, editable',
                        onEditingComplete: () {
                          _formatearMoney(_vlrBaseComCtrl);
                          _recalcularComision();
                        },
                        onChanged: (_) => _recalcularComision()),
                  ),
                ]),

                // ── Comisiones ────────────────────────────────────────────────
                _seccion('Comisiones', [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: _campo('% Com.', _porcComCtrl,
                          num: true,
                          maxDec: 5,
                          helper: 'Desde producto',
                          onEditingComplete: () {
                            _formatearNum(_porcComCtrl);
                            _recalcularComision();
                          },
                          onChanged: (_) => _recalcularComision()),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _campo('Vlr. Com.', _vlrComCtrl,
                          num: true,
                          money: true,
                          helper: 'Automático, editable',
                          onEditingComplete: () =>
                              _formatearMoney(_vlrComCtrl)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _campo('+ Com. Fija', _vlrComFijaCtrl,
                          num: true,
                          money: true,
                          onEditingComplete: () =>
                              _formatearMoney(_vlrComFijaCtrl)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _campo('% Com. Adicional', _porcomAdicCtrl,
                          num: true,
                          maxDec: 5,
                          onEditingComplete: () =>
                              _formatearNum(_porcomAdicCtrl)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _campo('Vlr. Com. Adicional', _vlrComAdicCtrl,
                          num: true,
                          money: true,
                          onEditingComplete: () =>
                              _formatearMoney(_vlrComAdicCtrl)),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  // Com a distrib y Com Adic a distrib
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: _campo(
                        'Com. a Distribuir',
                        _comDistribCtrl,
                        num: true,
                        money: true,
                        helper: 'Base para repartir entre asesores',
                        onEditingComplete: () =>
                            _formatearMoney(_comDistribCtrl),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _campo(
                        'Com. Adic. a Distribuir',
                        _comAdicDistribCtrl,
                        num: true,
                        money: true,
                        helper: 'Base para repartir com. adicional',
                        onEditingComplete: () =>
                            _formatearMoney(_comAdicDistribCtrl),
                      ),
                    ),
                  ]),
                ]),

                // ── Distribución de comisiones ────────────────────────────────
                _seccion('Distribución de Comisiones', [
                  _filaAsesor(
                      'Asesor 1',
                      asesor1,
                      (v) => setState(() => asesor1 = v),
                      _porcomAsesor1Ctrl,
                      _comDistribCtrl,
                      req: true),
                  const SizedBox(height: 12),
                  _filaAsesor(
                      'Asesor 2',
                      asesor2,
                      (v) => setState(() => asesor2 = v),
                      _porcomAsesor2Ctrl,
                      _comDistribCtrl),
                  const SizedBox(height: 12),
                  _filaAsesor(
                      'Asesor 3',
                      asesor3,
                      (v) => setState(() => asesor3 = v),
                      _porcomAsesor3Ctrl,
                      _comDistribCtrl),
                  const SizedBox(height: 12),
                  _filaAsesor(
                      'Agencia',
                      agencia,
                      (v) => setState(() => agencia = v),
                      _porcomAgenciaCtrl,
                      _comDistribCtrl),
                  const SizedBox(height: 8),
                  // Indicador total % principales
                  Builder(builder: (_) {
                    final total = (_parseNumero(_porcomAsesor1Ctrl.text) ?? 0) +
                        (_parseNumero(_porcomAsesor2Ctrl.text) ?? 0) +
                        (_parseNumero(_porcomAsesor3Ctrl.text) ?? 0) +
                        (_parseNumero(_porcomAgenciaCtrl.text) ?? 0);
                    final excede = total > 100;
                    return Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Icon(
                              excede
                                  ? Icons.warning_amber_rounded
                                  : Icons.check_circle_outline,
                              size: 16,
                              color: excede ? AppTheme.danger : AppTheme.green),
                          const SizedBox(width: 4),
                          Text(
                            'Total: ${total.toStringAsFixed(2)}%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: excede ? AppTheme.danger : AppTheme.green,
                            ),
                          ),
                        ]);
                  }),
                  const Divider(height: 24),
                  _filaAsesor(
                      'Asesor Adicional',
                      asesorAd,
                      (v) => setState(() => asesorAd = v),
                      _porcomAsesoradCtrl,
                      _comAdicDistribCtrl),
                  const SizedBox(height: 12),
                  _filaAsesor(
                      'Agencia Adicional',
                      agenciaAd,
                      (v) => setState(() => agenciaAd = v),
                      _porcomAgenciaadCtrl,
                      _comAdicDistribCtrl),
                  const SizedBox(height: 8),
                  // Indicador total % adicionales
                  Builder(builder: (_) {
                    final total =
                        (_parseNumero(_porcomAsesoradCtrl.text) ?? 0) +
                            (_parseNumero(_porcomAgenciaadCtrl.text) ?? 0);
                    final excede = total > 100;
                    if (total == 0) return const SizedBox.shrink();
                    return Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Icon(
                              excede
                                  ? Icons.warning_amber_rounded
                                  : Icons.check_circle_outline,
                              size: 16,
                              color: excede ? AppTheme.danger : AppTheme.green),
                          const SizedBox(width: 4),
                          Text(
                            'Total adic.: ${total.toStringAsFixed(2)}%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: excede ? AppTheme.danger : AppTheme.green,
                            ),
                          ),
                        ]);
                  }),
                ]),

                // ── Estado + Vlr Prima Pagada ─────────────────────────────────
                _seccion('Estado y Cierre', [
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    Expanded(child: _selectorEstado()),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 200,
                      child: _campo('Vlr. Prima Pagada', _vlrPrimaPagadaCtrl,
                          num: true,
                          money: true,
                          onEditingComplete: () =>
                              _formatearMoney(_vlrPrimaPagadaCtrl)),
                    ),
                  ]),
                ]),

                // ── Observaciones ─────────────────────────────────────────────
                _seccion('Observaciones', [
                  _campo('Observación', _obsCtrl, lines: 4),
                ]),

                // ── Botón guardar ─────────────────────────────────────────────
                FilledButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: _guardando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(_guardando ? 'Guardando...' : 'Guardar póliza'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
