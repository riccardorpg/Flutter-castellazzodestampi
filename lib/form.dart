import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'segnalazioni.dart';
import 'services/api_service.dart';

class FormScreen extends StatefulWidget {
  final Map<String, dynamic> reportType;
  const FormScreen({super.key, required this.reportType});

  @override
  State<FormScreen> createState() => _FormScreenState();
}

class _FormScreenState extends State<FormScreen> {
  final _detailsController = TextEditingController();
  final _addressController = TextEditingController();
  final _addressFocus = FocusNode();
  final _picker = ImagePicker();

  List<XFile> _images = [];
  double? _latitude;
  double? _longitude;
  bool _locating = false;
  bool _loading = false;
  String? _error;

  List<Map<String, dynamic>> _suggestions = [];
  bool _noResults = false;
  Timer? _debounce;

  /// Bounding box del Comune di Corbetta: fuori da qui la segnalazione
  /// non viene accettata (stesso vincolo applicato lato server).
  static const double _corbettaMinLat = 45.4200;
  static const double _corbettaMaxLat = 45.5150;
  static const double _corbettaMinLon = 8.8500;
  static const double _corbettaMaxLon = 8.9650;

  bool get _hasValidPosition =>
      _latitude != null &&
      _longitude != null &&
      _isInCorbetta(_latitude!, _longitude!);

  static bool _isInCorbetta(double lat, double lon) =>
      lat >= _corbettaMinLat &&
      lat <= _corbettaMaxLat &&
      lon >= _corbettaMinLon &&
      lon <= _corbettaMaxLon;

  @override
  void dispose() {
    _detailsController.dispose();
    _addressController.dispose();
    _addressFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── Autocomplete indirizzi (solo Corbetta) ─────────────────────

  void _onAddressChanged(String value) {
    _debounce?.cancel();
    // modificando il testo a mano le coordinate scelte non valgono piu'
    if (_latitude != null || _longitude != null) {
      _latitude = null;
      _longitude = null;
    }
    if (value.trim().length < 3) {
      if (_suggestions.isNotEmpty || _noResults) {
        setState(() {
          _suggestions = [];
          _noResults = false;
        });
      }
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 600), () => _searchAddress(value));
  }

  Future<void> _searchAddress(String query) async {
    // L'endpoint server restituisce solo indirizzi del Comune di Corbetta.
    final results = await ApiService.autocompleteAddress(query);
    if (!mounted) return;
    setState(() {
      _suggestions = results;
      _noResults = results.isEmpty;
    });
  }

  void _selectSuggestion(Map<String, dynamic> item) {
    final display = item['display_name'] as String? ?? '';
    final lat = double.tryParse(item['lat']?.toString() ?? '');
    final lon = double.tryParse(item['lon']?.toString() ?? '');
    _addressController.text = display;
    _addressFocus.unfocus();
    setState(() {
      _latitude = lat;
      _longitude = lon;
      _suggestions = [];
      _noResults = false;
      _error = null;
    });
  }

  // ── GPS + reverse geocoding ────────────────────────────────────

  Future<void> _getLocation() async {
    setState(() {
      _locating = true;
      _error = null;
    });

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        setState(() {
          _error = 'Permesso posizione negato.';
          _locating = false;
        });
        return;
      }

      // Prima prova la posizione in cache (istantanea)
      Position? pos = await Geolocator.getLastKnownPosition();

      // Se non disponibile, acquisisce con precisione media (più veloce)
      pos ??= await Geolocator.getCurrentPosition(
        locationSettings: Platform.isAndroid
            ? AndroidSettings(
                accuracy: LocationAccuracy.medium,
                timeLimit: const Duration(seconds: 15),
              )
            : AppleSettings(
                accuracy: LocationAccuracy.medium,
                timeLimit: const Duration(seconds: 15),
              ),
      );

      if (!mounted) return;

      // Fuori dal territorio comunale la posizione non viene accettata
      if (!_isInCorbetta(pos.latitude, pos.longitude)) {
        setState(() {
          _latitude = null;
          _longitude = null;
          _locating = false;
          _error = 'Ti trovi fuori dal territorio di Corbetta: '
              'cerca un indirizzo del Comune per proseguire.';
        });
        return;
      }

      setState(() {
        _latitude = pos!.latitude;
        _longitude = pos.longitude;
        _locating = false;
      });

