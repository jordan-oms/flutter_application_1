import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'home_screen.dart';
import 'chantier_plus_screen.dart';
import 'role_selection_screen.dart';
import '../widgets/tranche_selector.dart';

class LocalogScreen extends StatefulWidget {
  final String userId;

  const LocalogScreen({super.key, required this.userId});

  @override
  State<LocalogScreen> createState() => _LocalogScreenState();
}

class _LocalogScreenState extends State<LocalogScreen> {
  final Color oMSGreen = const Color(0xFF8EBB21);
  late MobileScannerController cameraController;
  final TextEditingController _searchController = TextEditingController();
  bool _isScannerOpen = false;
  final List<String> _materiels = ['UFS', 'BFS', 'SPMB', 'Déprimogène'];
  Map<String, dynamic>? _currentInventoryItem;

  // Rôles et permissions
  bool _hasConsignes = false;
  bool _hasAMCR = false;
  bool _hasCAPILog = false;
  bool _hasLocaLog = false;
  String _currentUserNomPrenom = "Chargement...";
  String _roleDisplay = "Chargement...";
  List<String> _userRoles = [];

  // Filtres
  String _searchQuery = '';
  String? _selectedFilterTR;
  String? _selectedFilterRetour;

  @override
  void initState() {
    super.initState();
    cameraController = MobileScannerController();
    _fetchUserPermissions();
  }

  Future<void> _fetchUserPermissions() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('utilisateurs')
          .doc(widget.userId)
          .get();

