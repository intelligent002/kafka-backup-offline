#!/usr/bin/env bash

function handle_directory()
{
    # Save the original directory
    ORIGINAL_DIR="$(pwd)"

    # Change to the script's directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "$SCRIPT_DIR" || {
        echo "Error: Failed to change directory to $SCRIPT_DIR"
        exit 1
    }

    # Ensure the script returns to the original directory upon exit
    trap 'cd "$ORIGINAL_DIR"' EXIT
}

# Loads configuration settings from an INI file and stores them in global variables.
# Validates if the configuration file exists before parsing.
# Extracts values from the "general" and "storage" sections using `parse_ini_file`.
# Sets log levels, file paths, and storage-related parameters.
function handle_configuration()
{
    local config_file="$SCRIPT_DIR/config.ini"

    # Check if the configuration file exists
    if [[ ! -f "$config_file" ]]; then
        echo "Error: The configuration file '$config_file' was not found!"
        exit 1
    fi

    # Handle log levels
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
    LOG_LEVEL="${ini_data[general.LOG_LEVEL]}" # Log level threshold: errors at or above this level will be shown in the console, while all logs are recorded.
    INVENTORY="${ini_data[general.INVENTORY]}" # inventory folder
    ANSIBLE_ATTEMPTS="${ini_data[general.ANSIBLE_ATTEMPTS]}" # Ansbile retry attempts

    # Load storage configuration variables for temporary and cold backup storage paths.
    parse_ini_file "$config_file" "storage"
    STORAGE_TEMP="${ini_data[storage.STORAGE_TEMP]}"                         # Temporary storage directory on the GUI server
    STORAGE_COLD="${ini_data[storage.STORAGE_COLD]}"                         # Permanent cold storage directory for backups
    STORAGE_WARN_LOW="${ini_data[storage.STORAGE_WARN_LOW]}"                 # Percentage of free space, below which we will show a warning

    # make sure we can log stuff
    mkdir -p "$(dirname $LOG_FILE)"

    log "INFO" "Configuration loaded from '$config_file'"
    ensure_free_space $STORAGE_COLD
}

# Parses a specific section of an INI file and stores its key-value pairs in an associative array.
# Skips comments and empty lines while trimming whitespace from keys and values.
# Stores the results in the global associative array "ini_data" using "section.key" as the index.
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

