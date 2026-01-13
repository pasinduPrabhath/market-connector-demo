# ✅ Setup Checklist - Market Connector Demo


## Phase 1: Source Database Configuration

### PostgreSQL Configuration
- [ ] Find PostgreSQL config file location
  ```bash
  sudo -u postgres psql -c "SHOW config_file;"
  Location: _______________________
  ```

- [ ] Edit `postgresql.conf`
  - [ ] Set `wal_level = logical`
  - [ ] Set `max_replication_slots = 10`
  - [ ] Set `max_wal_senders = 10`

- [ ] Restart PostgreSQL
  ```bash
  sudo systemctl restart postgresql
  sudo systemctl status postgresql
  ```
  Status: [ ] Running

### Create Replication User
- [ ] Created `debezium_user` with password
- [ ] Granted REPLICATION privilege
- [ ] Granted SUPERUSER privilege
- [ ] Granted database access
  ```sql
  CREATE ROLE debezium_user WITH LOGIN ENCRYPTED PASSWORD 'debezium_pass';
  ALTER ROLE debezium_user REPLICATION;
  ALTER ROLE debezium_user SUPERUSER;
  GRANT ALL PRIVILEGES ON DATABASE your_db_name TO debezium_user;
  GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO debezium_user;
  ```

### Update pg_hba.conf
- [ ] Added debezium_user entries
  ```
  host    all             debezium_user   0.0.0.0/0               md5
  host    replication     debezium_user   0.0.0.0/0               md5
  ```

- [ ] Restarted PostgreSQL again

### Verify Source DB Setup
- [ ] Test connection works
  ```bash
  psql -h localhost -U debezium_user -d your_db_name -c "SELECT version();"
  ```
  Result: [ ] Success  [ ] Failed (error: _______________)

---

## Phase 2: Docker Configuration

### Grant Docker Permissions
- [ ] Added user to docker group
  ```bash
  sudo usermod -aG docker $USER
  ```

- [ ] Applied changes
  - [ ] Option A: Logged out and back in
  - [ ] Option B: Used `newgrp docker`
  - [ ] Option C: Rebooted system

### Verify Docker Access
- [ ] Tested docker without sudo
  ```bash
  docker ps
  ```
  Result: [ ] Success  [ ] Failed (error: _______________)

### Make Scripts Executable
- [ ] Made scripts executable
  ```bash
  chmod +x setup.sh cleanup.sh
  ```

---

## Phase 3: Run Setup

### Execute Setup Script
- [ ] Ran setup script
  ```bash
  ./setup.sh
  ```

- [ ] All services became healthy
  - [ ] Zookeeper: healthy
  - [ ] Kafka: healthy
  - [ ] PostgreSQL: healthy
  - [ ] Debezium: healthy

- [ ] Source connector registered successfully
  HTTP Status: _____

- [ ] Sink connector registered successfully
  HTTP Status: _____

---

## Phase 4: Verification

### Check Container Status
- [ ] All containers running
  ```bash
  docker-compose ps
  ```
  Number of containers running: _____

### Check Connector Status
- [ ] Source connector state = RUNNING
  ```bash
  curl -s http://localhost:8083/connectors/pos-inventory-connector/status | jq '.connector.state'
  ```
  State: ___________________

- [ ] Sink connector state = RUNNING
  ```bash
  curl -s http://localhost:8083/connectors/jdbc-sink-inventory/status | jq '.tasks[0].state'
  ```
  State: ___________________

### Verify Data Sync
- [ ] Checked source database record count
  ```sql
  SELECT COUNT(*) FROM inventory;
  ```
  Source count: ___________________

- [ ] Checked target database record count
  ```bash
  docker exec -it market-connector-postgres-target \
    psql -U integration_user -d integration_db \
    -c "SELECT COUNT(*) FROM inventory_cache;"
  ```
  Target count: ___________________

- [ ] Counts match: [ ] Yes  [ ] No (difference: _______)

### View Kafka Messages
- [ ] Viewed sample Kafka messages
  ```bash
  docker exec -it market-connector-kafka kafka-console-consumer \
    --bootstrap-server localhost:9092 \
    --topic pos.public.inventory \
    --from-beginning \
    --max-messages 3
  ```
  Result: [ ] Messages visible  [ ] No messages

---

## Phase 5: Real-Time Sync Testing (10 minutes)

### Test INSERT
- [ ] Inserted new record in source database
  ```sql
  INSERT INTO inventory (productitem, quantity, currentcost, retailsalesprice, movementdate, organisation_id)
  VALUES (99999, 100, 25.50, 49.99, CURRENT_DATE, 1);
  ```

- [ ] Checked target database (wait 5 seconds)
  ```sql
  SELECT * FROM inventory_cache WHERE productitem = 99999;
  ```
  Result: [ ] Record appeared  [ ] Not found  
  Sync delay: _____ seconds

### Test UPDATE
- [ ] Updated record in source database
  ```sql
  UPDATE inventory SET quantity = 150 WHERE productitem = 99999;
  ```

- [ ] Checked target database (wait 5 seconds)
  Result: [ ] Updated  [ ] Not updated  
  Sync delay: _____ seconds

### Test DELETE
- [ ] Deleted record in source database
  ```sql
  DELETE FROM inventory WHERE productitem = 99999;
  ```

- [ ] Checked target database (wait 5 seconds)
  Result: [ ] Deleted  [ ] Still exists  
  Sync delay: _____ seconds

---

## Phase 6: Performance & Monitoring (5 minutes)

### Check Logs
- [ ] Reviewed Debezium logs
  ```bash
  docker logs market-connector-debezium | tail -50
  ```
  Errors found: [ ] None  [ ] Yes (describe: _______________)

- [ ] Reviewed Kafka logs
  Errors found: [ ] None  [ ] Yes (describe: _______________)

### Monitor Resource Usage
- [ ] Checked CPU usage
  ```bash
  docker stats --no-stream
  ```
  Highest CPU: _____ (container: _______________)

- [ ] Checked memory usage
  Highest memory: _____ (container: _______________)

- [ ] Checked disk usage
  ```bash
  docker system df
  ```
  Total size: _____

