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

# ===== Kafka Cluster Safe Mode =====
# Ensures that all Kafka containers are stopped before certain operations
function ensure_containers_stopped()
{
    local role
    declare -A pids         # Associative array for background task process IDs
    declare -a failed_roles # Array to track roles that failed

    log "DEBUG" "Test - Ensure Kafka Containers on all nodes are stopped - started"

    # Launch container_start for each role in the background
    for role in "${order_startup[@]}"; do
        ensure_container_stopped "$role" &
        pids["$role"]=$! # Capture the process ID of the background job
    done

    # Wait for all background jobs and log any failures
    failed_roles=()
    for role in "${!pids[@]}"; do
        if ! wait "${pids[$role]}"; then
            failed_roles+=("$role")
        fi
    done

    # Final summary log
    if ((${#failed_roles[@]} > 0)); then
        log "ERROR" "Failed roles: ${failed_roles[*]}."
        log "ERROR" "Test - Ensure Kafka Containers on all nodes are stopped - Stop containers on all nodes"
        return 1
    fi

    log "DEBUG" "Test - Ensure Kafka Containers on all nodes are stopped - OK"
    return 0
}

# Ensures that all Kafka containers are stopped before certain operations
function ensure_container_stopped()
{
    local role ip

    role=$1
    ip=${nodes[$role]}

    status=$(ssh -i "$SSH_KEY_PRI" "$SSH_USER"@"$ip" "docker inspect -f '{{.State.Running}}' $role" 2>/dev/null)

    if [[ "$status" == "true" ]]; then
        log "DEBUG" "Error: Container $role at $ip is still running. Please stop all containers before proceeding."
        return 1
    fi

    return 0
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

# ===== Kafka Cluster Wide Data Format =====
# Formats data on all cluster nodes
function cluster_wide_data_format()
{
    run_ansible_routine "Kafka Data Format" "parallel" "data_format"
    return $?
}

# ===== Kafka Cluster Wide Data Backup =====
# Performs a full data backup of the Kafka cluster across all nodes.
function cluster_wide_data_backup()
{
    run_ansible_routine "Kafka Data Backup" "parallel" "data_backup"
    return $?
}

# ===== Kafka Cluster Wide Data Restore Menu =====
# Presents a menu to the user to select and restore a Kafka data backup.
# Displays available backups from the `STORAGE_COLD/data` directory and validates user input.
# Pinned folder is not being rotated.
# Rotated folder is being rotated, according to retention policy of keep days
function cluster_wide_data_restore_menu()
{
    local storage_data i choice backup_files num_files selected_backup

    storage_data="$STORAGE_COLD/data"

    # Find all available backup files with their sizes
    backup_files=()
    mapfile -t backup_files < <(find "$storage_data" -type f -name "*.tar.*" -exec ls -lh {} \; | awk '{print $9, $5}' | sort)
    num_files=${#backup_files[@]}

    if [ "$num_files" -eq 0 ]; then
        log "WARN" "No backup files found in $storage_data."
        return 1
    fi

    # Display available backup files with sizes
    echo "Available backup files (size):"
    echo
    echo "0) Exit restore menu"
    for i in "${!backup_files[@]}"; do
        echo "$((i + 1))) ${backup_files[$i]}"
    done
    echo

    # Prompt the user for input
    choice=""
    while true; do
        read -rp "Enter the number corresponding to the backup file you want to restore (or 0 to exit): " choice

        # Handle exit option
        if [[ $choice == "0" ]]; then
            echo "Exiting restore menu."
            return 1
        fi

        # Validate choice
        if [[ $choice =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$num_files" ]; then
            # Extract the file path (first field of the entry)
            selected_backup=$(echo "${backup_files[$((choice - 1))]}" | awk '{print $1}')
            log "DEBUG" "Selected backup file: $selected_backup"
            break
        else
            echo "Invalid choice. Please select a valid number between 0 and $num_files."
        fi
    done

    # Call recovery with the selected backup file
    cluster_wide_data_restore "$selected_backup"
}

# ===== Kafka Cluster Wide Data Restore =====
# Restores a Kafka cluster's data from a specified backup archive.
# Parameters:
#   $1 - Path to the cluster-wide data backup archive (e.g., /backup/cold/data/rotated/YYYY/MM/DD/backup.tar.gz).
# Actions:
# - Ensures that all containers are stopped before proceeding.
# - Extracts the cluster-wide archive to a temporary storage directory.
# - Distributes per-node archives to their respective nodes.
# - Deletes existing data and restores from the archives.
# - Does not restart the containers after restoration.
function cluster_wide_data_restore()
{
    local archive=$1
    run_ansible_routine "Kafka Data Restore" "parallel" "data_restore" "--extra-vars \"restore_archive=$archive\""
    return $?
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
# Actions:
# - Rotates existing backups based on retention policy (default: 30 days).
# - Collects configuration files from each node using `rsync`.
# - Compresses the collected configuration files into a timestamped archive.
# - Cleans up temporary files after backup.
# Stored at: `$STORAGE_COLD/config/rotated/YYYY/MM/DD/backup.tar.gz`.
function cluster_wide_config_backup()
{
    run_ansible_routine "Kafka Config Backup" "parallel" "config_backup"
    return $?
}

# ===== Kafka Cluster Wide Config Restore Menu =====
# Presents a menu to the user to select and restore a Kafka configuration backup.
# Displays available backups from the `STORAGE_COLD/config` directory and validates user input.
# Invokes the `cluster_wide_config_restore` function to restore the selected backup.
function cluster_wide_config_restore_menu()
{
    local storage_config i config_backup_files num_files choice selected_backup

    storage_config="$STORAGE_COLD/config"

    # Find all available configuration backup files with their sizes
    config_backup_files=()
    mapfile -t config_backup_files < <(find "$storage_config" -type f -name "*.tar.*" -exec ls -lh {} \; | awk '{print $9, $5}' | sort)
    num_files=${#config_backup_files[@]}

    if [ "$num_files" -eq 0 ]; then
        log "WARN" "No configuration backup files found in $storage_config."
        return 1
    fi

    # Display available configuration backup files with sizes
    echo "Available configuration backup files (size):"
    echo
    echo "0) Exit restore menu"
    for i in "${!config_backup_files[@]}"; do
        echo "$((i + 1))) ${config_backup_files[$i]}"
    done
    echo

    choice=""
    while true; do
        read -rp "Enter the number corresponding to the configuration backup you want to restore (or 0 to exit): " choice

        # Handle exit option
        if [[ $choice == "0" ]]; then
            echo "Exiting restore menu."
            return 1
        fi

        # Validate choice
        if [[ $choice =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$num_files" ]; then
            # Extract the file path (first field of the entry)
            selected_backup=$(echo "${config_backup_files[$((choice - 1))]}" | awk '{print $1}')
            log "DEBUG" "Selected configuration backup file: $selected_backup"
            break
        else
            echo "Invalid choice. Please select a valid number between 0 and $num_files."
        fi
    done

    # Call restore with the selected backup file
    cluster_wide_config_restore "$selected_backup"
}

# ===== Kafka Cluster Wide Config Restore =====
# Restores Kafka cluster configuration files to all nodes from a specified backup archive.
# Parameters:
#   $1 - Path to the cluster-wide config backup archive (e.g., /backup/cold/config/rotated/YYYY/MM/DD/backup.tar.gz).
function cluster_wide_config_restore()
{
    local archive=$1
    run_ansible_routine "Kafka Config Restore" "parallel" "config_restore" "--extra-vars \"restore_archive=$archive\""
    return $?
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


# ===== Containers Submenu =====
function containers_menu() {
    while true; do
        choice=$(whiptail --title "Containers Menu" \
            --menu "Choose an action:\nESC - to return to the main menu" 15 50 6 \
            "1" "Run Containers" \
            "2" "Start Containers" \
            "3" "Stop Containers" \
            "4" "Restart Containers" \
            "5" "Remove Containers" \
            3>&1 1>&2 2>&3)

        # Exit on ESC or cancel
        [[ $? -ne 0 ]] && break

        case $choice in
            1) containers_run ;;
            2) containers_start ;;
            3) containers_stop ;;
            4) containers_restart ;;
            5) containers_remove ;;
        esac
    done
}

# ===== Data Submenu =====
function data_menu() {
    while true; do
        choice=$(whiptail --title "Data Menu" \
            --menu "Choose an action:\nESC - to return to the main menu" 15 50 5 \
            "1" "Format Data" \
            "2" "Backup Data" \
            "3" "Restore Data" \
            3>&1 1>&2 2>&3)

        # Exit on ESC or cancel
        [[ $? -ne 0 ]] && break

        case $choice in
            1) cluster_wide_data_format ;;
            2) cluster_wide_data_backup ;;
            3) cluster_wide_data_restore_menu ;;
        esac
    done
}

# ===== Config Submenu =====
function config_menu() {
    while true; do
        choice=$(whiptail --title "Config Menu" \
            --menu "Choose an action:\nESC - to return to the main menu" 15 50 4 \
            "1" "Generate Config" \
            "2" "Backup Config" \
            "3" "Restore Config" \
            3>&1 1>&2 2>&3)

        # Exit on ESC or cancel
        [[ $? -ne 0 ]] && break

        case $choice in
            1) cluster_wide_config_generate ;;
            2) cluster_wide_config_backup ;;
            3) cluster_wide_config_restore_menu ;;
        esac
    done
}

# ===== Certificates Submenu =====
function certificates_menu() {
    while true; do
        choice=$(whiptail --title "Certificates Menu" \
            --menu "Choose an action:\nESC - to return to the main menu" 15 50 4 \
            "1" "Generate Certificates" \
            "2" "Backup Certificates" \
            "3" "Restore Certificates" \
            3>&1 1>&2 2>&3)

        # Exit on ESC or cancel
        [[ $? -ne 0 ]] && break

        case $choice in
            1) cluster_wide_certificates_generate ;;
            2) cluster_wide_certificates_backup ;;
            3) cluster_wide_certificates_restore_menu ;;
        esac
    done
}

