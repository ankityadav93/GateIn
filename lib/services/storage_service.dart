import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/constants.dart';

class StorageService {
  final FlutterSecureStorage _storage;

  const StorageService(this._storage);

  // Credentials
  Future<String?> getUsername() => _storage.read(key: AppConstants.usernameKey);
  Future<String?> getPassword() => _storage.read(key: AppConstants.passwordKey);
  
  Future<void> saveCredentials(String username, String password) async {
    await _storage.write(key: AppConstants.usernameKey, value: username);
    await _storage.write(key: AppConstants.passwordKey, value: password);
  }

  Future<void> deleteDefaultCredentials() async {
    await _storage.delete(key: AppConstants.usernameKey);
    await _storage.delete(key: AppConstants.passwordKey);
  }

  // Accounts
  Future<Map<String, String>> readAllAccounts() async {
    final raw = await _storage.read(key: AppConstants.accountsKey);
    if (raw == null) return {};
    try {
      final Map parsed = jsonDecode(raw);
      return parsed.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> writeAllAccounts(Map<String, String> accounts) async {
    await _storage.write(
      key: AppConstants.accountsKey,
      value: jsonEncode(accounts),
    );
  }
}