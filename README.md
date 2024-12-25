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

| **Aspect**                  | **Cloud-Managed Services**                      | **Kubernetes**                                       | **Docker in VM with KBO**                             | **Docker in VMs**                           | **Virtual Machines**                          | **Bare Metal**                          | **Docker Compose**                        |
|-----------------------------|-------------------------------------------------|------------------------------------------------------|-------------------------------------------------------|---------------------------------------------|-----------------------------------------------|-----------------------------------------|-------------------------------------------|
| **Overall Rating**          | 58 stars<br>⭐⭐⭐⭐⭐                               | 50 stars<br>⭐⭐⭐⭐                                     | 51 stars<br>⭐⭐⭐⭐                                      | 43 stars<br>⭐⭐⭐                             | 36 stars<br>⭐⭐⭐                               | 31 stars<br>⭐⭐                          | 22 stars<br>⭐⭐                            |
| **Definition**              | Fully managed Kafka services.                   | Orchestrates containerized Kafka clusters.           | Kafka in containers on VMs with KBO.                  | Kafka in containers on VMs.                 | Kafka binaries on VMs.                        | Kafka binaries on physical servers.     | Kafka in containers on single docker.     |
| **Performance**             | ★★★★★<br>Optimized by provider.                 | ★★★★<br>Depends on container resources.              | ★★★★<br>Limited by hypervisor + downtime for backups. | ★★★★<br>Limited by hypervisor.              | ★★★★<br>Limited by hypervisor.                | ★★★★★<br>Direct hardware access.        | ★<br>Suitable for small workloads.        |
| **Performance Overhead**    | ★★★★★<br>Minimal overhead.                      | ★★★★<br>Moderate, resource allocation.               | ★★★★<br>VM + container overhead.                      | ★★★★<br>VM + container overhead.            | ★★★★<br>Moderate, due to virtualization.      | ★★★★★<br>None, direct access.           | ★★<br>Low, single Docker engine.          |
| **Operational Overhead**    | ★★★★★<br>Minimal, fully managed.                | ★★★★<br>Moderate, requires scripting.                | ★★★★<br>Low due to KBO.                               | ★★★<br>Moderate, manual processes.          | ★★<br>Moderate, requires snapshot management. | ★<br>High, manual operations required.  | ★<br>High, manual interventions needed.   |
| **Operational Confidence**  | ★★★★★<br>High confidence with managed services. | ★★★★★<br>Stable with proper configuration.           | ★★★★★<br>High confidence with foolproof routines.     | ★★★<br>Good but requires experience.        | ★★★<br>Moderate with VM snapshots.            | ★★<br>Dependent on manual effort.       | ★★<br>Low for production setups.          |
| **Resource Isolation**      | ★★★★★<br>Strong, managed by provider.           | ★★★★<br>Container-level isolation.                   | ★★★★★<br>VM-level isolation.                          | ★★★★★<br>VM-level isolation.                | ★★★★★<br>VM-level isolation.                  | ★★★★★<br>Strong, dedicated hardware.    | ★<br>No isolation.                        |
| **Updates**                 | ★★★★★<br>Automatic updates.                     | ★★★★<br>Managed via Helm or Operators.               | ★★★★★<br>Automated, requires downtime.                | ★★★★<br>Easy with Docker images.            | ★<br>Requires manual snapshots.               | ★<br>Manual, time-consuming.            | ★★★★<br>Easy with Docker images.          |
| **Backup**                  | ★★★★★<br>Built-in backups.                      | ★★★★<br>Requires external tools.                     | ★★★★★<br>Automated, requires downtime.                | ★★<br>Volume-based manual backups.          | ★★★<br>VM snapshots available.                | ★★<br>Manual backups needed.            | ★★<br>Manual volume backups.              |
| **Scaling**                 | ★★★★★<br>Auto-scales with demand.               | ★★★★★<br>Highly scalable.                            | ★★★<br>Horizontal scaling via new VMs.                | ★★★<br>Horizontal scaling via new VMs.      | ★★★<br>Horizontal scaling via additional VMs. | ★<br>Vertical scaling only.             | ★★<br>Limited to single host.             |
| **Flexibility**             | ★★★★<br>Cloud-driven, moderate flexibility.     | ★★★★<br>Highly flexible for containerized workloads. | ★★★★★<br>Highly portable, simple restores.            | ★★★★★<br>Highly portable (VM + containers). | ★★<br>Moderate, depends on VM capabilities.   | ★<br>Low, tied to hardware.             | ★★<br>Limited by single host.             |
| **Automation**              | ★★★★★<br>Fully automated.                       | ★★★★<br>Partial automation with Helm.                | ★★★★<br>Possible with KBO.                            | ★<br>No automation.                         | ★<br>No automation.                           | ★<br>No automation.                     | ★<br>No automation.                       |
| **Modern DevOps Practices** | ★★★★★<br>Fully aligned with CI/CD.              | ★★★★★<br>Supports containerized workflows.           | ★★★★★<br>Fully aligned with modern DevOps.            | ★★★★<br>Supports CI/CD workflows.           | ★★<br>Not containerized.                      | ★<br>Not aligned with modern practices. | ★★★<br>Good for development environments. |

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