function handle_main()
{
    # Decide what to run
    if [[ $# -eq 0 ]]; then
        # No parameters provided, show the menu, but first require coffee
        disclaimer
        menu_main
    else
        # Parameter provided, assume it's a function name
        if declare -f "$1" >/dev/null; then
            # require coffee
            if [[ "$1" != "help" ]]; then
                disclaimer
            fi
            # Call the function by name if it exists
            "$1"
        else
            # Show help if the function doesn't exist
            log "ERROR" "Error: Function '$1' not found."
            help
            exit 1
        fi
    fi
}

# Displays a disclaimer message for the Kafka-Backup-Offline Utility.
# Warns that this solution is unsuitable for production, as it requires taking Kafka offline.
# Includes author contact details and version information.
function disclaimer()
{
    log "INFO" "==================================================================================================================="
    log "INFO" "                                    Kafka-Backup-Offline Utility - version 2.0.0                                   "
    log "INFO" "==================================================================================================================="
    log "INFO" "                                                                                                                   "
    log "INFO" "  © 2025 Rosenberg Arkady @ Dynamic Studio                      Contact: +972546373566 / intelligent002@gmail.com  "
    log "INFO" "                                                                                                                   "
    log "INFO" "  ** IMPORTANT NOTICE: **                                                                                          "
    log "INFO" "  This solution is **NOT SUITABLE FOR PRODUCTION USE** as it requires taking the Kafka Cluster offline             "
    log "INFO" "  for backup and restore operations. It is specifically designed for development and testing environments.         "
    log "INFO" "                                                                                                                   "
    log "INFO" "  Support the project: [Buy Me a Coffee] ( https://buymeacoffee.com/intelligent002 ) ☕                            "
    log "INFO" "                                                                                                                   "
    log "INFO" "==================================================================================================================="
}

# Displays a help message detailing available functions in the Kafka-Backup-Offline Utility.
function help()
{
    # everything starts with a coffee ...
    disclaimer
    log "INFO" ""
    log "INFO" "  Usage:"
    log "INFO" ""
    log "INFO" "    GUI: ./kafka-backup-offline.sh"
    log "INFO" "    CLI: ./kafka-backup-offline.sh [function_name]"
    log "INFO" ""
    log "INFO" "  All internal functions are runnable via the parameter, only one parameter is supported."
    log "INFO" ""
    log "INFO" "-------------------------------------------------------------------------------------------------------------------"
    log "INFO" "  cluster_backup        Perform a Full Kafka Cluster Backup:"
    log "INFO" ""
    log "INFO" "                          1. Validate availability of free space on backup location."
    log "INFO" "                          2. Rotate all backups according to section policies:"
    log "INFO" "                               2.1 data         - keep last 30 days."
    log "INFO" "                               2.2 config       - keep last 365 days."
    log "INFO" "                               2.3 credentials  - keep last 365 days."
    log "INFO" "                               2.4 certificates - keep last 365 days."
    log "INFO" "                               2.5 each component has a 'rotated' folder, which is periodically rotated."
    log "INFO" "                               2.6 each component has a 'pinned' folder, which is NOT rotated."
    log "INFO" "                               2.7 to keep some modular backup forever - move it to the pinned folder."
    log "INFO" "                          3. Validate availability of free space on backup location."
    log "INFO" "                          4. Shut down the cluster by 'docker stop' all containers in defined shutdown order."
    log "INFO" "                          5. Zip and store the cluster, in separate archives, to allow modular recovery:"
    log "INFO" "                               5.1 data"
    log "INFO" "                               5.2 config"
    log "INFO" "                               5.3 credentials"
    log "INFO" "                               5.4 certificates"
    log "INFO" "                          6. Start up the cluster by 'docker start' all containers in defined startup order."
    log "INFO" "                          7. Validate availability of free space on backup location."
    log "INFO" ""
    log "INFO" "  If no function name is provided, the script will display an interactive menu."
    log "INFO" ""
    log "INFO" "==================================================================================================================="
}

# Cron-oriented function for automated Kafka cluster backups.
# 1. Stops all Kafka containers to ensure data consistency.
# 2. Backs up configurations, certificates, credentials, and data, storing everything in cold storage.
# 3. Starts all Kafka containers after the backup process completes.
function cluster_backup()
{
    log "INFO" "---------------------------------------=[ INITIATING FULL CLUSTER BACKUP ]=----------------------------------------"
    # validate storage space
    ensure_free_space $STORAGE_COLD

    # cleanup old stuff
    configs_rotate
    certificates_rotate
    credentials_rotate
    data_rotate

    # validate storage space
    ensure_free_space $STORAGE_COLD

    # create new stuff
    configs_backup
    certificates_backup
    credentials_backup

    # offline actions to maintain data integrity
    containers_stop
    data_backup
    containers_start

    # validate storage space
    ensure_free_space $STORAGE_COLD
    log "INFO" "----------------------------------------=[ COMPLETED FULL CLUSTER BACKUP ]=----------------------------------------"
}

function cluster_reboot()
{
    run_ansible_routine "Kafka Cluster Reboot" "parallel" "cluster_reboot" "" "true"
    return $?
}

function cluster_reinstall()
{
    log "WARN" "--------------------------------------=[ INITIATING FULL CLUSTER REINSTALL ]=--------------------------------------"
    # stop everything
    containers_remove

    # regenerate all components
    configs_generate
    certificates_generate
    credentials_generate
    data_format

    # apply ACL, on running containers, they will produce errors in logs as running without ACLs.
    containers_run
    acls_apply

    # start containers from scratch, to: 1 - start failed nodes, 2 - wipe errors about missing ACLs.
    containers_remove
    containers_run
    log "WARN" "--------------------------------------=[ COMPLETED FULL CLUSTER REINSTALL ]=---------------------------------------"
}

# Creates a PID file to prevent multiple instances of the script from running.
# If the PID file already exists, the script exits; otherwise, it writes the current PID and sets a trap to remove the file upon exit.
function handle_pid_file()
{
    if [ -f "$PID_FILE" ]; then
        OLD_PID=$(cat "$PID_FILE")

        # Check if the process is still running
        if ps -p "$OLD_PID" > /dev/null 2>&1; then
            log "INFO" "The script is already running (PID: $OLD_PID). Exiting."
            exit 1
        else
            log "WARN" "Stale PID file found (PID: $OLD_PID). Removing and starting fresh."
            rm -f "$PID_FILE"
        fi
    fi

    # Create new PID file
    echo $$ >"$PID_FILE"

    # Trap to remove PID file on exit
    trap "kill 0; exit 130" SIGINT  # Kill all processes and exit gracefully when CTRL+C is pressed
    trap remove_pid_file EXIT       # Ensure the PID file is removed on any exit

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
        echo "The specified log level [$level] is not defined."
        exit 1
    fi

    # Check if the $level is greater or equal to the $LOG_LEVEL
    if [[ "${LOG_LEVELS[$level]}" -ge "${LOG_LEVELS[$LOG_LEVEL]}" ]]; then
        echo "[$level] $message"
    fi

    # Always logs the message, regardless of the log level.
    echo "[$(date '+%Y/%m/%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"
}

# Converts a file size from bytes to a human-readable format (B, KB, MB, GB).
# The IEC and SI recommend no space between the number and unit for file sizes.
function format_filesize() {
    local size=$1
    if ((size < 1024)); then
        echo "${size}B"
    elif ((size < 1048576)); then
        echo "$((size / 1024))KB"
    elif ((size < 1073741824)); then
        echo "$((size / 1048576))MB"
    else
        echo "$((size / 1073741824))GB"
    fi
}

# Checks the free disk space on a specified mount point and logs a warning if space is below the threshold.
# Logs a warning if the available disk space drops below 20% (or the configured `STORAGE_WARN_LOW` threshold).
function ensure_free_space()
{
    local mount free_storage free_percent

    mount=$1

    # Get the free storage (in KB & %) for the directory
    free_storage=$(df -P "$mount" | awk 'NR==2 {print $4}')
    free_percent=$(df -P "$mount" | awk 'NR==2 {print 100 - $5}')

    # Check if the free percentage is less than 20%
    if ((free_percent < STORAGE_WARN_LOW)); then
        log "WARN" "Low disk space on $mount. Available: ${free_storage} KB (${free_percent}% of total)."
    fi
}

# Runs an Ansible playbook inside a Docker container with specified routines and tags.
# Logs the start and end of the routine, and handles errors by logging the failed command.
function run_ansible_routine()
{
    local routine=$1
    local playbook=$2
    local tag=$3
    local extra_vars=${4:-""}  # Ensure extra_vars is always set
    local interactive_mode=${5:-false}  # Default to false if not provided
    local attempt=1
    local max_attempts=${ANSIBLE_ATTEMPTS:-3}  # Use ANSIBLE_ATTEMPTS if set, otherwise default to 3

    # Determine if -it should be included
    local docker_options="--rm"
    [[ "$interactive_mode" == "true" ]] && docker_options="-it --rm"

    # Prepare the Docker command as an array (to avoid eval issues)
    local docker_command=(
        docker run $docker_options
        -v ~/.ssh:/root/.ssh
        -v "$SCRIPT_DIR":/apps
        -v /var/log/ansible:/var/log/ansible
        -w /apps
        alpine/ansible:2.18.1 ansible-playbook
        -i "inventories/$INVENTORY/hosts.yml"
        "playbooks/$playbook.yml"
        --tags "$tag"
    )

    # Append extra_vars only if it's not empty
    if [[ -n "$extra_vars" ]]; then
        docker_command+=("$extra_vars")
    fi

    # Loop for a few attempts
    while [[ $attempt -le $max_attempts ]]; do
        log "INFO" "Routine - ${routine^} - started (attempt #${attempt} of ${max_attempts})"
        "${docker_command[@]}" && {
            log "INFO" "Routine - ${routine^} - OK"
            return 0
        }
        log "WARN" "Routine - ${routine^} - Failed attempt #${attempt} of ${max_attempts}, retrying."
        ((attempt++))
    done

    log "ERROR" "Routine - ${routine^} - Failed, attempts exhausted. Failed command: ${docker_command[*]}"
    return 1
}


# Deploys SSH public keys to all cluster nodes in parallel using Ansible.
# If SSH keys are not set up, the script will use the password provided via `--ask-pass` for all nodes.
function install_ssh_keys()
{
    run_ansible_routine "Deploy SSH Public Key on all nodes" "parallel" "ssh_keys" "--ask-pass" "true"
    return $?
}

# Deploys prerequisites to all cluster nodes in parallel using Ansible.
# Validates if /data is mounted and has at least 40GB free space.
# Ensures /var/lib/docker is symlinked to /data/docker.
# Installs and verifies: Docker, XZ, Java, and rsync.
# Ensures Docker service is enabled and running.
function install_prerequisites()
{
    run_ansible_routine "Deploy prerequisites on all nodes" "parallel" "prerequisites"
    return $?
}

# Generates Kafka certificates on all cluster nodes in parallel using Ansible.
# Ensures SSL/mTLS authentication files are created for secure communication.
function certificates_generate()
{
    run_ansible_routine "Kafka Certificates Generate" "parallel" "certificates_generate"
    return $?
}

# Backs up Kafka certificates on all cluster nodes in parallel using Ansible.
# Ensures certificate files are preserved for recovery or migration.
function certificates_backup()
{
    run_ansible_routine "Kafka Certificates Backup" "parallel" "certificates_backup"
    return $?
}

# Restores Kafka certificates on all cluster nodes in parallel using Ansible.
# Uses the specified archive file to restore certificate files.
function certificates_restore()
{
    local extra_vars="--extra-vars={\"restore_archive\":\"$1\"}"
    run_ansible_routine "Kafka Certificates Restore" "parallel" "certificates_restore" "$extra_vars"
    return $?
}

# Deletes old archives according to retention_policy_certificates days amount value
function certificates_rotate()
{
    run_ansible_routine "Kafka Certificates Rotate" "parallel" "certificates_rotate"
    return $?
}

# Deploys Kafka configuration files to all cluster nodes in parallel using Ansible.
# Ensures all nodes have the latest configuration settings from inventory template.
function configs_generate()
{
    run_ansible_routine "Kafka Configs Generate" "parallel" "configs_generate"
    return $?
}

# Backs up Kafka configuration files from all cluster nodes in parallel using Ansible.
# Ensures configuration settings are preserved for recovery or migration.
function configs_backup()
{
    run_ansible_routine "Kafka Configs Backup" "parallel" "configs_backup"
    return $?
}

# Restores Kafka configuration files on all cluster nodes in parallel using Ansible.
# Uses the specified archive file to restore configuration settings.
function configs_restore()
{
    local extra_vars="--extra-vars={\"restore_archive\":\"$1\"}"
    run_ansible_routine "Kafka Configs Restore" "parallel" "configs_restore" "$extra_vars"
    return $?
}

# Deletes old archives according to retention_policy_configs days amount value
function configs_rotate()
{
    run_ansible_routine "Kafka Configs Rotate" "parallel" "configs_rotate"
    return $?
}

# Starts Kafka containers on all cluster nodes in serial using Ansible.
# Ensures proper startup order and avoids simultaneous resource contention.
function containers_run()
{
    run_ansible_routine "Kafka Containers Run" "serial" "containers_run"
    return $?
}

# Resumes existing Kafka containers on all cluster nodes in serial using Ansible.
# Ensures a controlled startup sequence to prevent conflicts.
function containers_start()
{
    run_ansible_routine "Kafka Containers Start" "serial" "containers_start"
    return $?
}

# Stops Kafka containers on all cluster nodes in serial using Ansible.
# Ensures a controlled shutdown to prevent data corruption or inconsistencies.
function containers_stop()
{
    run_ansible_routine "Kafka Containers Stop" "serial" "containers_stop"
    return $?
}

# Restarts Kafka containers on all cluster nodes in serial using Ansible.
# Stops containers first, then starts them again in a controlled order.
function containers_restart()
{
    containers_stop
    containers_start
}

# Removes Kafka containers on all cluster nodes in serial using Ansible.
# Ensures a controlled removal sequence to prevent dependency issues.
function containers_remove()
{
    run_ansible_routine "Kafka Containers Remove" "serial" "containers_remove"
    return $?
}

# Applies Kafka ACLs to enforce access control policies across the cluster.
function acls_apply()
{
    run_ansible_routine "Kafka ACLs Apply" "parallel" "acls_apply"
    return $?
}

# Generates Kafka credentials on all cluster nodes in parallel using Ansible.
# Ensures secure authentication files are created for user access control.
function credentials_generate()
{
    run_ansible_routine "Kafka Credentials Generate" "parallel" "credentials_generate"
    return $?
}

# Backs up Kafka credentials on all cluster nodes in parallel using Ansible.
# Ensures authentication data is preserved for recovery or migration.
function credentials_backup()
{
    run_ansible_routine "Kafka Credentials Backup" "parallel" "credentials_backup"
    return $?
}

# Restores Kafka credentials on all cluster nodes in parallel using Ansible.
# Uses the specified archive file to restore authentication data.
function credentials_restore()
{
    local extra_vars="--extra-vars={\"restore_archive\":\"$1\"}"
    run_ansible_routine "Kafka Credentials Restore" "parallel" "credentials_restore" "$extra_vars"
    return $?
}

# Deletes old archives according to retention_policy_credentials days amount value
function credentials_rotate()
{
    run_ansible_routine "Kafka Credentials Rotate" "parallel" "credentials_rotate"
    return $?
}

# Formats Kafka data on all cluster nodes in parallel using Ansible.
# Prepares storage for new data by ensuring a clean state.
function data_format()
{
    run_ansible_routine "Kafka Data Format" "parallel" "data_format"
    return $?
}

# Backs up Kafka data on all cluster nodes in parallel using Ansible.
# Ensures data is preserved for recovery or migration.
function data_backup()
{
    run_ansible_routine "Kafka Data Backup" "parallel" "data_backup"
    return $?
}

# Restores Kafka data on all cluster nodes in parallel using Ansible.
# Uses the specified archive file to recover data.
function data_restore()
{
    local extra_vars="--extra-vars={\"restore_archive\":\"$1\"}"
    run_ansible_routine "Kafka Data Restore" "parallel" "data_restore" "$extra_vars"
    return $?
}

# Deletes old archives according to retention_policy_data days amount value
function data_rotate()
{
    run_ansible_routine "Kafka Data Rotate" "parallel" "data_rotate"
    return $?
}

# Displays a failure message using a Whiptail dialog box.
# Accepts a message string as an argument and shows it in a 10x60 box.
function show_failure_message() {
    whiptail --title "Failure" --msgbox "$1" 10 60 --ok-button "WTF"
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
# Allows navigation to submenus. Exits when the user selects "Quit" or presses ESC/cancel.
function menu_main() {
    while true; do
        choice=$(whiptail --title "Kafka Backup Offline" \
            --cancel-button "Quit" \
            --menu "Choose a section:" 16 50 8 \
            "1" "Quit" \
            "2" "Prerequisites" \
            "3" "Cluster Simple" \
            "4" "Cluster Advanced" \
            "5" "GUI(s)" \
            3>&1 1>&2 2>&3)

        # Capture the exit status of whiptail
        local exit_status=$?

        # Exit on ESC or cancel
        if [[ $exit_status -eq 1 || $exit_status -eq 255 ]]; then
            exit 0
        fi

        # Handle user choices
        case "$choice" in
            1) exit 0 ;;
            2) menu_prerequisites ;;
            3) menu_cluster_simple ;;
            4) menu_cluster_advanced ;;
            5) menu_gui ;;
        esac
    done
}

