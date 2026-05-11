import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:file_saver/file_saver.dart';
import 'home_screen.dart';
import 'chantier_plus_screen.dart';
import 'role_selection_screen.dart';

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
  bool _isExporting = false;
  final List<String> _materiels = [
    'UFS',
    'Bouteille',
    'Déprimogène',
    'MIP10',
    'Sonde MIP10',
    'SPMB',
    'BFS',
    'Rallonge Electrique',
    'Adaptateur Electrique',
    'MEDGV',
    'MEDCP',
    'Lot Canon lumière',
    'Orfo',
    'Pompe à membrane',
    'Nettoyeur HP',
    'Canon à Mousse',
    'Autre → Préciser'
  ];
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

  bool get _isAdmin => _userRoles.contains('administrateur');
  bool get _isChefChantier =>
      _userRoles.contains('chef_de_chantier') ||
      _userRoles.contains('chef_de_chantier_amcr');

  bool get _canExportExcel => _isAdmin || _isChefChantier;

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
      debugPrint('QR Code scanné : $qrCode');
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
      debugPrint('Erreur Firestore lors du scan : $e');
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
        isAdmin: _isAdmin,
      ),
    );
  }

  void _confirmDelete(String qrCode) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le matériel ?'),
        content: Text(
            'Voulez-vous vraiment supprimer définitivement le matériel $qrCode de l\'inventaire ? Cette action est irréversible.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await FirebaseFirestore.instance
                    .collection('localog_inventory')
                    .doc(qrCode)
                    .delete();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Matériel supprimé avec succès'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erreur lors de la suppression : $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child:
                const Text('Supprimer', style: TextStyle(color: Colors.white)),
          ),
        ],
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

  void _showScanChoice(bool isManual) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Type de saisie'),
        content: const Text(
            'Souhaitez-vous effectuer un scan unique ou un multi-scan ?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (isManual) {
                _showManualEntryDialog();
              } else {
                _openScanner();
              }
            },
            child: const Text('Unique'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startMultiScanFlow(isManual);
            },
            child: const Text('Multi-scan'),
          ),
        ],
      ),
    );
  }

  void _startMultiScanFlow(bool isManual) {
    final TextEditingController localController = TextEditingController();
    String? selectedTR;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Configuration Multi-scan'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Veuillez renseigner le local et la TR communs.'),
              const SizedBox(height: 16),
              TextField(
                controller: localController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Local',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedTR,
                decoration: const InputDecoration(
                  labelText: 'TR',
                  border: OutlineInputBorder(),
                ),
                items: List.generate(10, (index) => index.toString())
                    .map(
                        (val) => DropdownMenuItem(value: val, child: Text(val)))
                    .toList(),
                onChanged: (val) => setDialogState(() => selectedTR = val),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                if (localController.text.isNotEmpty && selectedTR != null) {
                  Navigator.pop(ctx);
                  if (isManual) {
                    _runManualMultiScan(
                        localController.text.toUpperCase(), selectedTR!);
                  } else {
                    _runCameraMultiScan(
                        localController.text.toUpperCase(), selectedTR!);
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Local et TR obligatoires')),
                  );
                }
              },
              child: const Text('Valider'),
            ),
          ],
        ),
      ),
    );
  }

  void _runManualMultiScan(String local, String tr) {
    final List<String> codes = [];
    final TextEditingController codeController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Saisie Multi-manuelle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Code QR',
                  hintText: 'Entrez un code',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add_circle, color: Colors.green),
                    onPressed: () {
                      final val = codeController.text.trim().toUpperCase();
                      if (val.isNotEmpty && !codes.contains(val)) {
                        setDialogState(() {
                          codes.add(val);
                          codeController.clear();
                        });
                      }
                    },
                  ),
                ),
                onSubmitted: (val) {
                  if (val.isNotEmpty && !codes.contains(val.toUpperCase())) {
                    setDialogState(() {
                      codes.add(val.toUpperCase());
                      codeController.clear();
                    });
                  }
                },
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 150,
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    children: codes
                        .map((c) => Chip(
                              label: Text(c),
                              onDeleted: () =>
                                  setDialogState(() => codes.remove(c)),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (codes.isNotEmpty) {
                  _showMultiScanSummary(codes, local, tr);
                }
              },
              child: const Text('Terminer'),
            ),
          ],
        ),
      ),
    );
  }

  void _runCameraMultiScan(String local, String tr) async {
    setState(() => _isScannerOpen = true);
    final List<String>? results = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => MultiQRScannerScreen(controller: cameraController),
      ),
    );
    setState(() => _isScannerOpen = false);

    if (results != null && results.isNotEmpty) {
      _showMultiScanSummary(results, local, tr);
    }
  }

  void _showMultiScanSummary(List<String> codes, String local, String tr) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => MultiScanSummaryDialog(
        codes: codes,
        local: local,
        tr: tr,
        userId: widget.userId,
        materiels: _materiels,
        isAdmin: _isAdmin,
      ),
    );
  }

  Future<void> _exportToExcel() async {
    setState(() => _isExporting = true);

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('localog_inventory')
          .get();

      final excel = Excel.createExcel();
      const String sheetName = "Inventaire";
      excel.rename(excel.getDefaultSheet()!, sheetName);
      final Sheet sheet = excel[sheetName];

      CellStyle headerStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#FFC0C0C0'),
        horizontalAlign: HorizontalAlign.Center,
      );

      final headers = [
        'QR Code',
        'Matériel',
        'Local',
        'TR',
        'Retour',
        'HS',
        'Motif HS',
        'DeD (mSv/h)',
        'Date Validité',
        'Dernière Maj',
        'Par',
        'Historique'
      ];

      for (var i = 0; i < headers.length; i++) {
        var cell =
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
      }

      for (int i = 0; i < querySnapshot.docs.length; i++) {
        final doc = querySnapshot.docs[i];
        final data = doc.data() as Map<String, dynamic>;
        final rowIndex = i + 1;

        // Formater l'historique complet pour l'Excel
        final List<dynamic> history = data['history'] ?? [];
        final String historyText = history.reversed.map((entry) {
          final String ts = entry['timestamp'] ?? 'N/A';
          final String action = entry['action'] ?? '';
          final String author =
              "${entry['modifiedBy']?['prenom'] ?? entry['createdBy']?['prenom'] ?? ''} ${entry['modifiedBy']?['nom'] ?? entry['createdBy']?['nom'] ?? ''}";

          String details = "";
          if (action == 'modification' && entry['changes'] != null) {
            final Map<String, dynamic> changes = entry['changes'];
            details = " (${changes.keys.join(', ')})";
          }
          return "[$ts] $author : $action$details";
        }).join(' | ');

        final rowData = [
          doc.id,
          data['materiel'] ?? '',
          data['local'] ?? '',
          data['tr']?.toString() ?? '',
          data['retour'] ?? '',
          (data['hs'] == true) ? 'OUI' : 'NON',
          data['motifHS'] ?? '',
          data['ded']?.toString() ?? '',
          data['validityDate'] ?? '',
          data['lastUpdatedAt'] ?? '',
          "${data['lastUpdatedBy']?['prenom'] ?? ''} ${data['lastUpdatedBy']?['nom'] ?? ''}",
          historyText
        ];

        for (var j = 0; j < rowData.length; j++) {
          sheet
              .cell(CellIndex.indexByColumnRow(
                  columnIndex: j, rowIndex: rowIndex))
              .value = TextCellValue(rowData[j].toString());
        }
      }

      final fileBytes = excel.encode();
      if (fileBytes == null) throw Exception("Erreur encodage Excel");

      final String fileName =
          "Inventaire_Localog_${DateTime.now().millisecondsSinceEpoch}";

      if (kIsWeb ||
          Platform.isWindows ||
          Platform.isMacOS ||
          Platform.isLinux) {
        // Utilisation de FileSaver pour Windows/Web/Desktop
        await FileSaver.instance.saveFile(
          name: '$fileName.xlsx',
          bytes: Uint8List.fromList(fileBytes),
          mimeType: MimeType.microsoftExcel,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Export terminé ! Consultez votre dossier Téléchargements.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // Pour Mobile (Android/iOS)
        final directory = await getTemporaryDirectory();
        final String filePath = '${directory.path}/$fileName.xlsx';
        final file = File(filePath);
        await file.writeAsBytes(fileBytes);
        await OpenFile.open(filePath);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erreur export : $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
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
          if (_canExportExcel) ...[
            FloatingActionButton.small(
              heroTag: 'excel_btn',
              onPressed: _isExporting ? null : _exportToExcel,
              backgroundColor: Colors.green.shade700,
              child: _isExporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.file_download, color: Colors.white),
            ),
            const SizedBox(height: 12),
          ],
          FloatingActionButton.small(
            heroTag: 'manual_btn',
            onPressed: () => _showScanChoice(true),
            backgroundColor: Colors.blueGrey,
            child: const Icon(Icons.keyboard, color: Colors.white),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'scanner_btn',
            onPressed: _isScannerOpen ? null : () => _showScanChoice(false),
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
          debugPrint('Firestore Error: ${snapshot.error}');
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'QR: $qrCode',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (data['lastUpdatedAt'] != null)
                          Builder(builder: (context) {
                            String displayMaJ =
                                data['lastUpdatedAt'].toString();
                            try {
                              DateTime dt = DateFormat('yyyy-MM-dd HH:mm:ss')
                                  .parse(displayMaJ);
                              displayMaJ =
                                  DateFormat('dd/MM/yyyy HH:mm').format(dt);
                            } catch (_) {
                              displayMaJ = displayMaJ.split(' ').first;
                            }
                            return Text(
                              'MaJ: $displayMaJ',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.grey.shade500),
                            );
                          }),
                      ],
                    ),
                    if (data['ded'] != null &&
                        data['ded'].toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.amber.shade800),
                          ),
                          child: Text(
                            'Dernier DeD: ${data['ded']} mSv/h',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isAdmin)
                      IconButton(
                        icon:
                            const Icon(Icons.delete_outline, color: Colors.red),
                        tooltip: 'Supprimer ce matériel',
                        onPressed: () => _confirmDelete(qrCode),
                      ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
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

class QRScannerScreen extends StatelessWidget {
  final MobileScannerController controller;
  const QRScannerScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner un QR Code'),
        backgroundColor: const Color(0xFF8EBB21),
        foregroundColor: Colors.white,
      ),
      body: MobileScanner(
        controller: controller,
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
          if (barcodes.isNotEmpty) {
            final String? code = barcodes.first.rawValue;
            if (code != null && code.isNotEmpty) {
              Navigator.pop(context, code);
            }
          }
        },
      ),
    );
  }
}

