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
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "config_restore"      --extra-vars "restore_archive=/backup/cold/config/rotated/2025/01/02/2025-01-02---16-25-28---config.tar.zx"
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "data_backup"
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "data_restore"        --extra-vars "restore_archive=/backup/cold/data/rotated/2025/01/02/2025-01-02---16-12-46---data.tar.zx"
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "certificate_backup"
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "certificate_restore" --extra-vars "restore_archive=/backup/cold/certificate/rotated/2025/01/05/2025-01-05---11-11-34---certificate.tar.zx"
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "certificate_restore"
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "containers_stop"
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "containers_start"
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "containers_restart"
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "containers_remove"
ansible-playbook -i inventories/kafka-3-vms/inventory playbooks/backup.yml --tags "containers_run"