# Displays the Prerequisites menu using Whiptail for managing auxiliary tasks.
# Provides options to deploy SSH keys and prerequisites across all nodes.
# Returns to the main menu when "Back" is selected or ESC/cancel is pressed.
function menu_prerequisites() {
    while true; do
        # Display Whiptail menu for choosing an prerequisites-related action
        choice=$(whiptail --title "Kafka Backup Offline" \
            --cancel-button "Back" \
            --menu "Prerequisites > Choose an action:" 16 50 8 \
            "1" "Return to Main Menu" \
            "2" "Deploy SSH certificate - (ssh-copy-id)" \
            "3" "Deploy prerequisites - (docker etc)" \
            3>&1 1>&2 2>&3)

        # Capture the exit status of whiptail
        local exit_status=$?

        # Exit the function if ESC or cancel is pressed
        if [[ $exit_status -eq 1 || $exit_status -eq 255 ]]; then
            return 0
        fi

        # Handle the user's menu choice
        case "$choice" in
            1)
               # Return to the parent menu
               return 0 ;;
            2)
               install_ssh_keys
               if [[ $? -eq 0 ]]; then
                    show_success_message "SSH public key deployed successfully on all nodes!"
               else
                    show_failure_message "Failed to deploy SSH public key.\n\nExit the tool and review the logs."
               fi
               ;;
            3)
               install_prerequisites
               if [[ $? -eq 0 ]]; then
                    show_success_message "Prerequisites were deployed on all nodes successfully!"
               else
                    show_failure_message "Failed to deploy prerequisites!\n\nExit the tool and review the logs."
               fi
               ;;
        esac
    done
}

