import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'login.dart';
import 'form.dart';
import 'segnalazioni.dart';
import 'services/api_service.dart';
import 'utils/responsive.dart';
import 'widgets/bottom_nav_bar.dart';

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
      // Le AppBar sono bianche: le icone di sistema in cima vanno forzate
      // scure, altrimenti su alcuni Android restano bianche su bianco e
      // ora'/batteria spariscono.
      theme: ThemeData(
        appBarTheme: const AppBarTheme(
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          ),
        ),
      ),
      // I caratteri di sistema molto grandi (Android "Dimensioni
      // carattere", iOS "Testo piu' grande") arrivavano fino a 2x e
      // facevano sfondare barre e card. Restano regolabili, ma entro un
      // limite che le schermate reggono.
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.9,
              maxScaleFactor: 1.35,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: FutureBuilder<bool>(
        future: ApiService.loadToken(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const _SplashScreen();
          }
          if (!snapshot.data!) return const LoginScreen();
          // Chi ha un accesso all'app e' un cittadino che segnala: la
          // schermata iniziale e' sempre il menu dei tipi.
          return const MenuScreen();
        },
      ),
      routes: {'/menu': (_) => const MenuScreen()},
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    // Il logo occupa una quota della larghezza, con un minimo e un
    // massimo: resta leggibile su un telefono stretto e non diventa un
    // cartellone su un iPad.
    final logoSize = (context.screenWidth * 0.4).clamp(120.0, 240.0);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Image.asset(
          'android/app/src/main/res/drawable/logo.png',
          width: logoSize,
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
        // Titolo lungo + logo + pulsante esci: su un telefono da 320dp
        // non ci sta a 18px, quindi si rimpicciolisce invece di essere
        // tagliato a meta'.
        title: Text(
          'NUOVA SEGNALAZIONE',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: const Color(0xFF111111),
            fontSize: context.isNarrowScreen ? 15 : context.adaptive(18),
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
      bottomNavigationBar: BottomNavBar(
        icon: Icons.list_alt,
        label: 'Le mie segnalazioni',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SegnalazioniScreen()),
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
        child: Padding(
          // Senza margini un errore lungo arrivava a filo dei bordi.
          padding: context.centeredPadding(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
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
      // piu' spazio sopra la prima card; ai lati il padding cresce sui
      // tablet in modo che le card restino centrate e leggibili invece
      // di allungarsi da bordo a bordo
      padding: context.centeredPadding(top: 28, bottom: 16),
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
    // Tutte le misure della card partono dal formato telefono e crescono
    // su tablet, cosi' il rapporto fra quadrato, icona e testo resta lo
    // stesso su ogni schermo.
    final squareSize = context.adaptive(56, tablet: 68);
    final iconSize = squareSize * 0.7;
    final fallbackIconSize = squareSize * 0.46;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.all(context.adaptive(14, tablet: 18)),
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
              width: squareSize, // <-- grandezza quadrato
              height: squareSize, // <-- grandezza quadrato
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
                            width: iconSize, // <-- grandezza icona SVG
                            height: iconSize, // <-- grandezza icona SVG
                            fit: BoxFit.contain,
                            colorFilter: const ColorFilter.mode(
                              Color(0xFF7BA566),
                              BlendMode.srcIn,
                            ),
                            placeholderBuilder: (_) => Icon(
                              Icons.report_problem,
                              color: const Color(0xFF7BA566),
                              size: fallbackIconSize,
                            ),
                          )
                        // ── Icona PNG/JPG ───────────────────────────
                        : Image.network(
                            iconUrl!,
                            width: iconSize, // <-- grandezza icona PNG
                            height: iconSize, // <-- grandezza icona PNG
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.report_problem,
                              color: const Color(0xFF7BA566),
                              size: fallbackIconSize,
                            ),
                          )
                  : Icon(
                      Icons.report_problem,
                      color: const Color(0xFF7BA566),
                      size: fallbackIconSize,
                    ),
            ),
            SizedBox(width: context.adaptive(14, tablet: 18)),
            // ── Nome + descrizione ──────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: const Color(0xFF111111),
                      fontSize: context.adaptive(15, tablet: 17),
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
                      style: TextStyle(
                        color: const Color(0xFF6B7280),
                        fontSize: context.adaptive(13, tablet: 14),
                        fontFamily: 'Inter',
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: const Color(0xFF9CA3AF),
              size: context.adaptive(22, tablet: 24),
            ),
          ],
        ),
      ),
    );
  }
}
