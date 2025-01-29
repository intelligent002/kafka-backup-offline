#!/usr/bin/env bash

# Parses a specific section of an INI file and stores key-value pairs in an associative array.
# Skips comments and empty lines while trimming whitespace from keys and values.
# Stores results in the global associative array "ini_data" using "section.key" as the index.
function parse_ini_file()
{
    local ini_file=$1
    local section=$2
    local value
    declare -gA ini_data=()

    # Read the .ini file, skipping comments and empty lines
    while IFS="=" read -r key value; do
        key=$(echo "$key" | tr -d '[:space:]')         # Trim whitespace from key
        value=$(echo "$value" | tr -d '[:space:]')     # Trim whitespace from value
        [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue # Skip comments and blank lines
        ini_data["$section.$key"]="$value"
    done < <(awk -F '=' "/\[$section\]/,/^$/{if(NF==2)print}" "$ini_file")
}

# Loads configuration settings from an INI file and stores them in global variables.
# Validates if the configuration file exists before parsing.
# Uses `parse_ini_file` to extract values from the "general" and "storage" sections.
# Sets logging levels, file paths, and storage-related parameters.
function load_configuration()
{
    local config_file=$1 # Accept the config file path as an argument

    # Check if the configuration file exists
    if [[ ! -f "$config_file" ]]; then
        echo "Error: Configuration file '$config_file' not found!"
        exit 1
    fi

    declare -gA LOG_LEVELS=(
        ["DEBUG"]=0
        ["INFO"]=1
        ["WARN"]=2
        ["ERROR"]=3
    )

    # Load general configuration variables such as paths for PID and log files.
    parse_ini_file "$config_file" "general"
    PID_FILE="${ini_data[general.PID_FILE]}"   # Path to the PID file for ensuring single script execution
    LOG_FILE="${ini_data[general.LOG_FILE]}"   # Path to the log file for logging events
    LOG_LEVEL="${ini_data[general.LOG_LEVEL]}" # Log level above which the errors will be shown in console, log will contain all
    INVENTORY="${ini_data[general.INVENTORY]}" # inventory folder

    # Load storage configuration variables for temporary and cold backup storage paths.
    parse_ini_file "$config_file" "storage"
    STORAGE_TEMP="${ini_data[storage.STORAGE_TEMP]}"                         # Temporary storage directory on the GUI server
    STORAGE_COLD="${ini_data[storage.STORAGE_COLD]}"                         # Permanent cold storage directory for backups
    STORAGE_WARN_LOW="${ini_data[storage.STORAGE_WARN_LOW]}"                 # Percentage of free space, below which we will show a warning


    log "INFO" "Configuration loaded from '$config_file'"
}

# Displays a disclaimer message for the Kafka-Backup-Offline Utility.
# Warns that the solution is not suitable for production as it requires taking Kafka offline.
# Provides author contact details and version information.
function disclaimer()
{
    echo "==================================================================================================================="
    echo "                                    Kafka-Backup-Offline Utility - version 1.0.0                                   "
    echo "==================================================================================================================="
    echo
    echo "  © 2025 Rosenberg Arkady @ Dynamic Studio                      Contact: +972546373566 / intelligent002@gmail.com  "
    echo
    echo "  ** IMPORTANT NOTICE: **                                                                                          "
    echo "  This solution is **NOT SUITABLE FOR PRODUCTION USE** as it requires taking the Kafka Cluster offline             "
    echo "  for backup and restore operations. It is specifically designed for development and testing environments.         "
    echo
#    echo "  Support the project: [Buy Me a Coffee] ( https://buymeacoffee.com/intelligent002 ) ☕                            "
#    echo
    echo "==================================================================================================================="
}

# Displays a help message detailing available functions in the Kafka-Backup-Offline Utility.
# Categorizes routines into Coziness, Containers, and Backup sections.
# Provides usage instructions and descriptions for each function.
# Warns that without a specified function name, an interactive menu will be shown.
function help()
{
    disclaimer
    echo
    echo "  Usage: $0 [function_name]                                                                                        "
    echo
    echo "  Available routines:                                                                                              "
    echo
    echo "    Coziness section:                                                                                              "
    echo
    echo "      setup_sshs         Configure password-less SSH access to all cluster nodes by setting up SSH keys.           "
    echo
    echo "    Containers section:                                                                                            "
    echo
    echo "      cluster_containers_run     'docker run' the Kafka Cluster containers in the defined startup order                    "
    echo "      cluster_containers_start   'docker start' the Kafka Cluster containers in the defined startup order                  "
    echo "      cluster_containers_stop    'docker stop' the Kafka Cluster containers in the defined shutdown order                  "
    echo "      cluster_containers_restart 'docker restart' the Kafka Cluster containers in the defined shutdown & startup order     "
    echo "      cluster_containers_remove  'docker rm' the Kafka Cluster containers in the defined shutdown order                    "
    echo
    echo "    Backup section:                                                                                                "
    echo
    echo "      rotate_backups     Perform a backup rotation by deleting archives that are:                                  "
    echo "                         1. Older than retention policy days.                                                      "
    echo "                         2. Folders /backup/cold/config/rotated/ & /backup/cold/data/rotated/ are rotated.         "
    echo "                         3. Folders /backup/cold/config/pinned/  & /backup/cold/data/pinned/  are NOT rotated.     "
    echo "                            to keep a CONFIG backup forever - move it to /backup/cold/config/pinned/'              "
    echo "                            to keep a DATA backup forever   - move it to /backup/cold/data/pinned/'                "
    echo
    echo "      cluster_backup     Perform a Full Kafka Cluster Backup:                                                      "
    echo "                         1. Rotate backups                                                                         "
    echo "                         2. Shut down the cluster by 'docker stop' all containers in defined shutdown order        "
    echo "                         3. Backup cluster config, archive to cold storage                                         "
    echo "                         4. Backup cluster data, archive to cold storage                                           "
    echo "                         5. Start up the cluster by 'docker start' all containers in defined startup order         "
    echo
    echo "  If no routine name is specified, an interactive menu will be displayed.                                          "
    echo
    echo "==================================================================================================================="
    echo
}

# Cron-oriented function for automated Kafka cluster backups.
# 1. Stops all Kafka containers to ensure data consistency.
# 2. Backs up configurations, certificates, credentials & data. storing everything in cold storage.
# 3. Starts all Kafka containers after the backup process completes.
function cluster_backup()
{
    #cluster_containers_stop
    cluster_configs_backup
    cluster_certificates_backup
    cluster_credentials_backup
    #cluster_data_backup
    #cluster_containers_start
}

# Creates a PID file to prevent multiple script instances from running.
# Exits if the PID file exists, otherwise writes the current PID and sets a trap to remove the file on exit.
function create_pid_file()
{
    if [ -f "$PID_FILE" ]; then
        log "INFO" "Script is already running (PID: $(cat "$PID_FILE")). Exiting."
        exit 1
    fi

    echo $$ >"$PID_FILE"
    trap remove_pid_file EXIT
    log "DEBUG" "PID file created with PID: $$"
}

# Removes the PID file to allow future script executions.
# Logs the removal of the PID file for debugging purposes.
function remove_pid_file()
{
    rm -f "$PID_FILE"
    log "DEBUG" "PID file removed"
}

# Logs messages with a specified log level to both the console and log file.
# Compares the log level with the configured threshold to decide whether to print the message to the console.
function log()
{
    local level=$1
    local message=$2

    # Check if the $level exists in the LOG_LEVELS
    if [[ -z "${LOG_LEVELS[$level]}" ]]; then
        echo "specified log level [$level] is not defined"
        exit 1
    fi

    # Check if the $level is greater or equal to the $LOG_LEVEL
    if [[ "${LOG_LEVELS[$level]}" -ge "${LOG_LEVELS[$LOG_LEVEL]}" ]]; then
        echo "[$level] $message"
    fi

    # In any case - log the message
    echo "[$(date '+%Y/%m/%d %H:%M:%S')] [$level] $message" >>"$LOG_FILE"
}

# Checks the free disk space on a specified mount point and logs a warning if space is below the threshold.
# Logs a warning message if the available space is below 20% (or the configured `STORAGE_WARN_LOW` value).
function ensure_free_space()
{
    local mount free_storage free_percent

    mount=$1

    # Get the free storage (in KB & %) for the directory
    free_storage=$(df -P "$mount" | awk 'NR==2 {print $4}')
    free_percent=$(df -P "$mount" | awk 'NR==2 {print 100 - $5}')

    # Check if the free percentage is less than 20%
    if ((free_percent < STORAGE_WARN_LOW)); then
        log "WARN" "Low disk space in $mount. Available: ${free_storage}KB (${free_percent}% of total)."
    fi
}

# Runs an Ansible playbook inside a Docker container with specified routines and tags.
# Logs the start and end of the routine, and handles errors by logging the failed command.
function run_ansible_routine()
{
    local routine=$1
    local playbook=$2
    local tag=$3
    local extra_vars=${4:-}

    log "INFO" "Routine - ${routine^} - started"

    # Prepare the Docker command as a variable
    local docker_command="docker run -ti --rm
        -v ~/.ssh:/root/.ssh
        -v $(pwd):/apps
        -v /var/log/ansible:/var/log/ansible
        -w /apps alpine/ansible ansible-playbook
        -i inventories/$INVENTORY/hosts.yml playbooks/$playbook.yml
        --tags \"$tag\" $extra_vars"

    # Execute the command
    eval $docker_command || {
        log "ERROR" "Playbook failed! Exact command: $docker_command"
        return 1
    }

    log "INFO" "Routine - ${routine^} - OK"
    return 0
}

# Deploys SSH public keys to all cluster nodes **in parallel** using Ansible.
# If SSH keys are not set up, will use the password supplied using `--ask-pass` for all nodes.
function cluster_ssh_keys()
{
    run_ansible_routine "Deploy SSH Public Key on all nodes" "parallel" "ssh_keys" "--ask-pass"
    return $?
}

# Deploys prerequisites to all cluster nodes **in parallel** using Ansible.
# Validates if /data is mounted and has at least 40GB free space.
# Ensures /var/lib/docker is symlinked to /data/docker.
# Installs and verifies: Docker, XZ, Java, and rsync.
# Ensures Docker service is enabled and running.
function cluster_prerequisites()
{
    run_ansible_routine "Deploy prerequisites on all nodes" "parallel" "prerequisites"
    return $?
}

# Backs up Kafka certificates on all cluster nodes **in parallel** using Ansible.
# Ensures certificate files are preserved for recovery or migration.
function cluster_certificates_backup()
{
    run_ansible_routine "Kafka Certificates Backup" "parallel" "certificates_backup"
    return $?
}

# Restores Kafka certificates on all cluster nodes **in parallel** using Ansible.
# Uses the specified archive file to restore certificate files.
function cluster_certificates_restore()
{
    local archive=$1
    run_ansible_routine "Kafka Certificates Restore" "parallel" "certificates_restore" "--extra-vars \"restore_archive=$archive\""
    return $?
}

# Deploys Kafka configuration files to all cluster nodes **in parallel** using Ansible.
# Ensures all nodes have the latest configuration settings from inventory template.
function cluster_configs_generate()
{
    run_ansible_routine "Kafka Configs Deploy" "parallel" "configs_deploy"
    return $?
}

# Backs up Kafka configuration files from all cluster nodes **in parallel** using Ansible.
# Ensures configuration settings are preserved for recovery or migration.
function cluster_configs_backup()
{
    run_ansible_routine "Kafka Configs Backup" "parallel" "configs_backup"
    return $?
}

# Restores Kafka configuration files on all cluster nodes **in parallel** using Ansible.
# Uses the specified archive file to restore configuration settings.
function cluster_configs_restore()
{
    local archive=$1
    run_ansible_routine "Kafka Configs Restore" "parallel" "configs_restore" "--extra-vars \"restore_archive=$archive\""
    return $?
}

# Starts Kafka containers on all cluster nodes **in serial** using Ansible.
# Ensures proper startup order and avoids simultaneous resource contention.
function cluster_containers_run()
{
    run_ansible_routine "Kafka Containers Run" "serial" "containers_run"
    return $?
}

# Resumes existing Kafka containers on all cluster nodes **in serial** using Ansible.
# Ensures a controlled startup sequence to prevent conflicts.
function cluster_containers_start()
{
    run_ansible_routine "Kafka Containers Start" "serial" "containers_start"
    return $?
}

# Stops Kafka containers on all cluster nodes **in serial** using Ansible.
# Ensures a controlled shutdown to prevent data corruption or inconsistencies.
function cluster_containers_stop()
{
    run_ansible_routine "Kafka Containers Stop" "serial" "containers_stop"
    return $?
}

# Restarts Kafka containers on all cluster nodes **in serial**.
# Stops containers first, then starts them again in a controlled order.
function cluster_containers_restart()
{
    cluster_containers_stop
    cluster_containers_start
}

# Removes Kafka containers on all cluster nodes **in serial** using Ansible.
# Ensures a controlled removal sequence to prevent dependency issues.
function cluster_containers_remove()
{
    run_ansible_routine "Kafka Containers Remove" "serial" "containers_remove"
    return $?
}

# Backs up Kafka credentials on all cluster nodes **in parallel** using Ansible.
# Ensures authentication data is preserved for recovery or migration.
function cluster_credentials_backup()
{
    run_ansible_routine "Kafka Credentials Backup" "parallel" "credentials_backup"
    return $?
}

# Restores Kafka credentials on all cluster nodes **in parallel** using Ansible.
# Uses the specified archive file to restore authentication data.
function cluster_credentials_restore()
{
    local archive=$1
    run_ansible_routine "Kafka Credentials Restore" "parallel" "credentials_restore" "--extra-vars \"restore_archive=$archive\""
    return $?
}

# Formats Kafka data on all cluster nodes **in parallel** using Ansible.
# Prepares storage for new data by ensuring a clean state.
function cluster_data_format()
{
    run_ansible_routine "Kafka Data Format" "parallel" "data_format"
    return $?
}

# Backs up Kafka data on all cluster nodes **in parallel** using Ansible.
# Ensures data is preserved for recovery or migration.
function cluster_data_backup()
{
    run_ansible_routine "Kafka Data Backup" "parallel" "data_backup"
    return $?
}

# Restores Kafka data on all cluster nodes **in parallel** using Ansible.
# Uses the specified archive file to recover data.
function cluster_data_restore()
{
    local archive=$1
    run_ansible_routine "Kafka Data Restore" "parallel" "data_restore" "--extra-vars \"restore_archive=$archive\""
    return $?
}

# Displays a failure message using a Whiptail dialog box.
# Accepts a message string as an argument and shows it in a 10x60 box.
function show_failure_message() {
    whiptail --title "Failure" --msgbox "$1" 10 60
}

# Displays a success message using a Whiptail dialog box.
# Accepts a message string as an argument and shows it in a 10x60 box.
function show_success_message() {
    whiptail --title "Success" --msgbox "$1" 10 60
}

# Displays a warning message using a Whiptail dialog box.
# Accepts a message string as an argument and shows it in a 10x60 box.
function show_warning_message() {
    whiptail --title "Warning" --msgbox "$1" 10 60
}

# Displays the main menu using Whiptail for managing Kafka backup and restore.
# Allows navigation to submenus, Exits when the user selects "Quit" or presses ESC/cancel.
function main_menu() {
    while true; do
        choice=$(whiptail --title "Kafka Backup Offline" \
            --cancel-button "Quit" \
            --menu "Choose a section:" 15 50 8 \
            "1" "Quit" \
            "5" "Containers" \
            "2" "Accessories" \
            "3" "Certificates" \
            "4" "Configs" \
            "6" "Credentials" \
            "7" "Data" \
            3>&1 1>&2 2>&3)

        # Capture the exit status of whiptail
        local exit_status=$?

        # Exit on ESC or cancel
        if [[ $exit_status -eq 1 || $exit_status -eq 255 ]]; then
            exit 0
        fi

        # Handle user choices
        case $choice in
            1) exit 0 ;; # Exit
            2) accessories_menu ;;
            3) certificates_menu ;;
            4) configs_menu ;;
            5) containers_menu ;;
            6) credentials_menu ;;
            7) data_menu ;;
        esac
    done
}

