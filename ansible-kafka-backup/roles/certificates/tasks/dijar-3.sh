#!/bin/bash

# Configuration
DAYS=3650
PASSWORD="changeme"
OUTPUT_DIR="output"
DOMAINS=("node-1.intel.r7g.org" "node-2.intel.r7g.org" "node-3.intel.r7g.org" "node-4.intel.r7g.org" "node-5.intel.r7g.org" "node-6.intel.r7g.org" "node-7.intel.r7g.org" "node-8.intel.r7g.org" "node-9.intel.r7g.org")
IP_ADDRESSES=("10.1.3.21" "10.1.3.22" "10.1.3.23" "10.1.3.24" "10.1.3.25" "10.1.3.26" "10.1.3.27" "10.1.3.28" "10.1.3.29")
USERS=("admin" "pub" "sub" "connect")  # List of users

# Recreate directories
rm -rf ca "$OUTPUT_DIR" users
mkdir -p ca "$OUTPUT_DIR" users

# 1. Generate CA
openssl req -new -x509 -keyout ca/ca.key -out ca/ca.crt -days "$DAYS" \
  -passout pass:"$PASSWORD" -subj "/CN=Kafka-CA"

# 2. Generate individual certificates for each node
for i in "${!DOMAINS[@]}"; do
  domain="${DOMAINS[$i]}"
  ip="${IP_ADDRESSES[$i]}"
  echo "Generating certs for: $domain (IP: $ip)"

  mkdir -p "$domain"

  # Generate a custom OpenSSL config for this node
  cat > "$domain/$domain.cnf" <<EOF
[ req ]
default_bits       = 4096
default_keyfile    = kafka.key
distinguished_name = req_distinguished_name
req_extensions     = v3_req
x509_extensions    = v3_ca
prompt             = no
encrypt_key        = no

[ req_distinguished_name ]
CN = $domain

[ v3_req ]
subjectAltName = @alt_names
keyUsage = keyEncipherment, dataEncipherment, digitalSignature
extendedKeyUsage = serverAuth, clientAuth

[ v3_ca ]
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always,issuer
basicConstraints=CA:true

[ alt_names ]
DNS.1 = $domain
IP.1  = $ip
EOF

  # Generate private key
  openssl genpkey -algorithm RSA -out "$domain/$domain.key" -pass pass:"$PASSWORD"

  # Generate CSR using the per-node OpenSSL config
  openssl req -new -key "$domain/$domain.key" -out "$domain/$domain.csr" \
    -subj "/CN=$domain" -config "$domain/$domain.cnf"

  # Sign certificate using the custom config
  openssl x509 -req -in "$domain/$domain.csr" -CA ca/ca.crt -CAkey ca/ca.key \
    -passin pass:"$PASSWORD" -CAcreateserial -out "$domain/$domain.crt" -days "$DAYS" -extensions v3_req \
    -extfile "$domain/$domain.cnf"

  # Create PKCS12 keystore
  openssl pkcs12 -export -in "$domain/$domain.crt" -inkey "$domain/$domain.key" \
    -certfile ca/ca.crt -name "$domain" -passin pass:"$PASSWORD" -passout pass:"$PASSWORD" \
    -out "$OUTPUT_DIR/$domain.keystore.p12"

  # Cleanup
  rm "$domain/$domain.csr" "$domain/$domain.cnf"
done

# 3. Generate certificates for users
for user in "${USERS[@]}"; do
  echo "Generating certs for user: $user"

  mkdir -p "users/$user"

  # Generate private key
  openssl genpkey -algorithm RSA -out "users/$user/$user.key" -pass pass:"$PASSWORD"

  # Generate CSR for user (no SAN needed)
  openssl req -new -key "users/$user/$user.key" -out "users/$user/$user.csr" \
    -subj "/CN=$user"

  # Sign user certificate
  openssl x509 -req -in "users/$user/$user.csr" -CA ca/ca.crt -CAkey ca/ca.key \
    -passin pass:"$PASSWORD" -CAcreateserial -out "users/$user/$user.crt" -days "$DAYS"

  # Create PKCS12 keystore for user
  openssl pkcs12 -export -in "users/$user/$user.crt" -inkey "users/$user/$user.key" \
    -certfile ca/ca.crt -name "$user" -passin pass:"$PASSWORD" -passout pass:"$PASSWORD" \
    -out "$OUTPUT_DIR/$user.keystore.p12"

  # Cleanup
  rm "users/$user/$user.csr"
done

# 4. Create truststore with CA
keytool -import -trustcacerts -noprompt -alias ca -file ca/ca.crt \
  -keystore "$OUTPUT_DIR/shared.truststore.jks" -storepass "$PASSWORD"

echo "Certificates generated in $OUTPUT_DIR:"
ls -lh "$OUTPUT_DIR"
