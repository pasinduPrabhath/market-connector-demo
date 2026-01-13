# Market Connector Demo - CDC & Kafka Integration Proof of Concept

## 📋 Executive Summary

This is a **proof-of-concept demo project** to validate the technical feasibility of our proposed Integration Microservice Architecture before full-scale implementation. The demo will test the core CDC (Change Data Capture) flow using Debezium, Kafka, and Spring Boot 3.x (with Hibernate 6) to sync data from our existing POS database to a new integration microservice database.

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
✅ **Spring Boot 3.x Integration** - Leverage Spring Data JPA with Hibernate 6.x under the hood
✅ **Database Connectivity** - Establish dual datasource connections (source + target)
✅ **Error Handling** - Implement Dead Letter Queue (DLQ) pattern for failed events
✅ **Monitoring & Observability** - Health checks, metrics, and sync logging
✅ **Comprehensive Testing** - Unit, integration, and end-to-end tests
✅ **Minimal Working Flow** - Sync 1-2 tables (e.g., `inventory`) in real-time

---

## 🏛️ Architecture Overview

```
┌─────────────────┐         ┌──────────────────┐         ┌─────────────────────┐
│   POS Database  │         │  Debezium CDC    │         │   Kafka Cluster     │
│   (PostgreSQL)  │────────▶│  (Kafka Connect) │────────▶│   (External)        │
│                 │   WAL   │                  │  Events │                     │
└─────────────────┘         └──────────────────┘         └──────────┬──────────┘
                                                                     │
                                                                     ▼
                            ┌────────────────────────────────────────────────┐
                            │   Spring Boot Integration Service              │
                            │                                                │
                            │   ┌─────────────────────────────────────────┐ │
                            │   │  @KafkaListener                         │ │
                            │   │  InventoryChangeConsumer                │ │
                            │   └──────────────┬──────────────────────────┘ │
                            │                  │                            │
                            │   ┌──────────────▼──────────────────────────┐ │
                            │   │  InventoryEventMapper                   │ │
                            │   │  (Parse Debezium envelope)              │ │
                            │   └──────────────┬──────────────────────────┘ │
                            │                  │                            │
                            │   ┌──────────────▼──────────────────────────┐ │
                            │   │  InventorySyncService                   │ │
                            │   │  (Business logic + error handling)      │ │
                            │   └──────────────┬──────────────────────────┘ │
                            │                  │                            │
                            │   ┌──────────────▼──────────────────────────┐ │
                            │   │  InventoryCacheRepository               │ │
                            │   │  SyncLogRepository                      │ │
                            │   └──────────────┬──────────────────────────┘ │
                            └──────────────────┼────────────────────────────┘
                                               │
                                               ▼
                            ┌─────────────────────────────────────┐
                            │   Integration Database              │
                            │   (PostgreSQL)                      │
                            │   - inventory_cache                 │
                            │   - sync_log                        │
                            │   - failed_events                   │
                            └─────────────────────────────────────┘
```

**Key Point:** Debezium runs as a **separate Kafka Connect service** in docker-compose, NOT embedded in the Spring Boot application.

---

## 📂 Project Structure

```
market-connector-demo/
├── src/
│   ├── main/
│   │   ├── java/com/example/marketconnector/
│   │   │   ├── MarketConnectorDemoApplication.java
│   │   │   │
│   │   │   ├── config/
│   │   │   │   ├── SourceDatabaseConfig.java      # POS DB configuration
│   │   │   │   ├── TargetDatabaseConfig.java      # Integration DB configuration
│   │   │   │   └── KafkaConsumerConfig.java       # Kafka consumer setup
│   │   │   │
│   │   │   ├── entity/
│   │   │   │   ├── source/                        # POS DB entities (read-only)
│   │   │   │   │   └── Inventory.java
│   │   │   │   └── target/                        # Integration DB entities
│   │   │   │       ├── InventoryCache.java
│   │   │   │       ├── SyncLog.java               # Tracks all sync operations
│   │   │   │       └── FailedEvent.java           # DLQ for failed messages
│   │   │   │
│   │   │   ├── repository/
│   │   │   │   ├── source/
│   │   │   │   │   └── InventoryRepository.java   # Read-only repository
│   │   │   │   └── target/
│   │   │   │       ├── InventoryCacheRepository.java
│   │   │   │       ├── SyncLogRepository.java
│   │   │   │       └── FailedEventRepository.java
│   │   │   │
│   │   │   ├── dto/
│   │   │   │   ├── DebeziumEnvelope.java          # Full CDC event structure
│   │   │   │   └── InventoryChangePayload.java    # Parsed inventory data
│   │   │   │
│   │   │   ├── mapper/
│   │   │   │   └── InventoryEventMapper.java      # CDC event → Entity
│   │   │   │
│   │   │   ├── consumer/
│   │   │   │   ├── InventoryChangeConsumer.java   # Main Kafka listener
│   │   │   │   └── DeadLetterQueueHandler.java    # Failed message handler
│   │   │   │
│   │   │   ├── service/
│   │   │   │   ├── InventorySyncService.java      # Sync business logic
│   │   │   │   └── SyncMonitoringService.java     # Metrics and logging
│   │   │   │
│   │   │   └── monitoring/
│   │   │       └── SyncHealthIndicator.java       # Custom health check
│   │   │
│   │   └── resources/
│   │       ├── application.yml                    # Base configuration
│   │       ├── application-dev.yml                # Local development
│   │       ├── application-prod.yml               # Production settings
│   │       └── logback-spring.xml                 # Logging configuration
│   │
│   └── test/
│       └── java/com/example/marketconnector/
│           ├── unit/
│           │   ├── service/InventorySyncServiceTest.java
│           │   └── mapper/InventoryEventMapperTest.java
│           ├── integration/
│           │   ├── repository/RepositoryIntegrationTest.java
│           │   └── consumer/KafkaConsumerTest.java
│           └── testcontainers/
│               └── CdcEndToEndTest.java           # Full CDC flow test
│
├── docker/
│   ├── docker-compose.yml                         # All infrastructure services
│   ├── debezium/
│   │   ├── register-connector.sh                  # Auto-register connector
│   │   └── inventory-connector.json               # Debezium connector config
│   ├── postgres/
│   │   ├── init-source-db.sql                     # POS DB schema + test data
│   │   └── init-target-db.sql                     # Integration DB schema
│   └── README.md                                  # Infrastructure setup guide
│
├── docs/
│   ├── integration-architecture.html              # Full architecture diagrams
│   ├── CDC-FLOW.md                                # Step-by-step data flow
│   └── TESTING-GUIDE.md                           # How to test the POC
│
├── pom.xml
└── README.md
```

