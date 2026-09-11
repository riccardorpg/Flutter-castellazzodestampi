import 'package:flutter/material.dart';
import 'login.dart';
import 'scheda.dart';
import 'services/api_service.dart';
import 'services/draft_store.dart';
import 'utils/responsive.dart';
import 'widgets/bottom_nav_bar.dart';

class SegnalazioniScreen extends StatefulWidget {
  const SegnalazioniScreen({super.key});

  @override
  State<SegnalazioniScreen> createState() => _SegnalazioniScreenState();
}

class _SegnalazioniScreenState extends State<SegnalazioniScreen> {
  List<Map<String, dynamic>> _reports = [];
  bool _loading = true;
  String _filter = 'all';

  /// Messaggio d'errore dell'ultimo caricamento: se c'e', prende il posto
  /// della lista.
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() => _loading = true);
    // Le bozze locali non passano dal server: si leggono dal dispositivo
    // e si mescolano alle segnalazioni gia' inviate.
    final drafts = await DraftStore.load();
    // Questa chiamata riallinea anche il permesso: il server lo manda
    // insieme all'elenco, quindi un cambiamento fatto sul sito arriva qui
    // senza bisogno di uscire e rientrare.
    final result = await ApiService.getMyReports();
    if (!mounted) return;
    // Token scaduto, oppure permesso revocato mentre l'app era aperta:
    // in tutti e due i casi non si va oltre.
    if (ApiService.isUnauthenticated(result) || !ApiService.canRead) {
      await ApiService.clearToken();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
      return;
    }
    final ok = result['success'] == true;
    // Solo le proprie: il server manda solo quelle, il filtro qui e' la
    // rete di sicurezza (vedi ApiService.onlyMine).
    final data = ok
        ? ApiService.onlyMine(
            List<Map<String, dynamic>>.from(result['data'] as List),
          )
        : <Map<String, dynamic>>[];
    data.addAll(drafts);
    _sortByInsertion(data);
    setState(() {
      _reports = data;
      _error = ok
          ? null
          : result['message'] as String? ??
                'Non e\' stato possibile caricare le segnalazioni.';
      _loading = false;
    });
  }

  /// Schede in ordine di inserimento, dalla piu' recente alla piu' vecchia,
  /// bozze locali comprese. A parita' di data decide l'id, che cresce con
  /// l'inserimento.
  static void _sortByInsertion(List<Map<String, dynamic>> reports) {
    reports.sort((a, b) {
      final byDate = _parseDate(
        b['datetime'],
      ).compareTo(_parseDate(a['datetime']));
      if (byDate != 0) return byDate;
      return _parseId(b['id']).compareTo(_parseId(a['id']));
    });
  }

  static DateTime _parseDate(dynamic raw) =>
      DateTime.tryParse(raw?.toString() ?? '') ?? DateTime(1970);

  /// Le bozze locali hanno id tipo `local_1712345678`: si confronta la
  /// parte numerica, che e' il momento di creazione.
  static int _parseId(dynamic raw) =>
      int.tryParse((raw?.toString() ?? '').replaceAll(RegExp(r'[^0-9]'), '')) ??
      0;

  /// Chip della barra filtri, nell'ordine in cui compaiono.
  static const Map<String, String> _filters = {
    'all': 'Tutte',
    'in_creazione': 'In creazione',
    'pending': 'In attesa',
    'in_progress': 'In lavorazione',
    'resolved': 'Risolte',
    'rejected': 'Rifiutate',
  };

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'all') return _reports;
    return _reports.where((r) => r['status'] == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Sfondo bianco uniforme: appbar, barra filtri, lista e barra
      // inferiore hanno tutti lo stesso colore.
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leadingWidth: 72,
        leading: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Image.asset(
            'android/app/src/main/res/drawable/logo.png',
            fit: BoxFit.contain,
          ),
        ),
        // Dall'app si vedono sempre e solo le proprie: vedere quelle di
        // tutti e' un lavoro da area riservata del sito.
        title: Text(
          'Le mie segnalazioni',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: const Color(0xFF111111),
            fontSize: context.isNarrowScreen ? 15 : context.adaptive(18),
            fontFamily: 'Inter',
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Filtri ────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: context.centeredPadding(top: 10, bottom: 10),
            child: Row(
              spacing: 8,
              children: [
                for (final f in _filters.entries)
                  _FilterChip(
                    label: f.value,
                    selected: _filter == f.key,
                    onTap: () => setState(() => _filter = f.key),
                  ),
              ],
            ),
          ),
          // ── Lista ─────────────────────────────────────────────
          Expanded(child: _buildBody()),
        ],
      ),
      bottomNavigationBar: BottomNavBar(
        icon: Icons.add_circle_outline,
        label: 'Nuova',
        onTap: () => Navigator.pop(context),
      ),
    );
  }

  /// Schermata centrale, usata sia per la lista vuota sia per l'errore.
  Widget _message({
    required IconData icon,
    required String text,
    Future<void> Function()? onRetry,
  }) =>
      // Resta centrato finche' c'e' spazio, ma puo' scorrere: su un
      // telefono coricato, o basso, icona + testo + "Riprova" non ci
      // stanno in altezza e senza scorrimento andrebbero in overflow.
      LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: context.centeredPadding(
                  horizontal: 32,
                  top: 24,
                  bottom: 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: context.isShortScreen
                          ? 44
                          : context.adaptive(64, tablet: 72),
                      color: Colors.grey.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF888888),
                        fontFamily: 'Inter',
                      ),
                    ),
                    if (onRetry != null) ...[
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: onRetry,
                        child: const Text(
                          'Riprova',
                          style: TextStyle(
                            color: Color(0xFF7BA566),
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF7BA566)),
      );
    }
    // Un errore del server non deve somigliare a "non hai segnalazioni":
    // si mostra il messaggio ricevuto, con la possibilita' di riprovare.
    if (_error != null) {
      return _message(
        icon: Icons.cloud_off_outlined,
        text: _error!,
        onRetry: _loadReports,
      );
    }
    final list = _filtered;
    if (list.isEmpty) {
      return _message(
        icon: Icons.inbox_outlined,
        text: _filter == 'all'
            ? 'Non c\'e\' ancora nessuna segnalazione.'
            : 'Nessuna segnalazione in questa categoria.',
      );
    }
    return RefreshIndicator(
      color: const Color(0xFF7BA566),
      onRefresh: _loadReports,
      child: ListView.builder(
        padding: context.centeredPadding(top: 16, bottom: 16),
        itemCount: list.length,
        itemBuilder: (_, i) =>
            ReportCard(report: list[i], onChanged: _loadReports),
      ),
    );
  }
}