class MultiQRScannerScreen extends StatefulWidget {
  final MobileScannerController controller;
  const MultiQRScannerScreen({super.key, required this.controller});

  @override
  State<MultiQRScannerScreen> createState() => _MultiQRScannerScreenState();
}

class _MultiQRScannerScreenState extends State<MultiQRScannerScreen> {
  final List<String> _scannedCodes = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Multi-scan (${_scannedCodes.length})'),
        backgroundColor: const Color(0xFF8EBB21),
        foregroundColor: Colors.white,
        actions: [
          if (_scannedCodes.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: () => Navigator.pop(context, _scannedCodes),
            )
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: widget.controller,
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                final code = barcode.rawValue;
                if (code != null &&
                    code.isNotEmpty &&
                    !_scannedCodes.contains(code)) {
                  setState(() {
                    _scannedCodes.add(code);
                  });
                  HapticFeedback.lightImpact();
                }
              }
            },
          ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              height: 100,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _scannedCodes.isEmpty
                  ? const Center(
                      child: Text('Scannez vos matériels...',
                          style: TextStyle(color: Colors.white)))
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _scannedCodes.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: Chip(
                            label: Text(_scannedCodes[index]),
                            onDeleted: () =>
                                setState(() => _scannedCodes.removeAt(index)),
                          ),
                        );
                      },
                    ),
            ),
          )
        ],
      ),
    );
  }
}

