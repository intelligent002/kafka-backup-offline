#!/usr/bin/env bash

# ===== Load Configuration from .ini File =====
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

# This function loads configuration variables from an .ini file and populates global variables.
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

# Help function to display available options
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
    echo "      containers_run     'docker run' the Kafka Cluster containers in the defined startup order                    "
    echo "      containers_start   'docker start' the Kafka Cluster containers in the defined startup order                  "
    echo "      containers_stop    'docker stop' the Kafka Cluster containers in the defined shutdown order                  "
    echo "      containers_restart 'docker restart' the Kafka Cluster containers in the defined shutdown & startup order     "
    echo "      containers_remove  'docker rm' the Kafka Cluster containers in the defined shutdown order                    "
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

function cluster_backup()
{
    containers_stop
    cluster_wide_config_backup
    cluster_wide_data_backup
    containers_start
}

# Creates a PID file to ensure only one instance of the script runs at a time
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

# Removes the PID file on script exit.
function remove_pid_file()
{
    rm -f "$PID_FILE"
    log "DEBUG" "PID file removed"
}

# Logs messages to the console and the specified log file
# Parameters:
#   $1 - The message to log.
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

# ===== Coziness Functions =====
# Copies SSH keys to all nodes for password-less access
function setup_sshs()
{
    local role

    log "INFO" "Routine - Setup up SSH Keys on all nodes - started"
    for role in "${order_startup[@]}"; do setup_ssh "$role"; done
    log "INFO" "Routine - Setup up SSH Keys on all nodes - OK"
}

# Copies SSH key to a specific node
# Parameters:
#   $1 - The role of the node (e.g., kafka-controller-1)
function setup_ssh()
{
    local role ip

    role=$1
    ip=${nodes[$role]}

    log "DEBUG" "Setup SSH key to $role at $ip"
    ssh-copy-id -i "$SSH_KEY_PUB" "$SSH_USER"@"$ip" || {
        log "WARN" "Failed to copy SSH key to $role at $ip. Password-less access might not work."
        return 1
    }
}

# Ensures that there is enough space for stable operation
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

# ===== Kafka Containers Run =====
function run_ansible_routine()
{
    local routine=$1
    local playbook=$2
    local tag=$3
    local extra_vars=${4:-} # Optional extra variables

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

# ===== Menu Function =====
function menu()
{
    local choice

    while true; do
        echo "Available routines:"
        echo "---------------------------------------------"
        echo "0) Exit"
        echo "1) Setup SSH Keys (ssh-copy-id)"
        echo "---------------------------------------------"
        echo "2) Containers Run"
        echo "3) Containers Start"
        echo "4) Containers Stop"
        echo "5) Containers Restart"
        echo "6) Containers Remove"
        echo "---------------------------------------------"
        echo "7) Data Format"
        echo "8) Data Backup"
        echo "9) Data Restore"
        echo "---------------------------------------------"
        echo "10) Config Generate"
        echo "11) Config Backup"
        echo "12) Config Restore"
        echo "---------------------------------------------"
        echo "13) Certificates Generate"
        echo "14) Certificates Backup"
        echo "15) Certificates Restore"
        echo "---------------------------------------------"
        echo "16) Credentials Generate"
        echo "17) Credentials Backup"
        echo "18) Credentials Restore"
        echo "---------------------------------------------"
        read -rp "Choose an option [0-11]: " choice

        case $choice in
            0)
                log "INFO" "Have a nice day!"
                break
                ;;
            1) setup_sshs ;;
            2) containers_run ;;
            3) containers_start ;;
            4) containers_stop ;;
            5) containers_restart ;;
            6) containers_remove ;;
            7) cluster_wide_data_format ;;
            8) cluster_wide_data_backup ;;
            9) cluster_wide_data_restore_menu ;;
            10) cluster_wide_config_generate ;;
            11) cluster_wide_config_backup ;;
            12) cluster_wide_config_restore_menu ;;
            13) cluster_wide_certificates_generate ;;
            14) cluster_wide_certificates_backup ;;
            15) cluster_wide_certificates_restore_menu ;;
            16) cluster_wide_credentials_generate ;;
            17) cluster_wide_credentials_backup ;;
            18) cluster_wide_credentials_restore_menu ;;
            *) echo "Invalid choice. Please try again." ;;
        esac
    done
}

# Function to display a failure message
function show_failure_message() {
    whiptail --title "Failure" --msgbox "$1" 10 60
}

# Function to display a success message
function show_success_message() {
    whiptail --title "Success" --msgbox "$1" 10 60
}

# ===== Main Menu =====
function main_menu() {
    while true; do
        choice=$(whiptail --title "Kafka Backup Offline" \
            --cancel-button "Quit" \
            --menu "Choose a section:" 15 50 6 \
            "1" "Quit" \
            "2" "Certificates" \
            "3" "Configs" \
            "4" "Containers" \
            "5" "Credentials" \
            "6" "Data" \
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
            2) certificates_menu ;;
            3) config_menu ;;
            4) containers_menu ;;
            5) credentials_menu ;;
            6) data_menu ;;
        esac
    done
}


