import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'login.dart';
import 'form.dart';
import 'segnalazioni.dart';
import 'services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Castellazzo dei Stampi',
      home: FutureBuilder<bool>(
        future: ApiService.loadToken(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const _SplashScreen();
          }
          if (!snapshot.data!) return const LoginScreen();
          // Chi ha la sola lettura non passa dal menu "Nuova
          // segnalazione": la sua schermata iniziale e' l'elenco.
          return ApiService.canWrite
              ? const MenuScreen()
              : const SegnalazioniScreen();
        },
      ),
      routes: {
        // Anche arrivandoci per route, senza scrittura il menu delle
        // nuove segnalazioni non si apre.
        '/menu': (_) => ApiService.canWrite
            ? const MenuScreen()
            : const SegnalazioniScreen(),
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Image.asset(
          'android/app/src/main/res/drawable/logo.png',
          width: 160,
        ),
      ),
    );
  }
}

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  List<Map<String, dynamic>> _reportTypes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReportTypes();
  }

  Future<void> _loadReportTypes() async {
    final result = await ApiService.getReportTypes();
    if (!mounted) return;
    if (result['success'] == true) {
      final data = List<Map<String, dynamic>>.from(result['data'] as List);
      for (final t in data) {
        // I campi disponibili servono a capire con che nome il backend
        // manda la descrizione: se manca, comparira' qui l'elenco reale.
        debugPrint(
          '[tipo] ${t['name']} → campi: ${t.keys.join(', ')} '
          '| descrizione=${reportTypeDescription(t) ?? '(assente)'}',
        );
      }
      setState(() {
        _reportTypes = data;
        _loading = false;
      });
    } else if (ApiService.isUnauthenticated(result)) {
      await ApiService.clearToken();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } else {
      setState(() {
        _error = result['message'] as String?;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: Image.asset('android/app/src/main/res/drawable/logo.png'),
        ),
        title: const Text(
          'NUOVA SEGNALAZIONE',
          style: TextStyle(
            color: Color(0xFF111111),
            fontSize: 18,
            fontFamily: 'Inter',
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Esci',
            icon: const Icon(Icons.logout, color: Color(0xFF666666)),
            onPressed: () async {
              final navigator = Navigator.of(context);
              await ApiService.logout();
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
            },
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SegnalazioniScreen()),
        ),
        child: Container(
          height: 68,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.list_alt, color: Color(0xFF666666), size: 22),
              SizedBox(width: 10),
              Text(
                'Le mie segnalazioni',
                style: TextStyle(
                  color: Color(0xFF666666),
                  fontSize: 14,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF7BA566)),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontFamily: 'Inter'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _loadReportTypes();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7BA566),
                foregroundColor: Colors.white,
              ),
              child: const Text('Riprova'),
            ),
          ],
        ),
      );
    }
    if (_reportTypes.isEmpty) {
      return const Center(
        child: Text(
          'Nessun tipo di segnalazione disponibile.',
          style: TextStyle(color: Color(0xFF666666), fontFamily: 'Inter'),
        ),
      );
    }
    return ListView.builder(
      // piu' spazio sopra la prima card
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
      itemCount: _reportTypes.length,
      itemBuilder: (context, index) {
        final type = _reportTypes[index];
        return _ReportTypeCard(
          name: type['name'] as String? ?? '',
          description: reportTypeDescription(type),
          iconUrl: ApiService.mediaUrl(type['icon_file'] as String?),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => FormScreen(reportType: type)),
          ),
        );
      },
    );
  }
}

/// Nomi con cui il backend puo' mandare la descrizione di un tipo.
/// Il primo valore testuale non vuoto vince.
const _descriptionKeys = [
  'description',
  'descrizione',
  'short_description',
  'subtitle',
  'note',
  'desc',
];

/// Descrizione del tipo di segnalazione, o null se il backend non la manda.
/// Ignora i valori non testuali invece di lanciare, come faceva il cast diretto.
String? reportTypeDescription(Map<String, dynamic> type) {
  for (final key in _descriptionKeys) {
    final value = type[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

class _ReportTypeCard extends StatelessWidget {
  final String name;
  final String? description;
  final String? iconUrl;
  final VoidCallback onTap;

  const _ReportTypeCard({
    required this.name,
    this.description,
    this.iconUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final desc = description?.trim() ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // ── Quadrato verde ──────────────────────────────────
            Container(
              width: 56, // <-- grandezza quadrato
              height: 56, // <-- grandezza quadrato
              decoration: BoxDecoration(
                color: const Color(0xFFEDF5E9),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: iconUrl != null
                  ? iconUrl!.toLowerCase().endsWith('.svg')
                        // ── Icona SVG ──────────────────────────────
                        ? SvgPicture.network(
                            iconUrl!,
                            width: 40, // <-- grandezza icona SVG
                            height: 40, // <-- grandezza icona SVG
                            fit: BoxFit.contain,
                            colorFilter: const ColorFilter.mode(
                              Color(0xFF7BA566),
                              BlendMode.srcIn,
                            ),
                            placeholderBuilder: (_) => const Icon(
                              Icons.report_problem,
                              color: Color(0xFF7BA566),
                              size: 26,
                            ),
                          )
                        // ── Icona PNG/JPG ───────────────────────────
                        : Image.network(
                            iconUrl!,
                            width: 40, // <-- grandezza icona PNG
                            height: 40, // <-- grandezza icona PNG
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.report_problem,
                              color: Color(0xFF7BA566),
                              size: 26,
                            ),
                          )
                  : const Icon(
                      Icons.report_problem,
                      color: Color(0xFF7BA566),
                      size: 26,
                    ),
            ),
            const SizedBox(width: 14),
            // ── Nome + descrizione ──────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Color(0xFF111111),
                      fontSize: 15,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 13,
                        fontFamily: 'Inter',
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF), size: 22),
          ],
        ),
      ),
    );
  }
}