      if (userDoc.exists && mounted) {
        final data = userDoc.data()!;
        setState(() {
          _hasConsignes = data['isConsignes'] == true;
          _hasAMCR = data['isAMCR'] == true;
          _hasCAPILog = data['isCAPILog'] == true;
          _hasLocaLog = data['isLocaLog'] == true;
          _currentUserNomPrenom =
              "${data['prenom'] ?? ''} ${data['nom'] ?? ''}".trim();
          _userRoles = List<String>.from(data['roles'] ?? []);

          if (_userRoles.contains('administrateur')) {
            _roleDisplay = "Administrateur";
            _hasConsignes = true;
            _hasAMCR = true;
            _hasCAPILog = true;
            _hasLocaLog = true;
          } else if (_userRoles.contains('chef_de_chantier') ||
              _userRoles.contains('chef_de_chantier_amcr')) {
            _roleDisplay = "Chef de Chantier";
          } else if (_userRoles.contains('chef_equipe') ||
              _userRoles.contains('chef_equipe_amcr')) {
            _roleDisplay = "Chef d'Équipe";
          } else {
            _roleDisplay = "Intervenant";
          }
        });
      }
    } catch (e) {
      debugPrint("Erreur lors de la récupération des permissions: $e");
    }
  }

  @override
  void dispose() {
    cameraController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _openScanner() async {
    setState(() => _isScannerOpen = true);
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => QRScannerScreen(controller: cameraController),
      ),
    );
    setState(() => _isScannerOpen = false);

    if (result != null && result.isNotEmpty) {
      await _handleQRCodeScanned(result);
    }
  }

  Future<void> _handleQRCodeScanned(String qrCode) async {
    try {
      print('QR Code scanné : $qrCode');
      // Nettoyage du code QR pour l'utiliser comme ID Firestore (pas de /)
      final sanitizedId = qrCode.replaceAll('/', '_').replaceAll(' ', '_');

      final auth = FirebaseAuth.instance;
      final currentUser = auth.currentUser;
      if (currentUser == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Erreur: Utilisateur non authentifié'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final firestore = FirebaseFirestore.instance;
      final inventoryDoc = await firestore
          .collection('localog_inventory')
          .doc(sanitizedId)
          .get();

      if (mounted) {
        if (inventoryDoc.exists) {
          final data = inventoryDoc.data();
          setState(() => _currentInventoryItem = data);
          _showInventoryDialog(sanitizedId, isExisting: true, data: data);
        } else {
          setState(() => _currentInventoryItem = null);
          _showInventoryDialog(sanitizedId, isExisting: false);
        }
      }
    } catch (e) {
      print('Erreur Firestore lors du scan : $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur Cloud : $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showInventoryDialog(String qrCode,
      {required bool isExisting, Map<String, dynamic>? data}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => InventoryFormDialog(
        qrCode: qrCode,
        isExisting: isExisting,
        initialData: data ?? _currentInventoryItem,
        userId: widget.userId,
        materiels: _materiels,
      ),
    );
  }

  void _showManualEntryDialog() {
    final TextEditingController manualController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Saisie manuelle'),
        content: TextField(
          controller: manualController,
          decoration: const InputDecoration(
            labelText: 'Code QR ou Identifiant',
            hintText: 'Entrez le code ici',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            // On peut ajouter des filtres ici si certains caractères sont interdits
            // Pour l'instant on force juste l'éventuelle casse si besoin,
            // bien que le handleQRCodeScanned s'occupe du nettoyage Firestore
            TextInputFormatter.withFunction((oldValue, newValue) {
              return newValue.copyWith(text: newValue.text.toUpperCase());
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              final code = manualController.text.trim().toUpperCase();
              if (code.isNotEmpty) {
                Navigator.pop(ctx);
                _handleQRCodeScanned(code);
              }
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int interfacesCount = 0;
    if (_hasConsignes) interfacesCount++;
    if (_hasAMCR) interfacesCount++;
    if (_hasCAPILog) interfacesCount++;
    if (_hasLocaLog) interfacesCount++;

    final bool showSwitcher = interfacesCount > 1;

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: showSwitcher
              ? () {
                  showModalBottomSheet(
                    context: context,
                    builder: (context) => SafeArea(
                      child: Wrap(
                        children: [
                          if (_hasConsignes)
                            ListTile(
                              leading: Image.asset('assets/images/icon1.png',
                                  height: 24,
                                  errorBuilder: (c, e, s) => const Icon(
                                      Icons.assignment_outlined,
                                      color: Colors.green)),
                              title: const Text("Interface Consignes"),
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => HomeScreen(
                                      userId: widget.userId,
                                      interfaceType: 'consignes',
                                    ),
                                  ),
                                );
                              },
                            ),
                          if (_hasAMCR)
                            ListTile(
                              leading: Image.asset('assets/images/AMCR.png',
                                  height: 24,
                                  errorBuilder: (c, e, s) => const Icon(
                                      Icons.engineering_outlined,
                                      color: Colors.blueGrey)),
                              title: const Text("Interface AMCR"),
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => HomeScreen(
                                      userId: widget.userId,
                                      interfaceType: 'amcr',
                                    ),
                                  ),
                                );
                              },
                            ),
                          if (_hasCAPILog)
                            ListTile(
                              leading: Image.asset('assets/images/CAPILog.png',
                                  height: 24,
                                  errorBuilder: (c, e, s) => const Icon(
                                      Icons.business,
                                      color: Colors.blue)),
                              title: const Text("Interface CAPILog"),
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const ChantierPlusScreen(),
                                    maintainState: true,
                                  ),
                                );
                              },
                            ),
                          if (_hasLocaLog)
                            ListTile(
                              leading: Image.asset('assets/images/LocaLog.png',
                                  height: 24,
                                  errorBuilder: (c, e, s) => const Icon(
                                      Icons.location_on,
                                      color: Colors.blueGrey)),
                              title: const Text("Interface LocaLog"),
                              subtitle: const Text("Interface actuelle"),
                              onTap: () => Navigator.pop(context),
                            ),
                        ],
                      ),
                    ),
                  );
                }
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'LOCALOG - Inventaire Matériel',
                      style: TextStyle(fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Text(
                      "Mode: $_roleDisplay ($_currentUserNomPrenom)",
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.normal),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              if (showSwitcher)
                const Padding(
                  padding: EdgeInsets.only(left: 4.0),
                  child: Icon(Icons.arrow_drop_down, color: Colors.white70),
                ),
            ],
          ),
        ),
        backgroundColor: oMSGreen,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Se déconnecter",
            onPressed: () => RoleSelectionScreen.forceSignOut(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Icon(Icons.inventory_2, color: Colors.blueGrey),
                const SizedBox(width: 10),
                Text(
                  'Matériels Inventoriés',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.blueGrey,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (value) =>
                      setState(() => _searchQuery = value.toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Rechercher matériel, local, QR...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: (_searchQuery.isNotEmpty ||
                            _selectedFilterTR != null ||
                            _selectedFilterRetour != null)
                        ? IconButton(
                            icon: const Icon(Icons.filter_list_off,
                                color: Colors.red),
                            onPressed: () => setState(() {
                              _searchController.clear();
                              _searchQuery = '';
                              _selectedFilterTR = null;
                              _selectedFilterRetour = null;
                            }),
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedFilterTR,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'TR',
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 10),
                        ),
                        items: [
                          const DropdownMenuItem(
                              value: null,
                              child: Text('Toutes',
                                  overflow: TextOverflow.ellipsis)),
                          ...List.generate(10, (index) => index.toString())
                              .map((val) => DropdownMenuItem(
                                    value: val,
                                    child: Text('TR $val',
                                        overflow: TextOverflow.ellipsis),
                                  )),
                        ],
                        onChanged: (val) =>
                            setState(() => _selectedFilterTR = val),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedFilterRetour,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Retour',
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 10),
                        ),
                        items: [
                          const DropdownMenuItem(
                              value: null,
                              child: Text('Tous',
                                  overflow: TextOverflow.ellipsis)),
                          ...[
                            'SUT',
                            'atelier chaud',
                            'BSI',
                            'Magasin BAN7',
                            'Magasin BAN8',
                            'Magasin BAN9'
                          ].map((val) => DropdownMenuItem(
                                value: val,
                                child:
                                    Text(val, overflow: TextOverflow.ellipsis),
                              )),
                        ],
                        onChanged: (val) =>
                            setState(() => _selectedFilterRetour = val),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _buildInventoryList(),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'manual_btn',
            onPressed: _showManualEntryDialog,
            backgroundColor: Colors.blueGrey,
            child: const Icon(Icons.keyboard, color: Colors.white),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'scanner_btn',
            onPressed: _isScannerOpen ? null : _openScanner,
            backgroundColor: oMSGreen,
            child: const Icon(Icons.qr_code_scanner, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('localog_inventory')
          .orderBy('lastUpdatedTime', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          print('Firestore Error: ${snapshot.error}');
          return Center(
            child: Text(
              'Erreur de chargement\n${snapshot.error.toString().contains('index') ? 'Index manquant' : ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: Colors.red),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        // Application des filtres côté client
        final filteredDocs = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;

          // Filtre Recherche (Matériel ou Local ou QR)
          bool matchesSearch = true;
          if (_searchQuery.isNotEmpty) {
            final materiel = (data['materiel'] ?? '').toString().toLowerCase();
            final local = (data['local'] ?? '').toString().toLowerCase();
            final qr = doc.id.toLowerCase();
            matchesSearch = materiel.contains(_searchQuery) ||
                local.contains(_searchQuery) ||
                qr.contains(_searchQuery);
          }

          // Filtre TR
          bool matchesTR = true;
          if (_selectedFilterTR != null) {
            matchesTR = data['tr']?.toString() == _selectedFilterTR;
          }

          // Filtre Retour
          bool matchesRetour = true;
          if (_selectedFilterRetour != null) {
            matchesRetour = data['retour']?.toString() == _selectedFilterRetour;
          }

          return matchesSearch && matchesTR && matchesRetour;
        }).toList();

        if (filteredDocs.isEmpty) {
          return const Center(
              child: Text('Aucun matériel ne correspond à ces critères'));
        }

        return ListView.builder(
          itemCount: filteredDocs.length,
          itemBuilder: (ctx, index) {
            final data = filteredDocs[index].data() as Map<String, dynamic>;
            final qrCode = filteredDocs[index].id;

            // Logique de couleur et alertes (HS et Recalification)
            bool isHS = data['hs'] == true;
            bool isNearRecalification = false;
            final validityStr = data['validityDate'];
            if (validityStr != null && validityStr != 'N/A') {
              try {
                final validityDate = DateTime.parse(validityStr);
                final now = DateTime.now();
                // On normalise à minuit pour comparer des jours pleins
                final today = DateTime(now.year, now.month, now.day);
                final difference = validityDate.difference(today).inDays;

                // Alerte si <= 15 jours OU si c'est un dimanche (indépendamment du délai)
                if (difference <= 15 ||
                    validityDate.weekday == DateTime.sunday) {
                  isNearRecalification = true;
                }
              } catch (_) {}
            }

            Color cardColor = Colors.white;
            if (isNearRecalification) {
              cardColor =
                  Colors.red.shade50; // Rouge prioritaire pour recalification
            } else if (isHS) {
              cardColor = Colors.blue.shade50; // Bleu si HS uniquement
            }

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              elevation: 2,
              color: cardColor,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isNearRecalification
                      ? Colors.red.shade100
                      : (isHS ? Colors.blue.shade100 : Colors.blueGrey.shade50),
                  child: Icon(
                    isHS ? Icons.warning_amber : Icons.inventory_2,
                    color: isNearRecalification
                        ? Colors.red
                        : (isHS ? Colors.blue : Colors.blueGrey),
                  ),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        data['materiel'] ?? 'N/A',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (isHS) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'HS',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (isNearRecalification) const SizedBox(width: 4),
                    ],
                    if (isNearRecalification)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Recalification',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (data['retour'] != null &&
                        data['retour'].toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          'RETOUR: ${data['retour']}',
                          style: TextStyle(
                            color: Colors.orange.shade900,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      )
                    else
                      Text(
                        'Local: ${(data['local'] == null || data['local'].toString().isEmpty) ? 'N/A' : data['local']}${data['tr'] != null ? ' | TR: ${data['tr']}' : ''}',
                      ),
                    const SizedBox(height: 2),
                    Text(
                      'QR: $qrCode',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    _showInventoryDialog(qrCode, isExisting: true, data: data),
              ),
            );
          },
        );
      },
    );
  }
}

