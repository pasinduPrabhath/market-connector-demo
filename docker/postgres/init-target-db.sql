-- Integration Service Database Schema
-- This database will receive real-time synced data from POS via Kafka

-- ============================================================================
-- INVENTORY CACHE TABLE
-- Simplified version of POS inventory table with only fields needed for APIs
-- ============================================================================
CREATE TABLE IF NOT EXISTS inventory_cache (
    -- Internal primary key
    id BIGSERIAL PRIMARY KEY,
    
    -- Core fields from POS inventory table
    inventoryid BIGINT NOT NULL UNIQUE,
    productitem BIGINT,
    quantity BIGINT,
    
    -- Location tracking
    fromlocation INTEGER,
    tolocation INTEGER,
    frombin INTEGER,
    tobin INTEGER,
    fromspeciallocation INTEGER,
    tospeciallocation INTEGER,
    
    -- Pricing information (for third-party sync)
    currentcost DOUBLE PRECISION,
    lastcost DOUBLE PRECISION,
    retailsalesprice DOUBLE PRECISION,
    list DOUBLE PRECISION,
    lpprice DOUBLE PRECISION,
    lppricecurrency INTEGER,
    nfbrsp DOUBLE PRECISION,
    reserveprice1 DOUBLE PRECISION,
    reserveprice2 DOUBLE PRECISION,
    reserveprice3 DOUBLE PRECISION,
    
    -- Transaction tracking
    movementdate DATE,
    expirydate DATE,
    transactioncode VARCHAR(255),
    transactionnumber VARCHAR(255),
    doc_number VARCHAR(255),
    doc_type INTEGER,
    remark TEXT,
    
    -- Movement modes
    incomingmode INTEGER,
    outgoingmode INTEGER,
    
    -- Business logic flags
    intransit INTEGER DEFAULT 0,
    offline INTEGER DEFAULT 0,
    reserveinventory INTEGER DEFAULT 0,
    customer INTEGER DEFAULT 0,
    purpose INTEGER DEFAULT 0,
    purposestatus INTEGER DEFAULT 0,
    purposedocument VARCHAR(255),
    
    -- Multi-tenant support
    organisation_id INTEGER DEFAULT 1,
    
    -- Original timestamp from POS
    createdatetime TIMESTAMP,
    
    -- CDC metadata (added by our sync service)
    last_synced_at TIMESTAMP DEFAULT NOW(),
    cdc_event_timestamp TIMESTAMP,
    cdc_operation VARCHAR(10),  -- 'c' = create, 'u' = update, 'd' = delete, 'r' = read
    
    -- Audit fields
    sync_count INTEGER DEFAULT 1,
    first_synced_at TIMESTAMP DEFAULT NOW()
);

-- ============================================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_inventory_cache_inventoryid ON inventory_cache(inventoryid);
CREATE INDEX IF NOT EXISTS idx_inventory_cache_productitem ON inventory_cache(productitem);
CREATE INDEX IF NOT EXISTS idx_inventory_cache_quantity ON inventory_cache(quantity);
CREATE INDEX IF NOT EXISTS idx_inventory_cache_organisation ON inventory_cache(organisation_id);
CREATE INDEX IF NOT EXISTS idx_inventory_cache_last_synced ON inventory_cache(last_synced_at);
CREATE INDEX IF NOT EXISTS idx_inventory_cache_transactioncode ON inventory_cache(transactioncode);
CREATE INDEX IF NOT EXISTS idx_inventory_cache_movementdate ON inventory_cache(movementdate);
CREATE INDEX IF NOT EXISTS idx_inventory_cache_intransit ON inventory_cache(intransit);
CREATE INDEX IF NOT EXISTS idx_inventory_cache_offline ON inventory_cache(offline);

-- Composite indexes for common queries
CREATE INDEX IF NOT EXISTS idx_inventory_cache_org_product ON inventory_cache(organisation_id, productitem);
CREATE INDEX IF NOT EXISTS idx_inventory_cache_location ON inventory_cache(fromlocation, tolocation);