# Displays the Accessories menu using Whiptail for managing auxiliary tasks.
# Provides options to deploy SSH keys and prerequisites across all nodes.
# Returns to the main menu when "Back" is selected or ESC/cancel is pressed.
function accessories_menu() {
    while true; do
        choice=$(whiptail --title "Kafka Backup Offline" \
            --cancel-button "Back" \
            --menu "Accessories > Choose an action:" 15 50 6 \
            "1" "Main menu" \
            "2" "Deploy SSH certificate - (ssh-copy-id)" \
            "3" "Deploy prerequisites - (docker etc)" \
            3>&1 1>&2 2>&3)

        # Capture the exit status of whiptail
        local exit_status=$?

        # Exit on ESC or cancel
        if [[ $exit_status -eq 1 || $exit_status -eq 255 ]]; then
            return 0
        fi

        case $choice in
            1)
               return 0 ;;
            2)
               cluster_ssh_keys
               if [[ $? -eq 0 ]]; then
                    show_success_message "SSH public key was deployed on all nodes successfully!"
               else
                    show_failure_message "Failed to deploy ssh public key!\nExit the tool and review the logs."
               fi
               ;;
            3)
               cluster_prerequisites
               if [[ $? -eq 0 ]]; then
                    show_success_message "Prerequisites was deployed on all nodes successfully!"
               else
                    show_failure_message "Failed to deploy prerequisites!\nExit the tool and review the logs."
               fi
               ;;
        esac
    done
}

