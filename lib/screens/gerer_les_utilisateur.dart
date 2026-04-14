import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'creation_utilisateur_admin_screen.dart';

class GererLesUtilisateursScreen extends StatefulWidget {
  const GererLesUtilisateursScreen({super.key});

  @override
  State<GererLesUtilisateursScreen> createState() =>
      _GererLesUtilisateursScreenState();
}

class _GererLesUtilisateursScreenState extends State<GererLesUtilisateursScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gérer les utilisateurs'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'À Valider'),
            Tab(text: 'Utilisateurs Actifs'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          UserListView(statut: 'en_attente'),
          UserListView(statut: 'valide'),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const CreationUtilisateurAdminScreen(),
            ),
          );
        },
        tooltip: 'Créer un utilisateur',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class UserListView extends StatefulWidget {
  final String statut;

  const UserListView({super.key, required this.statut});

  @override
  State<UserListView> createState() => _UserListViewState();
}

class _UserListViewState extends State<UserListView> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedFilterRole;
  final List<String> _roles = const [
    'administrateur',
    'chef_de_chantier',
    'chef_equipe',
    'intervenant',
    'client_alog',
    'chef_de_chantier_amcr',
    'referent_amcr',
    'intervenant_amcr',
    'client_amcr',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  CollectionReference get _collection =>
      FirebaseFirestore.instance.collection('utilisateurs');

  Future<void> _updateUser(
      BuildContext context, String uid, Map<String, dynamic> data) async {
    if (!context.mounted) return;
    try {
      await _collection.doc(uid).update(data);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Utilisateur mis à jour avec succès'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur lors de la mise à jour: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteUser(BuildContext context, String uid) async {
    if (!context.mounted) return;

    // Avertissement : Cette action ne supprime que de Firestore.
    // Pour une suppression complète, il faut aussi utiliser les Cloud Functions
    // pour le retirer de Firebase Authentication.
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmer la suppression'),
        content: const Text(
            'Êtes-vous sûr de vouloir supprimer cet utilisateur ? Cette action est irréversible.'),
        actions: [
          TextButton(
            child: const Text('Annuler'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          TextButton(
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await _collection.doc(uid).delete();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Utilisateur supprimé de Firestore.'),
                    backgroundColor: Colors.orange,
                  ),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Erreur lors de la suppression: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  String _displayRole(String role) {
    return role.replaceAll('_', ' ').replaceFirstMapped(
          RegExp(r'\b\w'),
          (match) => match.group(0)!.toUpperCase(),
        );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Barre de recherche
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Rechercher par nom ou prénom',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() {}),
          ),
        ),
        // Filtre par rôle, seulement pour les utilisateurs actifs
        if (widget.statut == 'valide')
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: DropdownButtonFormField<String>(
              initialValue: _selectedFilterRole,
              decoration: const InputDecoration(
                labelText: 'Filtrer par rôle',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('Tous les rôles'),
                ),
                ..._roles.map((r) => DropdownMenuItem<String>(
                      value: r,
                      child: Text(_displayRole(r)),
                    )),
              ],
              onChanged: (val) => setState(() => _selectedFilterRole = val),
            ),
          ),
        // Liste
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _collection
                .where('statut', isEqualTo: widget.statut)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('Erreur de chargement'));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Text(
                    widget.statut == 'en_attente'
                        ? "Aucun utilisateur à valider"
                        : "Aucun utilisateur actif",
                  ),
                );
              }

              // Filtrer et trier
              List<DocumentSnapshot> filteredDocs =
                  snapshot.data!.docs.where((doc) {
                if (doc.id == FirebaseAuth.instance.currentUser?.uid) {
                  return false; // Ne pas s'afficher soi-même
                }
                final data = doc.data() as Map<String, dynamic>? ?? {};
                final nom = data['nom']?.toString() ?? '';
                final prenom = data['prenom']?.toString() ?? '';
                final email = data['email']?.toString() ?? '';
                final String displayName = (nom.isNotEmpty && prenom.isNotEmpty)
                    ? '$prenom $nom'
                    : email;

                // Recherche
                if (_searchController.text.isNotEmpty &&
                    !displayName
                        .toLowerCase()
                        .contains(_searchController.text.toLowerCase()) &&
                    !email
                        .toLowerCase()
                        .contains(_searchController.text.toLowerCase())) {
                  return false;
                }

                // Filtre par rôle
                if (_selectedFilterRole != null) {
                  final rolesList = List<String>.from(data['roles'] ?? []);
                  if (!rolesList.contains(_selectedFilterRole)) {
                    return false;
                  }
                }

                return true;
              }).toList();

              // Trier par ordre alphabétique
              filteredDocs.sort((a, b) {
                final dataA = a.data() as Map<String, dynamic>? ?? {};
                final nomA = dataA['nom']?.toString() ?? '';
                final prenomA = dataA['prenom']?.toString() ?? '';
                final emailA = dataA['email']?.toString() ?? '';
                final String displayNameA =
                    (nomA.isNotEmpty && prenomA.isNotEmpty)
                        ? '$prenomA $nomA'
                        : emailA;

                final dataB = b.data() as Map<String, dynamic>? ?? {};
                final nomB = dataB['nom']?.toString() ?? '';
                final prenomB = dataB['prenom']?.toString() ?? '';
                final emailB = dataB['email']?.toString() ?? '';
                final String displayNameB =
                    (nomB.isNotEmpty && prenomB.isNotEmpty)
                        ? '$prenomB $nomB'
                        : emailB;

                return displayNameA
                    .toLowerCase()
                    .compareTo(displayNameB.toLowerCase());
              });

              return ListView(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 80),
                children: filteredDocs.map((doc) {
                  if (widget.statut == 'valide') {
                    return ActiveUserCard(
                      userDocument: doc,
                      onUpdate: (uid, data) => _updateUser(context, uid, data),
                      onDelete: (uid) => _deleteUser(context, uid),
                    );
                  } else {
                    return UserValidationCard(
                      userDocument: doc,
                      onValidate: (uid, data) =>
                          _updateUser(context, uid, data),
                    );
                  }
                }).toList(),
              );
            },
          ),
        ),
      ],
    );
  }
}

