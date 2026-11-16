import 'package:shared_preferences/shared_preferences.dart';

/// The last room search's length and start time (in minutes) and room types.
typedef LastRoomSearch = ({int? duration, int? start, List<String>? types});

const _prefDuration = 'book_duration';
const _prefStart = 'book_start';
const _prefTypes = 'book_types';

/// The last search, or null if preferences can't be read. Preferences are a
/// convenience; callers carry on with their defaults.
Future<LastRoomSearch?> loadLastRoomSearch() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return (
      duration: prefs.getInt(_prefDuration),
      start: prefs.getInt(_prefStart),
      types: prefs.getStringList(_prefTypes),
    );
  } catch (_) {
    return null;
  }
}

/// Keeps this search for next time; failures are ignored.
Future<void> saveLastRoomSearch({required int duration, required int start, required Iterable<String> types}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefDuration, duration);
    await prefs.setInt(_prefStart, start);
    await prefs.setStringList(_prefTypes, types.toList());
  } catch (_) {}
}