# ===== Credentials Submenu =====
function credentials_menu() {
    while true; do
        choice=$(whiptail --title "Credentials Menu" \
            --menu "Choose an action:\nESC - to return to the main menu" 15 50 4 \
            "1" "Generate Credentials" \
            "2" "Backup Credentials" \
            "3" "Restore Credentials" \
            3>&1 1>&2 2>&3)

        # Exit on ESC or cancel
        [[ $? -ne 0 ]] && break

        case $choice in
            1) cluster_wide_credentials_generate ;;
            2) cluster_wide_credentials_backup ;;
            3) cluster_wide_credentials_restore_menu ;;
        esac
    done
}

# ===== Main Menu Function =====
function main_menu() {
    while true; do
        choice=$(whiptail --title "Kafka-Backup-Offline Utility" \
            --menu "Use arrow keys to navigate and Enter to select. ESC to exit." 15 50 6 \
            "Containers" "Manage container-related tasks" \
            "Data" "Backup and restore data" \
            "Config" "Generate and manage configurations" \
            "Certificates" "Manage certificates" \
            "Credentials" "Manage credentials" \
            3>&1 1>&2 2>&3)

        # Capture the exit status of whiptail
        exit_status=$?

        # Handle ESC or Cancel
        if [[ $exit_status -ne 0 ]]; then
            echo "Exiting..."
            break
        fi

        # Handle text-based choices
        case $choice in
            "Containers") containers_menu ;;
            "Data") data_menu ;;
            "Config") config_menu ;;
            "Certificates") certificates_menu ;;
            "Credentials") credentials_menu ;;
            *) whiptail --msgbox "Invalid choice. Please try again." 10 40 ;;
        esac
    done
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
