# Market Connector Demo - CDC & Kafka Integration Proof of Concept

## 📋 Executive Summary

This is a **proof-of-concept demo project** to validate the technical feasibility of our proposed Integration Microservice Architecture before full-scale implementation. The demo will test the core CDC (Change Data Capture) flow using Debezium, Kafka, and Hibernate 6 to sync data from our existing POS database to a new integration microservice database.

**Goal:** Validate that we can capture real-time database changes from our POS system and replicate them to our integration service without modifying existing POS code.

---

## 🎯 Problem Statement

Our current POS system (Octopus) is experiencing performance issues due to direct third-party API traffic hitting the main database. We need to:

1. **Isolate POS from third-party load** - Serve inventory queries from a separate cache
2. **Enable real-time synchronization** - Push inventory updates to marketplaces (Shopify, Lazada) within seconds
3. **Scale independently** - Handle 100+ req/s without impacting POS performance
4. **Avoid POS code changes** - Use CDC to capture database changes automatically

---

## 🏗️ Demo Scope

### What This Demo Will Accomplish

✅ **Validate CDC Setup** - Prove Debezium can capture changes from our PostgreSQL POS database  
✅ **Test Kafka Pipeline** - Verify event streaming from source DB → Kafka → target DB  
✅ **Hibernate 6 Integration** - Demonstrate ORM capabilities with modern JPA standards  
✅ **Database Connectivity** - Establish connections to both source (POS) and target (Integration) databases  
✅ **Logging & Observability** - Implement proper logging for troubleshooting  
✅ **Minimal Working Flow** - Select 1-2 tables (e.g., `inventory`, `products`) and sync changes in real-time  


---

## 📂 Proposed Project Structure

```
market-connector-demo/
├── src/
│   ├── main/
│   │   ├── java/
│   │   │   └── com/example/marketconnector/
│   │   │       ├── MarketConnectorDemoApplication.java
│   │   │       ├── config/
│   │   │       │   ├── DatabaseConfig.java          # Multi-datasource config
│   │   │       │   ├── KafkaConfig.java            # Consumer configuration
│   │   │       │   └── DebeziumConfig.java         # CDC connector setup
│   │   │       ├── entity/
│   │   │       │   ├── source/                     # POS DB entities (read-only)
│   │   │       │   │   └── Inventory.java
│   │   │       │   └── target/                     # Integration DB entities
│   │   │       │       └── InventoryCache.java
│   │   │       ├── consumer/
│   │   │       │   └── InventoryChangeConsumer.java # Kafka listener
│   │   │       ├── service/
│   │   │       │   └── InventorySyncService.java   # Business logic
│   │   │       └── dto/
│   │   │           └── DebeziumChangeEvent.java    # Debezium event model
│   │   └── resources/
│   │       ├── application.yml                      # Main configuration
│   │       ├── application-dev.yml                  # Dev profile
│   │       ├── logback-spring.xml                   # Logging config
│   │       └── debezium-connector.json              # Debezium connector def
│   └── test/
│       └── java/
│           └── com/example/marketconnector/
│               └── InventorySyncServiceTest.java
├── docker/
│   ├── docker-compose.yml           # Kafka, Zookeeper, Debezium
│   └── postgres/
│       └── init-source-db.sql       # Sample POS data for testing
├── docs/
│   └── integration-architecture.html # Full architecture reference
├── pom.xml
└── README.md
```

---

## 🗄️ Database Schema (Demo)

### Source Database (POS - Read Only)
```sql
-- Existing POS inventory table (we won't modify this)
CREATE TABLE inventory (
    id BIGSERIAL PRIMARY KEY,
    product_id VARCHAR(100) NOT NULL,
    sku VARCHAR(100) NOT NULL,
    quantity INTEGER NOT NULL,
    store_id VARCHAR(50),
    last_updated TIMESTAMP DEFAULT NOW()
);
```

### Target Database (Integration Service - Write)
```sql
-- Cached inventory in our new microservice
CREATE TABLE inventory_cache (
    id BIGSERIAL PRIMARY KEY,
    product_id VARCHAR(100) NOT NULL,
    sku VARCHAR(100) NOT NULL,
    quantity INTEGER NOT NULL,
    store_id VARCHAR(50),
    last_synced_at TIMESTAMP DEFAULT NOW(),
    cdc_event_timestamp TIMESTAMP,
    UNIQUE(product_id, store_id)
);

-- Sync monitoring
CREATE TABLE sync_log (
    id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT NOW(),
    table_name VARCHAR(100),
    operation VARCHAR(20),       -- INSERT, UPDATE, DELETE
    record_id VARCHAR(100),
    status VARCHAR(20),           -- SUCCESS, FAILED
    error_message TEXT
);
```

