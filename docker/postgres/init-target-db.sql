-- Target database initialization
-- Tables will be created AUTOMATICALLY by JDBC Sink Connector

-- Create sync monitoring table
CREATE TABLE IF NOT EXISTS sync_log (
    id SERIAL PRIMARY KEY,
    connector_name VARCHAR(100),
    operation_type VARCHAR(20),
    records_processed INTEGER,
    status VARCHAR(50),
    error_message TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert initial log entry
INSERT INTO sync_log (connector_name, operation_type, records_processed, status)
VALUES ('jdbc-sink-all-tables', 'INITIALIZATION', 0, 'READY');

-- Display confirmation
SELECT 'Target database initialized successfully!' AS status;