class QRScannerScreen extends StatefulWidget {
  final MobileScannerController controller;

  const QRScannerScreen({super.key, required this.controller});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  String? _scannedCode;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner QR Code'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: MobileScanner(
        controller: widget.controller,
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
          if (barcodes.isNotEmpty && _scannedCode == null) {
            final code = barcodes.first.rawValue ?? '';
            setState(() => _scannedCode = code);
            Navigator.pop(context, code);
          }
        },
      ),
    );
  }
}

class InventoryFormDialog extends StatefulWidget {
  final String qrCode;
  final bool isExisting;
  final Map<String, dynamic>? initialData;
  final String userId;
  final List<String> materiels;

  const InventoryFormDialog({
    super.key,
    required this.qrCode,
    required this.isExisting,
    this.initialData,
    required this.userId,
    required this.materiels,
  });

  @override
  State<InventoryFormDialog> createState() => _InventoryFormDialogState();
}

class _InventoryFormDialogState extends State<InventoryFormDialog> {
  String _selectedMateriel = '';
  DateTime? _validityDate;
  final TextEditingController _localController = TextEditingController();
  final TextEditingController _motifHSController = TextEditingController();
  bool _isHS = false;
  String? _selectedTR;
  String? _selectedRetour;
  bool _isLoading = false;
  bool _showHistory = false;
  List<String> _filteredMateriels = [];

