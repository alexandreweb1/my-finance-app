import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import '../../../../core/error/exceptions.dart';
import '../models/user_model.dart';

abstract class AuthRemoteDataSource {
  Future<UserModel> signInWithEmailAndPassword({
    required String email,
    required String password,
  });

  Future<UserModel> signUpWithEmailAndPassword({
    required String email,
    required String password,
    String? displayName,
  });

  Future<UserModel?> signInWithGoogle();

  Future<void> signOut();

  Stream<UserModel?> get authStateChanges;

  UserModel? getCurrentUser();

  Future<void> updateProfile({String? displayName});

  Future<void> updatePassword(String currentPassword, String newPassword);

  /// Links an email+password credential to the current (Google) account,
  /// enabling dual sign-in for the same Firebase user.
  Future<void> linkEmailPassword(String password);

  /// Deletes the current user's Firebase Auth account.
  /// [password] is required for email/password users; pass null for Google-only users.
  Future<void> deleteAccount({String? password});
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;
  // Web client ID (OAuth type 3) — used as clientId on Web, serverClientId on Android
  static const _webClientId =
      '53669256636-ebovakj9raemrpkmj7hl5j32i4h357t7.apps.googleusercontent.com';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: kIsWeb ? _webClientId : null,
    serverClientId: kIsWeb ? null : _webClientId,
  );

  static const _kTimeout = Duration(seconds: 12);

  AuthRemoteDataSourceImpl(this._firebaseAuth, this._firestore);

  @override
  Future<UserModel> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (credential.user == null) throw const AuthException();
      return UserModel.fromFirebaseUser(credential.user!);
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.message ?? 'Erro de autenticação.');
    }
  }

  @override
  Future<UserModel> signUpWithEmailAndPassword({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (credential.user == null) throw const AuthException();
      if (displayName != null) {
        await credential.user!.updateDisplayName(displayName);
        await credential.user!.reload();
      }
      final user = _firebaseAuth.currentUser!;
      // Save user profile to Firestore
      await _firestore.collection('users').doc(user.uid).set({
        'userId': user.uid,
        'email': user.email,
        'displayName': displayName ?? '',
        'photoUrl': '',
        'createdAt': FieldValue.serverTimestamp(),
      }).timeout(_kTimeout);
      // Usa displayName diretamente — currentUser.displayName pode estar
      // desatualizado imediatamente após updateDisplayName + reload()
      return UserModel(
        id: user.uid,
        email: user.email ?? '',
        displayName: displayName ?? user.displayName,
        photoUrl: user.photoURL,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.message ?? 'Erro ao criar conta.');
    }
  }

  @override
  Future<UserModel?> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      // User cancelled the sign-in picker
      if (googleUser == null) return null;

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _firebaseAuth
          .signInWithCredential(credential)
          .timeout(_kTimeout);
      final fbUser = userCredential.user!;

      // Sync profile to Firestore (merge so existing data is preserved)
      await _firestore.collection('users').doc(fbUser.uid).set({
        'userId': fbUser.uid,
        'email': fbUser.email ?? '',
        'displayName': fbUser.displayName ?? '',
        'photoUrl': fbUser.photoURL ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(_kTimeout);

      return UserModel(
        id: fbUser.uid,
        email: fbUser.email ?? '',
        displayName: fbUser.displayName,
        photoUrl: fbUser.photoURL,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.message ?? 'Erro de autenticação com Google.');
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(e.toString());
    }
  }

  @override
  Future<void> signOut() async {
    try {
      // Sign out of Firebase first — triggers authStateChanges immediately.
      await _firebaseAuth.signOut();
      // Google sign-out in background (slower network call, not required for UI update).
      _googleSignIn.signOut().ignore();
    } catch (e) {
      throw const AuthException('Erro ao sair da conta.');
    }
  }

  @override
  Stream<UserModel?> get authStateChanges {
    return _firebaseAuth.userChanges().map(
      (user) => user != null ? UserModel.fromFirebaseUser(user) : null,
    );
  }

  @override
  UserModel? getCurrentUser() {
    final user = _firebaseAuth.currentUser;
    return user != null ? UserModel.fromFirebaseUser(user) : null;
  }

  @override
  Future<void> updateProfile({String? displayName}) async {
    try {
      final user = _firebaseAuth.currentUser;
      if (user == null) throw const AuthException('Usuário não autenticado.');
      if (displayName != null) {
        await user.updateDisplayName(displayName);
        await user.reload();
      }
      await _firestore.collection('users').doc(user.uid).set({
        'userId': user.uid,
        'email': user.email,
        'displayName': displayName ?? user.displayName ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(_kTimeout);
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.message ?? 'Erro ao atualizar perfil.');
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(e.toString());
    }
  }

  @override
  Future<void> updatePassword(
      String currentPassword, String newPassword) async {
    try {
      final user = _firebaseAuth.currentUser;
      if (user == null || user.email == null) {
        throw const AuthException('Usuário não autenticado.');
      }
      // Re-authenticate before changing password
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.message ?? 'Erro ao alterar senha.');
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(e.toString());
    }
  }

  @override
  Future<void> linkEmailPassword(String password) async {
    try {
      final user = _firebaseAuth.currentUser;
      if (user == null || user.email == null) {
        throw const AuthException('Usuário não autenticado.');
      }
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.linkWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.message ?? 'Erro ao definir senha.');
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(e.toString());
    }
  }

  @override
  Future<void> deleteAccount({String? password}) async {
    try {
      final user = _firebaseAuth.currentUser;
      if (user == null) throw const AuthException('Usuário não autenticado.');

      // Re-authenticate before deleting (Firebase security requirement)
      final hasPassword =
          user.providerData.any((p) => p.providerId == 'password');
      if (hasPassword) {
        if (password == null || password.isEmpty) {
          throw const AuthException('Senha obrigatória para confirmar exclusão.');
        }
        final credential = EmailAuthProvider.credential(
          email: user.email!,
          password: password,
        );
        await user.reauthenticateWithCredential(credential);
      } else {
        // Google-only user — re-authenticate with Google
        final googleUser = await _googleSignIn.signIn();
        if (googleUser == null) throw const AuthException('Autenticação cancelada.');
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        await user.reauthenticateWithCredential(credential);
      }

      await user.delete();
      // Explicitly sign out to guarantee authStateChanges emits null
      // (user.delete() alone may not always trigger the stream on all platforms).
      try { await _firebaseAuth.signOut(); } catch (_) {}
      _googleSignIn.signOut().ignore();
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.message ?? 'Erro ao excluir conta.');
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(e.toString());
    }
  }
}
