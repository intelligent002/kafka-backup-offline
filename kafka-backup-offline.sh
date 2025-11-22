#!/usr/bin/env bash

######################################################################
# Section 1: Core Logging, Utilities, Config & PID Handling
######################################################################

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

# Save/restore working directory – always run from the script’s directory.
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
    LOG_LEVEL="${ini_data[general.LOG_LEVEL]}" # Log level threshold
    INVENTORY="${ini_data[general.INVENTORY]}" # inventory folder
    ANSIBLE_ATTEMPTS="${ini_data[general.ANSIBLE_ATTEMPTS]}" # Ansible retry attempts

    # Load storage configuration variables for temporary and cold backup storage paths.
    parse_ini_file "$config_file" "storage"
    STORAGE_TEMP="${ini_data[storage.STORAGE_TEMP]}"                         # Temporary storage directory on the GUI server
    STORAGE_COLD="${ini_data[storage.STORAGE_COLD]}"                         # Permanent cold storage directory for backups
    STORAGE_WARN_LOW="${ini_data[storage.STORAGE_WARN_LOW]}"                 # Percentage threshold for warning

    # make sure we can log stuff
    mkdir -p "$(dirname "$LOG_FILE")"

    log "INFO" "Configuration loaded from '$config_file'"
    ensure_free_space $STORAGE_COLD
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

######################################################################
# Section 2: Core Engine – Ansible Execution
######################################################################