# Displays the Certificates menu using Whiptail for managing Kafka certificates.
# Provides options to generate, backup, or restore certificates.
# Returns to the main menu when "Back" is selected or ESC/cancel is pressed.
function certificates_menu() {
    while true; do
        # Display Whiptail menu for choosing a certificate-related action
        choice=$(whiptail --title "Kafka Backup Offline" \
            --cancel-button "Back" \
            --menu "Certificates > Choose an action:" 15 50 6 \
            "1" "Main menu" \
            "2" "Generate" \
            "3" "Backup" \
            "4" "Restore" \
            3>&1 1>&2 2>&3)

        # Capture the exit status of the Whiptail menu
        local exit_status=$?

        # Exit the function if ESC or cancel is pressed
        if [[ $exit_status -eq 1 || $exit_status -eq 255 ]]; then
            return 0
        fi

        # Handle the user's menu choice
        case $choice in
            # Return to the main menu if "Main menu" is selected
            1)
               return 0 ;;
            # Trigger the certificate generation process if "Generate" is selected
            2)
               cluster_certificates_generate ;;
            # Backup certificates and handle the result if "Backup" is selected
            3)
               cluster_certificates_backup
               if [[ $? -eq 0 ]]; then
                    # Show success message if the backup is successful
                    show_success_message "Certificates were backed up successfully!"
               else
                    # Show failure message if the backup fails
                    show_failure_message "Failed to backup certificates!\nExit the tool and review the logs."
               fi
               ;;
            # Trigger the menu for restoring certificates if "Restore" is selected
            4)
               cluster_certificates_restore_menu ;;
        esac
    done
}

