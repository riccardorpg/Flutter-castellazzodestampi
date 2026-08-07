import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'segnalazioni.dart';
import 'services/api_service.dart';
import 'services/draft_store.dart';
import 'widgets/action_bar.dart';

class FormScreen extends StatefulWidget {
  final Map<String, dynamic> reportType;

  /// Bozza locale da completare: se presente il form parte gia' compilato
  /// e il salvataggio aggiorna la stessa bozza invece di crearne un'altra.
  final Map<String, dynamic>? draft;

  const FormScreen({super.key, required this.reportType, this.draft});

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

  /// Id della bozza locale in modifica (null se e' una nuova segnalazione).
  String? _draftId;

  bool get _isEditingDraft => _draftId != null;

  /// Bounding box del Comune di Corbetta: fuori da qui la segnalazione
  /// non viene accettata (stesso vincolo applicato lato server).
  static const double _corbettaMinLat = 45.4200;
  static const double _corbettaMaxLat = 45.5150;
  static const double _corbettaMinLon = 8.8500;
  static const double _corbettaMaxLon = 8.9650;

  /// Indirizzo confermato dalla ricerca o dal GPS. Se il testo nel campo
  /// non e' piu' questo, l'indirizzo non e' verificato: niente spunta.
  String? _confirmedAddress;

  bool get _hasValidPosition =>
      _latitude != null &&
      _longitude != null &&
      _isInCorbetta(_latitude!, _longitude!) &&
      _confirmedAddress != null &&
      _addressController.text.trim() == _confirmedAddress!.trim();

  static bool _isInCorbetta(double lat, double lon) =>
      lat >= _corbettaMinLat &&
      lat <= _corbettaMaxLat &&
      lon >= _corbettaMinLon &&
      lon <= _corbettaMaxLon;

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    if (draft == null) return;
    // Riapre la bozza dove era stata lasciata; le foto sparite dalla
    // cache del telefono vengono semplicemente ignorate.
    _draftId = draft['id']?.toString();
    _detailsController.text = draft['details'] as String? ?? '';
    final savedAddress = draft['address'] as String? ?? '';
    _addressController.text = savedAddress;
    _latitude = double.tryParse(draft['latitude']?.toString() ?? '');
    _longitude = double.tryParse(draft['longitude']?.toString() ?? '');

