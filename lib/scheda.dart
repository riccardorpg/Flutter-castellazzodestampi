import 'package:flutter/material.dart';
import 'services/api_service.dart';

class SchedaScreen extends StatelessWidget {
  final Map<String, dynamic> report;
  const SchedaScreen({super.key, required this.report});

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

  @override
  Widget build(BuildContext context) {
    final type = report['type'] as Map<String, dynamic>?;
    final typeName = type?['name'] as String? ?? '—';
    final details = report['details'] as String? ?? '';
    final address = report['address'] as String? ?? '';
    final status = report['status'] as String? ?? '';
    final statusLabel = report['status_label'] as String? ?? status;
    final datetime = report['datetime'] as String? ?? '';
    final color = _statusColor(status);
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
            if (images.isNotEmpty) ...[
              _label('FOTO'),
              const SizedBox(height: 10),
              _ImageGrid(images: images, baseUrl: ApiService.baseUrl),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }

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
          '${dt.year}  '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }
}

// ── Grid gallery ──────────────────────────────────────────────────

class _ImageGrid extends StatelessWidget {
  final List<Map<String, dynamic>> images;
  final String baseUrl;

  const _ImageGrid({required this.images, required this.baseUrl});

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
        final thumb = images[i]['thumb_path'] as String? ??
            images[i]['file_path'] as String;
        return GestureDetector(
          onTap: () => _openFullscreen(context, i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              '$baseUrl$thumb',
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
          urls: images.map((a) => '$baseUrl${a['file_path']}').toList(),
          initialIndex: initialIndex,
        ),
      ),
    );
  }
}

// ── Fullscreen viewer ─────────────────────────────────────────────

class _FullscreenGallery extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const _FullscreenGallery({required this.urls, required this.initialIndex});

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
        title: widget.urls.length > 1
            ? Text(
                '${_current + 1} / ${widget.urls.length}',
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
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 0.8,
          maxScale: 4.0,
          child: Center(
            child: Image.network(
              widget.urls[i],
              fit: BoxFit.contain,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              },
              errorBuilder: (_, _, _) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 64,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
