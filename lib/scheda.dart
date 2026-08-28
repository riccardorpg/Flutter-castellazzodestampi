import 'dart:io';
import 'package:flutter/material.dart';
import 'form.dart';
import 'services/api_service.dart';
import 'services/draft_store.dart';
import 'widgets/action_bar.dart';

class SchedaScreen extends StatefulWidget {
  final Map<String, dynamic> report;
  const SchedaScreen({super.key, required this.report});

  @override
  State<SchedaScreen> createState() => _SchedaScreenState();
}

class _SchedaScreenState extends State<SchedaScreen> {
  bool _sending = false;

  /// Copia locale: dopo una modifica della bozza viene rimpiazzata
  /// con la versione aggiornata letta dallo store.
  late Map<String, dynamic> _report = widget.report;

  Map<String, dynamic> get report => _report;

  /// Bozza locale: non e' mai stata inviata al Comune.
  bool get _isDraft => DraftStore.isLocal(report);

  /// Percorsi delle foto della bozza ancora presenti sul dispositivo.
  List<String> get _localImages => List<String>.from(
    (report['image_paths'] as List? ?? const [])
        .map((p) => p.toString())
        .where((p) => File(p).existsSync()),
  );

  static const _imageExtensions = [
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.bmp',
    '.heic',
  ];

  List<Map<String, dynamic>> get _images {
    final attachments = report['attachments'] as List? ?? [];
    return List<Map<String, dynamic>>.from(
      attachments.where((a) {
        if (a is! Map) return false;
        final path = (a['file_path'] as String? ?? '').trim();
        if (path.isEmpty) return false;
        final ft = (a['file_type'] as String? ?? '').toLowerCase();
        if (ft.startsWith('image/')) return true;
        final lower = path.toLowerCase();
        return _imageExtensions.any(lower.endsWith);
      }),
    );
  }

  // ── Invio / eliminazione bozza ─────────────────────────────────