# Displays the Prerequisites menu using Whiptail for managing auxiliary tasks.
# Provides options to deploy SSH keys and prerequisites across all nodes.
# Returns to the main menu when "Back" is selected or ESC/cancel is pressed.
function menu_cluster_simple() {
    while true; do
        # Display Whiptail menu for choosing an prerequisites-related action
        choice=$(whiptail --title "Kafka Backup Offline" \
            --cancel-button "Back" \
            --menu "Cluster Simple > Choose an action:" 16 50 8 \
            "1" "Return to Main Menu" \
            "2" "Backup" \
            "3" "Reboot" \
            "4" "Wipe & Reinstall" \
            3>&1 1>&2 2>&3)

        # Capture the exit status of whiptail
        local exit_status=$?

        # Exit the function if ESC or cancel is pressed
        if [[ $exit_status -eq 1 || $exit_status -eq 255 ]]; then
            return 0
        fi

        # Handle the user's menu choice
        case "$choice" in
            1)
               # Return to the parent menu
               return 0 ;;
            2)
               cluster_backup
               if [[ $? -eq 0 ]]; then
                    show_success_message "Cluster Backup was successful!"
               else
                    show_failure_message "Cluster Backup Failed!\n\nExit the tool and review the logs."
               fi
               ;;
            3)
               cluster_reboot
               if [[ $? -eq 0 ]]; then
                    show_success_message "Cluster reboot was issued successfully!"
               else
                    show_failure_message "Failed to reboot the cluster!\n\nExit the tool and review the logs."
               fi
               ;;
            4)
               cluster_reinstall
               if [[ $? -eq 0 ]]; then
                    show_success_message "Cluster reinstall was performed successfully!"
               else
                    show_failure_message "Failed to reinstall the cluster!\n\nExit the tool and review the logs."
               fi
               ;;
        esac
    done
}

