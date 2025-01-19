cd /data/KBO/kafka-backup-offline/ansible-kafka-backup/
alias ansible-playbook="docker run -ti --rm -v ~/.ssh:/root/.ssh -v $(pwd):/apps -v /var/log/ansible:/var/log/ansible -w /apps alpine/ansible ansible-playbook"
alias ansible_playbook="docker run -ti --rm -v ~/.ssh:/root/.ssh -v $(pwd):/apps -v /var/log/ansible:/var/log/ansible -w /apps alpine/ansible ansible-playbook"

alias ansible-playbook="docker run -ti --rm -v ~/.ssh:/root/.ssh -v $(pwd):/apps -v /data:/data -v /backup:/backup -w /apps ansible-with-archivators ansible-playbook"

ansible-playbook -i inventories/kafka-6-vms/inventory playbooks/playbook.yml --tags "config_backup"

docker run -ti --rm `
    -v "c:\users\intel\.ssh:/root/.ssh" `
    -v "$(Get-Location):/apps" `
    -w "/apps" `
    alpine/ansible ansible-playbook -i inventory playbook.yml --tags "config_backup"

ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "certificate_generate"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "certificate_backup"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "certificate_rotate"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "certificate_restore" --extra-vars "restore_archive=/backup/cold/certificate/rotated/2025/01/07/2025-01-07---11-26-34---certificate.tar.zx"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "credentials_generate"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "credentials_apply"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "credentials_backup"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "credentials_rotate"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "credentials_restore" --extra-vars "restore_archive=/backup/cold/certificate/rotated/2025/01/07/2025-01-07---11-26-34---certificate.tar.zx"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "config_deploy"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "config_backup"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "config_rotate"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "config_restore"      --extra-vars "restore_archive=/backup/cold/config/rotated/2025/01/07/2025-01-07---11-28-08---config.tar.zx"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "data_format"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "data_backup"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "data_rotate"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "data_restore"        --extra-vars "restore_archive=/backup/cold/data/rotated/2025/01/07/2025-01-07---00-01-28---data.tar.zx"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/serial.yml --tags "containers_run"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/serial.yml --tags "containers_restart"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/serial.yml --tags "containers_stop"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/serial.yml --tags "containers_start"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/serial.yml --tags "containers_remove"


cd /data/KBO/kafka-backup-offline/ansible-kafka-backup/
alias ansible-playbook="docker run -ti --rm -v ~/.ssh:/root/.ssh -v $(pwd):/apps -v /var/log/ansible:/var/log/ansible -w /apps alpine/ansible ansible-playbook"
git pull && chmod +x /data/KBO/kafka-backup-offline/kafka-backup-offline.sh
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/serial.yml --tags "containers_remove"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "data_format"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "config_deploy"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "credentials_generate"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/serial.yml --tags "containers_run"



ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "certificate_backup"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "certificate_generate"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "certificate_restore" --extra-vars "restore_archive=/backup/cold/certificate/rotated/2025/01/06/2025-01-06---23-32-02---certificate.tar.zx"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "config_backup"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "config_restore"      --extra-vars "restore_archive=/backup/cold/config/rotated/2025/01/06/2025-01-06---23-30-04---config.tar.zx"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "config_rotate"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "data_backup"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "data_format"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "data_restore"        --extra-vars "restore_archive=/backup/cold/data/rotated/2025/01/06/2025-01-06---23-32-21---data.tar.zx"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/parallel.yml --tags "data_rotate"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/serial.yml --tags "containers_remove"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/serial.yml --tags "containers_restart"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/serial.yml --tags "containers_run"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/serial.yml --tags "containers_start"
ansible-playbook -i inventories/kafka-6-vms/hosts.yml playbooks/serial.yml --tags "containers_stop"
