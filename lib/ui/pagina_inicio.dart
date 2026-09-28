import 'package:flutter/material.dart';

import '../datos/repositorio_casos.dart';
import '../datos/sesion.dart';
import 'pagina_casos_revision.dart';
import 'pagina_login.dart';
import 'pagina_polizas.dart';
import 'pagina_catalogos.dart';
import 'pagina_reportes.dart';
import 'pagina_reportes_pago.dart';
import 'theme/app_layout.dart';
import 'theme/app_theme.dart';

class PaginaInicio extends StatefulWidget {
  final String appEnv;

  const PaginaInicio({super.key, required this.appEnv});

  @override
  State<PaginaInicio> createState() => _PaginaInicioState();
}

class _PaginaInicioState extends State<PaginaInicio> {
  /// Casos por revisar pendientes (null = no se pudo consultar).
  int? _casosPendientes;

  @override
  void initState() {
    super.initState();
    _contarCasos();
  }

  Future<void> _contarCasos() async {
    try {
      final n = await RepositorioCasos().contarPendientes();
      if (mounted) setState(() => _casosPendientes = n);
    } catch (_) {
      // Sin la tabla (o sin conexión) la tarjeta sale sin contador.
    }
  }

  void _cerrarSesion() {
    Sesion.cerrar();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PaginaLogin(appEnv: widget.appEnv),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final usuarioActivo = Sesion.usuario;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.appEnv == 'prod'
              ? ''
              : 'PRUEBAS',
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: AppLayout.pagePadding,
            children: [
              // ── Encabezado ─────────────────────────────────────────────────
              Card(
                elevation: 0,
                color: cs.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Image.asset(
                        'assets/images/LogoRuedaSerranoFondoTransparente2.png',
                        height: 60,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SegurApp',
                              style: tt.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: cs.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Rueda Serrano Asesores de Seguros',
                              style: tt.bodySmall?.copyWith(
                                color: AppTheme.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Sesión activa ──────────────────────────────────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: usuarioActivo != null
                            ? cs.secondaryContainer
                            : cs.surfaceContainerHighest,
                        child: Icon(
                          Icons.person_outline,
                          size: 18,
                          color: usuarioActivo != null
                              ? cs.onSecondaryContainer
                              : cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              usuarioActivo != null
                                  ? usuarioActivo.apodoUsuario
                                  : 'Sin sesión (Anónimo)',
                              style: tt.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (usuarioActivo != null)
                              Text(
                                usuarioActivo.nombreUsuario,
                                style: tt.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar sesión',
                        icon: const Icon(Icons.logout, size: 18),
                        onPressed: _cerrarSesion,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Pólizas ────────────────────────────────────────────────────
              _NavCard(
                icon: Icons.receipt_long_outlined,
                iconColor: cs.primary,
                title: 'Pólizas',
                subtitle: 'Crear, editar, buscar y controlar vencimientos',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PaginaPolizas()),
                ),
              ),
              const SizedBox(height: 10),

              // ── Casos por revisar ─────────────────────────────────────────
              _NavCard(
                icon: Icons.fact_check_outlined,
                iconColor: AppTheme.warning,
                title: 'Casos por revisar',
                subtitle: 'Pagos, pólizas o comisiones dudosas que hay que aclarar',
                contador: _casosPendientes,
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PaginaCasosRevision()),
                  );
                  _contarCasos();
                },
              ),
              const SizedBox(height: 10),

              // ── Catálogos (Admin: todos / Digitador: Clientes, Aseguradoras,
              // Ramos y Productos — PaginaCatalogos oculta el resto sola) ────
              _NavCard(
                icon: Icons.folder_open_outlined,
                iconColor: cs.tertiary,
                title: 'Catálogos',
                subtitle: Sesion.esAdmin
                    ? 'Clientes, asesores, aseguradoras, ramos, productos y más'
                    : 'Clientes, aseguradoras, ramos y productos',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PaginaCatalogos()),
                ),
              ),
              const SizedBox(height: 10),

              // ── Reportes ──────────────────────────────────────────────────
              _NavCard(
                icon: Icons.analytics_outlined,
                iconColor: cs.secondary,
                title: 'Reportes',
                subtitle: 'Dashboards y exportar a Excel',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PaginaReportes()),
                ),
              ),

              // ── Reportes de comisiones (no visible para digitadores) ────────
              if (Sesion.veComisiones) ...[
                const SizedBox(height: 10),
                _NavCard(
                  icon: Icons.request_quote_outlined,
                  iconColor: cs.primary,
                  title: 'Reportes de Comisiones',
                  subtitle: 'Registrar abonos y pagos de comisiones',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PaginaReportesPago()),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── NavCard ───────────────────────────────────────────────────────────────────

class _NavCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  /// Número a resaltar junto a la flecha (p. ej. casos pendientes); 0 o
  /// null = no se muestra.
  final int? contador;

  const _NavCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.contador,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if ((contador ?? 0) > 0)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.warning,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$contador',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              Icon(Icons.chevron_right, size: 20, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
