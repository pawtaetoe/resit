import 'package:resit/sites/rbs/rbs_parsers.dart';
import 'package:resit/sites/rbs/rbs_requests.dart';

/// Cancelling a booking on RBS.
class BookingCanceller {
  final RbsRequests _rbs;

  BookingCanceller(this._rbs);

  /// Cancels a booking the way RBS's own "Cancel" button does: RBS first
  /// encrypts the booking reference (EncryptDecryptFunc), then SaveToCancel
  /// takes the encrypted ID and answers "1" when it's done.
  Future<void> cancel(String bookingRef, String reason) async {
    final ref = bookingRef.trim();
    if (ref.isEmpty) throw Exception("This booking has no reference, so it can't be cancelled from the app.");
    final csrfToken = await _rbs.requireCsrfToken();
    final id = await _encryptId(ref, csrfToken);

    final response = await _rbs.post(
      "/DHB001/SaveToCancel",
      {
        "__RequestVerificationToken": csrfToken,
        "bookID[]": id,
        "reason": reason,
      },
      referer: RbsRequests.dashboardPage,
    );
    if (response.statusCode != 200) {
      throw Exception("RBS answered ${response.statusCode} to the cancellation.");
    }
    if (!cancelSucceeded(response.body)) {
      throw Exception("RBS didn't confirm the cancellation. Check My bookings.");
    }
  }

  /// RBS's own encryption of a booking reference, as its pages ask for it
  /// before cancelling. The answer is the encrypted ID as plain text.
  Future<String> _encryptId(String bookingRef, String csrfToken) async {
    final response = await _rbs.post(
      "/common/EncryptDecryptFunc",
      {
        "_isEncrypt": "true",
        "_encryptData": bookingRef,
        "_decryptData": "",
        "__RequestVerificationToken": csrfToken,
      },
      referer: RbsRequests.dashboardPage,
      accept: "*/*",
    );
    final id = encryptedIdFrom(response.body);
    if (response.statusCode != 200 || id == null) {
      throw Exception("RBS didn't prepare the cancellation (status ${response.statusCode}).");
    }
    return id;
  }
}