# Runs an Ansible playbook inside a Docker container with specified routines and tags.
# Logs the start and end of the routine, and handles errors by logging the failed command.
function run_ansible_routine()
{
    local routine=$1
    local tag=$2
    local extra_vars=${3:-""}          # Ensure extra_vars is always set
    local interactive_mode=${4:-false} # Default to false if not provided
    local attempt=1
    local max_attempts=${ANSIBLE_ATTEMPTS:-3}  # Use ANSIBLE_ATTEMPTS if set, otherwise default to 3

    # Determine if -it should be included
    local docker_options="--rm"
    [[ "$interactive_mode" == "true" ]] && docker_options="-it --rm"

    # Prepare the Docker command as an array (to avoid eval issues)
    local docker_command=(
        docker run $docker_options
        -v /root:/root
        -v "$SCRIPT_DIR":/apps
        -v /var/log/ansible:/var/log/ansible
        -w /apps
        alpine/ansible:2.18.1 ansible-playbook
        -i "inventories/$INVENTORY/hosts.yml"
        "playbooks/parallel.yml"
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

# Deploys SSH public keys to all cluster nodes using Ansible.
# Falls back to password authentication when keys are not yet installed.
function install_ssh_keys()
{
    run_ansible_routine "Deploy SSH Public Key on all nodes" "ssh_keys" "--ask-pass" "true"
    return $?
}

# Deploys required system prerequisites to all cluster nodes using Ansible.
# Verifies storage, installs dependencies, and ensures Docker is operational.
function install_prerequisites()
{
    run_ansible_routine "Deploy prerequisites on all nodes" "prerequisites"
    return $?
}

######################################################################
# Section 3: High-Level Cluster Operations
######################################################################

# Cron-oriented function for automated Kafka cluster backups.
# 1. Stops all Kafka containers to ensure data consistency.
# 2. Backs up involved vms /cluster/data/ folders: configs, certs, data etc - storing everything in single zip on cold storage.
# 3. Starts all Kafka containers after the backup process completes.
function cluster_backup()
{
    log "INFO" "---------------------------------------=[ INITIATING FULL CLUSTER BACKUP ]=----------------------------------------"
    # validate storage space
    ensure_free_space $STORAGE_COLD

    # offline actions to maintain data integrity
    containers_stop
    cluster_rotate
    cluster_backup_run
    containers_start

    # validate storage space
    ensure_free_space $STORAGE_COLD
    log "INFO" "----------------------------------------=[ COMPLETED FULL CLUSTER BACKUP ]=----------------------------------------"
}

# Executes the Ansible playbook responsible for performing the Kafka cluster backup.
# Returns the exit code from run_ansible_routine.
function cluster_rotate()
{
    run_ansible_routine "Kafka Cluster Backup" "cluster_rotate"
    return $?
}
# Executes the Ansible playbook responsible for performing the Kafka cluster backup.
# Returns the exit code from run_ansible_routine.
function cluster_backup_run()
{
    run_ansible_routine "Kafka Cluster Backup" "cluster_backup"
    return $?
}

# Performs a full Kafka cluster reinstall:
# - removes all containers and wipes runtime state
# - regenerates configs, credentials, certificates, and data directories
# - runs containers to apply ACLs (expected temporary errors)
# - restarts containers cleanly to eliminate ACL-related startup warnings
function cluster_reinstall()
{
    log "WARN" "--------------------------------------=[ INITIATING FULL CLUSTER REINSTALL ]=--------------------------------------"
    # stop everything
    containers_remove

    # regenerate all components
    configs_generate
    credentials_generate
    certificates_generate
    data_format

    # apply ACL, on running containers, they will produce errors in logs as running without ACLs.
    containers_run
    acls_apply

    # start containers from scratch, to: 1 - start failed nodes, 2 - wipe errors about missing ACLs.
    containers_remove
    containers_run
    log "WARN" "--------------------------------------=[ COMPLETED FULL CLUSTER REINSTALL ]=---------------------------------------"
}

# Restores a Kafka cluster snapshot from the provided archive file.
# Pass the snapshot path as the first argument.
function cluster_restore()
{
    local extra_vars="--extra-vars={\"restore_archive\":\"$1\"}"
    run_ansible_routine "Kafka Snapshot Restore" "cluster_restore" "$extra_vars"
    return $?
}

# Run the cluster reboot playbook via Ansible
# Return the exit code to the caller
function cluster_reboot()
{
    run_ansible_routine "Kafka Cluster Reboot" "cluster_reboot"
    return $?
}

######################################################################
# Section 4: Component Operations – ACLs, Certificates, Configs, Credentials, Data
######################################################################

# Applies Kafka ACLs to enforce access control policies across the cluster.
function acls_apply()
{
    run_ansible_routine "Kafka ACLs Apply" "acls_apply"
    return $?
}

# Generates Kafka certificates across all cluster nodes using Ansible.
# Creates all SSL and mTLS assets required for secure cluster communication.
function certificates_generate()
{
    run_ansible_routine "Kafka Certificates Generate" "certificates_generate"
    return $?
}

# Deploys Kafka configuration files across all cluster nodes using Ansible.
# Applies the latest inventory-based settings to ensure consistent cluster configuration.
function configs_generate()
{
    run_ansible_routine "Kafka Configs Generate" "configs_generate"
    return $?
}

# Generates Kafka credentials across all cluster nodes using Ansible.
# Creates secure authentication files required for user and service access control.
function credentials_generate()
{
    run_ansible_routine "Kafka Credentials Generate" "credentials_generate"
    return $?
}

# Formats Kafka data across all cluster nodes using Ansible.
# Prepares storage by ensuring a clean and consistent state for new data.
function data_format()
{
    run_ansible_routine "Kafka Data Format" "data_format"
    return $?
}

######################################################################
# Section 5: Container & GUI Operations
######################################################################

# Starts Kafka containers across all cluster nodes using Ansible.
# Ensures each node is initialized according to its defined service role.
function containers_run()
{
    run_ansible_routine "Kafka Containers Run" "containers_run"
    return $?
}

# Starts Kafka containers across all cluster nodes using Ansible automation.
# Ensures the cluster is brought online consistently according to node configuration.
function containers_start()
{
    run_ansible_routine "Kafka Containers Start" "containers_start"
    return $?
}

# Stops Kafka containers across all cluster nodes using Ansible.
# Ensures a clean and consistent shutdown to protect data integrity.
function containers_stop()
{
    run_ansible_routine "Kafka Containers Stop" "containers_stop"
    return $?
}

# Restarts Kafka containers across all cluster nodes using Ansible.
# Performs a clean stop followed by a coordinated start to ensure stability.
function containers_restart()
{
    run_ansible_routine "Kafka Containers Restart" "containers_restart"
}

# Removes Kafka containers across all cluster nodes using Ansible.
# Ensures each node is cleaned up consistently without leaving residual state.
function containers_remove()
{
    run_ansible_routine "Kafka Containers Remove" "containers_remove"
    return $?
}

# Deploy portainer on all nodes
function gui_portainer_install()
{
    run_ansible_routine "GUI Portainer - Install" "gui_portainer_install"
    return $?
}

# Start portainer on all nodes
function gui_portainer_start()
{
    run_ansible_routine "GUI Portainer - Start" "gui_portainer_start"
    return $?
}

# Stop portainer on all nodes
function gui_portainer_stop()
{
    run_ansible_routine "GUI Portainer - Stop" "gui_portainer_stop"
    return $?
}

# Restart portainer on all nodes
function gui_portainer_restart()
{
    run_ansible_routine "GUI Portainer - Restart" "gui_portainer_restart"
    return $?
}

# Uninstall portainer on all nodes
function gui_portainer_uninstall()
{
    run_ansible_routine "GUI Portainer - Uninstall" "gui_portainer_uninstall"
    return $?
}

# Deploy KPOW-CE on node-00
function gui_kpow_ce_install()
{
    run_ansible_routine "GUI KPOW-CE - Install" "gui_kpow_ce_install"
    return $?
}

# Start KPOW-CE
function gui_kpow_ce_start()
{
    run_ansible_routine "GUI KPOW-CE - Start" "gui_kpow_ce_start"
    return $?
}

# Stop KPOW-CE
function gui_kpow_ce_stop()
{
    run_ansible_routine "GUI KPOW-CE - Stop" "gui_kpow_ce_stop"
    return $?
}

# Restart KPOW-CE
function gui_kpow_ce_restart()
{
    run_ansible_routine "GUI KPOW-CE - Restart" "gui_kpow_ce_restart"
    return $?
}

# Uninstall KPOW-CE
function gui_kpow_ce_uninstall()
{
    run_ansible_routine "GUI KPOW-CE - Uninstall" "gui_kpow_ce_uninstall"
    return $?
}

######################################################################
# Section 6: Whiptail Helpers & Menus
######################################################################

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
            --menu "Choose a section:" 18 60 8 \
            "1" "Quit" \
            "2" "Cluster" \
            "3" "Components" \
            "4" "GUI" \
            "5" "Prerequisites" \
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
            2) menu_cluster ;;
            3) menu_components ;;
            4) menu_gui ;;
            5) menu_prerequisites ;;
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
            --menu "Prerequisites > Choose an action:" 18 60 8 \
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

