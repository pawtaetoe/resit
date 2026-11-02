#!/usr/bin/env bash
# Packages the Flutter Linux release build into a .deb.
#
# Usage: scripts/package_deb.sh <version> [output-dir]
#   Run `flutter build linux --release` first. The package installs the app
#   to /opt/resit, a `resit` command in /usr/bin, a desktop entry and an icon.
set -euo pipefail

VERSION="${1:?usage: package_deb.sh <version> [output-dir]}"
OUT="${2:-dist}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="$ROOT/build/linux/x64/release/bundle"
PKG="$(mktemp -d)"
chmod 755 "$PKG"   # mktemp makes it 700; that would become the package root
trap 'rm -rf "$PKG"' EXIT

[ -x "$BUNDLE/resit" ] || { echo "No Linux build at $BUNDLE; run: flutter build linux --release" >&2; exit 1; }

mkdir -p "$PKG/DEBIAN" "$PKG/opt/resit" "$PKG/usr/bin" "$PKG/usr/share/applications" "$PKG/usr/share/pixmaps"
cp -r "$BUNDLE/." "$PKG/opt/resit/"
ln -s /opt/resit/resit "$PKG/usr/bin/resit"
cp "$ROOT/assets/icon/app_icon.png" "$PKG/usr/share/pixmaps/resit.png"

cat > "$PKG/usr/share/applications/resit.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=reSIT
Comment=Rooms, classes and results at SIT
Exec=/opt/resit/resit
Icon=resit
Categories=Education;Office;
Terminal=false
DESKTOP

# Installed size in KiB, as dpkg expects.
SIZE="$(du -sk "$PKG/opt" "$PKG/usr" | awk '{s+=$1} END {print s}')"

# Depends: what the app links against. Ubuntu 24.04 renamed some of these
# (…t64), so either name is accepted (Ubuntu 22.04/24.04, Debian 12/13).
cat > "$PKG/DEBIAN/control" <<CONTROL
Package: resit
Version: $VERSION
Section: education
Priority: optional
Architecture: amd64
Installed-Size: $SIZE
Depends: libgtk-3-0t64 | libgtk-3-0, libglib2.0-0t64 | libglib2.0-0, libsecret-1-0, libstdc++6
Maintainer: reSIT <noreply@github.com>
Description: reSIT - rooms, classes and results at SIT
 Book rooms, see your timetable, exam results and the academic calendar
 for the Singapore Institute of Technology.
CONTROL

mkdir -p "$OUT"
dpkg-deb --build --root-owner-group "$PKG" "$OUT/resit_${VERSION}_amd64.deb"
echo "Built $OUT/resit_${VERSION}_amd64.deb"