# Displays a Whiptail menu for restoring Kafka certificates from backup files.
# Lists available backup files with their sizes and allows the user to select one for restoration.
# If no backups are found, shows a warning and exits.
# Calls `cluster_certificates_restore` with the selected backup file.
function cluster_certificates_restore_menu()
{
    local storage_certificate certificates_backup_files choice selected_backup

    # Define the path to certificate backup storage
    storage_certificate="$STORAGE_COLD/certificate"

    # Find all available certificates backup files with their sizes
    certificates_backup_files=()
    mapfile -t certificates_backup_files < <(find "$storage_certificate" -type f -name "*.tar.*" -exec ls -lh {} \; | awk '{print $9, $5}' | sort)

    # Check if no files are available
    if [[ ${#certificates_backup_files[@]} -eq 0 ]]; then
        log "DEBUG" "No backup files found in $storage_certificate."
        show_warning_message "No backup files found in $storage_certificate."
        return 1
    fi

    # Prepare the options for whiptail menu
    local menu_options=("back" "Return to certificate Menu") # Add "Back" option first
    for i in "${!certificates_backup_files[@]}"; do
        # Add each backup file with its details to the menu options
        menu_options+=("$i" "${certificates_backup_files[$i]}")
    done

    # Display the menu using whiptail for user selection
    choice=$(whiptail --title "Kafka Backup Offline" \
        --cancel-button "Back" \
        --menu "Certificates > Restore > Choose a backup file to restore:" 40 130 32 \
        "${menu_options[@]}" 3>&1 1>&2 2>&3)

    # Capture the exit status of whiptail
    local exit_status=$?

    # Exit on ESC or cancel
    if [[ $exit_status -eq 1 || $exit_status -eq 255 || $choice == "back" ]]; then
        return 0
    fi

    # Get the selected backup file path
    selected_backup=$(echo "${certificates_backup_files[$choice]}" | awk '{print $1}')
    log "DEBUG" "Selected certificates backup file: $selected_backup"

    # Call the restore function with the selected backup file
    cluster_certificates_restore "$selected_backup"
    if [[ $? -eq 0 ]]; then
        # Show success message if restoration is successful
        show_success_message "Certificates restored successfully!"
    else
        # Show failure message if restoration fails
        show_failure_message "Failed to restore certificates."
    fi
}

# Displays the Configs menu using Whiptail for managing Kafka configurations.
# Provides options to generate, backup, or restore configuration files.
# Returns to the main menu when "Back" is selected or ESC/cancel is pressed.
function configs_menu() {
    while true; do
        choice=$(whiptail --title "Kafka Backup Offline" \
            --cancel-button "Back" \
            --menu "Configs > Choose an action:" 15 50 6 \
            "1" "Main menu" \
            "2" "Generate" \
            "3" "Backup" \
            "4" "Restore" \
            3>&1 1>&2 2>&3)

        # Capture the exit status of whiptail
        local exit_status=$?

        # Exit on ESC or cancel
        if [[ $exit_status -eq 1 || $exit_status -eq 255 ]]; then
            return 0
        fi

        case $choice in
            1) return 0 ;;
            2) cluster_configs_generate
               if [[ $? -eq 0 ]]; then
                    show_success_message "Configuration was generated successfully!"
               else
                    show_failure_message "Failed to generate configuration!\nExit the tool and review the logs."
               fi
               ;;
            3) cluster_configs_backup
               if [[ $? -eq 0 ]]; then
                    show_success_message "Configuration was backed up successfully!"
               else
                    show_failure_message "Failed to backup configuration!\nExit the tool and review the logs."
               fi
               ;;
            4) cluster_configs_restore_menu
               ;;
        esac
    done
}