class MultiScanSummaryDialog extends StatefulWidget {
  final List<String> codes;
  final String local;
  final String tr;
  final String userId;
  final List<String> materiels;
  final bool isAdmin;

  const MultiScanSummaryDialog({
    super.key,
    required this.codes,
    required this.local,
    required this.tr,
    required this.userId,
    required this.materiels,
    this.isAdmin = false,
  });

  @override
  State<MultiScanSummaryDialog> createState() => _MultiScanSummaryDialogState();
}

class _MultiScanSummaryDialogState extends State<MultiScanSummaryDialog> {
  late List<String> _allCodes;

  @override
  void initState() {
    super.initState();
    _allCodes = List.from(widget.codes);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Matériels à traiter (${_allCodes.length})'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Local: ${widget.local} | TR: ${widget.tr}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const Divider(),
            if (_allCodes.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20.0),
                child: Text('Tous les matériels ont été traités.',
                    style: TextStyle(color: Colors.green)),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _allCodes.length,
                  itemBuilder: (context, index) {
                    final code = _allCodes[index];
                    return ListTile(
                      leading:
                          const Icon(Icons.qr_code_2, color: Colors.blueGrey),
                      title: Text(code),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => _processItem(code),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_allCodes.isEmpty ? 'Fermer' : 'Arrêter le batch'),
        ),
      ],
    );
  }

  Future<void> _processItem(String code) async {
    final sanitizedId = code.replaceAll('/', '_').replaceAll(' ', '_');

    final doc = await FirebaseFirestore.instance
        .collection('localog_inventory')
        .doc(sanitizedId)
        .get();

    if (mounted) {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => InventoryFormDialog(
          qrCode: sanitizedId,
          isExisting: doc.exists,
          initialData: doc.data(),
          userId: widget.userId,
          materiels: widget.materiels,
          batchLocal: widget.local,
          batchTR: widget.tr,
          isAdmin: widget.isAdmin,
        ),
      );

      if (result == true) {
        setState(() {
          _allCodes.remove(code);
        });

        if (_allCodes.isEmpty && mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Batch terminé avec succès'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    }
  }
}

class _DeDInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;

    String digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return const TextEditingValue();

    double value = double.parse(digits) / 1000;
    String newText = value.toStringAsFixed(3).replaceAll('.', ',');

    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}

