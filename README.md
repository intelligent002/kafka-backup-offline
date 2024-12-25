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

| **Aspect**                  | **Cloud-Managed Services**                      | **Docker in VM with<br>Kafka-Backup-Offline**         | **Kubernetes**                                       | **Docker in VMs**                           | **Virtual Machines**                          | **Bare Metal**                          | **Docker Compose**                        |
|-----------------------------|-------------------------------------------------|-------------------------------------------------------|------------------------------------------------------|---------------------------------------------|-----------------------------------------------|-----------------------------------------|-------------------------------------------|
| **Overall Rating**          | 58 ⭐⭐⭐⭐⭐                                        | 51 ⭐⭐⭐⭐                                               | 50 ⭐⭐⭐⭐                                              | 43 ⭐⭐⭐                                      | 36 ⭐⭐⭐                                        | 31 ⭐⭐                                   | 22 ⭐⭐                                     |
| **Definition**              | Fully managed Kafka services.                   | Kafka in containers on VMs with Kafka-Backup-Offline. | Orchestrates containerized Kafka clusters.           | Runs Kafka in containers on VMs.            | Kafka on virtualized servers.                 | Direct deployment on physical servers.  | Runs Kafka in lightweight containers.     |
| **Performance**             | ★★★★★<br>Optimized by provider.                 | ★★★★<br>Limited by hypervisor + downtime for backups. | ★★★★<br>Depends on container resources.              | ★★★★<br>Limited by hypervisor.              | ★★★★<br>Limited by hypervisor.                | ★★★★★<br>Direct hardware access.        | ★<br>Suitable for small workloads.        |
| **Performance Overhead**    | ★★★★★<br>Minimal overhead.                      | ★★★★<br>VM + container overhead.                      | ★★★★<br>Moderate, resource allocation.               | ★★★★<br>VM + container overhead.            | ★★★★<br>Moderate, due to virtualization.      | ★★★★★<br>None, direct access.           | ★★<br>Low, single Docker engine.          |
| **Operational Overhead**    | ★★★★★<br>Minimal, fully managed.                | ★★★★<br>Low due to Kafka-Backup-Offline.              | ★★★★<br>Moderate, requires scripting.                | ★★★<br>Moderate, manual processes.          | ★★<br>Moderate, requires snapshot management. | ★<br>High, manual operations required.  | ★<br>High, manual interventions needed.   |
| **Operational Confidence**  | ★★★★★<br>High confidence with managed services. | ★★★★★<br>High confidence with foolproof routines.     | ★★★★★<br>Stable with proper configuration.           | ★★★<br>Good but requires experience.        | ★★★<br>Moderate with VM snapshots.            | ★★<br>Dependent on manual effort.       | ★★<br>Low for production setups.          |
| **Resource Isolation**      | ★★★★★<br>Strong, managed by provider.           | ★★★★★<br>VM-level isolation.                          | ★★★★<br>Container-level isolation.                   | ★★★★★<br>VM-level isolation.                | ★★★★★<br>VM-level isolation.                  | ★★★★★<br>Strong, dedicated hardware.    | ★<br>No isolation.                        |
| **Updates**                 | ★★★★★<br>Automatic updates.                     | ★★★★★<br>Automated, requires downtime.                | ★★★★<br>Managed via Helm or Operators.               | ★★★★<br>Easy with Docker images.            | ★<br>Requires manual snapshots.               | ★<br>Manual, time-consuming.            | ★★★★<br>Easy with Docker images.          |
| **Backup**                  | ★★★★★<br>Built-in backups.                      | ★★★★★<br>Automated, requires downtime.                | ★★★★<br>Requires external tools.                     | ★★<br>Volume-based manual backups.          | ★★★<br>VM snapshots available.                | ★★<br>Manual backups needed.            | ★★<br>Manual volume backups.              |
| **Scaling**                 | ★★★★★<br>Auto-scales with demand.               | ★★★<br>Horizontal scaling via new VMs.                | ★★★★★<br>Highly scalable.                            | ★★★<br>Horizontal scaling via new VMs.      | ★★★<br>Horizontal scaling via additional VMs. | ★<br>Vertical scaling only.             | ★★<br>Limited to single host.             |
| **Flexibility**             | ★★★★<br>Cloud-driven, moderate flexibility.     | ★★★★★<br>Highly portable, simple restores.            | ★★★★<br>Highly flexible for containerized workloads. | ★★★★★<br>Highly portable (VM + containers). | ★★<br>Moderate, depends on VM capabilities.   | ★<br>Low, tied to hardware.             | ★★<br>Limited by single host.             |
| **Automation**              | ★★★★★<br>Fully automated.                       | ★★★★<br>Possible with Kafka-Backup-Offline.           | ★★★★<br>Partial automation with Helm.                | ★<br>No automation.                         | ★<br>No automation.                           | ★<br>No automation.                     | ★<br>No automation.                       |
| **Modern DevOps Practices** | ★★★★★<br>Fully aligned with CI/CD.              | ★★★★★<br>Fully aligned with modern DevOps.            | ★★★★★<br>Supports containerized workflows.           | ★★★★<br>Supports CI/CD workflows.           | ★★<br>Not containerized.                      | ★<br>Not aligned with modern practices. | ★★★<br>Good for development environments. |

in case cloud managed service is no match, and you do not want to deal with kubernetes, your next best option is VMs with docker on them, and Kafka Nodes as containers in those dockers, kafka-backup-offline will deal with the rest: which is backup and restore, as an option it can also deploy the containers, and if you will specify :latest and redeploy daily after the backup - you will achieve backed up and updated state on daily basis.
benefits of this approach are: resource isolation, data confidence.


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
