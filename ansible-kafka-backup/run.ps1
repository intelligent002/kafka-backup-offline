alias ansible-playbook="docker run -ti --rm -v ~/.ssh:/root/.ssh -v $(pwd):/apps -v /data:/data -v /backup:/backup -w /apps alpine/ansible ansible-playbook"
alias ansible-playbook="docker run -ti --rm -v ~/.ssh:/root/.ssh -v $(pwd):/apps -v /data:/data -v /backup:/backup -w /apps ansible-with-archivators ansible-playbook"

ansible-playbook -i inventories/productions/inventory playbooks/playbook.yml --tags "backup_config"

docker run -ti --rm `
    -v "c:\users\intel\.ssh:/root/.ssh" `
    -v "$(Get-Location):/apps" `
    -w "/apps" `
    alpine/ansible ansible-playbook -i inventory playbook.yml --tags "backup_config"