  /// Invia al Comune la bozza tenuta finora solo sul dispositivo:
  /// diventa una segnalazione "In attesa" e la copia locale sparisce.
  Future<void> _sendDraft() async {
    // Una bozza puo' essere incompleta: prima dell'invio servono
    // descrizione e indirizzo confermato, come per una nuova segnalazione.
    final details = (report['details'] as String? ?? '').trim();
    final address = (report['address'] as String? ?? '').trim();
    final hasPosition =
        report['latitude'] != null && report['longitude'] != null;
    if (details.isEmpty || address.isEmpty || !hasPosition) {
      _showMessage(
        'Completa la bozza con "Modifica": servono descrizione e '
        'indirizzo di Corbetta.',
        error: true,
      );
      return;
    }

    setState(() => _sending = true);

    final type = report['type'] as Map<String, dynamic>?;
    final result = await ApiService.createReport(
      typeId: type?['id']?.toString() ?? '',
      details: report['details'] as String?,
      address: report['address'] as String?,
      latitude: report['latitude']?.toString(),
      longitude: report['longitude']?.toString(),
      imagePaths: _localImages,
      status: 'pending',
    );

    if (!mounted) return;
    setState(() => _sending = false);

    if (result['success'] == true) {
      await DraftStore.delete(report['id'].toString());
      if (!mounted) return;
      _showMessage('Segnalazione inviata: ora e\' in attesa.');
      Navigator.pop(context);
    } else {
      _showMessage(
        result['message'] as String? ?? 'Errore durante l\'invio.',
        error: true,
      );
    }
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? Colors.redAccent : const Color(0xFF7BA566),
        content: Text(message, style: const TextStyle(fontFamily: 'Inter')),
      ),
    );
  }

  /// Riapre la bozza nel form per aggiungere foto e dettagli mancanti.
  Future<void> _editDraft() async {
    final type = report['type'] as Map<String, dynamic>? ?? const {};
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FormScreen(
          reportType: Map<String, dynamic>.from(type),
          draft: report,
        ),
      ),
    );
    if (!mounted) return;

    // Se la bozza non c'e' piu' e' stata inviata dal form: la scheda
    // locale non ha piu' senso e si torna all'elenco.
    final drafts = await DraftStore.load();
    final id = report['id']?.toString();
    final updated = drafts.where((d) => d['id']?.toString() == id).toList();
    if (!mounted) return;
    if (updated.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() => _report = updated.first);
  }

  Future<void> _deleteDraft() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Eliminare la bozza?',
          style: TextStyle(fontFamily: 'Inter', fontSize: 17),
        ),
        content: const Text(
          'La bozza verra\' rimossa da questo dispositivo.',
          style: TextStyle(fontFamily: 'Inter', fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla', style: TextStyle(fontFamily: 'Inter')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Elimina',
              style: TextStyle(fontFamily: 'Inter', color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    await DraftStore.delete(report['id'].toString());
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final type = report['type'] as Map<String, dynamic>?;
    final typeName = type?['name'] as String? ?? '—';
    final details = report['details'] as String? ?? '';
    final address = report['address'] as String? ?? '';
    final status = report['status'] as String? ?? '';
    final statusLabel = _isDraft
        ? 'In creazione'
        : (report['status_label'] as String? ?? status);
    final datetime = report['datetime'] as String? ?? '';
    // La bozza resta grigia: prende colore solo una volta inviata.
    final color = _isDraft ? const Color(0xFF9CA3AF) : _statusColor(status);
    final images = _images;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Color(0xFF111111),
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Dettaglio segnalazione',
          style: TextStyle(
            color: Color(0xFF111111),
            fontSize: 18,
            fontFamily: 'Inter',
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Banner stato ──────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.30)),
              ),
              child: Row(
                children: [
                  Icon(_statusIcon(status), color: color, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    statusLabel.toUpperCase(),
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Tipo ─────────────────────────────────────────────
            Text(
              typeName,
              style: const TextStyle(
                color: Color(0xFF111111),
                fontSize: 22,
                fontFamily: 'Inter',
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(color: Color(0xFFE5E7EB)),
            const SizedBox(height: 16),

            // ── Descrizione ───────────────────────────────────────
            if (details.isNotEmpty) ...[
              _label('DESCRIZIONE'),
              const SizedBox(height: 8),
              Text(
                details,
                style: const TextStyle(
                  color: Color(0xFF333333),
                  fontSize: 14,
                  fontFamily: 'Inter',
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ── Indirizzo ─────────────────────────────────────────
            if (address.isNotEmpty) ...[
              _label('INDIRIZZO'),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 16,
                    color: Color(0xFF7BA566),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      address,
                      style: const TextStyle(
                        color: Color(0xFF333333),
                        fontSize: 14,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],

            // ── Data ──────────────────────────────────────────────
            if (datetime.isNotEmpty) ...[
              _label('DATA'),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 14,
                    color: Color(0xFF9CA3AF),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(datetime),
                    style: const TextStyle(
                      color: Color(0xFF333333),
                      fontSize: 13,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],

            // ── Foto ──────────────────────────────────────────────
            if (_isDraft && _localImages.isNotEmpty) ...[
              _label('FOTO'),
              const SizedBox(height: 10),
              _LocalImageGrid(paths: _localImages),
              const SizedBox(height: 24),
            ] else if (!_isDraft && images.isNotEmpty) ...[
              _label('FOTO'),
              const SizedBox(height: 10),
              _ImageGrid(images: images),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
      // Invia / Modifica / Elimina solo a chi ha anche la scrittura.
      bottomNavigationBar: _isDraft && ApiService.canWrite
          ? _draftActions()
          : null,
    );
  }

  /// Barra azioni della bozza: stessi tre pulsanti del form.
  Widget _draftActions() => BottomActionBar(
    children: [
      Row(
        children: [
          Expanded(
            child: SecondaryBarButton.danger(
              label: 'Elimina',
              onPressed: _sending ? null : _deleteDraft,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SecondaryBarButton.neutral(
              label: 'Modifica',
              onPressed: _sending ? null : _editDraft,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      PrimaryBarButton(
        label: 'INVIA',
        loading: _sending,
        onPressed: _sendDraft,
      ),
    ],
  );

  static Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      color: Color(0xFF9CA3AF),
      fontSize: 11,
      fontFamily: 'Inter',
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    ),
  );

  static Color _statusColor(String status) {
    switch (status) {
      case 'in_creazione':
        return const Color(0xFF8B5CF6);
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'in_progress':
        return const Color(0xFF38BDF8);
      case 'resolved':
        return const Color(0xFF7BA566);
      case 'rejected':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF9CA3AF);
    }
  }

  static IconData _statusIcon(String status) {
    switch (status) {
      case 'in_creazione':
        return Icons.edit_note;
      case 'pending':
        return Icons.hourglass_empty;
      case 'in_progress':
        return Icons.build_outlined;
      case 'resolved':
        return Icons.check_circle_outline;
      case 'rejected':
        return Icons.cancel_outlined;
      default:
        return Icons.info_outline;
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
}

// ── Grid foto della bozza (file locali) ───────────────────────────

class _LocalImageGrid extends StatelessWidget {
  final List<String> paths;
  const _LocalImageGrid({required this.paths});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: paths.length,
      itemBuilder: (_, i) => GestureDetector(
        onTap: () => _openFullscreen(context, i),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(paths[i]),
            fit: BoxFit.cover,
            // miniatura in griglia da 3 colonne: basta decodificare a 300px
            cacheWidth: 300,
            errorBuilder: (_, _, _) => Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.broken_image_outlined,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openFullscreen(BuildContext context, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullscreenGallery(
          sources: paths,
          isLocal: true,
          initialIndex: initialIndex,
        ),
      ),
    );
  }
}

// ── Grid gallery ──────────────────────────────────────────────────

class _ImageGrid extends StatelessWidget {
  final List<Map<String, dynamic>> images;

  const _ImageGrid({required this.images});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: images.length,
      itemBuilder: (_, i) {
        // in griglia si usa la miniatura da 300px; il fullscreen carica
        // l'immagine originale
        final thumb =
            ApiService.mediaUrl(
              images[i]['thumb_path'] as String? ??
                  images[i]['file_path'] as String?,
            ) ??
            '';
        return GestureDetector(
          onTap: () => _openFullscreen(context, i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              thumb,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.broken_image_outlined,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openFullscreen(BuildContext context, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullscreenGallery(
          sources: images
              .map((a) => ApiService.mediaUrl(a['file_path'] as String?) ?? '')
              .toList(),
          initialIndex: initialIndex,
        ),
      ),
    );
  }
}

// ── Fullscreen viewer ─────────────────────────────────────────────

class _FullscreenGallery extends StatefulWidget {
  /// URL remoti, oppure percorsi sul dispositivo se [isLocal] e' true:
  /// le bozze non ancora inviate hanno le foto solo in locale.
  final List<String> sources;
  final bool isLocal;
  final int initialIndex;

  const _FullscreenGallery({
    required this.sources,
    required this.initialIndex,
    this.isLocal = false,
  });

  @override
  State<_FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<_FullscreenGallery> {
  late final PageController _controller;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: widget.sources.length > 1
            ? Text(
                '${_current + 1} / ${widget.sources.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Inter',
                  fontSize: 14,
                ),
              )
            : null,
        centerTitle: true,
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.sources.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 0.8,
          maxScale: 4.0,
          child: Center(child: _image(widget.sources[i])),
        ),
      ),
    );
  }

  Widget _image(String source) {
    if (widget.isLocal) {
      return Image.file(
        File(source),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _broken,
      );
    }
    return Image.network(
      source,
      fit: BoxFit.contain,
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      },
      errorBuilder: (_, _, _) => _broken,
    );
  }

  static const Widget _broken = Icon(
    Icons.broken_image_outlined,
    color: Colors.white54,
    size: 64,
  );
}
