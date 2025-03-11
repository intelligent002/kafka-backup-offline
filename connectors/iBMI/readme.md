# 🚀 Understanding Debezium AS400 CDC: Why Only Modified Fields Are Included?

In **Debezium for IBM i (DB2 AS/400)**, change events sometimes only include **modified fields** instead of the full record.  
This is controlled by **"Capture Mode" settings**, which determine **how CDC events are structured**.

---

## 🔹 The Configuration That Controls This Behavior

The setting responsible for this behavior is:

```yaml
"message.key.columns": "YOURSCHEMA.YOURTABLE:id",
"message.value.include.schema": "true",
"message.value.include.fields": "all"  # Change this for full records
"capture.mode": "changed"  # ✅ Only modified fields are included (default behavior).
"capture.mode": "all"      # ✅ Includes the full row, even unchanged fields.
