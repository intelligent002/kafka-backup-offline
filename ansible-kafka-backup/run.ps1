alias ansible-playbook="docker run -ti --rm -v ~/.ssh:/root/.ssh -v $(pwd):/apps -v /data:/data -v /backup:/backup -w /apps alpine/ansible ansible-playbook"
alias ansible-playbook="docker run -ti --rm -v ~/.ssh:/root/.ssh -v $(pwd):/apps -v /data:/data -v /backup:/backup -w /apps ansible-with-archivators ansible-playbook"

ansible-playbook -i inventories/productions/inventory playbooks/playbook.yml --tags "backup_config"

docker run -ti --rm `
    -v "c:\users\intel\.ssh:/root/.ssh" `
    -v "$(Get-Location):/apps" `
    -w "/apps" `
    alpine/ansible ansible-playbook -i inventory playbook.yml --tags "backup_config"

ansible-playbook -i inventories/production/inventory playbooks/backup.yml --tags "backup_config"
ansible-playbook -i inventories/production/inventory playbooks/backup.yml --tags "backup_data"

ansible-playbook -i inventories/production/inventory playbooks/backup.yml --tags "restore_config" --extra-vars "recovery_archive=/backup/cold/config/rotated/2024/12/31/2024-12-31---16-08-10---config.zip"
ansible-playbook -i inventories/production/inventory playbooks/backup.yml --tags "restore_data"  --extra-vars "recovery_archive=/backup/cold/data/rotated/2024/12/31/2024-12-31---16-08-27---data.zip"

ansible-playbook -i inventories/production/inventory playbooks/backup.yml --tags "containers_stop"
ansible-playbook -i inventories/production/inventory playbooks/backup.yml --tags "containers_start"