    // L'indirizzo salvato nella bozza vale solo se risulta di Corbetta:
    // altrimenti niente spunta e va riconfermato prima dell'invio.
    if (_latitude != null &&
        _longitude != null &&
        _isInCorbetta(_latitude!, _longitude!) &&
        _addressNamesCorbetta(savedAddress)) {
      _confirmedAddress = savedAddress;
    } else {
      _latitude = null;
      _longitude = null;
    }
    _images = (draft['image_paths'] as List? ?? const [])
        .map((p) => p.toString())
        .where((p) => File(p).existsSync())
        .map(XFile.new)
        .toList();
  }

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
    final short = value.trim().length < 3;
    // Modificando il testo a mano le coordinate scelte non valgono piu':
    // il setState serve anche a rimettere subito la x a lato del campo.
    setState(() {
      _latitude = null;
      _longitude = null;
      _confirmedAddress = null;
      if (short) {
        _suggestions = [];
        _noResults = false;
      }
    });
    if (short) return;
    _debounce = Timer(const Duration(milliseconds: 600), () => _searchAddress(value));
  }

  /// Icona a lato del campo indirizzo: spunta verde solo quando il testo
  /// e' esattamente l'indirizzo di Corbetta confermato dalla ricerca o dal
  /// GPS, x rossa in tutti gli altri casi (testo scritto o modificato a
  /// mano, suggerimento non ancora scelto, posizione rifiutata).
  Widget? _addressStatusIcon() {
    if (_hasValidPosition) {
      return const Icon(Icons.check_circle, color: Color(0xFF7BA566), size: 20);
    }
    if (_addressController.text.trim().isEmpty) return null;
    return const Icon(Icons.cancel, color: Color(0xFFEF4444), size: 20);
  }

  Future<void> _searchAddress(String query) async {
    // Doppio filtro lato app: vengono mostrate solo le vie di Corbetta,
    // qualsiasi altro risultato viene scartato senza comparire in elenco.
    var filtered = _onlyCorbetta(
      await ApiService.autocompleteAddress(_corbettaQuery(query)),
    );
    if (!mounted) return;

    // Molti civici non sono mappati: cercando "Via Roma 12" il geocoder
    // non trova nulla. Si riprova con la sola via e il numero scritto
    // viene poi riattaccato all'indirizzo scelto, invece di perderlo.
    final soloVia = _senzaCivico(query);
    if (filtered.isEmpty && soloVia != null) {
      filtered = _onlyCorbetta(
        await ApiService.autocompleteAddress(_corbettaQuery(soloVia)),
      );
      if (!mounted) return;
    }

    setState(() {
      _suggestions = filtered;
      _noResults = filtered.isEmpty;
    });
  }

  /// Numero civico scritto nel campo: "via Roma 12" → "12", "via Roma
  /// 12/a" → "12/a", "via Roma" → null. Si ferma a 4 cifre per non
  /// catturare il CAP.
  static final RegExp _civicoDigitatoRe =
      RegExp(r'(?:^|[\s,])(\d{1,4}(?:\s*[/-]\s*)?[a-zA-Z]?)\s*$');

  /// "Via Roma 12, Corbetta" → "Via Roma 12": il comune in coda e' il
  /// formato suggerito dal campo, ma nasconderebbe il civico.
  static final RegExp _comuneInCodaRe =
      RegExp(r'[,\s]+corbetta\.?$', caseSensitive: false);

  static String _senzaComune(String query) =>
      query.trim().replaceAll(_comuneInCodaRe, '').trim();

  static String? _civicoDigitato(String query) {
    final match = _civicoDigitatoRe.firstMatch(_senzaComune(query));
    return match?.group(1)?.replaceAll(' ', '');
  }

  /// La stessa ricerca senza il civico finale, `null` se non c'era.
  static String? _senzaCivico(String query) {
    final base = _senzaComune(query);
    if (!_civicoDigitatoRe.hasMatch(base)) return null;
    final via = base.replaceAll(_civicoDigitatoRe, '').trim();
    return via.length >= 3 ? via : null;
  }

  /// Il geocoder cerca su tutto il territorio nazionale: senza il comune
  /// "via Fabio Filzi" non trova la via di Corbetta, quindi viene aggiunto
  /// in coda alla ricerca (l'utente non deve scriverlo).
  static String _corbettaQuery(String query) {
    final trimmed = query.trim().replaceAll(RegExp(r'[,\s]+$'), '');
    if (trimmed.toLowerCase().contains('corbetta')) return trimmed;
    return '$trimmed, Corbetta';
  }

  /// Coordinate del suggerimento: il server puo' usare nomi di campo
  /// diversi, quindi vengono provate le varianti piu' comuni.
  static double? _latOf(Map<String, dynamic> item) =>
      _numOf(item, const ['lat', 'latitude']);

  static double? _lonOf(Map<String, dynamic> item) =>
      _numOf(item, const ['lon', 'lng', 'long', 'longitude']);

  static double? _numOf(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = double.tryParse(item[key]?.toString() ?? '');
      if (value != null) return value;
    }
    return null;
  }

  /// Frazioni di Corbetta: sono territorio comunale, ma il geocoder puo'
  /// metterle al posto del comune (village = "Castellazzo de' Stampi").
  static const List<String> _frazioniCorbetta = [
    'castellazzo de\' stampi',
    'castellazzo de stampi',
    'cerello',
    'soriano',
    'battuello',
  ];

  /// Nome che identifica il territorio di Corbetta.
  static bool _isCorbettaName(String name) =>
      name == 'corbetta' || _frazioniCorbetta.contains(name);

  /// Chiavi con cui il geocoder puo' indicare il comune del risultato.
  static const List<String> _comuneKeys = [
    'comune',
    'municipality',
    'city',
    'town',
    'village',
  ];

  /// Comune del risultato, minuscolo. Prima i campi strutturati (anche
  /// dentro `address`), poi il display_name: in Nominatim il comune e'
  /// uno dei pezzi separati da virgola.
  static String? _comuneOf(Map<String, dynamic> item) {
    final address = item['address'];
    final maps = [item, if (address is Map) address];
    for (final map in maps) {
      for (final key in _comuneKeys) {
        final value = map[key]?.toString().trim().toLowerCase();
        if (value != null && value.isNotEmpty) return value;
      }
    }
    return null;
  }

  /// Pezzo di indirizzo fatto di solo civico: "12", "12a", "12/A".
  static final RegExp _soloCivicoRe =
      RegExp(r'^\d{1,4}(?:\s*[/-]\s*)?[a-zA-Z]?$');

  /// Numero civico restituito dal geocoder nei campi strutturati.
  static String? _civicoOf(Map<String, dynamic> item) {
    final address = item['address'];
    final maps = [item, if (address is Map) address];
    for (final map in maps) {
      for (final key in const ['house_number', 'housenumber', 'civico']) {
        final value = map[key]?.toString().trim();
        if (value != null && value.isNotEmpty) return value;
      }
    }
    return null;
  }

  /// Indirizzo mostrato e salvato, col civico attaccato alla via:
  /// "Via Roma 12, Corbetta, …". Nominatim lo mette davanti ("12, Via
  /// Roma, …") e va spostato; se il geocoder non ce l'ha si tiene quello
  /// scritto a mano, che altrimenti andrebbe perso.
  static String _addressLabel(
    Map<String, dynamic> item, {
    String? civicoDigitato,
  }) {
    final parts = (item['display_name'] as String? ?? '')
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';

    // Civico in testa al display_name: passa in coda alla via.
    if (parts.length >= 2 && _soloCivicoRe.hasMatch(parts.first)) {
      final civico = parts.removeAt(0);
      parts[0] = '${parts[0]} $civico';
      return parts.join(', ');
    }

    final civico = _civicoOf(item) ?? civicoDigitato;
    // Nessun numero nella via: si aggiunge quello noto.
    if (civico != null && !parts.first.contains(RegExp(r'\d'))) {
      parts[0] = '${parts[0]} $civico';
    }
    return parts.join(', ');
  }

  /// Pezzi del display_name, minuscoli: "Via Corbetta, Vittuone, …"
  /// diventa ['via corbetta', 'vittuone', …].
  static List<String> _addressParts(Map<String, dynamic> item) =>
      (item['display_name'] as String? ?? '')
          .toLowerCase()
          .split(',')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();

  /// Indirizzo che nomina Corbetta o una sua frazione: serve a fidarsi
  /// di un indirizzo gia' salvato senza doverlo ricercare di nuovo.
  static bool _addressNamesCorbetta(String address) =>
      _addressParts({'display_name': address}).any(_isCorbettaName);

  /// Tiene solo le vie di Corbetta. Regola secca: passa unicamente il
  /// risultato che risulta di Corbetta; in ogni altro caso, comune
  /// diverso o indirizzo non riconoscibile, viene scartato.
  static List<Map<String, dynamic>> _onlyCorbetta(
      List<Map<String, dynamic>> results) {
    return results.where(_isCorbettaResult).toList();
  }

  static bool _isCorbettaResult(Map<String, dynamic> item) {
    final lat = _latOf(item);
    final lon = _lonOf(item);
    // Con coordinate note vale anche il bounding box, che pero' da solo
    // non basta: e' un rettangolo che contiene Vittuone e altri comuni.
    if (lat != null && lon != null && !_isInCorbetta(lat, lon)) return false;

    // Il comune dichiarato decide da solo.
    final comune = _comuneOf(item);
    if (comune != null) return _isCorbettaName(comune);

    // Senza campo comune serve comunque una conferma esplicita nel
    // display_name, confrontando i pezzi interi e non come sottostringhe:
    // "Via Corbetta, Vittuone" e' una via di Vittuone, non di Corbetta.
    return _addressParts(item).any(_isCorbettaName);
  }

  void _selectSuggestion(Map<String, dynamic> item) {
    // Il civico scritto a mano resta nell'indirizzo anche quando il
    // geocoder ha trovato solo la via.
    final display = _addressLabel(
      item,
      civicoDigitato: _civicoDigitato(_addressController.text),
    );
    final lat = _latOf(item);
    final lon = _lonOf(item);
    _addressController.text = display;
    _addressFocus.unfocus();
    setState(() {
      _latitude = lat;
      _longitude = lon;
      _confirmedAddress = display;
      _suggestions = [];
      _noResults = false;
      _error = null;
    });
  }

  // ── Avviso fuori territorio ────────────────────────────────────

  /// Scarta la posizione appena presa e avvisa: senza conferma che sia
  /// di Corbetta non viene mai tenuta.
  Future<void> _rejectPosition(String message) async {
    if (!mounted) return;
    setState(() {
      _latitude = null;
      _longitude = null;
      _confirmedAddress = null;
      _locating = false;
      _error = null;
    });
    await _showOutsideCorbettaDialog(message: message);
  }

  /// Popup bloccante mostrato quando la posizione e' fuori da Corbetta.
  Future<void> _showOutsideCorbettaDialog({String? message}) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: const [
            Icon(Icons.location_off_outlined, color: Colors.redAccent, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Fuori dal Comune di Corbetta',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message ??
              'Ti trovi fuori dal territorio di Corbetta.\n'
                  'Sono ammesse solo segnalazioni nel Comune di Corbetta: '
                  'cerca un indirizzo di Corbetta per proseguire.',
          style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Chiudi',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                color: Color(0xFF7BA566),
              ),
            ),
          ),
        ],
      ),
    );
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
        await _rejectPosition(
          'Ti trovi fuori dal territorio di Corbetta e la posizione non '
          'puo\' essere accettata.\n'
          'Sono ammesse solo segnalazioni nel Comune di Corbetta: cerca un '
          'indirizzo di Corbetta per proseguire.',
        );
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
    if (!mounted) return;

    // Senza risposta del geocoder il Comune non e' verificabile: la
    // posizione non viene tenuta, come se fosse fuori territorio.
    if (data == null) {
      await _rejectPosition(
        'Non e\' stato possibile verificare che la tua posizione sia nel '
        'Comune di Corbetta.\n'
        'Riprova oppure cerca un indirizzo di Corbetta.',
      );
      return;
    }

    // L'indirizzo trovato deve risultare di Corbetta: il bounding box da
    // solo non basta, e' un rettangolo che contiene anche i confinanti.
    if (!_isCorbettaLocation(data)) {
      await _rejectPosition(
        'L\'indirizzo della tua posizione non e\' nel Comune di Corbetta '
        'e non puo\' essere accettato.\n'
        'Sono ammesse solo segnalazioni nel Comune di Corbetta: cerca un '
        'indirizzo di Corbetta per proseguire.',
      );
      return;
    }

    // Senza un indirizzo da mostrare non c'e' niente da confermare: le
    // coordinate da sole non bastano.
    final display = (data['address'] as String? ?? '').trim();
    if (display.isEmpty) {
      await _rejectPosition(
        'Non e\' stato possibile ricavare l\'indirizzo della tua posizione.\n'
        'Riprova oppure cerca un indirizzo di Corbetta.',
      );
      return;
    }

    setState(() {
      _addressController.text = display;
      _confirmedAddress = display;
      _suggestions = [];
      _noResults = false;
    });
  }

  /// Esito del reverse geocoding: si accetta solo con una conferma
  /// esplicita di Corbetta, mai per mancanza di segnali contrari.
  static bool _isCorbettaLocation(Map<String, dynamic> data) {
    // Il server dice di no: chiuso qui.
    if (data['in_corbetta'] == false) return false;

    // L'indirizzo restituito arriva come stringa: viene letto con gli
    // stessi criteri dei suggerimenti.
    final item = <String, dynamic>{
      ...data,
      'display_name': data['address'] as String? ?? '',
    };

    final comune = _comuneOf(item);
    if (comune != null) return _isCorbettaName(comune);
    if (_addressParts(item).any(_isCorbettaName)) return true;

    // Nessun comune leggibile nell'indirizzo: vale solo il si' esplicito
    // del server, altrimenti si scarta.
    return data['in_corbetta'] == true;
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

  /// Salva la bozza solo sul dispositivo: non viene inviata al Comune
  /// e resta grigia nel filtro "In creazione" finche' non si preme INVIA.
  Future<void> _saveDraft() => _save(draft: true);

  Future<void> _save({required bool draft}) async {
    if (draft) {
      // La bozza puo' restare incompleta: si aggiungono foto e dettagli
      // in un secondo momento, prima di inviarla.
      if (!_hasContent) {
        setState(() =>
            _error = 'Inserisci almeno una descrizione o un indirizzo.');
        return;
      }
    } else {
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
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    // La bozza resta sul telefono: nessuna chiamata al server.
    if (draft) {
      await DraftStore.save(
        reportType: widget.reportType,
        details: _detailsController.text.trim(),
        address: _addressController.text.trim(),
        latitude: _latitude?.toString(),
        longitude: _longitude?.toString(),
        imagePaths: _images.map((x) => x.path).toList(),
        localId: _draftId,
      );
      if (!mounted) return;
      setState(() => _loading = false);
      _finish(_isEditingDraft
          ? 'Bozza aggiornata.'
          : 'Bozza salvata solo su questo dispositivo.');
      return;
    }

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
      // Inviata: la copia locale non serve piu'.
      if (_draftId != null) await DraftStore.delete(_draftId!);
      if (!mounted) return;
      _finish('Segnalazione inviata.');
    } else {
      setState(() =>
          _error = result['message'] as String? ?? 'Errore durante l\'invio.');
    }
  }

  /// Conferma e chiude il form: tornando alla scheda se si stava
  /// modificando una bozza, altrimenti all'elenco delle segnalazioni.
  void _finish(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF7BA566),
        content: Text(message, style: const TextStyle(fontFamily: 'Inter')),
      ),
    );
    if (_isEditingDraft) {
      Navigator.pop(context);
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const SegnalazioniScreen()),
    );
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
        title: Text(
          _isEditingDraft ? 'Modifica bozza' : 'Nuova Segnalazione',
          style: const TextStyle(
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
                          suffixIcon: _addressStatusIcon(),
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
                            // In elenco si legge gia' col civico in coda
                            // alla via, come verra' salvato.
                            final name = _addressLabel(
                              e.value,
                              civicoDigitato:
                                  _civicoDigitato(_addressController.text),
                            );
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
                                  // l'anteprima e' 80px: decodificare la foto
                                  // a piena risoluzione sprecherebbe memoria
                                  cacheWidth: 240,
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
          BottomActionBar(
            children: [
              // Annulla · Salva come bozza: i pulsanti piccoli stanno
              // sempre sopra l'azione principale.
              Row(
                children: [
                  Expanded(
                    child: SecondaryBarButton.neutral(
                      label: 'Annulla',
                      onPressed: _loading ? null : _cancel,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SecondaryBarButton.green(
                      label: 'Salva bozza',
                      onPressed: _loading ? null : _saveDraft,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              PrimaryBarButton(
                label: 'INVIA',
                loading: _loading,
                onPressed: _submit,
              ),
            ],
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