# Displays the Certificates menu using Whiptail for managing Kafka certificates.
# Provides options to generate, backup, or restore certificates.
# Returns to the main menu when "Back" is selected or ESC/cancel is pressed.
function menu_cluster_advanced() {
    while true; do
        # Display Whiptail menu for choosing a certificate-related action
        choice=$(whiptail --title "Kafka Backup Offline" \
            --cancel-button "Back" \
            --menu "Cluster Advanced > Choose an action:" 16 50 8 \
            "1" "Return to Main Menu" \
            "2" "ACLs" \
            "3" "Certificates" \
            "4" "Configs" \
            "5" "Containers" \
            "6" "Credentials" \
            "7" "Data" \
            3>&1 1>&2 2>&3)

        # Capture the exit status of the Whiptail menu
        local exit_status=$?

        # Exit the function if ESC or cancel is pressed
        if [[ $exit_status -eq 1 || $exit_status -eq 255 ]]; then
            return 0
        fi

        # Handle user choices
        case "$choice" in
            1)
               # Return to the parent menu
               return 0 ;;
            2) menu_acls ;;
            3) menu_certificates ;;
            4) menu_configs ;;
            5) menu_containers ;;
            6) menu_credentials ;;
            7) menu_data ;;
        esac
    done
}

# Displays a menu for managing Kafka ACLs, allowing users to apply ACL configurations.
# Handles user input via whiptail and executes ACL application with error handling.
function menu_acls() {
    while true; do
        choice=$(whiptail --title "Kafka Backup Offline" \
            --menu "Cluster Advanced > ACLs > Choose an action" 16 50 8 \
            "1" "Return to Advanced Menu" \
            "2" "ACL Apply" \
            3>&1 1>&2 2>&3)

        # Capture the exit status of whiptail
        local exit_status=$?

        # Exit on ESC or cancel
        if [[ $exit_status -eq 1 || $exit_status -eq 255 ]]; then
            return 0
        fi

        case "$choice" in
            1)
               # Return to the parent menu
               return 0 ;;
            2)
               acls_apply
               if [[ $? -eq 0 ]]; then
                    show_success_message "ACLs were applied successfully!"
               else
                    show_failure_message "Failed to apply ACLs!\n\nExit the tool and review the logs."
               fi
               ;;
        esac
    done
}

# Displays the Certificates menu using Whiptail for managing Kafka certificates.
# Provides options to generate, backup, or restore certificates.
# Returns to the main menu when "Back" is selected or ESC/cancel is pressed.
function menu_certificates() {
    while true; do
        # Display Whiptail menu for choosing a certificate-related action
        choice=$(whiptail --title "Kafka Backup Offline" \
            --cancel-button "Back" \
            --menu "Cluster Advanced > Certificates > Choose an action:" 16 50 8 \
            "1" "Return to Advanced Menu" \
            "2" "Generate" \
            "3" "Backup" \
            "4" "Restore" \
            "5" "Rotate" \
            3>&1 1>&2 2>&3)

        # Capture the exit status of the Whiptail menu
        local exit_status=$?

        # Exit the function if ESC or cancel is pressed
        if [[ $exit_status -eq 1 || $exit_status -eq 255 ]]; then
            return 0
        fi

        # Handle the user's menu choice
        case "$choice" in
            1)
               # Return to the parent menu
               return 0 ;;
            2)
               certificates_generate
               if [[ $? -eq 0 ]]; then
                    show_success_message "Certificates were generated successfully!"
               else
                    show_failure_message "Failed to generate certificates!\n\nExit the tool and review the logs."
               fi
               ;;
            3)
               certificates_backup
               if [[ $? -eq 0 ]]; then
                    show_success_message "Certificates were backed up successfully!"
               else
                    show_failure_message "Failed to backup certificates!\n\nExit the tool and review the logs."
               fi
               ;;
            4)
               menu_certificates_restore ;;
            5)
               certificates_rotate
               if [[ $? -eq 0 ]]; then
                    show_success_message "Certificates backups were rotated successfully!"
               else
                    show_failure_message "Failed to rotate certificates backups!\n\nExit the tool and review the logs."
               fi
               ;;
        esac
    done
}

