#!/bin/bash

# Get current date as version in format: YYYY-MM-DD---HH-MM-SS
version=$(date +"%Y-%m-%d---%H-%M-%S")
echo "Deployment version: $version"

# Define the hosts
hosts=("node-7.intel.r7g.org" "node-8.intel.r7g.org" "node-9.intel.r7g.org")

docker build . --tag docker.artifactory.intel.r7g.org/kafka-connect-kerberos:${version}
docker push docker.artifactory.intel.r7g.org/kafka-connect-kerberos:${version}

# Iterate over each host
for host in "${hosts[@]}"; do
    echo "Processing $host..."

    ssh root@$host <<EOF
        echo "Stopping and removing old container: $host"
        docker kill $host || true
        docker rm $host || true

        echo "Starting new Kafka Connect container on $host..."
        docker run -d --restart=always \
            --name=$host -h $host \
            -p 9999:9999 \
            -p 8080:8080 \
            -e KAFKA_HEAP_OPTS="-Xmx256M -Xms256M" \
            -e KAFKA_JMX_OPTS="
            -Djava.rmi.server.hostname=$host
            -Dcom.sun.management.jmxremote
            -Dcom.sun.management.jmxremote.port=9999
            -Dcom.sun.management.jmxremote.rmi.port=9999
            -Dcom.sun.management.jmxremote.authenticate=false
            -Dcom.sun.management.jmxremote.ssl=false
            " \
            -v /data/cluster/config:/mnt/shared/config \
            -v /data/cluster/certificates:/etc/kafka/secrets \
            -v /data/cluster/credentials:/credentials \
            -v /data/cluster/data/data:/var/lib/kafka/data \
            -v /data/cluster/data/meta:/var/lib/kafka/meta \
            -v /data/cluster/logs:/opt/kafka/logs \
            -v /data/cluster/plugins:/usr/share/java \
            docker.artifactory.intel.r7g.org/kafka-connect-kerberos:${version}

        echo "Kafka container started on $host!"
EOF

    echo "Finished processing $host."
done

echo "Deployment completed."
