# 🚀 Market Connector Demo - Complete Setup Guide

## 📋 Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Step 1: Configure Source PostgreSQL Database](#step-1-configure-source-postgresql-database)
4. [Step 2: Configure Environment Variables](#step-2-configure-environment-variables)
5. [Step 3: Grant Docker Permissions](#step-3-grant-docker-permissions)
6. [Step 4: Run Setup](#step-4-run-setup)
7. [Step 5: Verify Installation](#step-5-verify-installation)
8. [Step 6: Connect DBeaver](#step-6-connect-dbeaver-to-target-database)
9. [Adding New Tables](#adding-new-tables)
10. [Troubleshooting](#troubleshooting)
11. [Monitoring & Maintenance](#monitoring--maintenance)

---

## Overview

This project demonstrates real-time Change Data Capture (CDC) from a PostgreSQL POS database to a cache database using:
- **Debezium** - Captures database changes
- **Kafka** - Streams change events
- **JDBC Sink Connector** - Writes to target database
- **Docker** - Containerized infrastructure

**Goal**: Automatically sync inventory data from POS DB → Cache DB in real-time without modifying POS code.

---

## Prerequisites

### Required Software
- ✅ **Docker** (20.10 or higher)
- ✅ **Docker Compose** (v2.0 or higher)
- ✅ **PostgreSQL** (11 or higher) - Your existing POS database
- ✅ **sudo access** - For PostgreSQL configuration
- ✅ **curl** - For API calls
- ✅ **jq** (optional) - For JSON formatting

### Verify Prerequisites
```bash
docker --version          # Should show: Docker version 20.10+
docker-compose --version  # Should show: Docker Compose version v2.0+
psql --version           # Should show: PostgreSQL 11+
```

---

## Step 1: Configure Source PostgreSQL Database

**⚠️ CRITICAL: You MUST configure your existing POS PostgreSQL database for CDC before running the setup.**

### 1.1 Find PostgreSQL Configuration File
```bash
sudo -u postgres psql -c "SHOW config_file;"
```
**Example output**: `/etc/postgresql/15/main/postgresql.conf`

### 1.2 Edit PostgreSQL Configuration
```bash
# Replace '15' with your PostgreSQL version
sudo nano /etc/postgresql/15/main/postgresql.conf
```

**Find and modify these settings**:

```ini
# Around line 180-200, find:
#wal_level = replica
# Change to:
wal_level = logical

# Around line 260-280, find:
#max_replication_slots = 10
# Change to:
max_replication_slots = 10

# Around line 280-300, find:
#max_wal_senders = 10
# Change to:
max_wal_senders = 10
```

**Save and exit** (`Ctrl+X`, then `Y`, then `Enter`)

### 1.3 Restart PostgreSQL
```bash
sudo systemctl restart postgresql

# Verify it restarted successfully
sudo systemctl status postgresql
```

### 1.4 Create Replication User
Debezium needs a special PostgreSQL user with replication privileges:

```bash
# Connect to PostgreSQL as admin
sudo -u postgres psql

# Run these SQL commands:
CREATE ROLE debezium_user WITH LOGIN ENCRYPTED PASSWORD 'debezium_pass';
ALTER ROLE debezium_user REPLICATION;
ALTER ROLE debezium_user SUPERUSER;

# Grant access to your database (replace 'octopus_retaildb' with your DB name)
GRANT ALL PRIVILEGES ON DATABASE octopus_retaildb TO debezium_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO debezium_user;

# Exit
\q
```

### 1.5 Update PostgreSQL Authentication
```bash
# Find pg_hba.conf location
sudo -u postgres psql -c "SHOW hba_file;"

# Edit the file (replace '15' with your version)
sudo nano /etc/postgresql/15/main/pg_hba.conf
```

**Add these lines at the END of the file**:
```
# Allow debezium to connect for replication
host    all             debezium_user   0.0.0.0/0               md5
host    replication     debezium_user   0.0.0.0/0               md5
```

### 1.6 Restart PostgreSQL Again
```bash
sudo systemctl restart postgresql
```

### 1.7 Verify Configuration
```bash
# Test connection (replace with your database name)
psql -h localhost -U debezium_user -d octopus_retaildb -c "SELECT version();"
# Password: debezium_pass

# Should show PostgreSQL version info
```

✅ **Source database is now configured!**

---

## Step 2: Configure Environment Variables

### 2.1 Navigate to Project Directory
```bash
cd /home/pasindu/Documents/GitHub/market-connector-demo/docker
```

### 2.2 Edit `.env` File
```bash
nano .env
```

### 2.3 Update ALL Values
```bash
# ===========================================
# SOURCE DATABASE (Your POS Database)
# ===========================================
SOURCE_CONNECTOR_NAME=pos-cdc-connector
SOURCE_DB_HOST=192.168.1.74          # ⚠️ CHANGE: Your POS DB IP/hostname
SOURCE_DB_PORT=5432                   # Default PostgreSQL port
SOURCE_DB_NAME=octopus_retaildb       # ⚠️ CHANGE: Your database name
SOURCE_DB_USER=debezium_user          # Created in Step 1.4
SOURCE_DB_PASSWORD=debezium_pass      # Created in Step 1.4

# ===========================================
# KAFKA TOPIC CONFIGURATION
# ===========================================
TOPIC_PREFIX=pos

# Tables to sync (comma-separated, no spaces)
TABLE_INCLUDE_LIST=public.inventory,public.productitem

# ===========================================
# TARGET DATABASE (Integration Cache)
# ===========================================
TARGET_DB_NAME=integration_db         # Can keep or change
TARGET_DB_USER=integration_user       # Can keep or change
TARGET_DB_PASSWORD=integration_pass   # ⚠️ CHANGE: Use strong password
```

**Save and exit** (`Ctrl+X`, then `Y`, then `Enter`)

### 2.4 Verify Environment Variables
```bash
cat .env
```

---

## Step 3: Grant Docker Permissions

**⚠️ REQUIRED: Your user must be in the `docker` group.**

### 3.1 Add User to Docker Group
```bash
sudo usermod -aG docker $USER
```

### 3.2 Apply Changes
**Choose ONE option**:

**Option A: Log out and log back in** (recommended)
```bash
exit
# Then log back into your system
```

**Option B: Start new shell with docker group**
```bash
newgrp docker
```

**Option C: Reboot** (most reliable)
```bash
sudo reboot
```

### 3.3 Verify Docker Access
```bash
docker ps
# Should work WITHOUT "permission denied" error
```

---

## Step 4: Run Setup

### 4.1 Make Scripts Executable
```bash
cd /home/pasindu/Documents/GitHub/market-connector-demo/docker
chmod +x setup.sh cleanup.sh
```

### 4.2 Run Setup Script
```bash
./setup.sh
```

**Expected output**:
```
🚀 Starting Market Connector Infrastructure...
⏳ Waiting for services to be healthy...
   Zookeeper: healthy | Kafka: healthy | PostgreSQL: healthy | Debezium: healthy
✅ All services are healthy!
🔗 Registering Debezium Source Connector...
✅ Source connector registered (HTTP 201)
⏳ Waiting 15 seconds for initial snapshot to start...
🔗 Registering JDBC Sink Connectors...
📋 Registering: jdbc-sink-inventory
   Table: inventory
✅ Sink connector registered (HTTP 201)
📋 Registering: jdbc-sink-productitem
   Table: productitem
✅ Sink connector registered (HTTP 201)
✅ Setup Complete!
```

**⏱️ Duration**: 2-5 minutes (depends on data size)

### 4.3 What Happens During Setup

1. **Docker containers start** (Zookeeper, Kafka, Debezium, PostgreSQL target)
2. **Health checks** ensure all services are ready
3. **Debezium source connector** registers and starts reading your POS database
4. **Initial snapshot** copies ALL existing records to Kafka
5. **JDBC sink connectors** create target tables and write all records
6. **CDC monitoring begins** - Real-time changes are now captured

---

## Step 5: Verify Installation

### 5.1 Check All Containers Running
```bash
docker-compose ps
```

**Expected output** (all should show "Up" status):
```
NAME                                  STATUS
market-connector-zookeeper           Up (healthy)
market-connector-kafka               Up (healthy)
market-connector-debezium            Up (healthy)
market-connector-postgres-target     Up (healthy)
```

### 5.2 Check Connector Status
```bash
# List all connectors
curl -s http://localhost:8083/connectors | jq

# Check source connector
curl -s http://localhost:8083/connectors/pos-cdc-connector/status | jq

# Check sink connectors
curl -s http://localhost:8083/connectors/jdbc-sink-inventory/status | jq
curl -s http://localhost:8083/connectors/jdbc-sink-productitem/status | jq
```

**Expected**: All should show `"state": "RUNNING"`

### 5.3 Verify Data Synced
```bash
# Check record counts in target database
docker exec -it market-connector-postgres-target \
  psql -U integration_user -d integration_db \
  -c "SELECT 'inventory' AS table_name, COUNT(*) FROM inventory UNION ALL SELECT 'productitem', COUNT(*) FROM productitem;"
```

**Expected**: Should match the counts in your source database

### 5.4 View Kafka Topics
```bash
# List all topics
docker exec -it market-connector-kafka kafka-topics --list --bootstrap-server localhost:9092

# Should see:
# pos.public.inventory
# pos.public.productitem
```

---

## Step 6: Connect DBeaver to Target Database

### 6.1 Open DBeaver

### 6.2 Create New Connection
1. Click **"New Database Connection"**
2. Select **PostgreSQL**
3. Click **Next**

### 6.3 Connection Settings
```
Host:       localhost
Port:       5433         ⚠️ Note: 5433 not 5432
Database:   integration_db
Username:   integration_user
Password:   integration_pass
```

### 6.4 Test Connection
Click **"Test Connection"** → Should show "Connected"

### 6.5 Save and Connect

### 6.6 Explore Data
```sql
-- View table structures
\d inventory;
\d productitem;

-- Count records
SELECT COUNT(*) FROM inventory;
SELECT COUNT(*) FROM productitem;

-- View sample data
SELECT * FROM inventory LIMIT 10;
SELECT * FROM productitem LIMIT 10;

-- Check sync metadata
SELECT * FROM sync_log;
```

---

## Adding New Tables

When you want to add a new table (e.g., `orders`), follow these steps:

### Step 1: Update `.env` File

Add the new table to `TABLE_INCLUDE_LIST`:

```bash
nano docker/.env
```

```bash
# Add your new table here (comma-separated, no spaces)
TABLE_INCLUDE_LIST=public.inventory,public.productitem,public.orders
```

### Step 2: Add Table Definition to `init-target-db.sql`

Edit the initialization script:

```bash
nano docker/postgres/init-target-db.sql
```

Add the CREATE TABLE statement (use your source table structure):

```sql
-- Drop table if exists
DROP TABLE IF EXISTS public.orders CASCADE;

-- ===========================================
-- ORDERS TABLE
-- ===========================================
CREATE TABLE public.orders (
    -- Auto-increment surrogate key
    id BIGSERIAL PRIMARY KEY,
    
    -- Business key (used for UPSERT matching)
    orderid BIGINT NOT NULL UNIQUE,
    
    -- Add ALL columns from your source table
    customer_id INT4 NULL,
    order_date TIMESTAMP NULL,
    total_amount FLOAT8 NULL,
    status VARCHAR NULL,
    -- ... add all other columns
    
    created_at TIMESTAMP DEFAULT NOW()
);

-- Create index on business key
CREATE INDEX idx_orders_orderid ON public.orders(orderid);

-- Grant permissions
GRANT ALL PRIVILEGES ON TABLE public.orders TO integration_user;
GRANT USAGE, SELECT ON SEQUENCE public.orders_id_seq TO integration_user;
```

**💡 Pro Tip**: Get the exact column structure from your source database:
```bash
psql -h 192.168.1.74 -U debezium_user -d octopus_retaildb -c "\d orders"
```

### Step 3: Create Sink Connector Template

Create a new file for the sink connector:

```bash
nano docker/jdbc-sink-orders.json.template
```

Copy this template and update the highlighted values:

```json
{
  "name": "jdbc-sink-orders",
  "config": {
    "connector.class": "io.debezium.connector.jdbc.JdbcSinkConnector",
    "tasks.max": "1",
    "topics": "${TOPIC_PREFIX}.public.orders",
    "connection.url": "jdbc:postgresql://postgres-integration:5432/${TARGET_DB_NAME}",
    "connection.username": "${TARGET_DB_USER}",
    "connection.password": "${TARGET_DB_PASSWORD}",
    "insert.mode": "upsert",
    "delete.enabled": "true",
    "primary.key.mode": "record_key",
    "primary.key.fields": "orderid",
    "schema.evolution": "basic",
    "table.name.format": "orders"
  }
}
```

**What to change:**
- Line 2: `"name"` - Unique connector name
- Line 6: `"topics"` - Match your table name in format `${TOPIC_PREFIX}.public.{tablename}`
- Line 12: `"primary.key.fields"` - Your table's primary key column
- Line 14: `"table.name.format"` - Target table name

### Step 4: Update `setup.sh`

Edit the setup script:

```bash
nano docker/setup.sh
```

Find the `SINK_TEMPLATES` array and add your new template:

```bash
# Array of sink connector templates
SINK_TEMPLATES=(
    "jdbc-sink-inventory.json.template"
    "jdbc-sink-productitem.json.template"
    "jdbc-sink-orders.json.template"  # Add this line
)
```

### Step 5: Run Setup

```bash
cd docker
./cleanup.sh  # Clean up existing setup
./setup.sh    # Run fresh setup with new table
```

### Step 6: Verify New Table

```bash
# Check connector status
curl -s http://localhost:8083/connectors/jdbc-sink-orders/status | jq '.tasks[0].state'
# Should show: "RUNNING"

# Check record count
docker exec market-connector-postgres-target \
  psql -U integration_user -d integration_db \
  -c "SELECT COUNT(*) FROM orders;"

# View sample data
docker exec market-connector-postgres-target \
  psql -U integration_user -d integration_db \
  -c "SELECT * FROM orders LIMIT 5;"
```

---

### Quick Checklist for Adding Tables

For each new table, update these **4 files**:

- [ ] **`.env`** - Add to `TABLE_INCLUDE_LIST`
- [ ] **`postgres/init-target-db.sql`** - Add `CREATE TABLE` statement
- [ ] **`jdbc-sink-{tablename}.json.template`** - Create new sink connector config
- [ ] **`setup.sh`** - Add template to `SINK_TEMPLATES` array

Then run: `./cleanup.sh && ./setup.sh`

---

### Common Table Patterns

#### Pattern 1: Table with Composite Key

If your table has multiple columns as primary key (e.g., `order_id` + `line_item_id`):

```json
"primary.key.fields": "order_id,line_item_id"
```

#### Pattern 2: Table with Different Column Names

If your source and target tables have different column names, you need to handle this in the init script:

```sql
CREATE TABLE public.target_table (
    id BIGSERIAL PRIMARY KEY,
    source_column_name BIGINT NOT NULL UNIQUE,  -- Match source column name
    -- other columns
);
```

#### Pattern 3: Table Without Natural Key

If your table doesn't have a business key, use an auto-generated ID:

```sql
CREATE TABLE public.logs (
    id BIGSERIAL PRIMARY KEY,
    log_entry_id BIGINT GENERATED ALWAYS AS IDENTITY,
    -- other columns
);
```

```json
"primary.key.mode": "record_value",
"primary.key.fields": "log_entry_id"
```

---

## Troubleshooting

### ❌ Problem: "Permission denied" when running docker commands

**Solution**:
```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Log out and log back in, then try again
```

---

### ❌ Problem: Containers won't start / keep restarting

**Check logs**:
```bash
docker logs market-connector-debezium
docker logs market-connector-kafka
docker logs market-connector-postgres-target
```

**Common issues**:
- Port already in use (5433, 9092, 8083)
- Insufficient memory (Docker needs at least 4GB RAM)

---

### ❌ Problem: Connector status shows "FAILED"

**Check detailed error**:
```bash
curl -s http://localhost:8083/connectors/pos-cdc-connector/status | jq '.tasks[0].trace'
```

**Common issues**:
1. **Can't connect to source DB** - Check SOURCE_DB_HOST, firewall, credentials
2. **Table doesn't exist** - Verify TABLE_INCLUDE_LIST matches your table names
3. **Permission denied** - Verify debezium_user has proper grants

---

### ❌ Problem: No data in target database

**Check**:
```bash
# 1. Is source connector running?
curl -s http://localhost:8083/connectors/pos-cdc-connector/status | jq '.connector.state'

# 2. Are messages in Kafka?
docker exec -it market-connector-kafka kafka-topics --list --bootstrap-server localhost:9092

# 3. Check sink connector
curl -s http://localhost:8083/connectors/jdbc-sink-inventory/status | jq '.tasks[0].state'

# 4. View Kafka messages
docker exec market-connector-kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic pos.public.inventory \
  --from-beginning --max-messages 1
```

---

### ❌ Problem: New table not syncing

**Troubleshoot**:
```bash
# 1. Check if topic was created
docker exec market-connector-kafka kafka-topics --list --bootstrap-server localhost:9092 | grep "your_table"

# 2. Check if connector exists
curl -s http://localhost:8083/connectors | jq

# 3. Check connector status
curl -s http://localhost:8083/connectors/jdbc-sink-your-table/status | jq

# 4. View connector logs
docker logs market-connector-debezium | grep "your_table"
```

---

### ❌ Problem: CDC metadata columns appearing in target

If you see `__deleted`, `__op`, `__ts_ms` columns:

**Solution**: These are added for delete handling. The `__deleted` column is necessary for soft-delete functionality. To use hard deletes instead:

Edit `debezium-connector.json.template`:
```json
"transforms.unwrap.delete.handling.mode": "drop"
```

This will send actual DELETE operations instead of marking records as deleted.

---

### ❌ Problem: Setup script stuck on "still waiting..."

**Solution**:
```bash
# Press Ctrl+C to stop
# Check what's wrong:
docker-compose ps
docker logs market-connector-debezium

# Clean up and try again:
./cleanup.sh
./setup.sh
```

---

## Monitoring & Maintenance

### Daily Monitoring

**Check connector health**:
```bash
# Quick status check of all connectors
curl -s http://localhost:8083/connectors | jq -r '.[]' | while read connector; do
  echo -n "$connector: "
  curl -s http://localhost:8083/connectors/$connector/status | jq -r '.connector.state'
done
```

**Check data sync lag**:
```bash
# Source DB counts
psql -h 192.168.1.74 -U debezium_user -d octopus_retaildb -c "
  SELECT 'inventory' AS table_name, COUNT(*) FROM inventory
  UNION ALL
  SELECT 'productitem', COUNT(*) FROM productitem;"

# Target DB counts
docker exec market-connector-postgres-target psql -U integration_user -d integration_db -c "
  SELECT 'inventory' AS table_name, COUNT(*) FROM inventory
  UNION ALL
  SELECT 'productitem', COUNT(*) FROM productitem;"
```

### View Logs
```bash
# All services
docker-compose logs -f

# Specific service
docker logs -f market-connector-debezium
docker logs -f market-connector-kafka

# Last 100 lines
docker logs --tail 100 market-connector-debezium
```

### Restart Connectors
```bash
# Restart source connector
curl -X POST http://localhost:8083/connectors/pos-cdc-connector/restart

# Restart specific sink connector
curl -X POST http://localhost:8083/connectors/jdbc-sink-inventory/restart

# Restart all connectors
curl -s http://localhost:8083/connectors | jq -r '.[]' | while read connector; do
  curl -X POST http://localhost:8083/connectors/$connector/restart
  echo "Restarted: $connector"
done
```

### Pause/Resume Connectors
```bash
# Pause connector (stops processing, no data loss)
curl -X PUT http://localhost:8083/connectors/jdbc-sink-inventory/pause

# Resume connector
curl -X PUT http://localhost:8083/connectors/jdbc-sink-inventory/resume
```

### Delete Connector
```bash
# Delete connector (keeps data in target DB)
curl -X DELETE http://localhost:8083/connectors/jdbc-sink-inventory

# Re-register if needed
cd docker
export $(grep -v '^#' .env | xargs)
envsubst < jdbc-sink-inventory.json.template > generated-jdbc-sink-inventory.json
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @generated-jdbc-sink-inventory.json
```

### Complete Cleanup and Restart
```bash
# Stop everything and delete all data
./cleanup.sh

# When prompted:
# - Remove Docker images? N (unless updating)
# - Prune system? Y (to clean up unused resources)

# Start fresh
./setup.sh
```

---

## Testing Real-Time Sync

### Test 1: Insert New Record
```sql
-- In your POS database
INSERT INTO inventory (inventoryid, productitem, quantity, currentcost, retailsalesprice, movementdate, organisation_id)
VALUES (999999, 12345, 100, 25.50, 49.99, CURRENT_DATE, 1);
```

**Wait 2-5 seconds**, then check target DB:
```sql
SELECT * FROM inventory WHERE inventoryid = 999999;
```

### Test 2: Update Record
```sql
-- In POS database
UPDATE inventory SET quantity = 150 WHERE inventoryid = 999999;
```

**Check target DB** - quantity should update within seconds

### Test 3: Delete Record
```sql
-- In POS database
DELETE FROM inventory WHERE inventoryid = 999999;
```

**Check target DB** - record should be deleted (or `__deleted = true` if using soft deletes)

### Test 4: Bulk Operations
```sql
-- Insert 100 records
INSERT INTO inventory (inventoryid, productitem, quantity, organisation_id)
SELECT generate_series(900000, 900099), 12345, 10, 1;
```

**Monitor sync**:
```bash
# Watch Kafka lag
docker exec market-connector-kafka kafka-consumer-groups \
  --bootstrap-server localhost:9092 \
  --group connect-jdbc-sink-inventory \
  --describe

# Check target count
docker exec market-connector-postgres-target psql -U integration_user -d integration_db \
  -c "SELECT COUNT(*) FROM inventory WHERE inventoryid BETWEEN 900000 AND 900099;"
```

---

## Performance Tuning

### For Large Tables (100K+ rows)

**Edit `debezium-connector.json.template`**:
```json
"snapshot.fetch.size": "10000",
"max.batch.size": "2048",
"max.queue.size": "16384",
"poll.interval.ms": "100"
```

**Edit sink connector templates**:
```json
"tasks.max": "3",
"batch.size": "3000",
"consumer.max.poll.records": "500"
```

### Optimize PostgreSQL Target

```bash
docker exec -it market-connector-postgres-target psql -U integration_user -d integration_db
```

```sql
-- Increase shared buffers
ALTER SYSTEM SET shared_buffers = '256MB';

-- Increase work memory
ALTER SYSTEM SET work_mem = '16MB';

-- Reload config
SELECT pg_reload_conf();
```

---

## Security Best Practices

1. **Change default passwords** in `.env`
2. **Use SSL for PostgreSQL connections**:
   ```json
   "connection.url": "jdbc:postgresql://source:5432/db?sslmode=require"
   ```
3. **Restrict network access** - Use firewall rules
4. **Rotate credentials** regularly
5. **Monitor access logs**:
   ```bash
   docker logs market-connector-postgres-target | grep "authentication"
   ```
6. **Limit connector permissions** - Don't use SUPERUSER in production

---

## Backup and Recovery

### Backup Target Database
```bash
# Full backup
docker exec market-connector-postgres-target pg_dump \
  -U integration_user -d integration_db > backup_$(date +%Y%m%d).sql

# Compressed backup
docker exec market-connector-postgres-target pg_dump \
  -U integration_user -d integration_db | gzip > backup_$(date +%Y%m%d).sql.gz
```

### Restore from Backup
```bash
# Stop connectors first
curl -X PUT http://localhost:8083/connectors/jdbc-sink-inventory/pause

# Restore
gunzip -c backup_20260115.sql.gz | \
  docker exec -i market-connector-postgres-target \
  psql -U integration_user -d integration_db

# Resume connectors
curl -X PUT http://localhost:8083/connectors/jdbc-sink-inventory/resume
```

---

## Additional Resources

- **Debezium Documentation**: https://debezium.io/documentation/
- **Kafka Connect**: https://kafka.apache.org/documentation/#connect
- **PostgreSQL CDC**: https://www.postgresql.org/docs/current/logical-replication.html
- **JDBC Sink Connector**: https://docs.confluent.io/kafka-connect-jdbc/current/

---

## Support

If you encounter issues not covered in this guide:

1. **Check logs**: `docker logs market-connector-debezium`
2. **Search Debezium issues**: https://github.com/debezium/debezium/issues
3. **Check connector status**: `curl http://localhost:8083/connectors/{name}/status | jq`

---

**Last Updated**: January 2026  
**Version**: 2.0