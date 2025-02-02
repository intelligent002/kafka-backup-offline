#!/usr/bin/env bash

set -e  # Exit on error
set -u  # Treat unset variables as errors

# ==============================
# CONFIGURATION
# ==============================
VALIDITY_IN_DAYS=3650
TRUSTSTORE_DIR="truststore"
KEYSTORE_BASE_DIR="keystores"

# Common CA filenames
CA_CERT_FILE="ca-cert.pem"
CA_KEY_FILE="ca-key.pem"

# Passwords for keystores/truststores (ensure these are securely stored)
PARAM_PASS="changeme"

# List of brokers and users
CLUSTER_NODES=(node-{0..9})
CLIENT_USERS=(admin pub sub)

# Distinguished Name (DN) details
PARAM_OU="IT"
PARAM_O="Dynamic Studio"
PARAM_L="Tel Aviv"
PARAM_S="Center"
PARAM_C="IL"

# ==============================
# CLEANUP OLD ARTIFACTS
# ==============================
echo "🗑️  Removing old keystores and truststores..."
rm -rf "$TRUSTSTORE_DIR" "$KEYSTORE_BASE_DIR"
mkdir -p "$TRUSTSTORE_DIR" "$KEYSTORE_BASE_DIR"

# ==============================
# GENERATE TRUSTSTORE (CA)
# ==============================
echo "🔑 Generating CA private key and self-signed certificate..."
openssl req -new -x509 -passout pass:$PARAM_PASS -keyout "$TRUSTSTORE_DIR/$CA_KEY_FILE" \
    -out "$TRUSTSTORE_DIR/$CA_CERT_FILE" -days "$VALIDITY_IN_DAYS" \
    -subj "/C=$PARAM_C/ST=$PARAM_S/L=$PARAM_L/O=$PARAM_O/OU=$PARAM_OU/CN=Kafka-CA"

echo "📌 Truststore CA certificate created at: $TRUSTSTORE_DIR/$CA_CERT_FILE"

# Create a Java Truststore and import CA certificate
keytool -keystore "$TRUSTSTORE_DIR/kafka.truststore.jks" \
    -alias CARoot -import -file "$TRUSTSTORE_DIR/$CA_CERT_FILE" \
    -storepass "$PARAM_PASS" -noprompt

echo "📌 Truststore created: $TRUSTSTORE_DIR/kafka.truststore.jks"

# ==============================
# FUNCTION TO CREATE KEYSTORES
# ==============================
generate_keystore() {
    local entity="$1"
    local cn="$2"
    local dir="$KEYSTORE_BASE_DIR/$entity"
    local key_file="$dir/$entity.key"
    local csr_file="$dir/$entity.csr"
    local signed_cert_file="$dir/$entity.crt"
    local p12_keystore_file="$dir/kafka.keystore.p12"
    local jks_keystore_file="$dir/kafka.keystore.jks"

    echo "📌 Creating keystore for $entity ($cn)..."

    # Create a directory for the entity
    mkdir -p "$dir"

    # 1️⃣ Generate Private Key
    openssl genpkey -algorithm RSA -out "$key_file" -pass pass:$PARAM_PASS

    # 2️⃣ Generate CSR
    openssl req -new -key "$key_file" -out "$csr_file" \
        -subj "/C=$PARAM_C/ST=$PARAM_S/L=$PARAM_L/O=$PARAM_O/OU=$PARAM_OU/CN=$cn" \
        -passin pass:$PARAM_PASS

    # 3️⃣ Sign the CSR with CA
    openssl x509 -req -CA "$TRUSTSTORE_DIR/$CA_CERT_FILE" -CAkey "$TRUSTSTORE_DIR/$CA_KEY_FILE" \
        -passin pass:$PARAM_PASS -in "$csr_file" -out "$signed_cert_file" \
        -days "$VALIDITY_IN_DAYS" -CAcreateserial

    # 4️⃣ Create PKCS#12 (.p12) keystore
    openssl pkcs12 -export -in "$signed_cert_file" -inkey "$key_file" \
        -name "$entity" -certfile "$TRUSTSTORE_DIR/$CA_CERT_FILE" \
        -passin pass:$PARAM_PASS -passout pass:$PARAM_PASS \
        -out "$p12_keystore_file"

    echo "✅ PKCS#12 Keystore created: $p12_keystore_file"

    # 5️⃣ Convert PKCS#12 (.p12) to Java Keystore (.jks)
    keytool -importkeystore -srckeystore "$p12_keystore_file" -srcstoretype PKCS12 \
        -destkeystore "$jks_keystore_file" -deststoretype JKS \
        -srcstorepass "$PARAM_PASS" -deststorepass "$PARAM_PASS" -noprompt

    echo "✅ Java Keystore created: $jks_keystore_file"
}

# ==============================
# GENERATE KEYSTORES FOR NODES
# ==============================
echo "🔧 Generating keystores for nodes..."
for node in "${CLUSTER_NODES[@]}"; do
    generate_keystore "$node" "$node.intel.r7g.org"
done

# ==============================
# GENERATE KEYSTORES FOR CLIENTS
# ==============================
echo "👤 Generating keystores for clients..."
for client in "${CLIENT_USERS[@]}"; do
    generate_keystore "$client" "$client"
done

# ==============================
# DISTRIBUTE FILES AND CONFIGURE KAFKA
# ==============================
echo "🚀 All keystores and truststores generated successfully!"
echo "✅ Truststore: $TRUSTSTORE_DIR/kafka.truststore.jks"
echo "✅ Keystores: Stored under $KEYSTORE_BASE_DIR/{entity}/"