  final List<String> _retourOptions = [
    'SUT',
    'atelier chaud',
    'BSI',
    'Magasin BAN7',
    'Magasin BAN8',
    'Magasin BAN9',
  ];

  @override
  void initState() {
    super.initState();
    String initialLocal = '';
    String initialMotifHS = '';

    if (widget.isExisting && widget.initialData != null) {
      _selectedMateriel =
          (widget.initialData!['materiel'] ?? '').toString().trim();
      initialLocal = widget.initialData!['local'] ?? '';
      _isHS = widget.initialData!['hs'] ?? false;
      initialMotifHS = widget.initialData!['motifHS'] ?? '';
      final validityStr = widget.initialData!['validityDate'];
      _validityDate =
          validityStr != null ? DateTime.tryParse(validityStr) : null;
      _selectedTR = widget.initialData!['tr']?.toString();
      _selectedRetour = widget.initialData!['retour']?.toString();
    } else {
      _selectedMateriel =
          widget.materiels.isNotEmpty ? widget.materiels.first : '';
      _validityDate = null;
      _selectedTR = null;
      _selectedRetour = null;
      _isHS = false;
    }

    _localController.text = initialLocal;
    _motifHSController.text = initialMotifHS;

    // Initialisation sécurisée de la liste des matériels
    _updateFilteredMateriels();
  }

