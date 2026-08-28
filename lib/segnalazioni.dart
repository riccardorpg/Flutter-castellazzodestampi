import 'package:flutter/material.dart';
import 'login.dart';
import 'scheda.dart';
import 'services/api_service.dart';
import 'services/draft_store.dart';
import 'widgets/read_only_banner.dart';

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
    // e si mescolano alle segnalazioni gia' inviate. In sola lettura non
    // si possono creare bozze, quindi non si mostrano.
    final drafts = ApiService.canWrite
        ? await DraftStore.load()
        : <Map<String, dynamic>>[];
    final result = await ApiService.getMyReports();
    if (!mounted) return;
    if (ApiService.isUnauthenticated(result)) {
      await ApiService.clearToken();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
      return;
    }
    final ok = result['success'] == true;
    final data = ok
        ? List<Map<String, dynamic>>.from(result['data'] as List)
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
  ///
  /// "In creazione" riguarda solo le bozze locali: in sola lettura non se
  /// ne possono creare e quelle eventualmente rimaste sul dispositivo non
  /// vengono caricate, quindi il chip sparisce invece di aprire sempre una
  /// lista vuota. Restano le card gia' inserite online.
  Map<String, String> get _filters => {
    'all': 'Tutte',
    if (ApiService.canWrite) 'in_creazione': 'In creazione',
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
        // In sola lettura l'elenco non e' piu' solo il proprio: si vedono
        // tutte le segnalazioni, quindi il titolo non dice "le mie".
        title: Text(
          ApiService.canWrite ? 'Le mie segnalazioni' : 'Segnalazioni',
          style: const TextStyle(
            color: Color(0xFF111111),
            fontSize: 18,
            fontFamily: 'Inter',
            fontWeight: FontWeight.bold,
          ),
        ),
        // In sola lettura questa e' la schermata iniziale: il pulsante
        // per uscire, che di solito sta nel menu, serve qui.
        actions: [
          if (!ApiService.canWrite)
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
      body: Column(
        children: [
          if (!ApiService.canWrite) const ReadOnlyBanner(),
          // ── Filtri ────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
      // Senza permesso di scrittura non c'e' nessuna "Nuova
      // segnalazione" da raggiungere: la barra sparisce.
      bottomNavigationBar: !ApiService.canWrite
          ? null
          : GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                height: 68,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_circle_outline,
                      color: Color(0xFF666666),
                      size: 22,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Nuova',
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

  /// Schermata centrale, usata sia per la lista vuota sia per l'errore.
  Widget _message({
    required IconData icon,
    required String text,
    Future<void> Function()? onRetry,
  }) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Colors.grey.withValues(alpha: 0.4)),
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
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        itemBuilder: (_, i) =>
            _ReportCard(report: list[i], onChanged: _loadReports),
      ),
    );
  }
}

// ── Card ──────────────────────────────────────────────────────────

class _ReportCard extends StatelessWidget {
  final Map<String, dynamic> report;

  /// Richiamata al ritorno dalla scheda: una bozza puo' essere stata
  /// inviata o eliminata, quindi la lista va ricaricata.
  final Future<void> Function() onChanged;

  const _ReportCard({required this.report, required this.onChanged});

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
                                style: const TextStyle(
                                  color: Color(0xFF111111),
                                  fontSize: 15,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            // Badge stato
                            Container(
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
                                style: TextStyle(
                                  color: color,
                                  fontSize: 10,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
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