---

## 🗄️ Database Schema

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

### Target Database (Integration Service)

```sql
-- Cached inventory replicated from POS
CREATE TABLE inventory_cache (
    id BIGSERIAL PRIMARY KEY,
    product_id VARCHAR(100) NOT NULL,
    sku VARCHAR(100) NOT NULL,
    quantity INTEGER NOT NULL,
    store_id VARCHAR(50),
    last_synced_at TIMESTAMP DEFAULT NOW(),
    cdc_event_timestamp TIMESTAMP,
    source_record_id BIGINT,                -- Original POS record ID
    UNIQUE(product_id, store_id)
);

-- Audit log for all sync operations
CREATE TABLE sync_log (
    id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT NOW(),
    table_name VARCHAR(100),
    operation VARCHAR(20),                  -- INSERT, UPDATE, DELETE
    record_id VARCHAR(100),
    status VARCHAR(20),                     -- SUCCESS, FAILED
    error_message TEXT,
    processing_time_ms INTEGER
);

-- Dead Letter Queue for failed events
CREATE TABLE failed_events (
    id BIGSERIAL PRIMARY KEY,
    kafka_topic VARCHAR(255),
    kafka_partition INTEGER,
    kafka_offset BIGINT,
    event_payload JSONB NOT NULL,           -- Full Debezium event
    error_message TEXT,
    error_stacktrace TEXT,
    retry_count INTEGER DEFAULT 0,
    first_failed_at TIMESTAMP DEFAULT NOW(),
    last_retry_at TIMESTAMP,
    status VARCHAR(20) DEFAULT 'PENDING'    -- PENDING, RETRYING, RESOLVED, ABANDONED
);
```

---

## 🚀 Technology Stack

### Core Framework
- **Spring Boot 3.2+** - Application framework
- **Spring Data JPA 3.x** - Uses Hibernate 6.4+ under the hood
- **Spring Kafka 3.x** - Kafka consumer integration
- **Spring Boot Actuator** - Health checks and metrics

### Infrastructure
- **PostgreSQL 15+** - Both source and target databases
- **Apache Kafka 3.6+** - Event streaming platform
- **Kafka Connect** - Debezium connector runtime
- **Debezium 2.5+** - PostgreSQL CDC connector
- **Zookeeper** - Kafka coordination (or KRaft mode)

### Utilities
- **HikariCP** - Connection pooling
- **Jackson** - JSON processing (Debezium event parsing)
- **Micrometer** - Application metrics
- **Logback** - Logging framework

### Testing
- **JUnit 5** - Test framework
- **Testcontainers** - Integration testing with Docker
- **AssertJ** - Fluent assertions
- **Mockito** - Mocking framework

---

## 📋 Key Implementation Details

### 1. Debezium Event Structure

Debezium CDC events have a nested envelope structure:

```json
{
  "schema": {...},
  "payload": {
    "before": null,
    "after": {
      "id": 123,
      "product_id": "PROD-001",
      "sku": "SKU-12345",
      "quantity": 50,
      "store_id": "STORE-A",
      "last_updated": 1704067200000
    },
    "source": {
      "version": "2.5.0.Final",
      "connector": "postgresql",
      "name": "pos-db-server",
      "ts_ms": 1704067200000,
      "db": "pos_database",
      "schema": "public",
      "table": "inventory"
    },
    "op": "c",  // c=create, u=update, d=delete, r=read (snapshot)
    "ts_ms": 1704067200123
  }
}
```

