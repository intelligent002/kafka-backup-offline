# **Kafka-Backup-Offline Utility**

---

## **Project Overview**

The `Kafka-Backup-Offline Utility` is a robust Bash-based tool designed to manage Kafka clusters in **development and
testing environments**. Its primary focus is to enable **safe and reliable cluster backups and restores** while
following proper startup and shutdown procedures to maintain data integrity.

This utility is **NOT SUITABLE FOR PRODUCTION USE**, as it requires taking the Kafka cluster offline during backup and
restore operations.

---

## **Cluster Topology**

Kafka demands significant resources in terms of **Disk I/O, Memory & CPU**.

Deployment options are:

| **Aspect**                  | **Cloud-Managed Services**            | **Kubernetes**                             | **Bare Metal**                           | **Docker Compose**                    | **Virtual Machines**                   | **Docker in VMs**                           | **Docker in VM with<br>Kafka-Backup-Offline**              |
|-----------------------------|---------------------------------------|--------------------------------------------|------------------------------------------|---------------------------------------|----------------------------------------|---------------------------------------------|------------------------------------------------------------|
| **Rating**                  | ⭐⭐⭐⭐                                  | ⭐⭐⭐⭐                                       | ⭐⭐                                       | ⭐⭐                                    | ⭐⭐                                     | ⭐⭐⭐                                         | ⭐⭐⭐⭐                                                       |
| **Definition**              | Fully managed Kafka offerings.        | Orchestrates containerized Kafka clusters. | Direct deployment on physical servers.   | Runs Kafka in lightweight containers. | Kafka on virtualized servers.          | Runs Kafka in containers on VMs.            | Kafka in containers on VMs with offline backup utilities.  |
| **Performance**             | ⭐⭐⭐⭐<br>Optimized by provider.        | ⭐⭐⭐⭐<br>Depends on container resources.    | ⭐⭐⭐⭐⭐<br>Direct hardware access.         | ⭐<br>Suitable for small workloads.    | ⭐⭐⭐⭐<br>Limited by hypervisor.         | ⭐⭐⭐⭐<br>Limited by hypervisor.              | ⭐⭐⭐⭐<br>Limited by hypervisor + downtime for backups.      |
| **Performance Overhead**    | ⭐⭐⭐⭐<br>Optimized by provider.        | ⭐⭐⭐⭐<br>Moderate, resource allocation.     | ⭐⭐⭐⭐⭐<br>None, direct access.            | ⭐⭐<br>Low, single Docker engine.      | ⭐⭐⭐⭐<br>VM overhead.                   | ⭐⭐⭐⭐<br>VM + container overhead.            | ⭐⭐⭐⭐<br>VM + container overhead.                           |
| **Operational Overhead**    | ⭐⭐⭐⭐<br>Minimal, fully managed.       | ⭐⭐⭐⭐<br>Moderate, requires scripting.      | ⭐<br>High, manual operations.            | ⭐<br>High, manual interventions.      | ⭐⭐<br>Moderate, snapshot management.   | ⭐⭐<br>Moderate, manual processes.           | ⭐⭐⭐⭐<br>Low due to Kafka-Backup-Offline.                   |
| **Operational Confidence**  | ⭐⭐⭐⭐⭐<br>Developers worry-free.       | ⭐⭐⭐⭐<br>Stable with custom scripting.      | ⭐⭐<br>Highly dependent on manual effort. | ⭐⭐<br>Low for production setups.      | ⭐⭐⭐<br>Moderate with VM snapshots.     | ⭐⭐⭐<br>Good but requires experience.        | ⭐⭐⭐⭐⭐<br>Foolproof routines offer unparalleled confidence. |
| **Resource Isolation**      | ⭐⭐⭐⭐⭐<br>Strong, managed by provider. | ⭐⭐⭐⭐<br>Container-level isolation.         | ⭐⭐⭐⭐⭐<br>Strong, dedicated hardware.     | ⭐<br>No isolation.                    | ⭐⭐⭐⭐⭐<br>VM-level isolation.           | ⭐⭐⭐⭐⭐<br>VM-level isolation.                | ⭐⭐⭐⭐⭐<br>VM-level isolation.                               |
| **Updates**                 | ⭐⭐⭐⭐⭐<br>Automatic updates.           | ⭐⭐⭐⭐<br>Helm/Operator ease.                | ⭐<br>Manual, time-consuming.             | ⭐⭐⭐⭐<br>Easy with Docker images.      | ⭐<br>Snapshot updates.                 | ⭐⭐⭐⭐<br>Easy with Docker images.            | ⭐⭐⭐⭐⭐<br>Automated, requires downtime.                     |
| **Backup**                  | ⭐⭐⭐⭐⭐<br>Built-in backups.            | ⭐⭐⭐<br>Requires external tools.            | ⭐⭐<br>Manual, time-intensive.            | ⭐⭐<br>Volume-based manual backups.    | ⭐⭐⭐<br>VM snapshots available.         | ⭐⭐<br>Volume-based manual backups.          | ⭐⭐⭐⭐⭐<br>Automatic, with retention and pinning.            |
| **Scaling**                 | ⭐⭐⭐⭐⭐<br>Auto-scales with demand.     | ⭐⭐⭐⭐⭐<br>Highly scalable.                  | ⭐<br>Vertical scaling only.              | ⭐⭐<br>Limited to single host.         | ⭐⭐⭐<br>Horizontal scaling via new VMs. | ⭐⭐⭐<br>Horizontal scaling via new VMs.      | ⭐⭐⭐<br>Horizontal scaling via new VMs.                     |
| **Flexibility**             | ⭐⭐⭐⭐<br>Cloud-driven, moderate.       | ⭐⭐⭐⭐<br>Highly flexible for containers.    | ⭐<br>Low, tied to hardware.              | ⭐⭐<br>Limited by single host.         | ⭐⭐<br>Moderate, depends on VMs.        | ⭐⭐⭐⭐⭐<br>Highly portable (VM + containers). | ⭐⭐⭐⭐⭐<br>Highly portable, simple restores.                 |
| **Automation**              | ⭐⭐⭐⭐⭐<br>Fully automated.             | ⭐⭐⭐⭐<br>Partial automation via Helm.       | ⭐<br>None, entirely manual.              | ⭐<br>No automation.                   | ⭐<br>No automation.                    | ⭐<br>No automation.                         | ⭐⭐⭐⭐<br>Possible via utility scripts.                      |
| **Modern DevOps Practices** | ⭐⭐⭐⭐⭐<br>Fully aligned with CI/CD.    | ⭐⭐⭐⭐⭐<br>Supports containerized workflows. | ⭐<br>Not aligned.                        | ⭐⭐⭐<br>Good for dev environments.     | ⭐⭐<br>Not containerized.               | ⭐⭐⭐⭐<br>Supports CI/CD workflows.           | ⭐⭐⭐⭐⭐<br>Fully aligned with modern DevOps.                 |

