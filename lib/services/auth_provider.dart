// lib/services/auth_provider.dart
import 'dart:io';

abstract class AuthProvider {
  Future<bool> login(String username, String password);

  Future<Map<String, dynamic>?> currentUser();

  Future<bool> register({
    required String username,
    required String email,
    required String password,
    required String fullName,
    File? faceFile,
  });

  Future<void> logout();
}