# Displays the Cluster menu.
function menu_cluster() {
    while true; do
        # Display Whiptail menu for choosing an action
        choice=$(whiptail --title "Kafka Backup Offline" \
            --cancel-button "Back" \
            --menu "Cluster > Choose an action:" 18 60 8 \
            "1" "Return to Main Menu" \
            "2" "Cluster Backup" \
            "3" "Cluster Restore" \
            "4" "Cluster Reboot" \
            "5" "Cluster Wipe & Reinstall" \
            3>&1 1>&2 2>&3)

        # Capture the exit status of whiptail
        local exit_status=$?

        # Exit the function if ESC or cancel is pressed
        if [[ $exit_status -eq 1 || $exit_status -eq 255 ]]; then
            return 0
        fi

        # Handle the user's menu choice
        case "$choice" in
            1) return 0 ;;
            2) cluster_backup
               if [[ $? -eq 0 ]]; then
                    show_success_message "Cluster Backup was successful!"
               else
                    show_failure_message "Cluster Backup Failed!\n\nExit the tool and review the logs."
               fi
               ;;
            3) menu_cluster_restore ;;
            4) cluster_reboot
               if [[ $? -eq 0 ]]; then
                    show_success_message "Cluster reboot was issued successfully!"
               else
                    show_failure_message "Failed to reboot the cluster!\n\nExit the tool and review the logs."
               fi
               ;;
            5) cluster_reinstall
               if [[ $? -eq 0 ]]; then
                    show_success_message "Cluster reinstall was performed successfully!"
               else
                    show_failure_message "Failed to reinstall the cluster!\n\nExit the tool and review the logs."
               fi
               ;;
        esac
    done
}