// --- CARTE POUR LES UTILISATEURS ACTIFS (SIMPLIFIÉE) ---
class ActiveUserCard extends StatefulWidget {
  final DocumentSnapshot userDocument;
  final void Function(String uid, Map<String, dynamic> data) onUpdate;
  final void Function(String uid) onDelete;

  const ActiveUserCard({
    super.key,
    required this.userDocument,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  State<ActiveUserCard> createState() => _ActiveUserCardState();
}

class _ActiveUserCardState extends State<ActiveUserCard> {
  late List<String> _selectedRoles;
  late bool _isAMCR;
  late bool _isCAPILog;
  late bool _isConsignes;
  final List<String> _roles = const [
    'administrateur',
    'chef_de_chantier',
    'chef_equipe',
    'intervenant',
    'client_alog',
    'chef_de_chantier_amcr',
    'referent_amcr',
    'intervenant_amcr',
    'client_amcr',
  ];

  @override
  void initState() {
    super.initState();
    final data = widget.userDocument.data() as Map<String, dynamic>? ?? {};
    _selectedRoles = List<String>.from(data['roles'] ?? []);
    if (_selectedRoles.isEmpty) _selectedRoles = ['intervenant'];
    _isAMCR = data['isAMCR'] ?? false;
    _isCAPILog = data['isCAPILog'] ?? false;
    _isConsignes = data['isConsignes'] ?? false;
  }

  String _displayRole(String role) {
    return role.replaceAll('_', ' ').replaceFirstMapped(
          RegExp(r'\b\w'),
          (match) => match.group(0)!.toUpperCase(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.userDocument.data() as Map<String, dynamic>? ?? {};
    final email = data['email']?.toString() ?? 'Email non disponible';
    final nom = data['nom']?.toString();
    final prenom = data['prenom']?.toString();
    String displayName =
        (nom != null && prenom != null) ? '$prenom $nom' : email;

    final bool isAdmin = _selectedRoles.contains('administrateur');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
      child: ExpansionTile(
        leading: Icon(
          isAdmin ? Icons.shield_outlined : Icons.engineering,
          color: isAdmin ? Colors.red : Colors.blue,
        ),
        title: Text(displayName),
        subtitle: Text(
            "Rôles : ${_selectedRoles.map(_displayRole).join(', ')}${displayName != email ? '\n$email' : ''}"),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Gérer les rôles :',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8.0,
                  runSpacing: 4.0,
                  children: _roles.map((role) {
                    final isSelected = _selectedRoles.contains(role);
                    return FilterChip(
                      label: Text(_displayRole(role),
                          style: const TextStyle(fontSize: 12)),
                      selected: isSelected,
                      selectedColor: Colors.blue.shade100,
                      onSelected: (bool selected) {
                        setState(() {
                          if (selected) {
                            if (!_selectedRoles.contains(role)) {
                              _selectedRoles.add(role);
                            }
                          } else {
                            if (_selectedRoles.length > 1) {
                              _selectedRoles.remove(role);
                            }
                          }
                        });
                        widget.onUpdate(widget.userDocument.id, {
                          'roles': _selectedRoles,
                        });
                      },
                    );
                  }).toList(),
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Accès Consignes'),
                  subtitle:
                      const Text('Autoriser l\'accès à l\'interface Consignes'),
                  value: _isConsignes,
                  onChanged: (bool value) {
                    setState(() {
                      _isConsignes = value;
                    });
                    widget.onUpdate(widget.userDocument.id, {
                      'isConsignes': _isConsignes,
                    });
                  },
                ),
                SwitchListTile(
                  title: const Text('Accès CAPILog'),
                  subtitle:
                      const Text('Autoriser l\'accès à l\'interface CAPILog'),
                  value: _isCAPILog,
                  onChanged: (bool value) {
                    setState(() {
                      _isCAPILog = value;
                    });
                    widget.onUpdate(widget.userDocument.id, {
                      'isCAPILog': _isCAPILog,
                    });
                  },
                ),
                SwitchListTile(
                  title: const Text('Accès Interface AMCR'),
                  subtitle: const Text('Autoriser l\'accès au menu AMCR'),
                  value: _isAMCR,
                  onChanged: (bool value) {
                    setState(() {
                      _isAMCR = value;
                    });
                    widget.onUpdate(widget.userDocument.id, {
                      'isAMCR': _isAMCR,
                    });
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                      label: const Text('Supprimer',
                          style: TextStyle(color: Colors.red)),
                      onPressed: () => widget.onDelete(widget.userDocument.id),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- CARTE DE VALIDATION (RESTE IDENTIQUE, DÉJÀ SIMPLIFIÉE) ---
class UserValidationCard extends StatefulWidget {
  final DocumentSnapshot userDocument;
  final void Function(String uid, Map<String, dynamic> data) onValidate;

  const UserValidationCard({
    super.key,
    required this.userDocument,
    required this.onValidate,
  });

  @override
  State<UserValidationCard> createState() => _UserValidationCardState();
}

class _UserValidationCardState extends State<UserValidationCard> {
  late List<String> _selectedRoles;
  bool _isAMCR = false;
  bool _isCAPILog = false;
  bool _isConsignes = false;
  final List<String> _roles = const [
    'administrateur',
    'chef_de_chantier',
    'chef_equipe',
    'intervenant',
    'client_alog',
    'chef_de_chantier_amcr',
    'referent_amcr',
    'intervenant_amcr',
    'client_amcr',
  ];

  @override
  void initState() {
    super.initState();
    final data = widget.userDocument.data() as Map<String, dynamic>? ?? {};
    _selectedRoles = List<String>.from(data['roles'] ?? []);
    if (_selectedRoles.isEmpty) _selectedRoles = ['intervenant'];
    _isAMCR = data['isAMCR'] ?? false;
    _isCAPILog = data['isCAPILog'] ?? false;
    _isConsignes = data['isConsignes'] ?? false;
  }

  String _displayRole(String role) {
    return role.replaceAll('_', ' ').replaceFirstMapped(
          RegExp(r'\b\w'),
          (match) => match.group(0)!.toUpperCase(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.userDocument.data() as Map<String, dynamic>? ?? {};
    final email = data['email']?.toString() ?? 'Email non disponible';
    final nom = data['nom']?.toString() ?? 'N/A';
    final prenom = data['prenom']?.toString() ?? 'N/A';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
      child: ExpansionTile(
        title: Text('$prenom $nom',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text("En attente de validation",
            style: TextStyle(color: Colors.orange)),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Email: $email'),
                const SizedBox(height: 8),
                const Text('Attribuer les rôles :',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8.0,
                  runSpacing: 4.0,
                  children: _roles.map((role) {
                    final isSelected = _selectedRoles.contains(role);
                    return FilterChip(
                      label: Text(_displayRole(role),
                          style: const TextStyle(fontSize: 12)),
                      selected: isSelected,
                      onSelected: (bool selected) {
                        setState(() {
                          if (selected) {
                            if (!_selectedRoles.contains(role)) {
                              _selectedRoles.add(role);
                            }
                          } else {
                            if (_selectedRoles.length > 1) {
                              _selectedRoles.remove(role);
                            }
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Accès Consignes'),
                  value: _isConsignes,
                  onChanged: (bool value) {
                    setState(() {
                      _isConsignes = value;
                    });
                  },
                ),
                SwitchListTile(
                  title: const Text('Accès CAPILog'),
                  value: _isCAPILog,
                  onChanged: (bool value) {
                    setState(() {
                      _isCAPILog = value;
                    });
                  },
                ),
                SwitchListTile(
                  title: const Text('Accès Interface AMCR'),
                  value: _isAMCR,
                  onChanged: (bool value) {
                    setState(() {
                      _isAMCR = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      widget.onValidate(
                        widget.userDocument.id,
                        {
                          'statut': 'valide',
                          'roles': _selectedRoles,
                          'isAMCR': _isAMCR,
                          'isCAPILog': _isCAPILog,
                          'isConsignes': _isConsignes,
                          'isAwaitingValidation': false, // Correction cruciale
                        },
                      );
                    },
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    child: const Text('Valider l\'utilisateur',
                        style: TextStyle(color: Colors.white)),
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}
