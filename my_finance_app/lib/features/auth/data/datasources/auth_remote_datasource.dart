import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;
  // Web Client ID from google-services.json (oauth_client type 3)
  // Required on Android to resolve ApiException:10 (DEVELOPER_ERROR)
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId:
        '53669256636-ebovakj9raemrpkmj7hl5j32i4h357t7.apps.googleusercontent.com',
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
      await Future.wait([
        _firebaseAuth.signOut(),
        _googleSignIn.signOut(),
      ]);
    } catch (e) {
      throw const AuthException('Erro ao sair da conta.');
    }
  }

  @override
  Stream<UserModel?> get authStateChanges {
    return _firebaseAuth.authStateChanges().map(
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
}