class InventoryFormDialog extends StatefulWidget {
  final String qrCode;
  final bool isExisting;
  final Map<String, dynamic>? initialData;
  final String userId;
  final List<String> materiels;
  final String? batchLocal;
  final String? batchTR;
  final bool isAdmin;

  const InventoryFormDialog({
    super.key,
    required this.qrCode,
    required this.isExisting,
    this.initialData,
    required this.userId,
    required this.materiels,
    this.batchLocal,
    this.batchTR,
    this.isAdmin = false,
  });

  @override
  State<InventoryFormDialog> createState() => _InventoryFormDialogState();
}

class _InventoryFormDialogState extends State<InventoryFormDialog> {
  String _selectedMateriel = '';
  DateTime? _validityDate;
  final TextEditingController _customMaterialController =
      TextEditingController();
  final TextEditingController _localController = TextEditingController();
  final TextEditingController _motifHSController = TextEditingController();
  final TextEditingController _dedController = TextEditingController();
  final TextEditingController _qrController = TextEditingController();
  bool _isHS = false;
  String? _selectedTR;
  String? _selectedRetour;
  bool _isLoading = false;
  bool _showHistory = false;
  List<String> _filteredMateriels = [];
  String _initialDeD = '';

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
      String rawMateriel =
          (widget.initialData!['materiel'] ?? '').toString().trim();
      if (rawMateriel.startsWith('Autre : ')) {
        _selectedMateriel = 'Autre → Préciser';
        _customMaterialController.text =
            rawMateriel.replaceFirst('Autre : ', '');
      } else {
        _selectedMateriel = rawMateriel;
      }
      initialLocal = widget.initialData!['local'] ?? '';
      _isHS = widget.initialData!['hs'] ?? false;
      initialMotifHS = widget.initialData!['motifHS'] ?? '';
      _initialDeD = widget.initialData!['ded']?.toString() ?? '';