# ===== Certificates Submenu =====
function certificates_menu() {
    while true; do
        choice=$(whiptail --title "Kafka Backup Offline" \
            --cancel-button "Back" \
            --menu "Certificates > Choose an action:" 15 50 6 \
            "1" "Main menu" \
            "2" "Generate Certificates" \
            "3" "Backup Certificates" \
            "4" "Restore Certificates" \
            3>&1 1>&2 2>&3)

        # Capture the exit status of whiptail
        local exit_status=$?

        # Exit on ESC or cancel
        if [[ $exit_status -eq 1 || $exit_status -eq 255 ]]; then
            return 0
        fi

        case $choice in
            1) return 0 ;;
            2) cluster_wide_certificates_generate ;;
            3) cluster_wide_certificates_backup ;;
            4) cluster_wide_certificates_restore_menu ;;
        esac
    done
}

# ===== Config Submenu =====
function config_menu() {
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
            2) cluster_wide_config_generate
               if [[ $? -eq 0 ]]; then
                    show_success_message "Configuration was generated successfully!"
               else
                    show_failure_message "Failed to generate configuration!\nExit the tool and review the logs."
               fi
               ;;
            3) cluster_wide_config_backup
               if [[ $? -eq 0 ]]; then
                    show_success_message "Configuration was backed up successfully!"
               else
                    show_failure_message "Failed to backup configuration!\nExit the tool and review the logs."
               fi
               ;;
            4) cluster_wide_config_restore_menu
               ;;
        esac
    done
}

# ===== Kafka Cluster Wide Config Restore Menu =====
function cluster_wide_config_restore_menu()
{
    local storage_config config_backup_files choice selected_backup

    storage_config="$STORAGE_COLD/config"

    # Find all available configuration backup files with their sizes
    config_backup_files=()
    mapfile -t config_backup_files < <(find "$storage_config" -type f -name "*.tar.*" -exec ls -lh {} \; | awk '{print $9, $5}' | sort)

    # Check if no files are available
    if [[ ${#config_backup_files[@]} -eq 0 ]]; then
        log "DEBUG" "No configuration backup files found in $storage_config."
        whiptail --title "Restore Config" --msgbox "No configuration backup files found in $storage_config." 10 50
        return 1
    fi

    # Prepare the options for whiptail menu
    local menu_options=("back" "Return to Config Menu") # Add "Back" option first
    for i in "${!config_backup_files[@]}"; do
        menu_options+=("$i" "${config_backup_files[$i]}")
    done

    # Display the menu using whiptail
    choice=$(whiptail --title "Kafka Backup Offline" \
        --cancel-button "Back" \
        --menu "Config > Restore > Choose a backup file to restore:" 40 130 32 \
        "${menu_options[@]}" 3>&1 1>&2 2>&3)

    # Capture the exit status of whiptail
    local exit_status=$?

    # Exit on ESC or cancel
    if [[ $exit_status -eq 1 || $exit_status -eq 255 || $choice="back" ]]; then
        return 0
    fi

    # Get the selected backup file path
    selected_backup=$(echo "${config_backup_files[$choice]}" | awk '{print $1}')
    log "DEBUG" "Selected configuration backup file: $selected_backup"

    # Call the restore function with the selected backup file
    cluster_wide_config_restore "$selected_backup"
    if [[ $? -eq 0 ]]; then
        show_success_message "Configuration restored successfully!"
    else
        show_failure_message "Failed to restore configuration."
    fi
}

# ===== Kafka Config Generate =====
# Generates and deploy config files to all cluster nodes
function cluster_wide_config_generate()
{
    run_ansible_routine "Kafka Config Deploy" "parallel" "config_deploy"
    return $?
}

# ===== Kafka Cluster Wide Config Backup =====
# Backs up Kafka cluster configuration files from all nodes to a centralized storage location.
function cluster_wide_config_backup()
{
    run_ansible_routine "Kafka Config Backup" "parallel" "config_backup"
    return $?
}

# ===== Kafka Cluster Wide Config Restore =====
# Restores Kafka cluster configuration files to all nodes from a specified backup archive.
function cluster_wide_config_restore()
{
    local archive=$1
    run_ansible_routine "Kafka Config Restore" "parallel" "config_restore" "--extra-vars \"restore_archive=$archive\""
    return $?
}

# ===== Containers Submenu =====
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
            2) containers_run
               if [[ $? -eq 0 ]]; then
                   show_success_message "The containers were successfully started! All services are now running."
               else
                   show_failure_message "Unable to start the containers.\nPlease exit the tool and check the logs for details."
               fi
               ;;
            3) containers_start
               if [[ $? -eq 0 ]]; then
                   show_success_message "The containers were successfully resumed! Previously stopped services are now active."
               else
                   show_failure_message "Failed to resume the containers.\nEnsure the environment is correctly configured and review the logs."
               fi
               ;;
            4) containers_stop
               if [[ $? -eq 0 ]]; then
                   show_success_message "The containers were successfully stopped! All services are now inactive."
               else
                   show_failure_message "Unable to stop the containers.\nPlease verify permissions or configurations and check the logs."
               fi
               ;;
            5)
               containers_restart
               if [[ $? -eq 0 ]]; then
                   show_success_message "The containers were successfully restarted! All services have been refreshed."
               else
                   show_failure_message "Failed to restart the containers.\nEnsure no conflicting processes are running and review the logs."
               fi
               ;;
            6) containers_remove
               if [[ $? -eq 0 ]]; then
                   show_success_message "The containers were successfully removed! Resources have been freed."
               else
                   show_failure_message "Failed to remove the containers.\nCheck if the containers are running and review the logs for details."
               fi
               ;;
        esac
    done
}