      // Converte coordinate in indirizzo
      await _reverseGeocode(pos.latitude, pos.longitude);
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _error = 'Timeout GPS. Riprova o inserisci l\'indirizzo manualmente.';
        _locating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossibile ottenere la posizione.';
        _locating = false;
      });
    }
  }

  Future<void> _reverseGeocode(double lat, double lon) async {
    final data = await ApiService.reverseGeocode(lat, lon);
    if (!mounted || data == null) return;

    // Il bounding box e' un rettangolo: il server conferma il Comune
    if (data['in_corbetta'] == false) {
      setState(() {
        _latitude = null;
        _longitude = null;
        _error = 'Ti trovi fuori dal territorio di Corbetta: '
            'cerca un indirizzo del Comune per proseguire.';
      });
      return;
    }

    final display = data['address'] as String? ?? '';
    if (display.isNotEmpty) {
      setState(() {
        _addressController.text = display;
        _suggestions = [];
        _noResults = false;
      });
    }
  }

  // ── Foto ───────────────────────────────────────────────────────

  Future<void> _showPhotoOptions() async {
    setState(() => _error = null);
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined,
                    color: Color(0xFF7BA566)),
                title: const Text('Scatta una foto',
                    style: TextStyle(fontFamily: 'Inter')),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFromCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined,
                    color: Color(0xFF7BA566)),
                title: const Text('Scegli dalla galleria',
                    style: TextStyle(fontFamily: 'Inter')),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFromGallery();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFromCamera() async {
    try {
      final photo = await _picker.pickImage(source: ImageSource.camera);
      if (photo != null) setState(() => _images = [..._images, photo]);
    } catch (_) {
      setState(() => _error =
          'Impossibile accedere alla fotocamera. Verifica i permessi nelle impostazioni.');
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picked = await _picker.pickMultiImage();
      if (picked.isNotEmpty) setState(() => _images = [..._images, ...picked]);
    } catch (_) {
      try {
        final single = await _picker.pickImage(source: ImageSource.gallery);
        if (single != null) setState(() => _images = [..._images, single]);
      } catch (_) {
        setState(() => _error =
            'Impossibile accedere alla galleria. Verifica i permessi nelle impostazioni.');
      }
    }
  }

  void _removeImage(int index) => setState(() => _images.removeAt(index));

  // ── Salvataggio ────────────────────────────────────────────────

  bool get _hasContent =>
      _detailsController.text.trim().isNotEmpty ||
      _addressController.text.trim().isNotEmpty ||
      _images.isNotEmpty;

  /// Invia la segnalazione al Comune.
  Future<void> _submit() => _save(draft: false);

  /// Salva la segnalazione come bozza ("In creazione"), modificabile in seguito.
  Future<void> _saveDraft() => _save(draft: true);

  Future<void> _save({required bool draft}) async {
    if (_detailsController.text.trim().isEmpty) {
      setState(() => _error = 'Inserisci una descrizione.');
      return;
    }
    if (_addressController.text.trim().isEmpty) {
      setState(() => _error = 'Inserisci un indirizzo.');
      return;
    }
    // L'indirizzo deve essere stato confermato dalla ricerca o dal GPS:
    // senza coordinate non e' possibile verificare il territorio.
    if (!_hasValidPosition) {
      setState(() => _error =
          'Seleziona un indirizzo di Corbetta dai suggerimenti oppure usa la tua posizione.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await ApiService.createReport(
      typeId: widget.reportType['id'].toString(),
      details: _detailsController.text.trim(),
      address: _addressController.text.trim(),
      latitude: _latitude?.toString(),
      longitude: _longitude?.toString(),
      imagePaths: _images.map((x) => x.path).toList(),
      status: draft ? 'in_creazione' : 'pending',
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF7BA566),
          content: Text(
            draft ? 'Bozza salvata.' : 'Segnalazione inviata.',
            style: const TextStyle(fontFamily: 'Inter'),
          ),
        ),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SegnalazioniScreen()),
      );
    } else {
      setState(() =>
          _error = result['message'] as String? ?? 'Errore durante l\'invio.');
    }
  }

  /// Annulla la compilazione; se ci sono dati chiede conferma.
  Future<void> _cancel() async {
    if (!_hasContent) {
      Navigator.pop(context);
      return;
    }

    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annullare la segnalazione?',
            style: TextStyle(fontFamily: 'Inter', fontSize: 17)),
        content: const Text(
          'I dati inseriti andranno persi. Puoi invece salvarla come bozza.',
          style: TextStyle(fontFamily: 'Inter', fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continua a compilare',
                style: TextStyle(fontFamily: 'Inter')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Annulla segnalazione',
                style: TextStyle(fontFamily: 'Inter', color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (discard == true && mounted) Navigator.pop(context);
  }

  // ── UI ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final typeName = widget.reportType['name'] as String? ?? '';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Color(0xFF111111), size: 18),
          onPressed: _loading ? null : _cancel,
        ),
        title: const Text(
          'Nuova Segnalazione',
          style: TextStyle(
            color: Color(0xFF111111),
            fontSize: 18,
            fontFamily: 'Inter',
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                _addressFocus.unfocus();
                if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
              },
              behavior: HitTestBehavior.opaque,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Badge tipo
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDF5E9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.label_outline,
                              color: Color(0xFF7BA566), size: 16),
                          const SizedBox(width: 6),
                          Text(
                            typeName,
                            style: const TextStyle(
                              color: Color(0xFF7BA566),
                              fontSize: 13,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Descrizione ──────────────────────────────
                    _sectionLabel('DESCRIZIONE DETTAGLIATA'),
                    const SizedBox(height: 8),
                    _fieldBox(
                      child: TextField(
                        controller: _detailsController,
                        maxLines: 5,
                        style: _inputStyle,
                        decoration: const InputDecoration(
                          hintText: 'Descrivi il problema nel dettaglio…',
                          hintStyle: TextStyle(color: Color(0xFF9CA3AF)),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Indirizzo ────────────────────────────────
                    _sectionLabel('INDIRIZZO *'),
                    const SizedBox(height: 8),
                    _fieldBox(
                      child: TextField(
                        controller: _addressController,
                        focusNode: _addressFocus,
                        style: _inputStyle,
                        onChanged: _onAddressChanged,
                        decoration: InputDecoration(
                          hintText: 'Es. Via Roma 12, Corbetta…',
                          hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                          prefixIcon: const Icon(Icons.location_on_outlined,
                              color: Color(0xFF9CA3AF), size: 20),
                          // spunta verde quando la posizione e' confermata
                          suffixIcon: _hasValidPosition
                              ? const Icon(Icons.check_circle,
                                  color: Color(0xFF7BA566), size: 20)
                              : null,
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),

                    // Solo indirizzi del Comune di Corbetta
                    if (_suggestions.isEmpty && !_noResults) ...[
                      const SizedBox(height: 6),
                      const Text(
                        'Sono ammesse solo segnalazioni nel territorio di Corbetta.',
                        style: TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 11,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],

                    if (_noResults) ...[
                      const SizedBox(height: 6),
                      const Text(
                        'Nessun indirizzo trovato a Corbetta.',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 11,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],

                    // Suggerimenti indirizzo
                    if (_suggestions.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          children: _suggestions.asMap().entries.map((e) {
                            final name =
                                e.value['display_name'] as String? ?? '';
                            return Column(
                              children: [
                                if (e.key > 0)
                                  const Divider(
                                      height: 1, color: Color(0xFFF3F4F6)),
                                InkWell(
                                  onTap: () => _selectSuggestion(e.value),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 12),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.location_on_outlined,
                                            size: 14,
                                            color: Color(0xFF7BA566)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFF333333),
                                              fontSize: 13,
                                              fontFamily: 'Inter',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),

                    const SizedBox(height: 10),

                    // Pulsante GPS (conta come indirizzo)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _locating ? null : _getLocation,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF7BA566),
                          side: const BorderSide(color: Color(0xFF7BA566)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: _locating
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF7BA566)),
                              )
                            : const Icon(Icons.my_location, size: 16),
                        label: Text(
                          _locating
                              ? 'Acquisizione GPS…'
                              : 'Usa la mia posizione',
                          style: const TextStyle(
                              fontFamily: 'Inter', fontSize: 13),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Foto (opzionale) ──────────────────────────
                    _sectionLabel('FOTO (opzionale)'),
                    const SizedBox(height: 8),
                    if (_images.isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(_images.length, (i) {
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(_images[i].path),
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: GestureDetector(
                                  onTap: () => _removeImage(i),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close,
                                        color: Colors.white, size: 14),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                      const SizedBox(height: 8),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showPhotoOptions,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF7BA566),
                          side: const BorderSide(color: Color(0xFF7BA566)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.add_photo_alternate_outlined,
                            size: 16),
                        label: Text(
                          _images.isEmpty
                              ? 'Aggiungi foto'
                              : 'Aggiungi altre foto',
                          style: const TextStyle(
                              fontFamily: 'Inter', fontSize: 13),
                        ),
                      ),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFCA5A5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: Colors.redAccent, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 13,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
          ),

          // ── Barra pulsanti fissa ──────────────────────────────
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Annulla · Salva come bozza
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: OutlinedButton(
                            onPressed: _loading ? null : _cancel,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF666666),
                              side: const BorderSide(color: Color(0xFFD1D5DB)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Annulla',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: OutlinedButton(
                            onPressed: _loading ? null : _saveDraft,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF7BA566),
                              side: const BorderSide(color: Color(0xFF7BA566)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Salva',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7BA566),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            const Color(0xFF7BA566).withValues(alpha: 0.5),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Text(
                              'INVIA',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Inter',
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
          color: Color(0xFF444444),
          fontSize: 12,
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      );

  static Widget _fieldBox({required Widget child}) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: child,
      );

  static const TextStyle _inputStyle = TextStyle(
    color: Color(0xFF111111),
    fontSize: 14,
    fontFamily: 'Inter',
  );
}
