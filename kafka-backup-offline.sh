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

    # Load SSH-related configuration variables used for connecting to remote nodes.
    parse_ini_file "$config_file" "ssh"
    SSH_KEY_PRI="${ini_data[ssh.SSH_KEY_PRI]}" # SSH private key for connecting to nodes
    SSH_KEY_PUB="${ini_data[ssh.SSH_KEY_PUB]}" # SSH public key for sharing with nodes
    SSH_USER="${ini_data[ssh.SSH_USER]}"       # SSH user for accessing nodes

    # Load storage configuration variables for temporary and cold backup storage paths.
    parse_ini_file "$config_file" "storage"
    STORAGE_TEMP="${ini_data[storage.STORAGE_TEMP]}"                         # Temporary storage directory on the GUI server
    STORAGE_COLD="${ini_data[storage.STORAGE_COLD]}"                         # Permanent cold storage directory for backups
    STORAGE_RETENTION_POLICY="${ini_data[storage.STORAGE_RETENTION_POLICY]}" # Retention period for backup files (in days)
    STORAGE_WARN_LOW="${ini_data[storage.STORAGE_WARN_LOW]}"                 # Percentage of free space, below which we will show a warning

    # Load Kafka cluster-specific configuration variables such as image, cluster ID, and node paths.
    parse_ini_file "$config_file" "cluster"
    IMAGE="${ini_data[cluster.IMAGE]}"             # Kafka Docker image
    CLUSTER_ID="${ini_data[cluster.CLUSTER_ID]}"   # Kafka cluster identifier
    NODE_CONFIG="${ini_data[cluster.NODE_CONFIG]}" # Path to node config directory on nodes
    NODE_DATA="${ini_data[cluster.NODE_DATA]}"     # Path to node data directory on nodes
    NODE_META="${ini_data[cluster.NODE_META]}"     # Path to node meta directory on nodes
    NODE_LOGS="${ini_data[cluster.NODE_LOGS]}"     # Path to node logs directory on nodes
    NODE_CERT="${ini_data[cluster.NODE_CERT]}"     # Path to node cert directory on nodes
    NODE_CRED="${ini_data[cluster.NODE_CRED]}"     # Path to node cred directory on nodes
    NODE_TEMP="${ini_data[cluster.NODE_TEMP]}"     # Path to node temp directory on nodes

    # Load nodes configuration from the .ini file and store them in an associative array for easy lookup.
    parse_ini_file "$config_file" "nodes"
    declare -gA nodes
    local role
    for key in "${!ini_data[@]}"; do
        if [[ $key == nodes.* ]]; then
            role="${key#nodes.}"
            nodes["$role"]="${ini_data[$key]}" # Map the role to its respective IP address
        fi
    done

    # Load startup and shutdown orders for nodes to ensure proper Kafka cluster management.
    parse_ini_file "$config_file" "order"
    IFS=',' read -r -a order_startup <<<"${ini_data[order.startup]}"   # Load startup order into an array
    IFS=',' read -r -a order_shutdown <<<"${ini_data[order.shutdown]}" # Load shutdown order into an array
    log "INFO" "Configuration loaded from '$config_file'"
}

