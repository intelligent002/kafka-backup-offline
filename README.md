# **Kafka-Backup-Offline Utility**

---

## **Project Overview**

The `Kafka-Backup-Offline Utility` is a robust Bash-based tool designed to manage Kafka clusters in **development and
testing environments**. Its primary focus is to enable **safe and reliable cluster backups and restores** while
following proper startup and shutdown procedures to maintain data integrity.

This utility is **NOT SUITABLE FOR PRODUCTION USE**, as it requires taking the Kafka cluster offline during backup and
restore operations.

---

## **In general, Kafka Cluster deployment options are:**

| **Aspect**                  | **Cloud-Managed Services**   | **Kubernetes**                            | **Docker in VM with KBO**           | **Docker in VMs**          | **Virtual Machines**  | **Bare Metal**                     | **Docker Compose**                   |
|-----------------------------|------------------------------|-------------------------------------------|-------------------------------------|----------------------------|-----------------------|------------------------------------|--------------------------------------|
| **Overall Rating**          | ⭐⭐⭐⭐⭐                        | ⭐⭐⭐⭐	                                     | ⭐⭐⭐⭐	                               | ⭐⭐⭐                        | 	⭐⭐⭐	                 | ⭐⭐	                                | ⭐⭐                                   |
| **Definition**              | Fully managed Kafka services | Orchestrates containerized Kafka clusters | Kafka in containers on VMs with KBO | Kafka in containers on VMs | Kafka binaries on VMs | Kafka binaries on physical servers | Kafka in containers on single docker |
| **Performance**             | ★★★★★<br>Excelent            | ★★★★<br>Good                              | ★★★<br>Moderate                     | ★★★<br>Moderate            | ★★★★<br>Good          | ★★★★★<br>Excelent                  | ★★<br>Poor                           |
| **Performance Overhead**    | ★★★★★<br>Minimal             | ★★★★<br>Moderate                          | ★★★<br>Medium                       | ★★★<br>Medium              | ★★★★<br>Moderate      | ★★★★★<br>None                      | ★★<br>High                           |
| **Operational Overhead**    | ★★★★★<br>Minimal             | ★★★★<br>Moderate                          | ★★★★<br>Moderate                    | ★★★<br>Medium              | ★★<br>High            | ★<br>Very high                     | ★<br>Very high                       |
| **Operational Confidence**  | ★★★★★<br>High                | ★★★★<br>Good                              | ★★★★★<br>High                       | ★★★★<br>Good               | ★★★<br>Moderate       | ★★<br>Low                          | ★★<br>Low                            |
| **Resource Isolation**      | ★★★★★<br>Strong              | ★★★★<br>Good                              | ★★★★<br>Good                        | ★★★★<br>Good               | ★★★★<br>Good          | ★★★★★<br>Strong                    | ★★<br>Weak                           |
| **Updates**                 | ★★★★★<br>Fully Automatic     | ★★★<br>Helm or Operators                  | ★★★★★<br>With downtime              | ★★★<br>Docker images       | ★★<br>Manual          | ★<br>Manual                        | ★★★<br>Docker images                 |
| **Backup**                  | ★★★★★<br>Fully Automatic     | ★★<br>Requires tooling                    | ★★★★★<br>With downtime              | ★★<br>Manual               | ★★<br>Manual          | ★<br>Manual                        | ★<br>Manual                          |
| **Recovery**                | ★★★★★<br>On demand           | ★★<br>Requires tooling                    | ★★★★★<br>With downtime              | ★★<br>Manual               | ★★<br>Manual          | ★<br>Manual                        | ★<br>Manual                          |
| **Scaling**                 | ★★★★★<br>Auto-scales         | ★★★★<br>Good                              | ★★★<br>Moderate                     | ★★★<br>Moderate            | ★★★<br>Moderate       | ★★<br>Poor                         | ★<br>Very poor                       |
| **Flexibility**             | ★★★★<br>Good                 | ★★★★★<br>Excellent                        | ★★★★<br>Good                        | ★★★★<br>Good               | ★★★<br>Moderate       | ★★<br>Poor                         | ★★<br>Poor                           |
| **Automation**              | ★★★★★<br>Excellent           | ★★★★★<br>Excellent                        | ★★★<br>Moderate                     | ★★★<br>Moderate            | ★★<br>Poor            | ★<br>Very Poor                     | ★★<br>Poor                           |
| **Modern DevOps Practices** | ★★★★★<br>Excellent           | ★★★★★<br>Excellent                        | ★★★★<br>Good                        | ★★★<br>Moderate            | ★★<br>Poor            | ★<br>Very Poor                     | ★★<br>Poor                           |

In case a cloud-managed service is not a viable option, and you prefer to avoid the Kubernetes, your next best choice is
virtual machines (VMs) with Docker.

Deploy Kafka nodes as containers within those Dockers, and let Kafka-Backup-Offline handle the rest:

* backup on demand
* backup on schedule
* restore on demand
* option of container deployment
* daily updates on schedule. By specifying the tag `:latest` for containers and redeploying them daily after backups,
  you can achieve a fully backed-up and up-to-date Kafka cluster with minimal manual intervention.
* in case the next version will cause issues - you can safely recover from previous backup and redeploy older version of
  docker container.

## Benefits of this Approach: ##

1. **Resource Isolation:** The use of VMs ensures that each Kafka node operates in its own isolated environment,
   reducing risks of interference or resource contention.
   Data Confidence: Kafka-Backup-Offline provides foolproof routines for automated backups and restores, offering
   unparalleled reliability and peace of mind.
   Ease of Deployment: With Kafka-Backup-Offline, deploying and managing Kafka containers becomes a simple, streamlined
   process, even for complex setups.
   Cost Efficiency: Running Kafka in Docker on VMs eliminates the need for a fully managed service or complex Kubernetes
   infrastructure, making it a cost-effective solution.
   Portability: Containers can easily be moved between environments, whether on different VMs, clouds, or on-premises
   servers.
   Simplified Updates: Daily redeployments with the :latest tag ensure that your Kafka cluster stays updated without
   requiring additional maintenance efforts.
   Operational Flexibility: You can customize VM and container configurations to suit your workload, scaling
   horizontally as needed by adding more VMs and Kafka nodes.
   Improved Backup Retention: Kafka-Backup-Offline supports backup retention policies, ensuring that older backups are
   rotated out while critical backups can be pinned and retained.
   Disaster Recovery: With automated restore routines, recovering from system failures becomes a fast and
   straightforward process.
   Developer-Friendly: The foolproof tools offered by Kafka-Backup-Offline make it easy for developers to work with the
   cluster, enhancing productivity and reducing the learning curve.
   Minimal Downtime: Routine backups and updates can be performed with minimal impact on cluster availability, ensuring
   smooth operations.

## **Cluster Topology**

Kafka demands significant resources in terms of **Disk I/O, Memory & CPU**.

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