# Displays a Whiptail menu for restoring Kafka certificates from backup files.
# Lists available backup files with their sizes and allows the user to select one for restoration.
# If no backups are found, shows a warning and exits.
# Calls `certificates_restore` with the selected backup file.
function menu_certificates_restore()
{
    local storage backup_files choice selected_backup

    # Define the path to certificate backup storage
    storage="$STORAGE_COLD/certificates"

    # Find all available backup files with their sizes safely
    backup_files=()
    while IFS= read -r line; do
        filesize_bytes="${line##* }"                           # Extract the last field (file size)
        filename="${line:0:${#line} - ${#filesize_bytes} - 1}" # Remove the file size from the end
        formatted_size=$(format_filesize "$filesize_bytes")    # Convert size to readable format
        backup_files+=("${filename} ${formatted_size}")        # Store filename with formatted size
    done < <(find "$storage" -type f -name "*.tar.*" -printf '%P %s\n' | sort)

    # Check if no files are available
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        log "DEBUG" "No backup files found in $storage."
        show_warning_message "No backup files found in $storage."
        return 1
    fi

    # Prepare the options for whiptail menu
    local menu_options=("back" "Return to certificate Menu") # Add "Back" option first
    for i in "${!backup_files[@]}"; do
        # Add each backup file with its details to the menu options
        menu_options+=("$i" "${backup_files[$i]}")
    done

    # Display the menu using whiptail for user selection
    choice=$(whiptail --title "Kafka Backup Offline" \
        --cancel-button "Back" \
        --menu "Certificates > Restore > Choose a backup file to restore:" 40 140 32 \
        "${menu_options[@]}" 3>&1 1>&2 2>&3)

    # Capture the exit status of whiptail
    local exit_status=$?

    # Exit on ESC or cancel
    if [[ $exit_status -eq 1 || $exit_status -eq 255 || $choice == "back" ]]; then
        return 0
    fi

    # Extract the full filename safely (removes the last space-separated field which is the filesize)
    selected_backup="${backup_files[$choice]% *}"

    # Ensure the full path is included
    selected_backup="$storage/$selected_backup"
    log "DEBUG" "Selected backup file: $selected_backup"

    # Call the restore function with the selected backup file
    certificates_restore "$selected_backup"
    if [[ $? -eq 0 ]]; then
        show_success_message "Certificates restored successfully!"
    else
        show_failure_message "Failed to restore certificates.\n\nExit the tool and review the logs."
    fi
}

# Displays the Configs menu using Whiptail for managing Kafka configurations.
# Provides options to generate, backup, or restore configuration files.
# Returns to the main menu when "Back" is selected or ESC/cancel is pressed.
function menu_configs() {
    while true; do
        choice=$(whiptail --title "Kafka Backup Offline" \
            --cancel-button "Back" \
            --menu "Cluster Advanced > Configs > Choose an action:" 16 50 8 \
            "1" "Return to Advanced Menu" \
            "2" "Generate" \
            "3" "Backup" \
            "4" "Restore" \
            "5" "Rotate" \
            3>&1 1>&2 2>&3)

        # Capture the exit status of whiptail
        local exit_status=$?

        # Exit on ESC or cancel
        if [[ $exit_status -eq 1 || $exit_status -eq 255 ]]; then
            return 0
        fi

        case "$choice" in
            1)
               # Return to the parent menu
               return 0 ;;
            2)
               configs_generate
               if [[ $? -eq 0 ]]; then
                    show_success_message "Configuration was generated successfully!"
               else
                    show_failure_message "Failed to generate configuration!\n\nExit the tool and review the logs."
               fi
               ;;
            3)
               configs_backup
               if [[ $? -eq 0 ]]; then
                    show_success_message "Configuration was backed up successfully!"
               else
                    show_failure_message "Failed to backup configuration!\n\nExit the tool and review the logs."
               fi
               ;;
            4)
               menu_configs_restore;;
            5)
               configs_rotate
               if [[ $? -eq 0 ]]; then
                    # Show success message if the rotate is successful
                    show_success_message "Configuration backups were rotated successfully!"
               else
                    # Show failure message if the rotate fails
                    show_failure_message "Failed to rotate configuration backups!\n\nExit the tool and review the logs."
               fi
               ;;
        esac
    done
}

# Displays a Whiptail menu for restoring Kafka configuration backups.
# Lists available backup files with their sizes and allows the user to select one for restoration.
# If no backups are found, shows a warning and exits.
# Calls `configs_restore` with the selected backup file.
function menu_configs_restore()
{
    local storage backup_files choice selected_backup

    # Define the path to config backup storage
    storage="$STORAGE_COLD/configs"

    # Find all available backup files with their sizes safely
    backup_files=()
    while IFS= read -r line; do
        filesize_bytes="${line##* }"                           # Extract the last field (file size)
        filename="${line:0:${#line} - ${#filesize_bytes} - 1}" # Remove the file size from the end
        formatted_size=$(format_filesize "$filesize_bytes")    # Convert size to readable format
        backup_files+=("${filename} ${formatted_size}")        # Store filename with formatted size
    done < <(find "$storage" -type f -name "*.tar.*" -printf '%P %s\n' | sort)

    # Check if no files are available
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        log "DEBUG" "No backup files found in $storage."
        show_warning_message "No backup files found in $storage."
        return 1
    fi

    # Prepare the options for whiptail menu
    local menu_options=("back" "Return to Config Menu") # Add "Back" option first
    for i in "${!backup_files[@]}"; do
        menu_options+=("$i" "${backup_files[$i]}")
    done

    # Display the menu using whiptail
    choice=$(whiptail --title "Kafka Backup Offline" \
        --cancel-button "Back" \
        --menu "Configs > Restore > Choose a backup file to restore:" 40 140 32 \
        "${menu_options[@]}" 3>&1 1>&2 2>&3)

    # Capture the exit status of whiptail
    local exit_status=$?

    # Exit on ESC or cancel
    if [[ $exit_status -eq 1 || $exit_status -eq 255 || $choice == "back" ]]; then
        return 0
    fi

    # Extract the full filename safely (removes the last space-separated field which is the filesize)
    selected_backup="${backup_files[$choice]% *}"

    # Ensure the full path is included
    selected_backup="$storage/$selected_backup"
    log "DEBUG" "Selected backup file: $selected_backup"

    # Call the restore function with the selected backup file
    configs_restore "$selected_backup"
    if [[ $? -eq 0 ]]; then
        show_success_message "Configuration restored successfully!"
    else
        show_failure_message "Failed to restore configuration!\n\nExit the tool and review the logs."
    fi
}

