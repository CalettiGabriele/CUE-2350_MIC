#!/bin/zsh
# Creates the self-signed code-signing identity "CUE-2350 MIC Dev" in the login keychain.
# Run it once yourself. Afterwards bundle.sh signs the app with it, macOS ties the
# Accessibility grant to this certificate instead of the binary hash, and the grant survives
# rebuilds (no more reinstall.sh). The certificate is only valid on this Mac for local builds.
set -euo pipefail
NAME="CUE-2350 MIC Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OPENSSL=/usr/bin/openssl   # system LibreSSL: its PKCS#12 output is what `security import` expects

if security find-identity -p codesigning | grep -q "\"$NAME\""; then
  echo "L'identità \"$NAME\" esiste già."
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
PASS=$("$OPENSSL" rand -hex 16)
"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -out "$TMP/identity.p12" -passout "pass:$PASS"
# -T: let codesign use the key without a keychain prompt at every build.
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign

echo
security find-identity -p codesigning | grep "\"$NAME\"" && \
  echo "Fatto. Alla prossima build l'app verrà firmata con \"$NAME\"."