# Displays a Whiptail menu for restoring Kafka data from backup files.
# Lists available backup files with their sizes and allows the user to select one for restoration.
# If no backups are found, shows a warning and exits.
# Calls `cluster_restore` with the selected backup file.
function menu_cluster_restore()
{
    local storage backup_files choice selected_backup

    # Define the path to cluster backup storage
    storage="$STORAGE_COLD/cluster"

    # Find all available backup files with their sizes safely
    backup_files=()
    while IFS= read -r line; do
        filesize_bytes="${line##* }"                           # Extract the last field (file size)
        filename="${line:0:${#line} - ${#filesize_bytes} - 1}" # Remove the file size from the end
        formatted_size=$(format_filesize "$filesize_bytes")    # Convert size to readable format
        backup_files+=("${filename} ${formatted_size}")        # Store filename with formatted size
    done < <(find "$storage" -type f -name "*.tar.xz" -printf '%P %s\n' | sort)

    # Check if no backup files are available
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        log "DEBUG" "No backup files found in $storage."
        show_warning_message "No backup files found in $storage."
        return 1
    fi

    # Prepare options for the menu
    local menu_options=("back" "Return to cluster Menu") # Add a back option first
    for i in "${!backup_files[@]}"; do
        menu_options+=("$i" "${backup_files[$i]}") # Append each backup file as a menu option
    done

    # Display the menu and capture the user's choice
    choice=$(whiptail --title "Kafka Backup Offline" \
        --cancel-button "Back" \
        --menu "Cluster > Restore > Choose a backup file to restore:" 40 140 32 \
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
    cluster_restore "$selected_backup"
    if [[ $? -eq 0 ]]; then
        show_success_message "Cluster restoration completed successfully!\nThe cluster has been restored to the selected backup state."
    else
        show_failure_message "Cluster restoration failed!\n\nExit the tool and review the logs."
    fi
}

# Displays the Components menu.
function menu_components() {
    while true; do
        # Display Whiptail menu for choosing a certificate-related action
        choice=$(whiptail --title "Kafka Backup Offline" \
            --cancel-button "Back" \
            --menu "Components > Choose an action:" 18 60 8 \
            "1" "Return to Main Menu" \
            "2" "Apply Default ACLs" \
            "3" "Regenerate Certificates" \
            "4" "Regenerate Configs" \
            "5" "Regenerate Credentials" \
            "6" "Containers Kafka" \
            3>&1 1>&2 2>&3)

        # Capture the exit status of the Whiptail menu
        local exit_status=$?

        # Exit the function if ESC or cancel is pressed
        if [[ $exit_status -eq 1 || $exit_status -eq 255 ]]; then
            return 0
        fi

        # Handle user choices
        case "$choice" in
            1) return 0 ;;
            2) acls_apply
               if [[ $? -eq 0 ]]; then
                    show_success_message "ACLs were applied successfully!"
               else
                    show_failure_message "Failed to apply ACLs!\n\nExit the tool and review the logs."
               fi
               ;;
            3) certificates_generate
               if [[ $? -eq 0 ]]; then
                    show_success_message "Certificates were generated successfully!"
               else
                    show_failure_message "Failed to generate certificates!\n\nExit the tool and review the logs."
               fi
               ;;
            4) configs_generate
               if [[ $? -eq 0 ]]; then
                    show_success_message "Configuration was generated successfully!"
               else
                    show_failure_message "Failed to generate configuration!\n\nExit the tool and review the logs."
               fi
               ;;
            5) credentials_generate
               if [[ $? -eq 0 ]]; then
                    show_success_message "Credentials was generated successfully!"
               else
                    show_failure_message "Failed to generate credentials!\n\nExit the tool and review the logs."
               fi
               ;;
            6) menu_containers_kafka ;;
            7) menu_containers_balancers ;;
        esac
    done
}

