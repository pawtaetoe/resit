import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/features/calendar/calendar_providers.dart';
import 'package:resit/features/exams/exams_providers.dart';
import 'package:resit/features/lms/lms_providers.dart';
import 'package:resit/features/lms/lms_calendar_providers.dart';
import 'package:resit/features/timetable/timetable_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The login saved on the device, as the Account tab shows it.
class SavedLogin {
  final String? username;

  /// A password is saved (or held for this run of the app). The password
  /// itself is never handed to the screen, so it can't be put back into the
  /// form, where "show password" would reveal it to anyone holding the phone.
  final bool hasPassword;

  final bool remembersPassword;

  const SavedLogin({this.username, required this.hasPassword, required this.remembersPassword});
}

/// What the Account tab does: signing in with what was typed, signing out
/// (and removing what the app saved about the student), and whether the
/// password is kept on the device.
class AccountService {
  final Ref _ref;

  AccountService(this._ref);

  Future<SavedLogin> savedLogin() async {
    final storage = _ref.read(secureStorageProvider);
    final creds = await storage.getCredentials();
    final remember = await storage.remembersPassword();
    return SavedLogin(
      username: creds['username'],
      hasPassword: (creds['password'] ?? '').isNotEmpty,
      remembersPassword: remember,
    );
  }

  /// Signs in with [username] and [password], as typed. Whether it worked.
  Future<bool> signIn(String username, String password) async {
    // Left blank: keep the saved password (e.g. only the ID changed).
    // Passwords can legitimately start or end with spaces, so no trim.
    final usedPassword =
        password.isNotEmpty ? password : (await _ref.read(secureStorageProvider).getCredentials())['password'] ?? '';
    return _ref.read(sessionControllerProvider.notifier).signInWith(username.trim(), usedPassword);
  }

  Future<void> setRemembersPassword(bool remember) => _ref.read(secureStorageProvider).setRemembersPassword(remember);

  /// Signs out. Saved results, the timetable and xSiTe's copies are removed
  /// from the device either way; with [forgetDetails], so are the saved
  /// login, the code secret and settings that say something about the
  /// student.
  Future<void> signOut({required bool forgetDetails}) async {
    await _ref.read(sessionControllerProvider.notifier).signOut(forgetDetails: forgetDetails);
    // Grades and the timetable don't stay on the device after any sign-out.
    await _ref.read(academicRecordServiceProvider).clear();
    _ref.invalidate(savedAcademicRecordProvider);
    _ref.invalidate(academicRecordProvider);
    await _ref.read(upcomingClassesServiceProvider).clear();
    await _ref.read(timetableWeekStoreProvider).clear();
    _ref.invalidate(savedUpcomingClassesProvider);
    _ref.invalidate(upcomingClassesProvider);
    _ref.read(lmsServiceProvider).clearCache();
    _ref.invalidate(lmsProgressProvider);
    _ref.invalidate(lmsContentsProvider);
    for (final p in [
      lmsAnnouncementsProvider,
      lmsAssignmentsProvider,
      lmsQuizzesProvider,
      lmsGradesProvider,
      lmsGroupsProvider,
      lmsCourseDueProvider,
      lmsCourseUpdatesProvider,
    ]) {
      _ref.invalidate(p);
    }
    // Only if loaded: invalidating one that isn't would load it.
    for (final p in [lmsCalendarProvider, lmsUpdatesProvider]) {
      if (_ref.exists(p)) _ref.invalidate(p);
    }
    if (forgetDetails) {
      // Settings that say something about the student (their modules,
      // graduation year, usual booking) go too.
      try {
        final prefs = await SharedPreferences.getInstance();
        for (final key in const [
          'module_colours',
          'graduation_year',
          'graduation_date',
          'book_duration',
          'book_start',
          'book_types',
        ]) {
          await prefs.remove(key);
        }
      } catch (_) {}
      _ref.invalidate(graduationYearProvider);
      _ref.invalidate(totpConfigProvider);
    }
  }
}