      // Si c'est un matériel spécial et qu'on n'a pas de DeD actuel (mais qu'il existe dans le dernier historique)
      if (_isSpecialMaterial && _initialDeD.isEmpty) {
        final history = widget.initialData!['history'] as List<dynamic>?;
        if (history != null && history.isNotEmpty) {
          final lastEntry = history.last as Map<String, dynamic>;
          if (lastEntry['ded'] != null) {
            _initialDeD = lastEntry['ded'].toString();
          }
        }
      }

      final validityStr = widget.initialData!['validityDate'];
      _validityDate =
          validityStr != null ? DateTime.tryParse(validityStr) : null;
      _selectedTR = widget.initialData!['tr']?.toString();
      _selectedRetour = widget.initialData!['retour']?.toString();
    } else {
      _selectedMateriel =
          widget.materiels.isNotEmpty ? widget.materiels.first : '';
      _validityDate = null;
      _selectedTR = widget.batchTR;
      _selectedRetour = null;
      _isHS = false;
      initialLocal = widget.batchLocal ?? '';
    }

    _localController.text = initialLocal;
    _motifHSController.text = initialMotifHS;
    _dedController.text = _initialDeD;

    _qrController.text = widget.qrCode;
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
    _customMaterialController.dispose();
    _localController.dispose();
    _motifHSController.dispose();
    _dedController.dispose();
    _qrController.dispose();
    super.dispose();
  }

  bool get _isSpecialMaterial {
    final specialList = [
      'Déprimogène',
      'MEDGV',
      'MEDCP',
      'Pompe à membrane',
      'Orfo'
    ];
    return specialList.contains(_selectedMateriel);
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
    final qrCodeToSave = _qrController.text.trim();
    if (qrCodeToSave.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le QR Code ne peut pas être vide')),
      );
      return;
    }

    final localValue = _localController.text.trim().toUpperCase();
    final motifHSValue = _motifHSController.text.trim();
    final dedValue = _dedController.text.trim();

    final finalMateriel = _selectedMateriel == 'Autre → Préciser'
        ? 'Autre : ${_customMaterialController.text.trim()}'
        : _selectedMateriel;

    // Validation
    if (_selectedMateriel == 'Autre → Préciser' &&
        _customMaterialController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez préciser le matériel'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

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

    if (_isSpecialMaterial && dedValue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Le Débit de Dose (DeD) est obligatoire pour ce matériel'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (qrCodeToSave != widget.qrCode) {
      final existingDoc = await FirebaseFirestore.instance
          .collection('localog_inventory')
          .doc(qrCodeToSave)
          .get();
      if (existingDoc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Ce QR Code est déjà utilisé par un autre matériel'),
              backgroundColor: Colors.red,
            ),
          );
        }
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
        'qrCode': qrCodeToSave,
        'materiel': finalMateriel,
        'local': localValue,
        'tr': _selectedTR,
        'retour': _selectedRetour,
        'hs': _isHS,
        'motifHS': _isHS ? motifHSValue : '',
        'ded': _isSpecialMaterial ? dedValue : null,
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
        if (qrCodeToSave != widget.qrCode) {
          changes['qrCode'] = {'old': widget.qrCode, 'new': qrCodeToSave};
        }
        if (widget.initialData!['materiel'] != finalMateriel) {
          changes['materiel'] = {
            'old': widget.initialData!['materiel'],
            'new': finalMateriel
          };
        }
        // ... (suite des changements existants)
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
        if (_isSpecialMaterial &&
            widget.initialData!['ded']?.toString() != dedValue) {
          changes['ded'] = {
            'old': widget.initialData!['ded'] ?? 'N/A',
            'new': dedValue
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
        } else {
          // Aucun changement, on marque comme vérifié / vu
          Map<String, dynamic> verificationEntry = {
            'timestamp': formattedDate,
            'action': 'vérification',
            'modifiedBy': {
              'uid': currentUser.uid,
              'nom': userData['nom'] ?? 'N/A',
              'prenom': userData['prenom'] ?? 'N/A',
              'roles': userData['roles'] ?? [],
            },
          };

          // Si c'est un matériel spécial, on enregistre le DeD actuel dans la vérification
          if (_isSpecialMaterial) {
            verificationEntry['ded'] = dedValue;
          }

          history.add(verificationEntry);
        }
        inventoryData['history'] = history;
      } else {
        // Première saisie
        inventoryData['history'] = [
          {
            'timestamp': formattedDate,
            'action': 'création',
            'data': {
              'materiel': finalMateriel,
              'local': localValue,
              'tr': _selectedTR,
              'retour': _selectedRetour,
              'hs': _isHS,
              'motifHS': _isHS ? motifHSValue : '',
              'ded': _isSpecialMaterial ? dedValue : null,
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
          .doc(qrCodeToSave)
          .set(inventoryData, SetOptions(merge: true));

      if (qrCodeToSave != widget.qrCode) {
        await firestore
            .collection('localog_inventory')
            .doc(widget.qrCode)
            .delete();
      }

      if (mounted) {
        Navigator.pop(context, true);
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
                  if (widget.isAdmin)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: 'Supprimer définitivement',
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Supprimer le matériel ?'),
                            content: const Text(
                                'Voulez-vous vraiment supprimer définitivement ce matériel de l\'inventaire ? Cette action est irréversible.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Annuler'),
                              ),
                              ElevatedButton(
                                onPressed: () async {
                                  Navigator.pop(ctx);
                                  Navigator.pop(context);
                                  await FirebaseFirestore.instance
                                      .collection('localog_inventory')
                                      .doc(widget.qrCode)
                                      .delete();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content:
                                          Text('Matériel supprimé avec succès'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red),
                                child: const Text('Supprimer',
                                    style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('QR Code*'),
              const SizedBox(height: 5),
              TextField(
                controller: _qrController,
                readOnly: !widget.isAdmin,
                decoration: InputDecoration(
                  hintText: 'Code du matériel',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: !widget.isAdmin,
                  fillColor: !widget.isAdmin ? Colors.grey[200] : null,
                  suffixIcon: widget.isAdmin
                      ? const Icon(Icons.edit, size: 18)
                      : const Icon(Icons.lock_outline, size: 18),
                ),
              ),
              const SizedBox(height: 15),
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
              if (_selectedMateriel == 'Autre → Préciser') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _customMaterialController,
                  decoration: InputDecoration(
                    labelText: 'Préciser le matériel',
                    hintText: 'Entrez le nom du matériel',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
              if (_isSpecialMaterial) ...[
                const SizedBox(height: 16),
                const Text(
                  'Débit de Dose (DeD) maximum*',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _dedController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    _DeDInputFormatter(),
                  ],
                  decoration: InputDecoration(
                    hintText: 'ex: 0356',
                    suffixText: 'mSv/h',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
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
                    if (_isSpecialMaterial && _initialDeD.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          'DeD actuel: $_initialDeD mSv/h',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blueAccent,
                          ),
                        ),
                      ),
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
                              } else if (data['action'] == 'vérification') {
                                String label = 'Vérifié (aucun changement)';
                                if (data['ded'] != null) {
                                  label += ' - DeD: ${data['ded']} mSv/h';
                                }
                                details.add(label);
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
                                  if (key == 'ded') keyLabel = 'DeD';
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
