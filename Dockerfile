# Use Apache Kafka 3.9.0 as base image
FROM apache/kafka:3.9.0

# Set environment variables for Kerberos
ENV KRB5_CONFIG=/etc/krb5.conf \
    KRB5CCNAME=/var/run/krb5cc

# Install necessary Kerberos packages
USER root

# For Alpine-based images
RUN apk add --no-cache krb5-libs krb5

# Copy Kerberos configuration and keytab file from host
COPY krb5.conf /etc/krb5.conf
COPY krb5.keytab /etc/krb5.keytab

# Set permissions for keytab
RUN chmod 600 /etc/krb5.keytab

# Automatically authenticate using Kerberos at startup
CMD ["sh", "-c", "kinit -kt /etc/krb5.keytab MSSQLSvc/kafka-mssql.intel.r7g.org:1433@INTEL.R7G.ORG && /opt/kafka/bin/connect-distributed.sh /mnt/shared/config/kraft.properties"]

