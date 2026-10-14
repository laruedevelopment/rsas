import 'package:flutter/material.dart';
import '../../datos/catalogos.dart';
import '../../datos/repositorio_catalogos.dart';
import '../../datos/sesion.dart';
import '../theme/app_layout.dart';
import '../widgets/section_card.dart';
import '../../utils/mensajes_error.dart';

class FormUsuario extends StatefulWidget {
  final Usuario? usuario;
  const FormUsuario({super.key, this.usuario});

  @override
  State<FormUsuario> createState() => _FormUsuarioState();
}

class _FormUsuarioState extends State<FormUsuario> {
  final _formKey = GlobalKey<FormState>();
  final repo = RepositorioCatalogos();

  bool guardando = false;

  late final TextEditingController apodoCtrl;
  late final TextEditingController nombreCtrl;
  late final TextEditingController claveCtrl;
  late final TextEditingController correoCtrl;

  String _rol = 'D';
  bool _estadoUsuario = true;

  static const int _minLargoClave = 8;

  // A = Administrador, D = Digitador. Si el usuario ya tiene otro rol (ej.
  // S), se muestra y se conserva en vez de cambiarlo sin avisar.
  late final List<(String, String)> _roles;

  bool get esEdicion => widget.usuario != null;
  bool get _esUnoMismo => esEdicion && widget.usuario!.id == Sesion.usuarioId;

  @override
  void initState() {
    super.initState();
    final u = widget.usuario;
    apodoCtrl = TextEditingController(text: u?.apodoUsuario ?? '');
    nombreCtrl = TextEditingController(text: u?.nombreUsuario ?? '');
    claveCtrl = TextEditingController();
    correoCtrl = TextEditingController(text: u?.correoUsuario ?? '');

    _rol = u?.rol.toUpperCase() ?? 'D';
    _roles = [
      ('A', 'Administrador'),
      ('D', 'Digitador'),
      if (_rol != 'A' && _rol != 'D') (_rol, 'Rol actual'),
    ];
    _estadoUsuario = u?.estadoUsuario ?? true;
  }

  @override
  void dispose() {
    apodoCtrl.dispose();
    nombreCtrl.dispose();
    claveCtrl.dispose();
    correoCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String? _validarClave(String? v) {
    final s = v ?? '';
    if (s.isEmpty) return esEdicion ? null : 'Requerida para usuarios nuevos';
    if (s.length < _minLargoClave) return 'Mínimo $_minLargoClave caracteres';
    return null;
  }

  Future<void> _guardar() async {
    if (guardando) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_esUnoMismo && (!_estadoUsuario || _rol != 'A')) {
      _toast('No puede desactivarse ni quitarse el rol de Administrador a sí mismo.');
      return;
    }

    final apodo = apodoCtrl.text.trim();
    final nombre = nombreCtrl.text.trim();
    final clave = claveCtrl.text;

    setState(() => guardando = true);
    try {
      if (await repo.existeApodoUsuario(apodo, excludeId: widget.usuario?.id)) {
        _toast('Ya existe otro usuario con ese apodo.');
        return;
      }

      final correo = correoCtrl.text.trim().toLowerCase();
      final u = Usuario(
        id: widget.usuario?.id ?? 0,
        apodoUsuario: apodo,
        nombreUsuario: nombre,
        rol: _rol,
        correoUsuario: correo.isEmpty ? null : correo,
        estadoUsuario: _estadoUsuario,
        asesorId: widget.usuario?.asesorId,
      );

      if (esEdicion) {
        await repo.actualizarUsuario(widget.usuario!.id, u, nuevaClave: clave);
      } else {
        await repo.crearUsuario(u, nuevaClave: clave);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _toast(mensajeAmigable(e, accion: 'Error guardando'));
    } finally {
      if (mounted) setState(() => guardando = false);
    }
  }

  Widget _seccion(String titulo, List<Widget> campos) {
    return SectionCard(titulo: titulo, children: campos);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(esEdicion ? 'Editar usuario' : 'Nuevo usuario'),
        actions: [
          if (guardando)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextButton.icon(
              onPressed: _guardar,
              icon: const Icon(Icons.save),
              label: const Text('Guardar'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: AppLayout.pagePadding,
              children: [
                _seccion('Identificación', [
                  TextFormField(
                    controller: apodoCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Usuario (apodo) *',
                      border: const OutlineInputBorder(),
                      helperText: esEdicion
                          ? 'ID ${widget.usuario!.id} · nombre corto para iniciar sesión'
                          : 'Nombre corto para iniciar sesión',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nombreCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nombre completo *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: correoCtrl,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Correo electrónico',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (s.isEmpty) return null; // opcional
                      if (!s.contains('@') || !s.contains('.')) return 'Correo no válido';
                      return null;
                    },
                  ),
                ]),

                _seccion('Acceso', [
                  TextFormField(
                    controller: claveCtrl,
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: esEdicion ? 'Nueva contraseña (dejar vacío para no cambiar)' : 'Contraseña *',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock_outline),
                      helperText: 'Mínimo $_minLargoClave caracteres',
                    ),
                    validator: _validarClave,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _rol,
                    decoration: const InputDecoration(
                      labelText: 'Rol *',
                      border: OutlineInputBorder(),
                    ),
                    items: _roles
                        .map((r) => DropdownMenuItem(value: r.$1, child: Text('${r.$1} — ${r.$2}')))
                        .toList(),
                    onChanged: (v) { if (v != null) setState(() => _rol = v); },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: _estadoUsuario,
                    onChanged: (v) => setState(() => _estadoUsuario = v),
                    title: const Text('Usuario activo'),
                    subtitle: Text(_estadoUsuario ? 'Activo' : 'Inactivo'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ]),

                FilledButton.icon(
                  onPressed: guardando ? null : _guardar,
                  icon: guardando
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(guardando ? 'Guardando...' : 'Guardar usuario'),
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