-- ============================================================================
-- SYNC LOG TABLE
-- Tracks all sync operations for monitoring and debugging
-- ============================================================================
CREATE TABLE IF NOT EXISTS sync_log (
    id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT NOW(),
    table_name VARCHAR(100),
    operation VARCHAR(20),      -- 'INSERT', 'UPDATE', 'DELETE', 'SNAPSHOT'
    record_id VARCHAR(100),     -- inventoryid being synced
    status VARCHAR(20),         -- 'SUCCESS', 'FAILED', 'RETRY'
    error_message TEXT,
    event_timestamp BIGINT,     -- Original Debezium event timestamp
    processing_time_ms INTEGER, -- How long it took to process
    kafka_offset BIGINT,        -- Kafka message offset
    kafka_partition INTEGER     -- Kafka partition
);

CREATE INDEX IF NOT EXISTS idx_sync_log_timestamp ON sync_log(timestamp);
CREATE INDEX IF NOT EXISTS idx_sync_log_status ON sync_log(status);
CREATE INDEX IF NOT EXISTS idx_sync_log_table_name ON sync_log(table_name);
CREATE INDEX IF NOT EXISTS idx_sync_log_record_id ON sync_log(record_id);

-- ============================================================================
-- THIRD-PARTY MAPPINGS TABLE
-- Maps internal product IDs to external marketplace IDs (Shopify, Lazada, etc.)
-- ============================================================================
CREATE TABLE IF NOT EXISTS third_party_mappings (
    id BIGSERIAL PRIMARY KEY,
    productitem BIGINT NOT NULL,           -- Internal product ID
    third_party VARCHAR(50) NOT NULL,      -- 'shopify', 'lazada', 'amazon'
    external_product_id VARCHAR(255),      -- External marketplace product ID
    external_sku VARCHAR(255),             -- External marketplace SKU
    external_variant_id VARCHAR(255),      -- For products with variants
    sync_enabled BOOLEAN DEFAULT TRUE,     -- Enable/disable sync per product
    last_sync_at TIMESTAMP,
    last_sync_status VARCHAR(50),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    metadata JSONB,                        -- Additional marketplace-specific data
    
    UNIQUE(productitem, third_party)
);

CREATE INDEX IF NOT EXISTS idx_third_party_mappings_productitem ON third_party_mappings(productitem);
CREATE INDEX IF NOT EXISTS idx_third_party_mappings_third_party ON third_party_mappings(third_party);
CREATE INDEX IF NOT EXISTS idx_third_party_mappings_sync_enabled ON third_party_mappings(sync_enabled);
CREATE INDEX IF NOT EXISTS idx_third_party_mappings_external_id ON third_party_mappings(external_product_id);

-- ============================================================================
-- DEAD LETTER QUEUE TABLE
-- Stores failed sync events for manual investigation/retry
-- ============================================================================
CREATE TABLE IF NOT EXISTS sync_dead_letter_queue (
    id BIGSERIAL PRIMARY KEY,
    failed_at TIMESTAMP DEFAULT NOW(),
    table_name VARCHAR(100),
    operation VARCHAR(20),
    kafka_topic VARCHAR(255),
    kafka_partition INTEGER,
    kafka_offset BIGINT,
    raw_event_json TEXT,           -- Original Kafka message
    error_message TEXT,
    retry_count INTEGER DEFAULT 0,
    last_retry_at TIMESTAMP,
    resolved BOOLEAN DEFAULT FALSE,
    resolved_at TIMESTAMP,
    resolved_by VARCHAR(100)
);

CREATE INDEX IF NOT EXISTS idx_dlq_failed_at ON sync_dead_letter_queue(failed_at);
CREATE INDEX IF NOT EXISTS idx_dlq_resolved ON sync_dead_letter_queue(resolved);
CREATE INDEX IF NOT EXISTS idx_dlq_table_name ON sync_dead_letter_queue(table_name);

