import 'package:shared_preferences/shared_preferences.dart';

/// Accepts a phone number with optional leading + and separators (spaces, dashes).
bool isValidEmergencyPhone(String input) {
  final normalized = normalizeEmergencyPhone(input);
  return RegExp(r'^\+?[0-9]{8,15}$').hasMatch(normalized);
}

String normalizeEmergencyPhone(String input) =>
    input.trim().replaceAll(RegExp(r'[\s\-()]'), '');

abstract interface class EmergencyContactStore {
  Future<String?> read();
  Future<void> write(String phone);
}

/// The preset number is stored only on this device.
final class SharedPreferencesEmergencyContactStore
    implements EmergencyContactStore {
  static const _key = 'safe_walk.emergency_contact_phone';

  @override
  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<void> write(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, normalizeEmergencyPhone(phone));
  }
}
