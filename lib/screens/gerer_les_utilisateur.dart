import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'creation_utilisateur_admin_screen.dart';

class GererLesUtilisateursScreen extends StatefulWidget {
  const GererLesUtilisateursScreen({Key? key}) : super(key: key);

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

  const UserListView({Key? key, required this.statut}) : super(key: key);

  @override
  State<UserListView> createState() => _UserListViewState();
}

class _UserListViewState extends State<UserListView> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedFilterRole;
  final List<String> _roles = const [
    'chef_de_chantier',
    'administrateur',
    'chef_equipe',
    'intervenant',
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
              value: _selectedFilterRole,
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
    Key? key,
    required this.userDocument,
    required this.onUpdate,
    required this.onDelete,
  }) : super(key: key);

  @override
  State<ActiveUserCard> createState() => _ActiveUserCardState();
}

class _ActiveUserCardState extends State<ActiveUserCard> {
  late String _selectedRole;
  final List<String> _roles = const [
    'chef_de_chantier',
    'administrateur',
    'chef_equipe',
    'intervenant',
  ];

  final Map<String, Color> _roleColors = const {
    'administrateur': Colors.red,
    'chef_de_chantier': Colors.blue,
    'chef_equipe': Colors.green,
    'intervenant': Colors.orange,
  };

  @override
  void initState() {
    super.initState();
    final data = widget.userDocument.data() as Map<String, dynamic>? ?? {};
    final rolesList = List<String>.from(data['roles'] ?? []);
    _selectedRole = rolesList.isNotEmpty ? rolesList.first : 'intervenant';
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
    // On récupère le nom et prénom s'ils existent
    final nom = data['nom']?.toString();
    final prenom = data['prenom']?.toString();
    String displayName =
        (nom != null && prenom != null) ? '$prenom $nom' : email;

    final Color roleColor = _roleColors[_selectedRole] ?? Colors.grey;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
      child: ExpansionTile(
        leading: Icon(
          _selectedRole == 'administrateur'
              ? Icons.shield_outlined
              : Icons.engineering,
          color: roleColor,
        ),
        title: Text(displayName),
        subtitle: Text(
            "Rôle : ${_displayRole(_selectedRole)}${displayName != email ? '\n$email' : ''}"),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Changer le rôle',
                      border: OutlineInputBorder(),
                    ),
                    items: _roles
                        .map((r) => DropdownMenuItem<String>(
                              value: r,
                              child: Text(_displayRole(r)),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null && val != _selectedRole) {
                        widget.onUpdate(
                          widget.userDocument.id,
                          {
                            'roles': [val]
                          },
                        );
                        setState(() {
                          _selectedRole = val;
                        });
                      }
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16.0),
                  child: IconButton(
                    icon:
                        Icon(Icons.delete_forever, color: Colors.red.shade700),
                    tooltip: 'Supprimer cet utilisateur',
                    onPressed: () => widget.onDelete(widget.userDocument.id),
                  ),
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
    Key? key,
    required this.userDocument,
    required this.onValidate,
  }) : super(key: key);

  @override
  State<UserValidationCard> createState() => _UserValidationCardState();
}

class _UserValidationCardState extends State<UserValidationCard> {
  late String _selectedRole;
  final List<String> _roles = const [
    'chef_de_chantier',
    'administrateur',
    'chef_equipe',
    'intervenant',
  ];

  @override
  void initState() {
    super.initState();
    final data = widget.userDocument.data() as Map<String, dynamic>? ?? {};
    final rolesList = List<String>.from(data['roles'] ?? []);
    _selectedRole = rolesList.isNotEmpty ? rolesList.first : 'intervenant';
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

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$email (Nom: $nom)',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Text("En attente de validation",
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    value: _selectedRole,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: _roles
                        .map((r) => DropdownMenuItem<String>(
                              value: r,
                              child: Text(_displayRole(r)),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedRole = val);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () {
                    widget.onValidate(
                      widget.userDocument.id,
                      {
                        'statut': 'valide',
                        'roles': [_selectedRole],
                      },
                    );
                  },
                  style:
                      ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('Valider'),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }
}
