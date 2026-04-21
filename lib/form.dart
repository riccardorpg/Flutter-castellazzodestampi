import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
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
  Timer? _debounce;

  static const _nominatimHeaders = {
    'User-Agent': 'CastellazzoDestampiApp/1.0',
    'Accept-Language': 'it',
  };

  @override
  void dispose() {
    _detailsController.dispose();
    _addressController.dispose();
    _addressFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── Nominatim autocomplete ─────────────────────────────────────

  void _onAddressChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 3) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 600), () => _searchAddress(value));
  }

  Future<void> _searchAddress(String query) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'json',
        'limit': '5',
        'addressdetails': '1',
        'accept-language': 'it',
      });
      final res = await http
          .get(uri, headers: _nominatimHeaders)
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List;
        setState(() => _suggestions = List<Map<String, dynamic>>.from(data));
      }
    } catch (_) {
      // ricerca silenziosa
    }
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
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': '$lat',
        'lon': '$lon',
        'format': 'json',
        'addressdetails': '1',
        'zoom': '18',
        'accept-language': 'it',
      });
      final res = await http
          .get(uri, headers: _nominatimHeaders)
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final addr = data['address'] as Map<String, dynamic>? ?? {};
        final road   = addr['road'] ?? addr['pedestrian'] ?? addr['footway'] ?? addr['path'] ?? '';
        final number = addr['house_number']?.toString() ?? '';
        final city   = addr['city'] ?? addr['town'] ?? addr['village'] ?? addr['municipality'] ?? addr['suburb'] ?? '';
        final parts  = <String>[
          if (road.isNotEmpty) (number.isNotEmpty ? '$road $number' : road),
          if (city.isNotEmpty) city,
        ];
        final display = parts.isNotEmpty ? parts.join(', ') : (data['display_name'] as String? ?? '');
        if (display.isNotEmpty) setState(() => _addressController.text = display);
      }
    } catch (_) {
      // indirizzo non trovato — rimane quello scritto dall'utente
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

  // ── Submit ─────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_detailsController.text.trim().isEmpty) {
      setState(() => _error = 'Inserisci una descrizione.');
      return;
    }
    if (_addressController.text.trim().isEmpty) {
      setState(() => _error = 'Inserisci un indirizzo.');
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
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (result['success'] == true) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SegnalazioniScreen()),
      );
    } else {
      setState(() =>
          _error = result['message'] as String? ?? 'Errore durante l\'invio.');
    }
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
          onPressed: () => Navigator.pop(context),
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
                        decoration: const InputDecoration(
                          hintText: 'Es. Via Roma 12, Castellazzo…',
                          hintStyle: TextStyle(color: Color(0xFF9CA3AF)),
                          prefixIcon: Icon(Icons.location_on_outlined,
                              color: Color(0xFF9CA3AF), size: 20),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),

                    // Suggerimenti Nominatim
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

          // ── Bottone INVIA fisso ───────────────────────────────
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: SizedBox(
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