# Displays a Whiptail menu for restoring Kafka configuration backups.
# Lists available backup files with their sizes and allows the user to select one for restoration.
# If no backups are found, shows a warning and exits.
# Calls `cluster_configs_restore` with the selected backup file.
function cluster_configs_restore_menu()
{
    local storage_config configs_backup_files choice selected_backup

    storage_config="$STORAGE_COLD/config"

    # Find all available configuration backup files with their sizes
    configs_backup_files=()
    mapfile -t configs_backup_files < <(find "$storage_config" -type f -name "*.tar.*" -exec ls -lh {} \; | awk '{print $9, $5}' | sort)

    # Check if no files are available
    if [[ ${#configs_backup_files[@]} -eq 0 ]]; then
        log "DEBUG" "No backup files found in $storage_config."
        show_warning_message "No backup files found in $storage_config."
        return 1
    fi

    # Prepare the options for whiptail menu
    local menu_options=("back" "Return to Config Menu") # Add "Back" option first
    for i in "${!configs_backup_files[@]}"; do
        menu_options+=("$i" "${configs_backup_files[$i]}")
    done

    # Display the menu using whiptail
    choice=$(whiptail --title "Kafka Backup Offline" \
        --cancel-button "Back" \
        --menu "Configs > Restore > Choose a backup file to restore:" 40 130 32 \
        "${menu_options[@]}" 3>&1 1>&2 2>&3)

    # Capture the exit status of whiptail
    local exit_status=$?

    # Exit on ESC or cancel
    if [[ $exit_status -eq 1 || $exit_status -eq 255 || $choice == "back" ]]; then
        return 0
    fi

    # Get the selected backup file path
    selected_backup=$(echo "${configs_backup_files[$choice]}" | awk '{print $1}')
    log "DEBUG" "Selected configuration backup file: $selected_backup"

    # Call the restore function with the selected backup file
    cluster_configs_restore "$selected_backup"
    if [[ $? -eq 0 ]]; then
        show_success_message "Configuration restored successfully!"
    else
        show_failure_message "Failed to restore configuration."
    fi
}

# Displays the Containers menu using Whiptail for managing Kafka containers.
# Provides options to run, start, stop, restart, or remove containers.
# Returns to the main menu when "Back" is selected or ESC/cancel is pressed.
function containers_menu() {
    while true; do
        choice=$(whiptail --title "Kafka Backup Offline" \
            --menu "Containers > Choose an action" 15 50 6 \
            "1" "Main menu" \
            "2" "Run" \
            "3" "Start" \
            "4" "Stop" \
            "5" "Restart" \
            "6" "Remove" \
            3>&1 1>&2 2>&3)

        # Capture the exit status of whiptail
        local exit_status=$?

        # Exit on ESC or cancel
        if [[ $exit_status -eq 1 || $exit_status -eq 255 ]]; then
            return 0
        fi

        case $choice in
            1) return 0 ;;
            2) cluster_containers_run
               if [[ $? -eq 0 ]]; then
                   show_success_message "The containers were successfully started! All services are now running."
               else
                   show_failure_message "Unable to start the containers.\nPlease exit the tool and check the logs for details."
               fi
               ;;
            3) cluster_containers_start
               if [[ $? -eq 0 ]]; then
                   show_success_message "The containers were successfully resumed! Previously stopped services are now active."
               else
                   show_failure_message "Failed to resume the containers.\nEnsure the environment is correctly configured and review the logs."
               fi
               ;;
            4) cluster_containers_stop
               if [[ $? -eq 0 ]]; then
                   show_success_message "The containers were successfully stopped! All services are now inactive."
               else
                   show_failure_message "Unable to stop the containers.\nPlease verify permissions or configurations and check the logs."
               fi
               ;;
            5)
               cluster_containers_restart
               if [[ $? -eq 0 ]]; then
                   show_success_message "The containers were successfully restarted! All services have been refreshed."
               else
                   show_failure_message "Failed to restart the containers.\nEnsure no conflicting processes are running and review the logs."
               fi
               ;;
            6) cluster_containers_remove
               if [[ $? -eq 0 ]]; then
                   show_success_message "The containers were successfully removed! Resources have been freed."
               else
                   show_failure_message "Failed to remove the containers.\nCheck if the containers are running and review the logs for details."
               fi
               ;;
        esac
    done
}