// ── Card ──────────────────────────────────────────────────────────

/// Card di una segnalazione in elenco.
///
/// Pubblica perche' un test verifica che il badge di stato resti
/// appoggiato al bordo destro: e' gia' scivolato in mezzo una volta.
class ReportCard extends StatelessWidget {
  final Map<String, dynamic> report;

  /// Richiamata al ritorno dalla scheda: una bozza puo' essere stata
  /// inviata o eliminata, quindi la lista va ricaricata.
  final Future<void> Function() onChanged;

  const ReportCard({super.key, required this.report, required this.onChanged});

  static Color statusColor(String status) {
    switch (status) {
      case 'in_creazione':
        return const Color(0xFF8B5CF6); // viola
      case 'pending':
        return const Color(0xFFF59E0B); // giallo
      case 'in_progress':
        return const Color(0xFF38BDF8); // azzurro
      case 'resolved':
        return const Color(0xFF7BA566); // verde
      case 'rejected':
        return const Color(0xFFEF4444); // rosso
      default:
        return const Color(0xFF9CA3AF);
    }
  }

  static String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw);
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year}';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = report['type'] as Map<String, dynamic>?;
    final typeName = type?['name'] as String? ?? '—';
    final address = report['address'] as String? ?? '';
    final status = report['status'] as String? ?? '';
    final statusLabel = report['status_label'] as String? ?? status;
    final datetime = report['datetime'] as String? ?? '';
    // Le bozze locali sono card normali "In creazione": cambia solo il
    // grigio di bordo e badge, che prende colore dopo l'invio.
    final isDraft = DraftStore.isLocal(report);
    final color = isDraft ? const Color(0xFF9CA3AF) : statusColor(status);
    final label = isDraft ? 'In creazione' : statusLabel;

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SchedaScreen(report: report)),
        );
        await onChanged();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          // Bordo chiaro uniforme: su sfondo bianco la card resta
          // comunque distinguibile.
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Barra colorata di stato
                Container(width: 4, color: color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                typeName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF111111),
                                  fontSize: 15,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Badge stato, sempre appoggiato al bordo
                            // destro: non prende flex, cosi' l'Expanded
                            // qui sopra si mangia tutto lo spazio libero e
                            // lo spinge a destra. Il tetto di larghezza
                            // serve solo a non far sfondare la card a
                            // "IN LAVORAZIONE" sui telefoni stretti o coi
                            // caratteri di sistema ingranditi.
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: context.screenWidth * 0.42,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: color.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  label.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 10,
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (address.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                size: 12,
                                color: Color(0xFF9CA3AF),
                              ),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  address,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF9CA3AF),
                                    fontSize: 12,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_today_outlined,
                              size: 12,
                              color: Color(0xFF9CA3AF),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatDate(datetime),
                              style: const TextStyle(
                                color: Color(0xFF9CA3AF),
                                fontSize: 11,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Chip filtro ───────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF555555) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: selected ? null : Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF555555),
            fontSize: 12,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