In case you do not wish to deal with kubernetes cluster or do not want to run kafka cluster there, the recommended
deployment
approach is to use **virtual machines (VMs)** with guaranteed hardware resource allocation for each Kafka node, like you
would have with kubernetes.

### **VM Setup**

- **Resource Recommendations**: Ensure the VMs are provisioned with sufficient CPU, RAM, and disk space to meet Kafka's
  workload demands.
- **Storage Considerations**:
    - Avoid **RAID-5** due to its high write latency, which can degrade Kafka performance.
    - Prefer configurations such as:
        - **Single SSD** for maximum performance.
        - **RAID-0** for performance without redundancy.
        - **RAID-10** for a balance of performance and redundancy.
    - Use **eagerzeroedthick** provisioning for virtual disks to enhance I/O performance by pre-allocating disk space
      and avoiding fragmentation during write operations.

### **Cluster Roles**

The minimal development/testing cluster should include of the following roles:

1. **Central node(s):**
    - Responsible for running web console for GUI, backup & restore operations
    - Includes at least one node:
        - `kafka-central-1`


2. **Controllers**:
    - Responsible for managing cluster metadata, leader elections, and topic configurations.
    - Includes at least three controllers:
        - `kafka-controller-1`
        - `kafka-controller-2`
        - `kafka-controller-3`


3. **Brokers**:
    - Handle data storage, replication, and client requests.
    - Includes at least three brokers:
        - `kafka-broker-1`
        - `kafka-broker-2`
        - `kafka-broker-3`

## Plan your resources! ##

![resources map](charts/resources.png)

### **Deployment**

Each VM runs a **Docker engine** to streamline Kafka node management: including starting, stopping, backups, restores
and version updates.

The choice of Kafka vendor distribution — whether Apache, Confluent, Bitnami or others — is less critical, as all
provide easily deployable Docker images.

---

## **Cluster Procedures**

### **Cluster Startup Procedure**

To ensure proper initialization and data consistency, the following **controlled startup sequence** is followed:

1. **Start Controllers**:
    - Start controllers one by one, beginning with the **first controller** and proceeding to the **last**.

2. **Start Brokers**:
    - Once all controllers are operational, start brokers one by one, beginning with the **first broker** and proceeding
      to the **last**.

---

### **Cluster Shutdown Procedure**

To safely shut down the cluster and maintain data consistency, the following **controlled shutdown sequence** is
followed:

1. **Stop Brokers**:
    - Stop brokers one by one, starting with the **last broker** and proceeding to the **first**.

2. **Stop Controllers**:
    - After all brokers are stopped, stop controllers one by one, starting with the **last controller** and proceeding
      to the **first**.

---

## **Backup Routine**

The utility provides a reliable method for performing **full cluster backups**. Below is an overview of the backup
routine:

### **Key Features**

1. **Backup Rotation**:
    - Automatically removes old backups based on a retention policy (default: 30 days).
    - Archives are stored in `STORAGE_COLD` (e.g., `/backup/cold`) and organized by timestamp.

2. **Backup Workflow**:
    - **Shutdown Routine**:
        - Gracefully shuts down the cluster following the controlled shutdown procedure (stop brokers first, then
          controllers).
    - **Cluster Configuration Backup**:
        - Pulls configuration files from all nodes to a temporary folder on the backup server.
        - Archives configuration files and moves them to cold storage.
        - Cleans up temporary folders to free up space.
    - **Cluster Data Backup**:
        - Archives data files locally on each node into temporary folders.
        - Transfers archived files from nodes to the backup server.
        - Consolidates individual node archives into a single "zip of zips" for the entire cluster and stores it in cold
          storage.
        - Cleans up temporary folders after the backup.
    - **Startup Routine**:
        - Restarts the cluster following the controlled startup procedure (start controllers first, then brokers).

---

## **How to Use**

### **Backup Command**

To perform a full cluster backup, use the following command:

```bash
./kafka_manager.sh cluster_backup
