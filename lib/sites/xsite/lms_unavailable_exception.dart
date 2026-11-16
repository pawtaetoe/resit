/// A course tool xSiTe won't give the app (not used in the course, or not
/// open to students), as opposed to being signed out.
class LmsUnavailableException implements Exception {
  final String path;
  LmsUnavailableException(this.path);

  @override
  String toString() => "This isn't available for this course on xSiTe.";
}