### 2. Error Handling Strategy

**Three-tier error handling:**

1. **Transient Errors** - Retry with exponential backoff (Kafka consumer retries)
2. **Poison Pills** - Store in `failed_events` table with full context
3. **Monitoring** - Alert on DLQ threshold (e.g., >10 failed events)

### 3. Observability

**Health Checks:**
- Database connectivity (source + target)
- Kafka consumer lag
- Last successful sync timestamp

**Metrics:**
- Events processed per second
- Sync latency (CDC event timestamp → DB write)
- Error rate
- DLQ size

**Logging:**
- All sync operations logged to `sync_log` table
- Structured JSON logging for ELK/Splunk integration

---

## 🧪 Testing Strategy

### Unit Tests
- Service layer business logic
- Event mapper (Debezium JSON → Entity)
- Error handling paths

### Integration Tests
- Repository CRUD operations with @DataJpaTest
- Kafka consumer with EmbeddedKafka
- Transaction rollback scenarios

### End-to-End Tests (Testcontainers)
```java
@Testcontainers
class CdcEndToEndTest {
    @Container
    static PostgreSQLContainer<?> sourceDb = new PostgreSQLContainer<>("postgres:15");

    @Container
    static PostgreSQLContainer<?> targetDb = new PostgreSQLContainer<>("postgres:15");

    @Container
    static KafkaContainer kafka = new KafkaContainer(
        DockerImageName.parse("confluentinc/cp-kafka:7.5.0")
    );

    @Test
    void shouldSyncInventoryChangeFromSourceToTarget() {
        // 1. Insert record into source DB
        // 2. Wait for Debezium to capture change
        // 3. Verify record appears in target DB
        // 4. Verify sync_log entry
    }
}
```

---

## 🛠️ Setup Instructions

### Prerequisites
- Java 17+
- Maven 3.8+
- Docker & Docker Compose
- PostgreSQL client (psql) for testing

### Quick Start

1. **Clone and build the project:**
```bash
git clone <repo-url>
cd market-connector-demo
mvn clean install
```

2. **Start infrastructure services:**
```bash
cd docker
docker-compose up -d
```

This starts:
- PostgreSQL (source DB) on port 5432
- PostgreSQL (target DB) on port 5433
- Kafka on port 9092
- Kafka Connect (Debezium) on port 8083
- Kafka UI on port 8080

3. **Register Debezium connector:**
```bash
cd docker/debezium
./register-connector.sh
```

4. **Verify connector is running:**
```bash
curl http://localhost:8083/connectors/inventory-connector/status
```

5. **Start Spring Boot application:**
```bash
cd ../..
mvn spring-boot:run -Dspring-boot.run.profiles=dev
```

6. **Test the flow:**
```bash
# Insert test data into source DB
psql -h localhost -p 5432 -U pos_user -d pos_db
INSERT INTO inventory (product_id, sku, quantity, store_id)
VALUES ('PROD-001', 'SKU-001', 100, 'STORE-A');

# Check if it synced to target DB
psql -h localhost -p 5433 -U integration_user -d integration_db
SELECT * FROM inventory_cache WHERE product_id = 'PROD-001';

# Check sync logs
SELECT * FROM sync_log ORDER BY timestamp DESC LIMIT 10;
```

---

## 📊 Success Criteria

This POC is successful if we can demonstrate:

✅ **Sub-second latency** - Changes appear in target DB within 1 second
✅ **Zero data loss** - All INSERT/UPDATE/DELETE operations are captured
✅ **Failure recovery** - Failed events are stored in DLQ for manual review
✅ **No POS impact** - Source DB shows no performance degradation
✅ **Monitoring works** - Health checks and metrics accurately reflect system state
✅ **Testing coverage** - >80% code coverage with meaningful tests

---

## 🚧 Known Limitations (POC Scope)

- Only syncs `inventory` table (1 table for simplicity)
- No authentication/authorization on APIs
- No data transformation logic (simple 1:1 replication)
- Single Kafka partition (no horizontal scaling)
- Manual DLQ resolution (no auto-retry mechanism)
- No schema evolution handling

---

## 📚 Additional Resources

- [Debezium PostgreSQL Connector Documentation](https://debezium.io/documentation/reference/stable/connectors/postgresql.html)
- [Spring Kafka Documentation](https://docs.spring.io/spring-kafka/reference/)
- [CDC Pattern Best Practices](./docs/CDC-FLOW.md)
- [Testcontainers Guide](https://www.testcontainers.org/)

---

## 👥 Contributors

- Development Team - Initial POC implementation
- Architecture Team - Design review and validation

---

## 📝 License

Internal R&D Project - Proprietary