# Displays the Containers menu using Whiptail for managing Kafka containers.
# Provides options to run, start, stop, restart, or remove containers.
# Returns to the main menu when "Back" is selected or ESC/cancel is pressed.
function menu_containers() {
    while true; do
        choice=$(whiptail --title "Kafka Backup Offline" \
            --menu "Cluster Advanced > Containers > Choose an action" 16 50 8 \
            "1" "Return to Advanced Menu" \
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

        case "$choice" in
            1)
               # Return to the parent menu
               return 0 ;;
            2)
               containers_run
               if [[ $? -eq 0 ]]; then
                   show_success_message "The containers were successfully started!\nAll services are now running."
               else
                   show_failure_message "Unable to start the containers!\n\nExit the tool and review the logs."
               fi
               ;;
            3)
               containers_start
               if [[ $? -eq 0 ]]; then
                   show_success_message "The containers were successfully resumed!\nPreviously stopped services are now active."
               else
                   show_failure_message "Failed to resume the containers!\n\nExit the tool and review the logs."
               fi
               ;;
            4)
               containers_stop
               if [[ $? -eq 0 ]]; then
                   show_success_message "The containers were successfully stopped!\nAll services are now inactive."
               else
                   show_failure_message "Unable to stop the containers!\n\nExit the tool and review the logs."
               fi
               ;;
            5)
               containers_restart
               if [[ $? -eq 0 ]]; then
                   show_success_message "The containers were successfully restarted!\nAll services have been refreshed."
               else
                   show_failure_message "Failed to restart the containers!\n\nExit the tool and review the logs."
               fi
               ;;
            6)
               containers_remove
               if [[ $? -eq 0 ]]; then
                   show_success_message "The containers were successfully removed!\nResources have been freed."
               else
                   show_failure_message "Failed to remove the containers!\n\nExit the tool and review the logs."
               fi
               ;;
        esac
    done
}

# Displays the Credentials menu using Whiptail for managing Kafka credentials.
# Provides options to generate, backup, or restore credentials.
# Returns to the main menu when "Back" is selected or ESC/cancel is pressed.
function menu_credentials() {
    while true; do
        choice=$(whiptail --title "Kafka Backup Offline" \
            --menu "Cluster Advanced > Credentials > Choose an action" 16 50 8 \
            "1" "Return to Advanced Menu" \
            "2" "Generate" \
            "3" "Backup" \
            "4" "Restore" \
            "5" "Rotate" \
            3>&1 1>&2 2>&3)

        # Capture the exit status of whiptail
        local exit_status=$?

        # Exit on ESC or cancel
        if [[ $exit_status -eq 1 || $exit_status -eq 255 ]]; then
            return 0
        fi

        case "$choice" in
            1)
               # Return to the parent menu
               return 0 ;;
            2)
               credentials_generate
               if [[ $? -eq 0 ]]; then
                    show_success_message "Credentials was generated successfully!"
               else
                    show_failure_message "Failed to generate credentials!\n\nExit the tool and review the logs."
               fi
               ;;
            3)
               credentials_backup
               if [[ $? -eq 0 ]]; then
                    show_success_message "Credentials was backed up successfully!"
               else
                    show_failure_message "Failed to backup credentials!\n\nExit the tool and review the logs."
               fi
               ;;
            4)
               menu_credentials_restore;;
            5)
               credentials_rotate
               if [[ $? -eq 0 ]]; then
                    show_success_message "Credentials backups were rotated successfully!"
               else
                    show_failure_message "Failed to rotate credentials backups!\n\nExit the tool and review the logs."
               fi
               ;;
        esac
    done
}

# Displays a Whiptail menu for restoring Kafka credentials from backup files.
# Lists available backup files with their sizes and allows the user to select one for restoration.
# If no backups are found, shows a warning and exits.
# Calls `credentials_restore` with the selected backup file.
function menu_credentials_restore()
{
    local storage backup_files choice selected_backup

    # Define the path to credentials backup storage
    storage="$STORAGE_COLD/credentials"

    # Find all available backup files with their sizes safely
    backup_files=()
    while IFS= read -r line; do
        filesize_bytes="${line##* }"                           # Extract the last field (file size)
        filename="${line:0:${#line} - ${#filesize_bytes} - 1}" # Remove the file size from the end
        formatted_size=$(format_filesize "$filesize_bytes")    # Convert size to readable format
        backup_files+=("${filename} ${formatted_size}")        # Store filename with formatted size
    done < <(find "$storage" -type f -name "*.tar.*" -printf '%P %s\n' | sort)

    # Check if no files are available
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        log "DEBUG" "No backup files found in $storage."
        show_warning_message "No backup files found in $storage."
        return 1
    fi

    # Prepare the options for whiptail menu
    local menu_options=("back" "Return to credentials Menu") # Add "Back" option first
    for i in "${!backup_files[@]}"; do
        menu_options+=("$i" "${backup_files[$i]}")
    done

    # Display the menu using whiptail
    choice=$(whiptail --title "Kafka Backup Offline" \
        --cancel-button "Back" \
        --menu "Credentials > Restore > Choose a backup file to restore:" 40 140 32 \
        "${menu_options[@]}" 3>&1 1>&2 2>&3)

    # Capture the exit status of whiptail
    local exit_status=$?

    # Exit on ESC or cancel
    if [[ $exit_status -eq 1 || $exit_status -eq 255 || $choice == "back" ]]; then
        return 0
    fi

    # Extract the full filename safely (removes the last space-separated field which is the filesize)
    selected_backup="${backup_files[$choice]% *}"

    # Ensure the full path is included
    selected_backup="$storage/$selected_backup"
    log "DEBUG" "Selected backup file: $selected_backup"

    # Call the restore function with the selected backup file
    credentials_restore "$selected_backup"
    if [[ $? -eq 0 ]]; then
        show_success_message "Credentials restored successfully!"
    else
        show_failure_message "Failed to restore credentials!\n\nExit the tool and review the logs."
    fi
}