# Displays the Credentials menu using Whiptail for managing Kafka credentials.
# Provides options to generate, backup, or restore credentials.
# Returns to the main menu when "Back" is selected or ESC/cancel is pressed.
function credentials_menu() {
    while true; do
        choice=$(whiptail --title "Kafka Backup Offline" \
            --menu "Credentials > Choose an action" 15 50 4 \
            "1" "Main menu" \
            "2" "Generate" \
            "3" "Backup" \
            "4" "Restore" \
            3>&1 1>&2 2>&3)

        # Capture the exit status of whiptail
        local exit_status=$?

        # Exit on ESC or cancel
        if [[ $exit_status -eq 1 || $exit_status -eq 255 ]]; then
            return 0
        fi

        case $choice in
            1) return 0 ;;
            2)
               cluster_credentials_generate
               if [[ $? -eq 0 ]]; then
                    show_success_message "Credentials was generated successfully!"
               else
                    show_failure_message "Failed to generate credentials!\nExit the tool and review the logs."
               fi
               ;;
            3)
               cluster_credentials_backup
               if [[ $? -eq 0 ]]; then
                    show_success_message "Credentials was backed up successfully!"
               else
                    show_failure_message "Failed to backup credentials!\nExit the tool and review the logs."
               fi
               ;;
            4) cluster_credentials_restore_menu ;;
        esac
    done
}

