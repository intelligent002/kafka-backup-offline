#!/bin/bash

echo "controller ... "

rm /data/single-node/controller/data/logs/* -rf
rm /data/single-node/controller/data/meta/* -rf
rm /data/single-node/controller/logs/* -rf

docker run --rm \
-v /data/single-node/controller/config:/mnt/shared/config \
-v /data/single-node/controller/data/logs:/var/lib/kafka/data \
-v /data/single-node/controller/data/meta:/var/lib/kafka/meta \
-v /data/single-node/controller/logs:/opt/kafka/logs \
-v /data/single-node/controller/certificates:/etc/kafka/secrets \
apache/kafka:3.9.0 \
/opt/kafka/bin/kafka-storage.sh format \
--cluster-id AkU3OEVBNTcwNTJENDM2Qd \
--ignore-formatted \
--config /mnt/shared/config/kraft.properties

echo "broker ... "

rm /data/single-node/broker/data/logs/* -rf
rm /data/single-node/broker/data/meta/* -rf
rm /data/single-node/broker/logs/* -rf

docker run --rm \
-v /data/single-node/broker/config:/mnt/shared/config \
-v /data/single-node/broker/data/logs:/var/lib/kafka/data \
-v /data/single-node/broker/data/meta:/var/lib/kafka/meta \
-v /data/single-node/broker/logs:/opt/kafka/logs \
-v /data/single-node/broker/certificates:/etc/kafka/secrets \
apache/kafka:3.9.0 \
/opt/kafka/bin/kafka-storage.sh format \
--cluster-id AkU3OEVBNTcwNTJENDM2Qd \
--ignore-formatted \
--add-scram 'SCRAM-SHA-512=[name=admin,password=insecure]' \
--config /mnt/shared/config/kraft.properties