# Help function to display available options
function disclaimer()
{
    echo "==================================================================================================================="
    echo "                                    Kafka-Backup-Offline Utility - version 1.0.0                                   "
    echo "==================================================================================================================="
    echo
    echo "  © 2024 Rosenberg Arkady @ Dynamic Studio                      Contact: +972546373566 / intelligent002@gmail.com  "
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

function clear_temp_central()
{
    log "DEBUG" "Clear temp of central - started"

    (rm -rf "$STORAGE_TEMP" && mkdir -p "$STORAGE_TEMP") || {
        log "ERROR" "Clear temp of central - failed"
        return 1
    }

    log "DEBUG" "Clear temp of central - OK"
    return 0
}

function clear_temp_node()
{
    local role ip

    role=$1
    ip=${nodes[$role]}

    log "DEBUG" "Clear temp of $role at $ip - started"

    ssh -i "$SSH_KEY_PRI" "$SSH_USER"@"$ip" "rm -rf $NODE_TEMP && mkdir -p $NODE_TEMP " || {
        log "ERROR" "Clear temp of $role at $ip - failed"
        return 1
    }

    log "DEBUG" "Clear temp of $role at $ip - OK"
    return 0
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

# ===== Backups Rotation =====
# Rotates backups in the "rotated" directories, keeping only files younger than STORAGE_RETENTION_POLICY
function rotate_backups()
{
    log "DEBUG" "Rotating backups, retention policy: $STORAGE_RETENTION_POLICY days - started"

    # Find and remove backups older than $days_to_keep days
    find "$STORAGE_COLD/config/rotated/" -type f -mtime +"$STORAGE_RETENTION_POLICY" -name "*.tar.gz" -exec rm -f {} \;
    find "$STORAGE_COLD/data/rotated/" -type f -mtime +"$STORAGE_RETENTION_POLICY" -name "*.tar.gz" -exec rm -f {} \;

    log "DEBUG" "Rotating backups, retention policy: $STORAGE_RETENTION_POLICY days - OK"
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
        log "ERROR" "Test - Ensure Kafka Containers on all nodes are stopped - failed"
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
# Starts all Kafka containers in the pre-defined order
function containers_run()
{
    local role
    declare -a failed_roles # Array to track roles that failed

    log "INFO" "Routine - Kafka Containers Run on all nodes - started"

    # Launch container_run for each role one by one according to best practice
    for role in "${order_startup[@]}"; do
        container_run "$role" || {
            failed_roles+=("$role")
        }
    done

    # Final summary log
    if ((${#failed_roles[@]} > 0)); then
        log "ERROR" "Failed roles: ${failed_roles[*]}."
        log "ERROR" "Routine - Kafka Containers Run on all nodes - failed"
        return 1
    fi

    log "INFO" "Routine - Kafka Containers Run on all nodes - OK"
    return 0
}

# ===== Kafka Container Run =====
# Starts a Kafka container on a specific node
# Parameters:
#   $1 - The role of the node (e.g., kafka-controller-1)
function container_run()
{
    local role ip port_jmx port_kafka

    role=$1
    ip=${nodes[$role]}
    port_jmx=9999

    case "$role" in
        kafka-controller-*)
            port_kafka=9093
            ;;
        kafka-broker-*)
            port_kafka=9092
            ;;
        *)
            log "DEBUG" "Unknown role: $role"
            return 1
            ;;
    esac

    log "DEBUG" "Container run $role at $ip - started"

    ssh -i "$SSH_KEY_PRI" "$SSH_USER"@"$ip" "docker run -d --name=$role -h $role --restart=always \
        -p $port_kafka:$port_kafka \
        -p $port_jmx:$port_jmx \
        -e KAFKA_HEAP_OPTS='-Xmx2G -Xms2G' \
        -e KAFKA_JMX_OPTS='-Dcom.sun.management.jmxremote \
        -Dcom.sun.management.jmxremote.port=$port_jmx \
        -Dcom.sun.management.jmxremote.rmi.port=$port_jmx \
        -Dcom.sun.management.jmxremote.authenticate=false \
        -Dcom.sun.management.jmxremote.ssl=false \
        -Djava.rmi.server.hostname=$ip' \
        -v $NODE_CONFIG:/mnt/shared/config \
        -v $NODE_DATA:/var/lib/kafka/data \
        -v $NODE_META:/var/lib/kafka/meta \
        -v $NODE_CERT:/etc/kafka/secrets \
        -v $NODE_CRED:/etc/kafka/credentials \
        -v $NODE_LOGS:/opt/kafka/logs \
        $IMAGE /opt/kafka/bin/kafka-server-start.sh /mnt/shared/config/kraft.properties" || {
        log "ERROR" "Container run $role at $ip - failed"
        return 1
    }

    log "DEBUG" "Container run $role at $ip - OK"
    return 0
}

# ===== Kafka Containers Start =====
# Starts all Kafka containers in the defined startup order
function containers_start()
{
    local role
    declare -a failed_roles # Array to track roles that failed

    log "INFO" "Routine - Kafka Containers Start on all nodes - started"

    # Launch container_start for each role one by one according to best practice
    for role in "${order_startup[@]}"; do
        container_start "$role" || {
            failed_roles+=("$role")
        }
    done

    # Final summary log
    if ((${#failed_roles[@]} > 0)); then
        log "ERROR" "Failed roles: ${failed_roles[*]}."
        log "ERROR" "Routine - Kafka Containers Start on all nodes - failed"
        return 1
    fi

    log "INFO" "Routine - Kafka Containers Start on all nodes - OK"
    return 0
}

# ===== Kafka Container Start =====
# Starts a specific Kafka container on a node
# Parameters:
#   $1 - The role of the node (e.g., kafka-controller-1)
function container_start()
{
    local role ip

    role=$1
    ip=${nodes[$role]}

    log "DEBUG" "Container start $role at $ip - started"

    ssh -i "$SSH_KEY_PRI" "$SSH_USER"@"$ip" "docker start $role" || {
        log "ERROR" "Container start $role at $ip - failed"
        return 1
    }

    log "DEBUG" "Container start $role at $ip - OK"
    return 0
}

# ===== Kafka Containers Stop =====
# Stops all Kafka containers in the defined shutdown order
function containers_stop()
{
    local role
    declare -a failed_roles # Array to track roles that failed

    log "INFO" "Routine - Kafka Containers Stop on all nodes - started"

    # Launch container_stop for each role one by one according to best practice
    for role in "${order_shutdown[@]}"; do
        container_stop "$role" || {
            failed_roles+=("$role")
        }
    done

    # Final summary log
    if ((${#failed_roles[@]} > 0)); then
        log "ERROR" "Failed roles: ${failed_roles[*]}."
        log "ERROR" "Routine - Kafka Containers Stop on all nodes - failed"
        return 1
    fi

    log "INFO" "Routine - Kafka Containers Stop on all nodes - OK"
    return 0
}

# Stops a specific Kafka container on a node
# Parameters:
#   $1 - The role of the node (e.g., kafka-controller-1)
function container_stop()
{
    local role ip

    role=$1
    ip=${nodes[$role]}

    log "DEBUG" "Container stop $role at $ip - started"

    ssh -i "$SSH_KEY_PRI" "$SSH_USER"@"$ip" "docker stop $role" || {
        log "DEBUG" "Container stop $role at $ip - stop failed"
        return 1
    }

    log "DEBUG" "Container stop $role at $ip - OK"
    return 0
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
    local role
    declare -a failed_roles # Array to track roles that failed

    log "INFO" "Routine - Kafka Containers Remove on all nodes - started"

    # Launch container_remove for each role one by one according to best practice
    for role in "${order_shutdown[@]}"; do
        container_remove "$role" || {
            failed_roles+=("$role")
        }
    done

    # Final summary log
    if ((${#failed_roles[@]} > 0)); then
        log "ERROR" "Failed roles: ${failed_roles[*]}."
        log "ERROR" "Routine - Kafka Containers Remove on all nodes - failed"
        return 1
    fi

    log "INFO" "Routine - Kafka Containers Remove on all nodes - OK"
    return 0
}

# Removes a specific Kafka container on a node
# Parameters:
#   $1 - The role of the node (e.g., kafka-controller-1)
function container_remove()
{
    local role ip

    role=$1
    ip=${nodes[$role]}

    log "DEBUG" "Container remove $role at $ip - started"

    if ! ssh -i "$SSH_KEY_PRI" "$SSH_USER"@"$ip" "docker rm -f $role"; then
        log "ERROR" "Container remove $role at $ip - failed"
        return 1
    fi

    log "DEBUG" "Container remove $role at $ip - OK"
    return 0
}

# ===== Kafka Cluster Wide Data Delete =====
# Deletes all data on all nodes
function cluster_wide_data_delete()
{
    local role
    declare -A pids         # Associative array for background task process IDs
    declare -a failed_roles # Array to track roles that failed

    log "INFO" "Routine - Kafka Cluster Data Delete on all nodes - started"

    # Launch cluster_node_data_delete for each role in the background
    for role in "${order_shutdown[@]}"; do
        cluster_node_data_delete "$role" &
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
        log "ERROR" "Routine - Kafka Cluster Data Delete on all nodes - failed"
        return 1
    fi

    log "INFO" "Routine - Kafka Cluster Data Delete on all nodes - OK"
    return 0
}

# ===== Kafka Cluster Node Data Delete =====
# Deletes data on a specific node
# Parameters:
#   $1 - The role of the node (e.g., kafka-controller-1)
function cluster_node_data_delete()
{
    local role ip

    role=$1
    ip=${nodes[$role]}

    log "DEBUG" "Kafka Cluster Data Delete of $role at $ip - started"

    ssh -i "$SSH_KEY_PRI" "$SSH_USER"@"$ip" "\
         rm -rf $NODE_DATA && \
         mkdir -p $NODE_DATA && \
         chown -R 1000:1000 $NODE_DATA && \
         chmod -R 0750 $NODE_DATA" || {
        log "ERROR" "Kafka Cluster Data Delete of $role at $ip - failed"
        return 1
    }

    log "DEBUG" "Kafka Cluster Data Delete of $role at $ip - OK"
}

# ===== Kafka Cluster Wide Data Format =====
# Formats data on all nodes
function cluster_wide_data_format()
{
    local role
    declare -A pids         # Associative array for background task process IDs
    declare -a failed_roles # Array to track roles that failed

    log "INFO" "Routine - Kafka Cluster Data Format on all nodes - started"

    # Ensure all containers are stopped
    ensure_containers_stopped || {
        log "DEBUG" "Routine aborted due to running containers."
        return 1
    }

    # Launch cluster_node_data_delete && cluster_node_data_format for each role in the background
    for role in "${order_shutdown[@]}"; do
        cluster_node_data_delete "$role" && cluster_node_data_format "$role" &
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
        log "ERROR" "Routine - Kafka Cluster Data Format on all nodes - failed"
        return 1
    fi

    log "INFO" "Routine - Kafka Cluster Data Format on all nodes - OK"
    return 0
}

# ===== Kafka Cluster Node Data Format =====
# Formats data on a specific node
# Parameters:
#   $1 - The role of the node (e.g., kafka-controller-1)
function cluster_node_data_format()
{
    local role ip

    role=$1
    ip=${nodes[$role]}

    log "DEBUG" "Format Kafka node data of $role at $ip - started"

    ssh -i "$SSH_KEY_PRI" "$SSH_USER"@"$ip" "\
         docker run --rm \
            -v $NODE_CONFIG:/mnt/shared/config \
            -v $NODE_DATA:/var/lib/kafka/data \
            -v $NODE_META:/var/lib/kafka/meta \
            -v $NODE_LOGS:/opt/kafka/logs \
            -v $NODE_CRED:/etc/kafka/credentials \
            -v $NODE_CERT:/etc/kafka/secrets \
            $IMAGE \
            /opt/kafka/bin/kafka-storage.sh format -t $CLUSTER_ID -c /mnt/shared/config/kraft.properties" || {
        log "ERROR" "Format Kafka node data of $role at $ip - failed"
        return 1
    }

    log "DEBUG" "Format Kafka node data of $role at $ip - OK"
}

# ===== Kafka Cluster Wide Data Backup =====
# Performs a full data backup of the Kafka cluster across all nodes.
function cluster_wide_data_backup()
{
    local role ip backup_date backup_path backup_archive
    declare -A pids         # Associative array to track background task process IDs
    declare -a failed_roles # Array to track failed roles

    log "INFO" "Routine - Kafka Cluster Data Backup - started"

    # Rotating backups according to retention policy
    rotate_backups

    backup_date=$(date '+%Y-%m-%d---%H-%M-%S')
    backup_path="$STORAGE_COLD/data/rotated/$(date '+%Y/%m/%d')"
    backup_archive="$backup_path/$backup_date---data.tar.gz"

    # Ensure all containers are stopped
    ensure_containers_stopped || {
        log "DEBUG" "Routine aborted due to running containers."
        return 1
    }

    # Archive all nodes data on the nodes - simultaneously
    log "DEBUG" "Archiving Kafka data locally on all nodes - started"
    for role in "${order_startup[@]}"; do
        ip=${nodes[$role]}
        clear_temp_node "$role" &&
            log "DEBUG" "Archiving Kafka Cluster Data locally as $role.tar.gz on $role at $ip - started" &&
            ssh -i "$SSH_KEY_PRI" "$SSH_USER"@"$ip" "tar -czf $NODE_TEMP/$role.tar.gz -C $NODE_DATA ./" &&
            log "DEBUG" "Archiving Kafka Cluster Data locally as $role.tar.gz on $role at $ip - OK" &&
            log "DEBUG" "Collecting Kafka Cluster Data archive as $role.tar.gz from $role at $ip - started" &&
            rsync -aqz -e "ssh -i $SSH_KEY_PRI" "$SSH_USER@$ip:$NODE_TEMP/$role.tar.gz" "$STORAGE_TEMP/$role.tar.gz" &&
            log "DEBUG" "Collecting Kafka Cluster Data archive as $role.tar.gz from $role at $ip - OK" &&
            clear_temp_node "$role" &
        pids["$role"]=$! # Capture the process ID of the background job
    done

    # Wait for archiving tasks to complete
    failed_roles=()
    for role in "${!pids[@]}"; do
        if ! wait "${pids[$role]}"; then
            failed_roles+=("$role")
        fi
    done

    # Final summary log
    if ((${#failed_roles[@]} > 0)); then
        log "ERROR" "Failed roles: ${failed_roles[*]}."
        log "ERROR" "Routine - Kafka Cluster Data Backup - failed"
        return 1
    fi

    # Create the cluster zip of zips in cold storage
    log "DEBUG" "Creating a cluster-wide backup archive (zip of zips) - started"
    mkdir -p "$backup_path"
    (cd "$STORAGE_TEMP" && tar -czf "$backup_archive" ./*.tar.gz)
    log "DEBUG" "Creating a cluster-wide backup archive (zip of zips) - OK"

    ensure_free_space "$STORAGE_TEMP"
    ensure_free_space "$STORAGE_COLD"
    clear_temp_central

    log "INFO" "Kafka Cluster Data Archive stored at: $backup_archive"
    log "INFO" "Routine - Kafka Cluster Data Backup - OK"
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
    mapfile -t backup_files < <(find "$storage_data" -type f -name "*.tar.gz" -exec ls -lh {} \; | awk '{print $9, $5}' | sort)
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
    local cluster_archive role ip
    declare -A pids         # Associative array for background task process IDs
    declare -a failed_roles # Array to track roles that failed

    cluster_archive=$1

    log "INFO" "Routine - Kafka Cluster Data Restore - started"

    # Ensure all containers are stopped
    ensure_containers_stopped || {
        log "DEBUG" "Routine aborted due to running containers."
        return 1
    }

    # Extract the cluster zip on the central server
    log "DEBUG" "Extract Kafka Cluster Data (zip of zips) to $STORAGE_TEMP - started"
    mkdir -p "$STORAGE_TEMP"
    tar -xzf "$cluster_archive" -C "$STORAGE_TEMP" || {
        log "ERROR" "Extract Kafka Cluster Data (zip of zips) to $STORAGE_TEMP - failed"
        return 1
    }
    log "DEBUG" "Extract Kafka Cluster Data (zip of zips) to $STORAGE_TEMP - OK"

    # Stop containers on all nodes (optional, uncomment if needed)
    # containers_stop

    # Transfer node archives to respective nodes - simultaneously
    log "DEBUG" "Restoring Kafka Cluster Nodes Data - started"
    for role in "${order_startup[@]}"; do
        ip=${nodes[$role]}
        clear_temp_node "$role" &&
            log "DEBUG" "Distributing Kafka Cluster Data archive $role.tar.gz to $role at $ip - started" &&
            rsync -aqz --partial "$STORAGE_TEMP/$role.tar.gz" "$SSH_USER"@"$ip":"$NODE_TEMP"/ &&
            log "DEBUG" "Distributing Kafka Cluster Data archive $role.tar.gz to $role at $ip - OK" &&
            cluster_node_data_delete "$role" &&
            log "DEBUG" "Extracting Kafka Cluster Data from archive $role.tar.gz on $role at $ip - started" &&
            ssh -i "$SSH_KEY_PRI" "$SSH_USER"@"$ip" "tar -xzf $NODE_TEMP/$role.tar.gz -C $NODE_DATA" &&
            log "DEBUG" "Extracting Kafka Cluster Data from archive $role.tar.gz on $role at $ip - OK" &&
            clear_temp_node "$role" &
        pids["$role"]=$! # Capture the process ID of the background job
    done

    # Wait for transfer tasks to complete
    failed_roles=()
    for role in "${!pids[@]}"; do
        if ! wait "${pids[$role]}"; then
            failed_roles+=("$role")
        fi
    done

    # Log failures for transfers and abort if any failed
    if ((${#failed_roles[@]} > 0)); then
        log "ERROR" "Failed for roles: ${failed_roles[*]}."
        log "ERROR" "Routine - Kafka Cluster Data Restore - failed"
        return 1
    fi
    log "DEBUG" "Restoring Kafka Cluster Nodes Data - OK"

    clear_temp_central

    log "INFO" "Routine - Kafka Cluster Data Restore - OK"
    return 0
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
    local backup_date backup_path backup_archive backup_temp ip role
    declare -A pids         # Associative array to track background task process IDs
    declare -a failed_roles # Array to track failed roles

    log "INFO" "Routine - Kafka Cluster Config Backup - started"

    # Rotating backups according to retention policy
    rotate_backups

    # Local variables
    backup_date=$(date '+%Y-%m-%d---%H-%M-%S')
    backup_path="$STORAGE_COLD/config/rotated/$(date '+%Y/%m/%d')"
    backup_archive="$backup_path/$backup_date---config.tar.gz"
    backup_temp="$STORAGE_TEMP/config"

    # Ensure central temp directory exists
    mkdir -p "$backup_temp"

    # Collect configuration files from nodes
    log "DEBUG" "Collecting Kafka configuration files from all nodes - started"
    for role in "${order_startup[@]}"; do
        ip=${nodes[$role]}
        log "DEBUG" "Collecting config of $role at $ip - started" &&
            rsync -aqz -e "ssh -i $SSH_KEY_PRI" "$SSH_USER"@"$ip":"$NODE_CONFIG/" "$backup_temp/$role/" &&
            log "DEBUG" "Collecting config of $role at $ip - OK" &
        pids["$role"]=$! # Capture the process ID of the background job
    done

    # Wait for archiving tasks to complete
    failed_roles=()
    for role in "${!pids[@]}"; do
        if ! wait "${pids[$role]}"; then
            failed_roles+=("$role")
        fi
    done

    # Final summary log
    if ((${#failed_roles[@]} > 0)); then
        log "ERROR" "Failed roles: ${failed_roles[*]}."
        log "ERROR" "Routine - Kafka Cluster Config Backup - failed"
        return 1
    fi

    # Compress the collected configurations
    log "DEBUG" "Archiving collected configurations - started"
    mkdir -p "$backup_path"
    (cd "$backup_temp" && tar -czf "$backup_archive" .)
    log "DEBUG" "Archiving collected configurations - OK"

    clear_temp_central

    log "INFO" "Kafka Cluster Config Backup stored at: $backup_archive"
    log "INFO" "Routine - Kafka Cluster Config Backup - OK"
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
    mapfile -t config_backup_files < <(find "$storage_config" -type f -name "*.tar.gz" -exec ls -lh {} \; | awk '{print $9, $5}' | sort)
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
    local config_archive ip role
    declare -A pids         # Associative array for background task process IDs
    declare -a failed_roles # Array to track roles that failed

    config_archive=$1

    log "INFO" "Routine - Kafka Cluster Config Restore - started"

    # Extract the archive to the central temp folder
    log "DEBUG" "Extracting configuration archive to $STORAGE_TEMP - started"
    mkdir -p "$STORAGE_TEMP"
    tar -xzf "$config_archive" -C "$STORAGE_TEMP" || {
        log "DEBUG" "Failed to extract configuration archive: $config_archive"
        return 1
    }

    # Distribute configuration files to nodes
    log "DEBUG" "Distributing configuration files to all nodes - started"
    for role in "${order_startup[@]}"; do
        ip=${nodes[$role]}
        log "DEBUG" "Distributing configuration file for $role at $ip - started" &&
            rsync -aqz "$STORAGE_TEMP/$role/" "$SSH_USER"@"$ip":"$NODE_CONFIG/" &&
            log "DEBUG" "Distributing configuration file for $role at $ip - OK" &
        pids["$role"]=$! # Capture the process ID of the background job
    done

    # Wait for transfer tasks to complete
    failed_roles=()
    for role in "${!pids[@]}"; do
        if ! wait "${pids[$role]}"; then
            failed_roles+=("$role")
        fi
    done

    # Log failures for transfers and abort if any failed
    if ((${#failed_roles[@]} > 0)); then
        log "ERROR" "Failed for roles: ${failed_roles[*]}."
        log "ERROR" "Routine - Kafka Cluster Config Restore - failed"
        return 1
    fi

    log "DEBUG" "Distributing configuration files to all nodes - OK"

    clear_temp_central

    log "INFO" "Routine - Kafka Cluster Config Restore - OK"
}

# ===== Menu Function =====
function menu()
{
    local choice

    while true; do
        echo "Available routines:"
        echo "0) Exit"
        echo "1) Setup SSH Keys"
        echo "2) Containers Run"
        echo "3) Containers Start"
        echo "4) Containers Stop"
        echo "5) Containers Restart"
        echo "6) Containers Remove"
        echo "7) Data Backup"
        echo "8) Data Format"
        echo "9) Data Restore"
        echo "10) Config Backup"
        echo "11) Config Restore"
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
            7) cluster_wide_data_backup ;;
            8) cluster_wide_data_format ;;
            9) cluster_wide_data_restore_menu ;;
            10) cluster_wide_config_backup ;;
            11) cluster_wide_config_restore_menu ;;
            *) echo "Invalid choice. Please try again." ;;
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
    menu
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
