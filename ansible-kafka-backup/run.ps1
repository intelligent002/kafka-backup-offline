alias ansible-playbook="docker run -ti --rm -v ~/.ssh:/root/.ssh -v $(pwd):/apps -v /data:/data -v /backup:/backup -w /apps alpine/ansible ansible-playbook"
alias ansible-playbook="docker run -ti --rm -v ~/.ssh:/root/.ssh -v $(pwd):/apps -v /data:/data -v /backup:/backup -w /apps ansible-with-archivators ansible-playbook"

ansible-playbook -i inventories/productions/inventory playbooks/playbook.yml --tags "config_backup"

docker run -ti --rm `
    -v "c:\users\intel\.ssh:/root/.ssh" `
    -v "$(Get-Location):/apps" `
    -w "/apps" `
    alpine/ansible ansible-playbook -i inventory playbook.yml --tags "config_backup"

ansible-playbook -i inventories/production/inventory playbooks/backup.yml --tags "config_backup"
ansible-playbook -i inventories/production/inventory playbooks/backup.yml --tags "config_restore" --extra-vars "restore_archive=/backup/cold/config/rotated/2024/12/31/2024-12-31---20-58-12---config.tar.zx"

ansible-playbook -i inventories/production/inventory playbooks/backup.yml --tags "data_backup"
ansible-playbook -i inventories/production/inventory playbooks/backup.yml --tags "data_restore"  --extra-vars "restore_archive=/backup/cold/data/rotated/2024/12/31/2024-12-31---20-58-40---data.tar.zx"

ansible-playbook -i inventories/production/inventory playbooks/backup.yml --tags "containers_stop"
ansible-playbook -i inventories/production/inventory playbooks/backup.yml --tags "containers_start"
ansible-playbook -i inventories/production/inventory playbooks/backup.yml --tags "containers_restart"
ansible-playbook -i inventories/production/inventory playbooks/backup.yml --tags "containers_remove"
ansible-playbook -i inventories/production/inventory playbooks/backup.yml --tags "containers_run"