# Starts all Kafka containers in the pre-defined order
function containers_run()
{
    run_ansible_routine "Kafka Containers Run" "serial" "containers_run"
    return $?
}

# ===== Kafka Containers Start =====
# Starts all Kafka containers in the defined startup order
function containers_start()
{
    run_ansible_routine "Kafka Containers Start" "serial" "containers_start"
    return $?
}

# ===== Kafka Containers Stop =====
# Stops all Kafka containers in the defined shutdown order
function containers_stop()
{
    run_ansible_routine "Kafka Containers Stop" "serial" "containers_stop"
    return $?
}

# ===== Kafka Containers Restart =====
# Restarts all Kafka containers in the defined shutdown and startup orders
function containers_restart()
{
    containers_stop
    containers_start
}

# ===== Kafka Containers Remove =====
# Removes all Kafka containers in the defined shutdown order
function containers_remove()
{
    run_ansible_routine "Kafka Containers Remove" "serial" "containers_remove"
    return $?
}

# ===== Credentials Submenu =====
function credentials_menu() {
    while true; do
        choice=$(whiptail --title "Credentials Menu" \
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
            2) cluster_wide_credentials_generate ;;
            3) cluster_wide_credentials_backup ;;
            4) cluster_wide_credentials_restore_menu ;;
        esac
    done
}

# ===== Data Submenu =====
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
               cluster_wide_data_format
               if [[ $? -eq 0 ]]; then
                   show_success_message "Data formatting completed successfully!\nThe cluster is now ready for initialization with fresh data."
               else
                   show_failure_message "Data formatting failed.\nPlease exit the tool, review the logs, and verify the storage setup."
               fi
               ;;
            3)
               cluster_wide_data_backup
               if [[ $? -eq 0 ]]; then
                   show_success_message "Data backup completed successfully!\nYou can now safely proceed with any maintenance or restore operations."
               else
                   show_failure_message "Data backup failed.\nPlease exit the tool, review the logs, and ensure sufficient storage space is available."
               fi
               ;;
            4)
               cluster_wide_data_restore_menu ;;
        esac
    done
}

# ===== Kafka Cluster Wide Data Restore Menu =====
function cluster_wide_data_restore_menu() {
    local storage_data backup_files choice selected_backup

    storage_data="$STORAGE_COLD/data"

    # Find all available backup files with their sizes
    backup_files=()
    mapfile -t backup_files < <(find "$storage_data" -type f -name "*.tar.*" -exec ls -lh {} \; | awk '{print $9, $5}' | sort)

    # Check if no backup files are available
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        log "DEBUG" "No backup files found in $storage_data."
        whiptail --title "Data Restore" --msgbox "No backup files found in $storage_data." 10 50
        return 1
    fi

    # Prepare options for the menu
    local menu_options=("back" "Return to Data Menu") # Add a back option first
    for i in "${!backup_files[@]}"; do
        menu_options+=("$i" "${backup_files[$i]}") # Append each backup file as a menu option
    done

    # Display the menu and capture the user's choice
    choice=$(whiptail --title "Data Restore" \
        --cancel-button "Back" \
        --menu "Data > Restore > Select a backup file to restore:" 30 150 15 \
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
    cluster_wide_data_restore "$selected_backup"
    if [[ $? -eq 0 ]]; then
        show_success_message "Data restoration completed successfully!\nThe cluster has been restored to the selected backup state."
    else
        show_failure_message "Data restoration failed.\nPlease review the logs and verify the backup integrity."
    fi
}

# ===== Kafka Cluster Wide Data Format =====
# Formats data on all cluster nodes
function cluster_wide_data_format()
{
    run_ansible_routine "Kafka Data Format" "parallel" "data_format"
    return $?
}

# ===== Kafka Cluster Wide Data Backup =====
function cluster_wide_data_backup()
{
    run_ansible_routine "Kafka Data Backup" "parallel" "data_backup"
    return $?
}

# ===== Kafka Cluster Wide Data Restore =====
function cluster_wide_data_restore()
{
    local archive=$1
    run_ansible_routine "Kafka Data Restore" "parallel" "data_restore" "--extra-vars \"restore_archive=$archive\""
    return $?
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