  void _updateFilteredMateriels() {
    // Nettoyage de la liste de base
    final allPossible = widget.materiels.map((m) => m.trim()).toSet().toList();

    // Gestion de la valeur sélectionnée pour éviter les crashs de DropdownButton
    if (_selectedMateriel.isNotEmpty) {
      // Vérifier s'il y a un match exact (case-sensitive)
      bool hasExactMatch = allPossible.contains(_selectedMateriel);

      if (!hasExactMatch) {
        // Chercher un match insensible à la casse
        try {
          final caseInsensitiveMatch = allPossible.firstWhere(
            (m) => m.toLowerCase() == _selectedMateriel.toLowerCase(),
          );
          // Si on trouve un match avec une casse différente, on adopte la casse officielle
          _selectedMateriel = caseInsensitiveMatch;
        } catch (_) {
          // Si aucun match du tout, on ajoute la valeur actuelle comme option valide
          allPossible.add(_selectedMateriel);
        }
      }
    }

    _filteredMateriels = allPossible;
  }

  @override
  void dispose() {
    _localController.dispose();
    _motifHSController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _validityDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (pickedDate != null) {
      setState(() => _validityDate = pickedDate);
    }
  }

  Future<void> _saveInventory() async {
    final localValue = _localController.text.trim().toUpperCase();
    final motifHSValue = _motifHSController.text.trim();

    // Validation
    if (_selectedRetour == null) {
      if (localValue.isEmpty || _selectedTR == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Le local et la TR sont obligatoires'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    if (_isHS && motifHSValue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez renseigner le motif HS'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final auth = FirebaseAuth.instance;
      final currentUser = auth.currentUser;
      if (currentUser == null) throw Exception('Utilisateur non authentifié');

      final firestore = FirebaseFirestore.instance;
      final userDoc =
          await firestore.collection('utilisateurs').doc(currentUser.uid).get();
      final userData = userDoc.data() ?? {};

      final timestamp = DateTime.now();
      final formattedDate = DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp);

      // Préparer les données d'inventaire
      Map<String, dynamic> inventoryData = {
        'qrCode': widget.qrCode,
        'materiel': _selectedMateriel,
        'local': localValue,
        'tr': _selectedTR,
        'retour': _selectedRetour,
        'hs': _isHS,
        'motifHS': _isHS ? motifHSValue : '',
        'validityDate': _validityDate?.toIso8601String() ?? 'N/A',
        'lastUpdatedBy': {
          'uid': currentUser.uid,
          'nom': userData['nom'] ?? 'N/A',
          'prenom': userData['prenom'] ?? 'N/A',
          'roles': userData['roles'] ?? [],
        },
        'lastUpdatedAt': formattedDate,
        'lastUpdatedTime': timestamp,
      };

      // Si c'est une modification, ajouter à l'historique
      if (widget.isExisting && widget.initialData != null) {
        List<Map<String, dynamic>> history = List<Map<String, dynamic>>.from(
            widget.initialData!['history'] ?? []);

        // On enregistre les changements précis
        Map<String, dynamic> changes = {};
        if (widget.initialData!['materiel'] != _selectedMateriel) {
          changes['materiel'] = {
            'old': widget.initialData!['materiel'],
            'new': _selectedMateriel
          };
        }
        if (widget.initialData!['local'] != localValue) {
          changes['local'] = {
            'old': widget.initialData!['local'],
            'new': localValue
          };
        }
        if (widget.initialData!['tr']?.toString() != _selectedTR) {
          changes['tr'] = {
            'old': widget.initialData!['tr'],
            'new': _selectedTR
          };
        }
        if (widget.initialData!['retour']?.toString() != _selectedRetour) {
          changes['retour'] = {
            'old': widget.initialData!['retour'],
            'new': _selectedRetour
          };
        }
        if ((widget.initialData!['hs'] ?? false) != _isHS) {
          changes['hs'] = {
            'old': widget.initialData!['hs'] == true ? 'Oui' : 'Non',
            'new': _isHS ? 'Oui' : 'Non'
          };
        }
        if (widget.initialData!['motifHS'] != (_isHS ? motifHSValue : '')) {
          changes['motifHS'] = {
            'old': widget.initialData!['motifHS'],
            'new': _isHS ? motifHSValue : ''
          };
        }
        if (widget.initialData!['validityDate'] !=
            (_validityDate?.toIso8601String() ?? 'N/A')) {
          changes['validityDate'] = {
            'old': widget.initialData!['validityDate'],
            'new': _validityDate?.toIso8601String() ?? 'N/A'
          };
        }

        if (changes.isNotEmpty) {
          history.add({
            'timestamp': formattedDate,
            'action': 'modification',
            'changes': changes,
            'modifiedBy': {
              'uid': currentUser.uid,
              'nom': userData['nom'] ?? 'N/A',
              'prenom': userData['prenom'] ?? 'N/A',
              'roles': userData['roles'] ?? [],
            },
          });
        }
        inventoryData['history'] = history;
      } else {
        // Première saisie
        inventoryData['history'] = [
          {
            'timestamp': formattedDate,
            'action': 'création',
            'data': {
              'materiel': _selectedMateriel,
              'local': localValue,
              'tr': _selectedTR,
              'retour': _selectedRetour,
              'hs': _isHS,
              'motifHS': _isHS ? motifHSValue : '',
              'validityDate': _validityDate?.toIso8601String() ?? 'N/A',
            },
            'createdBy': {
              'uid': currentUser.uid,
              'nom': userData['nom'] ?? 'N/A',
              'prenom': userData['prenom'] ?? 'N/A',
              'roles': userData['roles'] ?? [],
            },
          }
        ];
      }

      // Enregistrer dans Firestore
      await firestore
          .collection('localog_inventory')
          .doc(widget.qrCode)
          .set(inventoryData, SetOptions(merge: true));

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Inventaire enregistré avec succès'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Inventaire Matériel',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // QR Code (non modifiable)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Code QR',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.qrCode,
                      style: const TextStyle(
                        fontSize: 14,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Sélection de matériel
              const Text(
                'Matériel*',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              DropdownButton<String>(
                isExpanded: true,
                // On s'assure que la valeur existe exactement une fois dans la liste affichée
                value: _filteredMateriels.contains(_selectedMateriel)
                    ? _selectedMateriel
                    : null,
                items: _filteredMateriels.toSet().map((m) {
                  return DropdownMenuItem<String>(
                    value: m,
                    child: Text(m),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedMateriel = val;
                    });
                  }
                },
                hint: const Text('Sélectionner un matériel'),
              ),
              const SizedBox(height: 16),
              // Local et TR
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Local*',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _localController,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [
                            TextInputFormatter.withFunction((old, newValue) {
                              return newValue.copyWith(
                                  text: newValue.text.toUpperCase());
                            }),
                          ],
                          onChanged: (val) {
                            if (val.isNotEmpty && _selectedRetour != null) {
                              setState(() => _selectedRetour = null);
                            }
                          },
                          decoration: InputDecoration(
                            hintText: 'Local',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TR',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: _selectedTR,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          items: List.generate(10, (index) => index.toString())
                              .map((val) => DropdownMenuItem(
                                    value: val,
                                    child: Text(val),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedTR = val;
                              if (val != null && _selectedRetour != null) {
                                _selectedRetour = null;
                              }
                            });
                          },
                          hint:
                              const Text('0-9', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Retour
              const Text(
                'Retour',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: _selectedRetour,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                items: _retourOptions
                    .map((val) => DropdownMenuItem(
                          value: val,
                          child: Text(val),
                        ))
                    .toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedRetour = val;
                    if (val != null) {
                      _localController.clear();
                      _selectedTR = null;
                    }
                  });
                },
                hint: const Text('Sélectionner un lieu de retour'),
              ),
              const SizedBox(height: 16),
              // Date de validité
              const Text(
                'Date de fin de validité',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _validityDate != null
                          ? DateFormat('dd/MM/yyyy').format(_validityDate!)
                          : 'N/A',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _selectDate,
                    child: const Text('Sélectionner'),
                  ),
                  if (_validityDate != null)
                    TextButton.icon(
                      onPressed: () => setState(() => _validityDate = null),
                      icon: const Icon(Icons.clear, size: 18),
                      label: const Text('Effacer la date'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // Etat HS
              Row(
                children: [
                  const Text(
                    'Matériel HS ?',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Switch(
                    value: _isHS,
                    activeColor: Colors.red,
                    onChanged: (val) {
                      setState(() {
                        _isHS = val;
                      });
                    },
                  ),
                  Text(_isHS ? 'OUI' : 'NON',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _isHS ? Colors.red : Colors.green,
                      )),
                ],
              ),
              if (_isHS) ...[
                const SizedBox(height: 8),
                const Text(
                  'Motif HS*',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _motifHSController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Expliquez pourquoi le matériel est HS',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // Historique (si modification)
              if (widget.isExisting && widget.initialData?['history'] != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Historique',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => _showHistory = !_showHistory),
                          icon: Icon(
                            _showHistory
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 18,
                          ),
                          label: Text(_showHistory ? 'Masquer' : 'Ouvrir'),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_showHistory)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children:
                              (widget.initialData!['history'] as List<dynamic>)
                                  .reversed
                                  .map(
                            (item) {
                              final data = item as Map<String, dynamic>;

                              // Formatage de la date jj/MM/AA HH:mm
                              String displayDate = data['timestamp'] ?? 'N/A';
                              try {
                                DateTime dt = DateFormat('yyyy-MM-dd HH:mm:ss')
                                    .parse(displayDate);
                                displayDate =
                                    DateFormat('dd/MM/yy HH:mm').format(dt);
                              } catch (_) {}

                              List<String> details = [];
                              if (data['action'] == 'création') {
                                details.add('Création de l\'inventaire');
                              } else if (data['changes'] != null) {
                                final changes =
                                    data['changes'] as Map<String, dynamic>;
                                changes.forEach((key, val) {
                                  String oldV = (val['old'] == null ||
                                          val['old'].toString().isEmpty)
                                      ? 'vide'
                                      : val['old'].toString();
                                  String newV = (val['new'] == null ||
                                          val['new'].toString().isEmpty)
                                      ? 'vide'
                                      : val['new'].toString();

                                  // Traduction des clés pour l'affichage
                                  String keyLabel = key;
                                  if (key == 'local') keyLabel = 'local';
                                  if (key == 'tr') keyLabel = 'TR';
                                  if (key == 'retour') keyLabel = 'retour';
                                  if (key == 'materiel') keyLabel = 'matériel';
                                  if (key == 'hs') keyLabel = 'HS';
                                  if (key == 'motifHS') keyLabel = 'motif HS';
                                  if (key == 'validityDate') {
                                    keyLabel = 'date';
                                    // Formater les dates ISO en dd/MM/yyyy pour la lisibilité
                                    try {
                                      if (oldV != 'N/A') {
                                        oldV = DateFormat('dd/MM/yyyy')
                                            .format(DateTime.parse(oldV));
                                      }
                                      if (newV != 'N/A') {
                                        newV = DateFormat('dd/MM/yyyy')
                                            .format(DateTime.parse(newV));
                                      }
                                    } catch (_) {}
                                  }

                                  details.add('$keyLabel $oldV en $newV');
                                });
                              }

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$displayDate par ${data['modifiedBy']?['prenom'] ?? data['createdBy']?['prenom'] ?? ''} ${data['modifiedBy']?['nom'] ?? data['createdBy']?['nom'] ?? ''}',
                                      style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    ...details.map((d) => Text(
                                          '• $d',
                                          style: const TextStyle(fontSize: 9),
                                        )),
                                  ],
                                ),
                              );
                            },
                          ).toList(),
                        ),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
              // Boutons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: const Text('Annuler'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _saveInventory,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Valider'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
