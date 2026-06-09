import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class UserTrackingScreen extends StatelessWidget {
  const UserTrackingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Suivi des Utilisateurs"),
        backgroundColor: Colors.redAccent.shade700,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('user_sessions')
            .orderBy('lastActivity', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return Center(child: Text("Erreur : ${snapshot.error}"));
          
          final allDocs = snapshot.data?.docs ?? [];

          // --- CALCUL DES STATISTIQUES ---
          final now = DateTime.now();
          final startOfToday = DateTime(now.year, now.month, now.day);
          final startOfMonth = DateTime(now.year, now.month, 1);

          final usersToday = <String>{};
          final usersMonth = <String>{};
          int readsToday = 0;
          int readsMonth = 0;

          final Map<String, Map<String, dynamic>> usersMap = {};

          for (var doc in allDocs) {
            final data = doc.data() as Map<String, dynamic>? ?? {};
            final userId = data['userId'] as String?;
            final startTime = (data['startTime'] as Timestamp?)?.toDate();
            final vCount = data['viewCount'] as int? ?? 0;

            if (userId != null) {
              if (!usersMap.containsKey(userId)) {
                usersMap[userId] = data;
              }

              if (startTime != null) {
                if (startTime.isAfter(startOfToday)) {
                  usersToday.add(userId);
                  readsToday += vCount;
                }
                if (startTime.isAfter(startOfMonth)) {
                  usersMonth.add(userId);
                  readsMonth += vCount;
                }
              }
            }
          }

          final usersList = usersMap.values.toList();

          return Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.redAccent.shade700,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  children: [
                    const Text("CONSOMMATION FIREBASE (LECTURES)", 
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white70)),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatCardWhite("Actifs (J)", "${usersToday.length}"),
                        _buildStatCardWhite("Actifs (M)", "${usersMonth.length}"),
                        _buildStatCardWhite("Lectures (J)", "$readsToday"),
                        _buildStatCardWhite("Lectures (M)", "$readsMonth"),
                      ],
                    ),
                  ],
                ),
              ),
              
              if (usersList.isEmpty)
                const Expanded(child: Center(child: Text("Aucune activité enregistrée.")))
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: usersList.length,
                    padding: const EdgeInsets.only(bottom: 15),
                    itemBuilder: (context, index) {
                      final user = usersList[index];
                      final String name = user['userName'] ?? user['userEmail'] ?? 'Inconnu';
                      final DateTime? lastAct = (user['lastActivity'] as Timestamp?)?.toDate();

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                        elevation: 4,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(15),
                          leading: CircleAvatar(
                            radius: 28,
                            backgroundColor: Colors.redAccent.shade700,
                            child: Text(name.substring(0, 1).toUpperCase(), 
                              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                          ),
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          subtitle: Text(
                            lastAct != null 
                            ? "Dernière activité : ${DateFormat('dd/MM à HH:mm').format(lastAct)}"
                            : "Inactif",
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios, color: Colors.redAccent),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => UserHistoryDaysScreen(userId: user['userId'], userName: name)),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class UserHistoryDaysScreen extends StatelessWidget {
  final String userId;
  final String userName;

  const UserHistoryDaysScreen({super.key, required this.userId, required this.userName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Activités de $userName")),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('user_sessions')
            .where('userId', isEqualTo: userId)
            .orderBy('startTime', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text("Erreur : ${snapshot.error}"));

          final sessions = snapshot.data?.docs ?? [];
          final Map<String, List<DocumentSnapshot>> groupedByDay = {};

          for (var doc in sessions) {
            final data = doc.data() as Map<String, dynamic>? ?? {};
            final date = (data['startTime'] as Timestamp?)?.toDate();
            if (date != null) {
              final day = DateFormat('dd MMMM yyyy', 'fr_FR').format(date);
              groupedByDay.putIfAbsent(day, () => []).add(doc);
            }
          }

          final days = groupedByDay.keys.toList();

          return ListView.builder(
            itemCount: days.length,
            itemBuilder: (context, index) {
              final day = days[index];
              final daySessions = groupedByDay[day]!;
              final int dayReads = daySessions.fold(0, (sum, doc) {
                final data = doc.data() as Map<String, dynamic>? ?? {};
                return sum + (data['viewCount'] as int? ?? 0);
              });

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: const Icon(Icons.calendar_today, color: Colors.blue),
                  title: Text(day, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("${daySessions.length} session(s) • $dayReads lectures"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => UserDayDetailScreen(day: day, sessions: daySessions)),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class UserDayDetailScreen extends StatelessWidget {
  final String day;
  final List<DocumentSnapshot> sessions;

  const UserDayDetailScreen({super.key, required this.day, required this.sessions});

  String _getReadablePageName(String? route) {
    if (route == null) return "Page inconnue";
    if (route.startsWith('/detail_repere')) return "CAPILog : Détail Repère";
    switch (route) {
      case '/': case '/selection_role': return "Sélection du Rôle";
      case '/login_chantier': return "Page de Connexion";
      case '/home_consignes': return "Consignes / Transferts";
      case '/consignes': return "Module Consignes";
      case '/transferts': return "Module Transferts";
      case '/infos': return "Infos Chantier";
      case '/export_excel': return "Export Excel / Archives";
      case '/home_amcr': return "AMCR : Accueil";
      case '/amcr_consignes': return "AMCR : Consignes";
      case '/amcr_transferts': return "AMCR : Transferts";
      case '/amcr_infos_chantier': return "AMCR : Infos Chantier";
      case '/chantier_plus': return "CAPILog : Liste Repères";
      case '/localog': return "Module LocaLog";
      case '/localog_scanner': return "LocaLog : Scan QR Code";
      case '/user_tracking': return "Suivi d'activité (Admin)";
      case '/gerer_utilisateurs': return "Gestion des Utilisateurs";
      case '/creation_utilisateur_admin': return "Création Utilisateur";
      case '/manage_tranches': return "Configuration des Tranches";
      default:
        if (route.contains(' : ')) return route;
        String clean = route.replaceAll('/', '').replaceAll('_', ' ');
        if (clean.isEmpty) return "Accueil";
        return clean[0].toUpperCase() + clean.substring(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Détail du $day")),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _getAllPageViews(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text("Erreur : ${snapshot.error}"));

          final allViews = snapshot.data ?? [];
          if (allViews.isEmpty) return const Center(child: Text("Aucun détail disponible."));

          return ListView.builder(
            itemCount: allViews.length,
            itemBuilder: (context, index) {
              final view = allViews[index];
              final time = view['timestamp'] as DateTime?;
              final duration = view['duration'] as Duration?;
              final String pageName = _getReadablePageName(view['pageName']);

              return ListTile(
                leading: Text(time != null ? DateFormat('HH:mm').format(time) : '--:--', 
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                title: Text(pageName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                trailing: duration != null && duration.inSeconds > 0
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                      child: Text("${duration.inMinutes}m ${duration.inSeconds % 60}s", 
                        style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold, fontSize: 12)),
                    )
                  : null,
              );
            },
          );
        },
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _getAllPageViews() async {
    List<Map<String, dynamic>> totalViews = [];
    for (var session in sessions) {
      final viewsSnap = await session.reference.collection('page_views').orderBy('timestamp', descending: false).get();
      final lastActivity = (session['lastActivity'] as Timestamp?)?.toDate();

      for (int i = 0; i < viewsSnap.docs.length; i++) {
        final data = viewsSnap.docs[i].data();
        final currentTs = (data['timestamp'] as Timestamp?)?.toDate();
        DateTime? nextTs = (i + 1 < viewsSnap.docs.length) 
            ? (viewsSnap.docs[i + 1].data()['timestamp'] as Timestamp?)?.toDate() 
            : lastActivity;

        Duration? duration;
        if (currentTs != null && nextTs != null) duration = nextTs.difference(currentTs);

        totalViews.add({
          'pageName': data['pageName'],
          'timestamp': currentTs,
          'duration': duration,
        });
      }
    }
    totalViews.sort((a, b) => (a['timestamp'] as DateTime).compareTo(b['timestamp'] as DateTime));
    return totalViews;
  }
}

Widget _buildStatCardWhite(String label, String value) {
  return Expanded(
    child: Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
      ],
    ),
  );
}