# Displays a Whiptail menu for restoring Kafka credentials from backup files.
# Lists available backup files with their sizes and allows the user to select one for restoration.
# If no backups are found, shows a warning and exits.
# Calls `cluster_credentials_restore` with the selected backup file.
function cluster_credentials_restore_menu()
{
    local storage_credentials credentials_backup_files choice selected_backup

    storage_credentials="$STORAGE_COLD/credentials"

    # Find all available credentials backup files with their sizes
    credentials_backup_files=()
    mapfile -t credentials_backup_files < <(find "$storage_credentials" -type f -name "*.tar.*" -exec ls -lh {} \; | awk '{print $9, $5}' | sort)

    # Check if no files are available
    if [[ ${#credentials_backup_files[@]} -eq 0 ]]; then
        log "DEBUG" "No backup files found in $storage_credentials."
        show_warning_message "No backup files found in $storage_credentials."
        return 1
    fi

    # Prepare the options for whiptail menu
    local menu_options=("back" "Return to credentials Menu") # Add "Back" option first
    for i in "${!credentials_backup_files[@]}"; do
        menu_options+=("$i" "${credentials_backup_files[$i]}")
    done

    # Display the menu using whiptail
    choice=$(whiptail --title "Kafka Backup Offline" \
        --cancel-button "Back" \
        --menu "Credentials > Restore > Choose a backup file to restore:" 40 130 32 \
        "${menu_options[@]}" 3>&1 1>&2 2>&3)

    # Capture the exit status of whiptail
    local exit_status=$?

    # Exit on ESC or cancel
    if [[ $exit_status -eq 1 || $exit_status -eq 255 || $choice == "back" ]]; then
        return 0
    fi

    # Get the selected backup file path
    selected_backup=$(echo "${credentials_backup_files[$choice]}" | awk '{print $1}')
    log "DEBUG" "Selected credentials backup file: $selected_backup"

    # Call the restore function with the selected backup file
    cluster_credentials_restore "$selected_backup"
    if [[ $? -eq 0 ]]; then
        show_success_message "Credentials restored successfully!"
    else
        show_failure_message "Failed to restore credentials."
    fi
}

# Displays the Data menu using Whiptail for managing Kafka data.
# Provides options to format, backup, or restore data.
# Returns to the main menu when "Back" is selected or ESC/cancel is pressed.
function data_menu() {
    while true; do
        choice=$(whiptail --title "Kafka Backup Offline" \
            --menu "Data > Choose an action:" 15 50 5 \
            "1" "Main menu" \
            "2" "Format" \
            "3" "Backup" \
            "4" "Restore" \
            3>&1 1>&2 2>&3)

        # Capture the exit status of whiptail
        local exit_status=$?

        # Exit on ESC or cancel
        if [[ $exit_status -eq 1 || $exit_status -eq 255 ]]; then
            return 0
        fi

        case $choice in
            1)
               return 0 ;;
            2)
               cluster_data_format
               if [[ $? -eq 0 ]]; then
                   show_success_message "Data formatting completed successfully!\nThe cluster is now ready for initialization with fresh data."
               else
                   show_failure_message "Data formatting failed.\nPlease exit the tool, review the logs, and verify the storage setup."
               fi
               ;;
            3)
               cluster_data_backup
               if [[ $? -eq 0 ]]; then
                   show_success_message "Data backup completed successfully!\nYou can now safely proceed with any maintenance or restore operations."
               else
                   show_failure_message "Data backup failed.\nPlease exit the tool, review the logs, and ensure sufficient storage space is available."
               fi
               ;;
            4)
               cluster_data_restore_menu ;;
        esac
    done
}