-- ============================================================================
-- CONNECTOR HEALTH TABLE
-- Monitors Debezium connector health and lag
-- ============================================================================
CREATE TABLE IF NOT EXISTS connector_health (
    id BIGSERIAL PRIMARY KEY,
    check_time TIMESTAMP DEFAULT NOW(),
    connector_name VARCHAR(100),
    status VARCHAR(50),            -- 'RUNNING', 'PAUSED', 'FAILED'
    lag_seconds INTEGER,           -- How far behind is the connector
    last_event_timestamp BIGINT,
    total_events_processed BIGINT,
    error_count INTEGER DEFAULT 0,
    last_error TEXT
);

CREATE INDEX IF NOT EXISTS idx_connector_health_check_time ON connector_health(check_time);
CREATE INDEX IF NOT EXISTS idx_connector_health_connector_name ON connector_health(connector_name);

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO integration_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO integration_user;
GRANT USAGE ON SCHEMA public TO integration_user;

-- ============================================================================
-- SAMPLE DATA FOR TESTING (Optional - Remove in production)
-- ============================================================================
-- Insert a test record to verify database connectivity
INSERT INTO sync_log (table_name, operation, status, record_id, processing_time_ms)
VALUES ('system', 'INIT', 'SUCCESS', 'database_initialized', 0);

-- ============================================================================
-- VIEWS FOR MONITORING (Optional but useful)
-- ============================================================================

-- View: Recent sync activity
CREATE OR REPLACE VIEW v_recent_syncs AS
SELECT 
    table_name,
    operation,
    status,
    COUNT(*) as count,
    AVG(processing_time_ms) as avg_processing_time,
    MAX(timestamp) as last_sync
FROM sync_log
WHERE timestamp > NOW() - INTERVAL '1 hour'
GROUP BY table_name, operation, status
ORDER BY last_sync DESC;

-- View: Failed syncs requiring attention
CREATE OR REPLACE VIEW v_failed_syncs AS
SELECT 
    id,
    timestamp,
    table_name,
    operation,
    record_id,
    error_message,
    processing_time_ms
FROM sync_log
WHERE status = 'FAILED'
  AND timestamp > NOW() - INTERVAL '24 hours'
ORDER BY timestamp DESC;

-- View: Inventory sync statistics
CREATE OR REPLACE VIEW v_inventory_sync_stats AS
SELECT 
    organisation_id,
    COUNT(*) as total_records,
    SUM(quantity) as total_quantity,
    COUNT(DISTINCT productitem) as unique_products,
    MAX(last_synced_at) as last_sync_time,
    MIN(cdc_event_timestamp) as oldest_event,
    MAX(cdc_event_timestamp) as newest_event
FROM inventory_cache
GROUP BY organisation_id;

-- ============================================================================
-- FUNCTIONS FOR MAINTENANCE
-- ============================================================================

-- Function: Clean old sync logs (keep last 30 days)
CREATE OR REPLACE FUNCTION cleanup_old_sync_logs()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM sync_log
    WHERE timestamp < NOW() - INTERVAL '30 days';
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Function: Get sync lag for a specific product
CREATE OR REPLACE FUNCTION get_product_sync_lag(p_productitem BIGINT)
RETURNS INTERVAL AS $$
DECLARE
    sync_lag INTERVAL;
BEGIN
    SELECT NOW() - cdc_event_timestamp INTO sync_lag
    FROM inventory_cache
    WHERE productitem = p_productitem
    ORDER BY cdc_event_timestamp DESC
    LIMIT 1;
    
    RETURN sync_lag;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- INITIAL SYSTEM CHECK
-- ============================================================================
DO $$ 
BEGIN
    RAISE NOTICE '✅ Integration Database Schema Created Successfully';
    RAISE NOTICE '📊 Tables created: inventory_cache, sync_log, third_party_mappings, sync_dead_letter_queue, connector_health';
    RAISE NOTICE '🔍 Views created: v_recent_syncs, v_failed_syncs, v_inventory_sync_stats';
    RAISE NOTICE '⚙️  Functions created: cleanup_old_sync_logs(), get_product_sync_lag()';
    RAISE NOTICE '👤 Permissions granted to: integration_user';
END $$;