# Displays the Containers menu using Whiptail for managing Kafka containers.
# Provides options to run, start, stop, restart, or remove containers.
# Returns to the main menu when "Back" is selected or ESC/cancel is pressed.
function menu_containers_kafka() {
    while true; do
        choice=$(whiptail --title "Kafka Backup Offline" \
            --menu "Components > Containers Kafka > Choose an action" 18 60 8 \
            "1" "Return to Components Menu" \
            "2" "Install" \
            "3" "Start" \
            "4" "Stop" \
            "5" "Restart" \
            "6" "Uninstall" \
            3>&1 1>&2 2>&3)

        # Capture the exit status of whiptail
        local exit_status=$?

        # Exit on ESC or cancel
        if [[ $exit_status -eq 1 || $exit_status -eq 255 ]]; then
            return 0
        fi

        case "$choice" in
            1)
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

# Displays the Containers menu using Whiptail for managing Kafka containers.
# Provides options to run, start, stop, restart, or remove containers.
# Returns to the main menu when "Back" is selected or ESC/cancel is pressed.
function menu_containers_balancers() {
    while true; do
        choice=$(whiptail --title "Kafka Backup Offline" \
            --menu "Components > Containers Balancers > Choose an action" 18 60 8 \
            "1" "Return to Components Menu" \
            "2" "Install" \
            "3" "Start" \
            "4" "Stop" \
            "5" "Restart" \
            "6" "Uninstall" \
            3>&1 1>&2 2>&3)

        # Capture the exit status of whiptail
        local exit_status=$?

        # Exit on ESC or cancel
        if [[ $exit_status -eq 1 || $exit_status -eq 255 ]]; then
            return 0
        fi

        case "$choice" in
            1)
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

# Displays the GUI menu.
function menu_gui() {
    while true; do
        choice=$(whiptail --title "Kafka Backup Offline" \
            --menu "GUI > Choose an action" 18 60 8 \
            "1" "Return to Main Menu" \
            "2" "Portainer-CE" \
            "3" "KPOW-CE" \
            3>&1 1>&2 2>&3)

        # Capture the exit status of whiptail
        local exit_status=$?

        # Exit on ESC or cancel
        if [[ $exit_status -eq 1 || $exit_status -eq 255 ]]; then
            return 0
        fi

        case "$choice" in
            1) return 0 ;;
            2) menu_gui_portainer ;;
            3) menu_gui_kpow_ce ;;
        esac
    done
}

# Portainer GUI menu
function menu_gui_portainer() {
    while true; do
        choice=$(whiptail --title "Kafka Backup Offline" \
            --menu "GUI > Portainer-CE > Choose an action" 18 60 8 \
            "1" "Return to GUI Menu" \
            "2" "Install" \
            "3" "Start" \
            "4" "Stop" \
            "5" "Restart" \
            "6" "Uninstall" \
            3>&1 1>&2 2>&3)

        # Capture the exit status of whiptail
        local exit_status=$?

        # Exit on ESC or cancel
        if [[ $exit_status -eq 1 || $exit_status -eq 255 ]]; then
            return 0
        fi

        case "$choice" in
            1)
               return 0 ;;
            2)
               gui_portainer_install
               if [[ $? -eq 0 ]]; then
                    show_success_message "Portainer-CE was installed on all nodes!"
               else
                    show_failure_message "Failed to install Portainer-CE\n\nExit the tool and review the logs."
               fi
               ;;
            3)
               gui_portainer_start
               if [[ $? -eq 0 ]]; then
                    show_success_message "Portainer-CE was started on all nodes!"
               else
                    show_failure_message "Failed to start Portainer-CE\n\nExit the tool and review the logs."
               fi
               ;;
            4)
               gui_portainer_stop
               if [[ $? -eq 0 ]]; then
                    show_success_message "Portainer-CE was stopped on all nodes!"
               else
                    show_failure_message "Failed to stop Portainer-CE\n\nExit the tool and review the logs."
               fi
               ;;
            5)
               gui_portainer_restart
               if [[ $? -eq 0 ]]; then
                    show_success_message "Portainer-CE was restarted on all nodes!"
               else
                    show_failure_message "Failed to restart Portainer-CE\n\nExit the tool and review the logs."
               fi
               ;;
            6)
               gui_portainer_uninstall
               if [[ $? -eq 0 ]]; then
                    show_success_message "Portainer-CE was uninstalled on all nodes!"
               else
                    show_failure_message "Failed to uninstall Portainer-CE\n\nExit the tool and review the logs."
               fi
               ;;
        esac
    done
}

