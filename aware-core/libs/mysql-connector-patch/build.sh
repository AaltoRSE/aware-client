#!/usr/bin/env bash
# Build the AWARE-patched MySQL Connector/J 5.1.48 jar
#
# Connector/J 5.1.48 does not check that the server certificate matches the
# host name. ExportControlled.patch adds that check to
# com.mysql.jdbc.ExportControlled.transformSocketToSSLSocket. This script
# downloads the official 5.1.48 sources from Maven Central, verifies their
# SHA-1, applies the patch, compiles the patched class (Java 7 bytecode)
# against the original jar and writes ../mysql-connector-java-5.1.48-aware.jar:
# a copy of the original jar with the ExportControlled*.class files replaced.
#
# Usage: build.sh [path/to/original/mysql-connector-java-5.1.48.jar]
#   The original jar defaults to ../mysql-connector-java-5.1.48.jar relative to
#   this script.
#   Requires JDK 11 (JAVA_HOME, default /usr/lib/jvm/java-11-openjdk-amd64),
#   curl, sha1sum and patch.
#
# Licence: MySQL Connector/J is licensed under GPLv2 with the Universal FOSS
# Exception. The modification is published here in source form
# (ExportControlled.patch) together with this build script.

set -euo pipefail

VERSION=5.1.48
SOURCES_URL="https://repo1.maven.org/maven2/mysql/mysql-connector-java/${VERSION}/mysql-connector-java-${VERSION}-sources.jar"
CLASS_SRC=com/mysql/jdbc/ExportControlled.java

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBS_DIR="$(dirname "$SCRIPT_DIR")"
PATCH_FILE="$SCRIPT_DIR/ExportControlled.patch"
ORIG_JAR="$(realpath "${1:-$LIBS_DIR/mysql-connector-java-${VERSION}.jar}")"
OUT_JAR="$LIBS_DIR/mysql-connector-java-${VERSION}-aware.jar"

JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-11-openjdk-amd64}"
JAVAC="$JAVA_HOME/bin/javac"
JAR="$JAVA_HOME/bin/jar"

for tool in "$JAVAC" "$JAR"; do
    if [ ! -x "$tool" ]; then
        echo "error: $tool not found; set JAVA_HOME to a JDK 11 installation" >&2
        exit 1
    fi
done
for cmd in curl sha1sum patch; do
    command -v "$cmd" >/dev/null || { echo "error: $cmd is required" >&2; exit 1; }
done
[ -f "$ORIG_JAR" ] || { echo "error: original jar not found: $ORIG_JAR" >&2; exit 1; }
[ -f "$PATCH_FILE" ] || { echo "error: patch not found: $PATCH_FILE" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

echo "Downloading Connector/J ${VERSION} sources"
curl -fsSL -o sources.jar "$SOURCES_URL"
curl -fsSL -o sources.jar.sha1 "$SOURCES_URL.sha1"
expected="$(tr -d '[:space:]' < sources.jar.sha1 | cut -c1-40)"
actual="$(sha1sum sources.jar | cut -d' ' -f1)"
if [ "$expected" != "$actual" ]; then
    echo "error: SHA-1 mismatch for sources jar (expected $expected, got $actual)" >&2
    exit 1
fi
echo "SHA-1 OK: $actual"

mkdir src classes
(cd src && "$JAR" xf ../sources.jar "$CLASS_SRC")

echo "Applying patch"
(cd src && patch -p0 < "$PATCH_FILE")

echo "Compiling patched ExportControlled"
"$JAVAC" --release 7 -nowarn -encoding UTF-8 -cp "$ORIG_JAR" -d classes "src/$CLASS_SRC"

echo "Writing $OUT_JAR"
cp "$ORIG_JAR" "$OUT_JAR"
(cd classes && "$JAR" uf "$OUT_JAR" com/mysql/jdbc/ExportControlled*.class)

echo "Updated classes:"
"$JAR" tvf "$OUT_JAR" | grep 'com/mysql/jdbc/ExportControlled'
