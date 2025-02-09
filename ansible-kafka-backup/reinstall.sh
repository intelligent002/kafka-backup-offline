#!/usr/bin/env bash
set -e

# Ensure the inventory is passed as an argument
if [ $# -ne 1 ]; then
    echo "Usage: $0 <inventory>"
    echo "Example: $0 kafka-3-vms"
    exit 1
fi

INVENTORY=$1

# Set the working directory based on the location
cd /data/KBO/ansible-kafka-backup/

# Define the ansible_playbook function
ansible_playbook() {
    docker run -ti --rm \
        -v ~/.ssh:/root/.ssh \
        -v $(pwd):/apps \
        -v /var/log/ansible:/var/log/ansible \
        -w /apps alpine/ansible ansible-playbook "$@"
}

# Update repository and set permissions
git pull && chmod +x /data/KBO/kafka-backup-offline.sh

# Execute Ansible playbooks
ansible_playbook -i inventories/kafka-6-vms/hosts.yml playbooks/serial.yml --tags "containers_remove"
ansible_playbook -i inventories/$INVENTORY/hosts.yml playbooks/parallel.yml --tags "configs_generate"
ansible_playbook -i inventories/$INVENTORY/hosts.yml playbooks/parallel.yml --tags "certificates_generate"
ansible_playbook -i inventories/$INVENTORY/hosts.yml playbooks/parallel.yml --tags "credentials_generate"
ansible_playbook -i inventories/$INVENTORY/hosts.yml playbooks/parallel.yml --tags "data_format"
ansible_playbook -i inventories/$INVENTORY/hosts.yml playbooks/serial.yml --tags "containers_run"
