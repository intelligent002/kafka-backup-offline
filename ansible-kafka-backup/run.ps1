alias ansible-playbook="docker run -ti --rm -v ~/.ssh:/root/.ssh -v $(pwd):/apps -v /var/log/ansible:/var/log/ansible -w /apps alpine/ansible ansible-playbook"
alias ansible-playbook="docker run -ti --rm -v ~/.ssh:/root/.ssh -v $(pwd):/apps -v /data:/data -v /backup:/backup -w /apps ansible-with-archivators ansible-playbook"

ansible-playbook -i inventories/kafka-6-vms/inventory playbooks/playbook.yml --tags "config_backup"

docker run -ti --rm `
    -v "c:\users\intel\.ssh:/root/.ssh" `
    -v "$(Get-Location):/apps" `
    -w "/apps" `
    alpine/ansible ansible-playbook -i inventory playbook.yml --tags "config_backup"

ansible-playbook -i inventories/kafka-6-vms/inventory playbooks/backup.yml --tags "config_backup"
ansible-playbook -i inventories/kafka-6-vms/inventory playbooks/backup.yml --tags "config_restore" --extra-vars "restore_archive=/backup/cold/config/rotated/2024/12/31/2024-12-31---20-58-12---config.tar.zx"
ansible-playbook -i inventories/kafka-6-vms/inventory playbooks/backup.yml --tags "data_backup"
ansible-playbook -i inventories/kafka-6-vms/inventory playbooks/backup.yml --tags "data_restore"  --extra-vars "restore_archive=/backup/cold/data/rotated/2024/12/31/2024-12-31---20-58-40---data.tar.zx"
ansible-playbook -i inventories/kafka-6-vms/inventory playbooks/backup.yml --tags "containers_stop"
ansible-playbook -i inventories/kafka-6-vms/inventory playbooks/backup.yml --tags "containers_start"
ansible-playbook -i inventories/kafka-6-vms/inventory playbooks/backup.yml --tags "containers_restart"
ansible-playbook -i inventories/kafka-6-vms/inventory playbooks/backup.yml --tags "containers_remove"
ansible-playbook -i inventories/kafka-6-vms/inventory playbooks/backup.yml --tags "containers_run"

ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "config_backup"
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "config_restore" --extra-vars "restore_archive=/backup/cold/config/rotated/2025/01/02/2025-01-02---16-25-28---config.tar.zx"
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "data_backup"
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "data_restore"  --extra-vars "restore_archive=/backup/cold/data/rotated/2025/01/02/2025-01-02---16-12-46---data.tar.zx"
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "containers_stop"
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "containers_start"
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "containers_restart"
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "containers_remove"
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "containers_run"
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "cert_deploy"

# Config Backup
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "config_backup"
# Data Backup
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "data_backup"

# Config Restore (with Docker Restart)
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "config_restore,docker_restart" --extra-vars "restore_archive=/backup/cold/config/rotated/2025/01/02/2025-01-02---16-25-28---config.tar.zx"
# Data Restore (with Docker Restart)
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "data_restore,docker_restart"   --extra-vars "restore_archive=/backup/cold/data/rotated/2025/01/02/2025-01-02---16-12-46---data.tar.zx"

# Stop Containers
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "containers_stop"

# Start Containers
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "containers_start"

# Restart Containers
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "containers_restart"

# Remove Containers
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "containers_remove"

# Run Containers
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "containers_run"

# Certificate Deployment (with Docker Restart)
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "cert_deploy,docker_restart"



i was thinking about:

backup (the existing on nodes into zip of zips like with configs and data)
restore (from zip of zips archive like with config and data)
renew - this one is cron based, also useful for initial generation and deployment
    1 validate presence, in case of missing - generate new set via certbot & convert to p12
    2 validate expiration, in case of expired by threshold - generate new set via certbot & convert to p12
    3 distribute to nodes,
    4 restart nodes
