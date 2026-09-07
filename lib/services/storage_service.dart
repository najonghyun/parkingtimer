import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/parking_state.dart';

/// Thin wrapper around [SharedPreferences] that (de)serializes [ParkingState]
/// as a single JSON blob under one key.
class StorageService {
  static const _stateKey = 'parking_state_v1';

  Future<ParkingState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_stateKey);
    if (raw == null) return ParkingState();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return ParkingState.fromJson(json);
    } catch (_) {
      return ParkingState();
    }
  }

  Future<void> save(ParkingState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stateKey, jsonEncode(state.toJson()));
  }
}
