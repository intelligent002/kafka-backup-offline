# **Kafka-Backup-Offline Utility**

---

## **Project Overview**

The `Kafka-Backup-Offline Utility` is a robust Bash-based tool designed to manage Kafka clusters in **development and testing environments**. Its primary focus is to enable **safe and reliable cluster backups and restores** while following proper startup and shutdown procedures to maintain data integrity.

This utility is **not suitable for production use**, as it requires taking the Kafka cluster offline during backup and restore operations. It also includes additional functionalities, such as SSH key setup, container lifecycle management, and automated backup rotation.

---

## **Cluster Topology**

Kafka demands significant resources in terms of **disk storage**, **memory**, and **CPU**. The recommended deployment approach is to use **virtual machines (VMs)** with guaranteed hardware resource allocation for each Kafka node.

### **VM Setup**
- **Resource Recommendations**: Ensure the VMs are provisioned with sufficient CPU, RAM, and disk space to meet Kafka's workload demands.
- **Storage Configuration**:
  - Avoid **RAID-5** due to its high write latency, which can degrade Kafka performance.
  - Prefer configurations such as:
    - **Single SSD** for maximum performance.
    - **RAID-0** for performance without redundancy.
    - **RAID-10** for a balance of performance and redundancy.
  - Use **eagerzeroedthick** provisioning for data drives to enhance I/O performance by pre-allocating disk space and avoiding fragmentation during write operations.

### **Cluster Roles**
The development/testing cluster consists of the following roles:

1. **Controllers**:
   - Responsible for managing cluster metadata, leader elections, and topic configurations.
   - Includes three controllers:
     - `kafka-controller-1`
     - `kafka-controller-2`
     - `kafka-controller-3`

2. **Brokers**:
   - Handle data storage, replication, and client requests.
   - Includes three brokers:
     - `kafka-broker-1`
     - `kafka-broker-2`
     - `kafka-broker-3`

### **Deployment**
Each VM hosts a **Docker container** to streamline Kafka node management, including starting, stopping, backups, restores, and version updates. The choice of Kafka distribution—whether Apache, Confluent, Bitnami, or others—is less critical, as all provide easily deployable Docker images.

---

## **Cluster Procedures**

### **Cluster Startup Procedure**
To ensure proper initialization and data consistency, the following **controlled startup sequence** is followed:

1. **Start Controllers**:
   - Start controllers one by one, beginning with the **first controller** and proceeding to the **last**.

2. **Start Brokers**:
   - Once all controllers are operational, start brokers one by one, beginning with the **first broker** and proceeding to the **last**.

---

### **Cluster Shutdown Procedure**
To safely shut down the cluster and maintain data consistency, the following **controlled shutdown sequence** is followed:

1. **Stop Brokers**:
   - Stop brokers one by one, starting with the **last broker** and proceeding to the **first**.

2. **Stop Controllers**:
   - After all brokers are stopped, stop controllers one by one, starting with the **last controller** and proceeding to the **first**.

---

## **Backup Routine**

The utility provides a reliable method for performing **full cluster backups**. Below is an overview of the backup routine:

### **Key Features**
1. **Backup Rotation**:
   - Automatically removes old backups based on a retention policy (default: 30 days).
   - Archives are stored in `STORAGE_COLD` (e.g., `/backup/cold`) and organized by timestamp.

2. **Backup Workflow**:
   - **Shutdown Routine**:
     - Gracefully shuts down the cluster following the controlled shutdown procedure (stop brokers first, then controllers).
   - **Cluster Configuration Backup**:
     - Pulls configuration files from all nodes to a temporary folder on the backup server.
     - Archives configuration files and moves them to cold storage.
     - Cleans up temporary folders to free up space.
   - **Cluster Data Backup**:
     - Archives data files locally on each node into temporary folders.
     - Transfers archived files from nodes to the backup server.
     - Consolidates individual node archives into a single "zip of zips" for the entire cluster and stores it in cold storage.
     - Cleans up temporary folders after the backup.
   - **Startup Routine**:
     - Restarts the cluster following the controlled startup procedure (start controllers first, then brokers).

---

## **How to Use**

### **Backup Command**
To perform a full cluster backup, use the following command:
```bash
./kafka_manager.sh cluster_backup