# Displays a Whiptail menu for restoring Kafka data from backup files.
# Lists available backup files with their sizes and allows the user to select one for restoration.
# If no backups are found, shows a warning and exits.
# Calls `cluster_data_restore` with the selected backup file.
function cluster_data_restore_menu() {
    local storage_data backup_files choice selected_backup

    storage_data="$STORAGE_COLD/data"

    # Find all available backup files with their sizes
    backup_files=()
    mapfile -t backup_files < <(find "$storage_data" -type f -name "*.tar.*" -exec ls -lh {} \; | awk '{print $9, $5}' | sort)

    # Check if no backup files are available
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        log "DEBUG" "No backup files found in $storage_data."
        show_warning_message "No backup files found in $storage_data."
        return 1
    fi

    # Prepare options for the menu
    local menu_options=("back" "Return to Data Menu") # Add a back option first
    for i in "${!backup_files[@]}"; do
        menu_options+=("$i" "${backup_files[$i]}") # Append each backup file as a menu option
    done

    # Display the menu and capture the user's choice
    choice=$(whiptail --title "Kafka Backup Offline" \
        --cancel-button "Back" \
        --menu "Data > Restore > Choose a backup file to restore:" 40 130 32 \
        "${menu_options[@]}" 3>&1 1>&2 2>&3)

    # Capture the exit status of whiptail
    local exit_status=$?

    # Exit on ESC or cancel
    if [[ $exit_status -eq 1 || $exit_status -eq 255 || $choice == "back" ]]; then
        return 0
    fi

    # Get the selected backup file path
    selected_backup=$(echo "${backup_files[$choice]}" | awk '{print $1}')
    log "DEBUG" "Selected backup file: $selected_backup"

    # Call the restore function with the selected backup file
    cluster_data_restore "$selected_backup"
    if [[ $? -eq 0 ]]; then
        show_success_message "Data restoration completed successfully!\nThe cluster has been restored to the selected backup state."
    else
        show_failure_message "Data restoration failed.\nPlease review the logs and verify the backup integrity."
    fi
}

# ===== Main Execution =====
# Call the configuration loader function with the path to your .ini file
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
CONFIG_FILE="$SCRIPT_DIR/config.ini"
load_configuration "$CONFIG_FILE"
create_pid_file
# Decide what to run
if [[ $# -eq 0 ]]; then
    # No parameters provided, show the menu
    disclaimer
    main_menu
    disclaimer
else
    # Parameter provided, assume it's a function name
    if declare -f "$1" >/dev/null; then
        # Call the function by name if it exists
        "$1"
    else
        # Show help if the function doesn't exist
        log "ERROR" "Error: Function '$1' not found."
        help
        exit 1
    fi
fi
