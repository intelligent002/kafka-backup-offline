#!/usr/bin/env bash

log=/var/log/kafka/cron.log
echo "-------------------------------------$(date) - Running backup-------------------------------------" >> $log
./kafka-backup-offline.sh cluster_backup >> $log 2>&1
