import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ActivityLogger {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static final ActivityLogger _instance = ActivityLogger._internal();
  factory ActivityLogger() => _instance;
  ActivityLogger._internal();

  String? _currentSessionId;

  /// Démarre une nouvelle session utilisateur
  Future<void> startSession() async {
    final user = _auth.currentUser;
    if (user == null || _currentSessionId != null) {
      print("ℹ️ Session already active or no user: $_currentSessionId");
      return;
    }

    final sessionRef = _firestore.collection('user_sessions').doc();
    _currentSessionId = sessionRef.id;

    try {
      // Récupérer les infos nom/prénom depuis la collection utilisateurs
      final userDoc = await _firestore.collection('utilisateurs').doc(user.uid).get();
      final userData = userDoc.data();
      final String userName = userData != null 
          ? "${userData['prenom'] ?? ''} ${userData['nom'] ?? ''}".trim()
          : (user.displayName ?? 'Utilisateur inconnu');

      await sessionRef.set({
        'userId': user.uid,
        'userEmail': user.email,
        'userName': userName.isEmpty ? user.email : userName,
        'startTime': FieldValue.serverTimestamp(),
        'lastActivity': FieldValue.serverTimestamp(),
        'viewCount': 0, // Initialisation du compteur de vues/lectures
        'deviceInfo': {}, 
      });
      print("🚀 Session started for $userName: $_currentSessionId");
    } catch (e) {
      print("❌ Error starting session: $e");
      _currentSessionId = null;
    }
  }

  /// Log une vue de page avec détails optionnels (ex: tranche)
  Future<void> logPageView(String pageName, {String? tranche}) async {
    final user = _auth.currentUser;
    if (user == null || _currentSessionId == null) return;

    await _firestore
        .collection('user_sessions')
        .doc(_currentSessionId)
        .collection('page_views')
        .add({
      'pageName': pageName,
      'tranche': tranche, // On ajoute la tranche ici
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Update last activity and increment view count
    await _firestore.collection('user_sessions').doc(_currentSessionId).update({
      'lastActivity': FieldValue.serverTimestamp(),
      'viewCount': FieldValue.increment(1),
    });
  }

  /// Met fin à la session actuelle
  Future<void> endSession({DateTime? endTime}) async {
    if (_currentSessionId == null) return;

    try {
      await _firestore.collection('user_sessions').doc(_currentSessionId).update({
        'endTime': endTime != null ? Timestamp.fromDate(endTime) : FieldValue.serverTimestamp(),
      });
      print("👋 Session ended: $_currentSessionId");
    } catch (e) {
      print("❌ Error ending session: $e");
    } finally {
      _currentSessionId = null;
    }
  }
}
