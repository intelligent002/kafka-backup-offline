#!/bin/bash

# Configuration
DAYS=3650
PASSWORD="insecure"
OUTPUT_DIR="output"
DOMAINS=("node-1.intel.r7g.org" "node-2.intel.r7g.org" "node-3.intel.r7g.org" "node-4.intel.r7g.org" "node-5.intel.r7g.org" "node-6.intel.r7g.org" )

# Create directories
mkdir -p ca brokers controllers "$OUTPUT_DIR"

# 1. Generate CA
openssl req -new -x509 -keyout ca/ca.key -out ca/ca.crt -days "$DAYS" \
  -passout pass:"$PASSWORD" -config openssl.cnf

# 2. Generate individual certificates for each node
for domain in "${DOMAINS[@]}"; do
  TYPE="brokers"
  [[ "$domain" == controller* ]] && TYPE="controllers"

  echo "Generating certs for: $domain"

  # Generate private key
  openssl genpkey -algorithm RSA -out "$TYPE/$domain.key" -pass pass:"$PASSWORD"

  # Generate CSR (using the pre-configured openssl.cnf)
  openssl req -new -key "$TYPE/$domain.key" -out "$TYPE/$domain.csr" \
    -subj "/CN=$domain" -config openssl.cnf

  # Sign certificate (using the pre-configured openssl.cnf)
  openssl x509 -req -in "$TYPE/$domain.csr" -CA ca/ca.crt -CAkey ca/ca.key \
    -CAcreateserial -out "$TYPE/$domain.crt" -days "$DAYS" -extensions v3_req \
    -extfile openssl.cnf # Important: Point to the config file directly

  # Create PKCS12 keystore
  openssl pkcs12 -export -in "$TYPE/$domain.crt" -inkey "$TYPE/$domain.key" \
    -name "$domain" -passin pass:"$PASSWORD" -passout pass:"$PASSWORD" \
    -out "$OUTPUT_DIR/$domain.keystore.p12"

  # Cleanup
  rm "$TYPE/$domain.csr"
done

# 3. Create truststore with CA
keytool -import -trustcacerts -noprompt -alias ca -file ca/ca.crt \
  -keystore "$OUTPUT_DIR/shared.truststore.jks" -storepass "$PASSWORD"

echo "Certificates generated in $OUTPUT_DIR:"
ls -lh "$OUTPUT_DIR"