# KPOW-CE GUI menu
function menu_gui_kpow_ce() {
    while true; do
        choice=$(whiptail --title "Kafka Backup Offline" \
            --menu "GUI > KPOW-CE > Choose an action" 18 60 8 \
            "1" "Return to GUI Menu" \
            "2" "Install" \
            "3" "Start" \
            "4" "Stop" \
            "5" "Restart" \
            "6" "Uninstall" \
            3>&1 1>&2 2>&3)

        # Capture the exit status of whiptail
        local exit_status=$?

        # Exit on ESC or cancel
        if [[ $exit_status -eq 1 || $exit_status -eq 255 ]]; then
            return 0
        fi

        case "$choice" in
            1)
               return 0 ;;
            2)
               gui_kpow_ce_install
               if [[ $? -eq 0 ]]; then
                    show_success_message "KPOW-CE was installed on all nodes!"
               else
                    show_failure_message "Failed to install KPOW-CE\n\nExit the tool and review the logs."
               fi
               ;;
            3)
               gui_kpow_ce_start
               if [[ $? -eq 0 ]]; then
                    show_success_message "KPOW-CE was started on all nodes!"
               else
                    show_failure_message "Failed to start KPOW-CE\n\nExit the tool and review the logs."
               fi
               ;;
            4)
               gui_kpow_ce_stop
               if [[ $? -eq 0 ]]; then
                    show_success_message "KPOW-CE was stopped on all nodes!"
               else
                    show_failure_message "Failed to stop KPOW-CE\n\nExit the tool and review the logs."
               fi
               ;;
            5)
               gui_kpow_ce_restart
               if [[ $? -eq 0 ]]; then
                    show_success_message "KPOW-CE was restarted on all nodes!"
               else
                    show_failure_message "Failed to restart KPOW-CE\n\nExit the tool and review the logs."
               fi
               ;;
            6)
               gui_kpow_ce_uninstall
               if [[ $? -eq 0 ]]; then
                    show_success_message "KPOW-CE was uninstalled on all nodes!"
               else
                    show_failure_message "Failed to uninstall KPOW-CE\n\nExit the tool and review the logs."
               fi
               ;;
        esac
    done
}

######################################################################
# Section 7: CLI UX – Disclaimer, Help, Dispatcher
######################################################################

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
    log "INFO" "  All internal functions can be executed directly by passing their name as a parameter."
    log "INFO" ""
    log "INFO" "-------------------------------------------------------------------------------------------------------------------"
    log "INFO" "  cluster_backup        Perform a full offline Kafka cluster backup:"
    log "INFO" ""
    log "INFO" "                          1. Validate free storage space on the cold backup location."
    log "INFO" "                          2. Stop all Kafka containers on all nodes (offline mode)."
    log "INFO" "                          3. Create per-node archives of /data/cluster into a temporary folder."
    log "INFO" "                          4. Transfer per-node archives to node-00."
    log "INFO" "                          5. Pack a unified cluster snapshot (tar.xz) in cold storage."
    log "INFO" "                          6. Start all Kafka containers back online."
    log "INFO" "                          7. Validate free storage space after backup completion."
    log "INFO" ""
    log "INFO" "  cluster_reboot        Restart Kafka containers across all nodes."
    log "INFO" ""
    log "INFO" "  cluster_reinstall     Perform full cluster wipe & reinstall (dangerous)."
    log "INFO" ""
    log "INFO" "  help                  Display this help message."
    log "INFO" ""
    log "INFO" "==================================================================================================================="
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

######################################################################
# Section 8: Main Execution
######################################################################

handle_directory
handle_configuration
handle_pid_file
handle_main "$@"
