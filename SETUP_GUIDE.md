# 🚀 Market Connector Demo - Complete Setup Guide

## 📋 Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Step 1: Configure Source PostgreSQL Database](#step-1-configure-source-postgresql-database)
4. [Step 2: Configure Environment Variables](#step-2-configure-environment-variables)
6. [Step 3: Grant Docker Permissions](#step-4-grant-docker-permissions)
7. [Step 4: Run Setup](#step-5-run-setup)
8. [Step 5: Verify Installation](#step-6-verify-installation)
9. [Step 6: Connect DBeaver](#step-7-connect-dbeaver-to-target-database)
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
SOURCE_DB_HOST=192.168.1.74          # ⚠️ CHANGE: Your POS DB IP/hostname
SOURCE_DB_PORT=5432                   # Default PostgreSQL port
SOURCE_DB_NAME=octopus_retaildb       # ⚠️ CHANGE: Your database name
SOURCE_DB_USER=debezium_user          # Created in Step 1.4
SOURCE_DB_PASSWORD=debezium_pass      # Created in Step 1.4

# ===========================================
# TARGET DATABASE (Integration Cache)
# ===========================================
TARGET_DB_NAME=integration_db         # Can keep or change
TARGET_DB_USER=integration_user       # Can keep or change
TARGET_DB_PASSWORD=integration_pass   # ⚠️ CHANGE: Use strong password

# ===========================================
# CONNECTOR SETTINGS
# ===========================================
CONNECTOR_NAME=pos-inventory-connector  # Connector name in Kafka Connect
TABLE_INCLUDE=public.inventory          # ⚠️ CHANGE: Your table (format: schema.table)
TOPIC_PREFIX=pos                         # Kafka topic prefix
```

**Save and exit** (`Ctrl+X`, then `Y`, then `Enter`)

### 2.4 Verify Environment Variables
```bash
cat .env
```

---

## Step 4: Grant Docker Permissions

**⚠️ REQUIRED: Your user must be in the `docker` group.**

### 4.1 Add User to Docker Group
```bash
sudo usermod -aG docker $USER
```

### 4.2 Apply Changes
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

### 4.3 Verify Docker Access
```bash
docker ps
# Should work WITHOUT "permission denied" error
```

---

## Step 5: Run Setup

### 5.1 Make Scripts Executable
```bash
cd /home/pasindu/Documents/GitHub/market-connector-demo/docker
chmod +x setup.sh cleanup.sh
```

### 5.2 Run Setup Script
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
🔗 Registering JDBC Sink Connector...
✅ Sink connector registered (HTTP 201)
✅ Setup Complete!
```

**⏱️ Duration**: 2-5 minutes (depends on data size)

### 5.3 What Happens During Setup

1. **Docker containers start** (Zookeeper, Kafka, Debezium, PostgreSQL target)
2. **Health checks** ensure all services are ready
3. **Debezium source connector** registers and starts reading your POS database
4. **Initial snapshot** copies ALL existing inventory records to Kafka
5. **JDBC sink connector** creates target table and writes all records
6. **CDC monitoring begins** - Real-time changes are now captured

---

## Step 6: Verify Installation

### 6.1 Check All Containers Running
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

### 6.2 Check Connector Status
```bash
# List all connectors
curl -s http://localhost:8083/connectors | jq

# Check source connector
curl -s http://localhost:8083/connectors/pos-inventory-connector/status | jq

# Check sink connector
curl -s http://localhost:8083/connectors/jdbc-sink-inventory/status | jq
```

**Expected**: Both should show `"state": "RUNNING"`

### 6.3 Verify Data Synced
```bash
# Check record count in target database
docker exec -it market-connector-postgres-target \
  psql -U integration_user -d integration_db \
  -c "SELECT COUNT(*) FROM inventory_cache;"
```

**Expected**: Should match the count in your source database

### 6.4 View Kafka Messages
```bash
docker exec -it market-connector-kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic pos.public.inventory \
  --from-beginning \
  --max-messages 5
```

**Expected**: JSON messages with your inventory data

---

## Step 7: Connect DBeaver to Target Database

### 7.1 Open DBeaver

### 7.2 Create New Connection
1. Click **"New Database Connection"**
2. Select **PostgreSQL**
3. Click **Next**

### 7.3 Connection Settings
```
Host:       localhost
Port:       5433         ⚠️ Note: 5433 not 5432
Database:   integration_db
Username:   integration_user
Password:   integration_pass
```

### 7.4 Test Connection
Click **"Test Connection"** → Should show "Connected"

### 7.5 Save and Connect

### 7.6 Explore Data
```sql
-- View table structure
\d inventory_cache;

-- Count records
SELECT COUNT(*) FROM inventory_cache;

-- View sample data
SELECT * FROM inventory_cache LIMIT 10;

-- Check sync metadata
SELECT * FROM sync_log;
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
curl -s http://localhost:8083/connectors/pos-inventory-connector/status | jq '.tasks[0].trace'
```

**Common issues**:
1. **Can't connect to source DB** - Check SOURCE_DB_HOST, firewall, credentials
2. **Table doesn't exist** - Verify TABLE_INCLUDE matches your table name
3. **Permission denied** - Verify debezium_user has proper grants

---

### ❌ Problem: No data in target database

**Check**:
```bash
# 1. Is source connector running?
curl -s http://localhost:8083/connectors/pos-inventory-connector/status | jq '.connector.state'

# 2. Are messages in Kafka?
docker exec -it market-connector-kafka kafka-topics --list --bootstrap-server localhost:9092

# 3. Check sink connector
curl -s http://localhost:8083/connectors/jdbc-sink-inventory/status | jq '.tasks[0].state'
```

---

### ❌ Problem: "Unable to determine Dialect" error

**Solution**: Verify `hibernate.dialect` is set in `jdbc-sink-connector.json.template`:
```json
"hibernate.dialect": "org.hibernate.dialect.PostgreSQLDialect"
```

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
curl -s http://localhost:8083/connectors/pos-inventory-connector/status | jq '.connector.state'
curl -s http://localhost:8083/connectors/jdbc-sink-inventory/status | jq '.tasks[0].state'
```

**Check lag** (how far behind is the sync):
```bash
# Source DB count
psql -h 192.168.1.74 -U debezium_user -d octopus_retaildb -c "SELECT COUNT(*) FROM inventory;"

# Target DB count
docker exec -it market-connector-postgres-target psql -U integration_user -d integration_db -c "SELECT COUNT(*) FROM inventory_cache;"
```

### View Logs
```bash
# All services
docker-compose logs -f

# Specific service
docker logs -f market-connector-debezium
```

### Restart Connectors
```bash
# Restart source connector
curl -X POST http://localhost:8083/connectors/pos-inventory-connector/restart

# Restart sink connector
curl -X POST http://localhost:8083/connectors/jdbc-sink-inventory/restart
```

### Complete Cleanup and Restart
```bash
# Stop everything and delete all data
./cleanup.sh

# Start fresh
./setup.sh
```

---

## Testing Real-Time Sync

### Test 1: Insert New Record
```sql
-- In your POS database
INSERT INTO inventory (productitem, quantity, currentcost, retailsalesprice, movementdate, organisation_id)
VALUES (12345, 100, 25.50, 49.99, CURRENT_DATE, 1);
```

**Wait 2-5 seconds**, then check target DB:
```sql
SELECT * FROM inventory_cache WHERE productitem = 12345;
```

### Test 2: Update Record
```sql
-- In POS database
UPDATE inventory SET quantity = 150 WHERE inventoryid = 123;
```

**Check target DB** - quantity should update within seconds

### Test 3: Delete Record
```sql
-- In POS database
DELETE FROM inventory WHERE inventoryid = 999;
```

**Check target DB** - record should be deleted

---

## Performance Tuning

### For Large Tables (100K+ rows)

**Edit `debezium-connector.json.template`**:
```json
"snapshot.fetch.size": "10000",
"max.batch.size": "2048",
"max.queue.size": "16384"
```

**Edit `jdbc-sink-connector.json.template`**:
```json
"tasks.max": "4",
"batch.size": "3000"
```

---

## Security Best Practices

1. **Change default passwords** in `.env`
2. **Use SSL for PostgreSQL connections** (add `?sslmode=require` to connection URLs)
3. **Restrict network access** - Use firewall rules
4. **Rotate credentials** regularly
5. **Monitor access logs**

---

## Additional Resources

- **Debezium Documentation**: https://debezium.io/documentation/
- **Kafka Connect**: https://kafka.apache.org/documentation/#connect
- **PostgreSQL CDC**: https://www.postgresql.org/docs/current/logical-replication.html

---