# Displays the Data menu using Whiptail for managing Kafka data.
# Provides options to format, backup, or restore data.
# Returns to the main menu when "Back" is selected or ESC/cancel is pressed.
function menu_data() {
    while true; do
        choice=$(whiptail --title "Kafka Backup Offline" \
            --menu "Cluster Advanced > Data > Choose an action:" 16 50 8 \
            "1" "Return to Advanced Menu" \
            "2" "Format" \
            "3" "Backup" \
            "4" "Restore" \
            "5" "Rotate" \
            3>&1 1>&2 2>&3)

        # Capture the exit status of whiptail
        local exit_status=$?

        # Exit on ESC or cancel
        if [[ $exit_status -eq 1 || $exit_status -eq 255 ]]; then
            return 0
        fi

        case "$choice" in
            1)
               # Return to the parent menu
               return 0 ;;
            2)
               data_format
               if [[ $? -eq 0 ]]; then
                   show_success_message "Data formatting completed successfully!\nThe cluster is now ready for initialization with fresh data."
               else
                   show_failure_message "Data formatting failed!\n\nExit the tool and review the logs."
               fi
               ;;
            3)
               data_backup
               if [[ $? -eq 0 ]]; then
                   show_success_message "Data backup completed successfully!\nYou can now safely proceed with any maintenance or restore operations."
               else
                   show_failure_message "Data backup failed!\n\nExit the tool and review the logs."
               fi
               ;;
            4)
               menu_data_restore;;
            5)
               data_rotate
               if [[ $? -eq 0 ]]; then
                    show_success_message "Data backups were rotated successfully!"
               else
                    show_failure_message "Failed to rotate data backups!\n\nExit the tool and review the logs."
               fi
               ;;
        esac
    done
}

# Displays a Whiptail menu for restoring Kafka data from backup files.
# Lists available backup files with their sizes and allows the user to select one for restoration.
# If no backups are found, shows a warning and exits.
# Calls `data_restore` with the selected backup file.
function menu_data_restore()
{
    local storage backup_files choice selected_backup

    # Define the path to data backup storage
    storage="$STORAGE_COLD/data"

    # Find all available backup files with their sizes safely
    backup_files=()
    while IFS= read -r line; do
        filesize_bytes="${line##* }"                           # Extract the last field (file size)
        filename="${line:0:${#line} - ${#filesize_bytes} - 1}" # Remove the file size from the end
        formatted_size=$(format_filesize "$filesize_bytes")    # Convert size to readable format
        backup_files+=("${filename} ${formatted_size}")        # Store filename with formatted size
    done < <(find "$storage" -type f -name "*.tar.*" -printf '%P %s\n' | sort)

    # Check if no backup files are available
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        log "DEBUG" "No backup files found in $storage."
        show_warning_message "No backup files found in $storage."
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
        --menu "Data > Restore > Choose a backup file to restore:" 40 140 32 \
        "${menu_options[@]}" 3>&1 1>&2 2>&3)

    # Capture the exit status of whiptail
    local exit_status=$?

    # Exit on ESC or cancel
    if [[ $exit_status -eq 1 || $exit_status -eq 255 || $choice == "back" ]]; then
        return 0
    fi

    # Extract the full filename safely (removes the last space-separated field which is the filesize)
    selected_backup="${backup_files[$choice]% *}"

    # Ensure the full path is included
    selected_backup="$storage/$selected_backup"
    log "DEBUG" "Selected backup file: $selected_backup"

    # Call the restore function with the selected backup file
    data_restore "$selected_backup"
    if [[ $? -eq 0 ]]; then
        show_success_message "Data restoration completed successfully!\nThe cluster has been restored to the selected backup state."
    else
        show_failure_message "Data restoration failed!\n\nExit the tool and review the logs."
    fi
}


# Displays a menu for managing Kafka ACLs, allowing users to apply ACL configurations.
# Handles user input via whiptail and executes ACL application with error handling.
function menu_gui() {
    while true; do
        choice=$(whiptail --title "Kafka Backup Offline" \
            --menu "GUI(s) > Choose an action" 16 50 8 \
            "1" "Return to Main Menu" \
            "2" "Deploy Docker GUI - 'Portainer-CE' on all nodes" \
            "3" "Deploy Kafka GUI - 'Kafka-UI' on node-0" \
            "4" "Deploy Kafka GUI - 'KPOW-CE' on node-0" \
            3>&1 1>&2 2>&3)

        # Capture the exit status of whiptail
        local exit_status=$?

        # Exit on ESC or cancel
        if [[ $exit_status -eq 1 || $exit_status -eq 255 ]]; then
            return 0
        fi

        case "$choice" in
            1)
               # Return to the parent menu
               return 0 ;;
            2)
               gui_portainer
               if [[ $? -eq 0 ]]; then
                    show_success_message "Portainer was deployed on all cluster nodes!"
               else
                    show_failure_message "Failed to deploy Portainer\n\nExit the tool and review the logs."
               fi
               ;;
            3)
               gui_kafka
               if [[ $? -eq 0 ]]; then
                    show_success_message "Kafka GUI - 'Kafka-UI' was deployed!"
               else
                    show_failure_message "Failed to deploy Kafka GUI - 'Kafka-UI'\n\nExit the tool and review the logs."
               fi
               ;;
            4)
               gui_kpow
               if [[ $? -eq 0 ]]; then
                    show_success_message "Kafka GUI - 'Kpow' was deployed!"
               else
                    show_failure_message "Failed to deploy Kafka GUI - 'Kpow'\n\nExit the tool and review the logs."
               fi
               ;;
        esac
    done
}

# ===== Main Execution =====
handle_directory
handle_configuration
handle_pid_file
handle_main