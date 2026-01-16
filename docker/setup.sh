#!/bin/bash
# note run 'chmod +x setup.sh' to make this executable

set -e  # Exit on error

# Load variables
if [ ! -f .env ]; then
    echo "❌ Error: .env file not found!"
    echo "Please create .env file first. See SETUP_GUIDE.md"
    exit 1
fi

export $(grep -v '^#' .env | xargs)

echo "🚀 Starting Market Connector Infrastructure..."
docker-compose up -d

echo ""
echo "⏳ Waiting for services to be healthy..."
echo "   This may take 60-90 seconds on first run..."
echo ""

# Wait for services with timeout
TIMEOUT=120
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    ZOOKEEPER_HEALTHY=$(docker inspect --format='{{.State.Health.Status}}' market-connector-zookeeper 2>/dev/null || echo "starting")
    KAFKA_HEALTHY=$(docker inspect --format='{{.State.Health.Status}}' market-connector-kafka 2>/dev/null || echo "starting")
    POSTGRES_HEALTHY=$(docker inspect --format='{{.State.Health.Status}}' market-connector-postgres-target 2>/dev/null || echo "starting")
    DEBEZIUM_HEALTHY=$(docker inspect --format='{{.State.Health.Status}}' market-connector-debezium 2>/dev/null || echo "starting")
    
    # Clear line and print status (no newlines in variables)
    printf "\r   Zookeeper: %-10s | Kafka: %-10s | PostgreSQL: %-10s | Debezium: %-10s" \
        "$ZOOKEEPER_HEALTHY" "$KAFKA_HEALTHY" "$POSTGRES_HEALTHY" "$DEBEZIUM_HEALTHY"
    
    if [ "$ZOOKEEPER_HEALTHY" = "healthy" ] && \
       [ "$KAFKA_HEALTHY" = "healthy" ] && \
       [ "$POSTGRES_HEALTHY" = "healthy" ] && \
       [ "$DEBEZIUM_HEALTHY" = "healthy" ]; then
        echo ""
        echo ""
        echo "✅ All services are healthy!"
        break
    fi
    
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo ""
    echo ""
    echo "❌ Timeout waiting for services to be healthy!"
    echo ""
    echo "🔍 Service Status:"
    docker-compose ps
    echo ""
    echo "📋 Check logs with:"
    echo "  docker logs market-connector-zookeeper | tail -20"
    echo "  docker logs market-connector-kafka | tail -20"
    echo "  docker logs market-connector-postgres-target | tail -20"
    echo "  docker logs market-connector-debezium | tail -20"
    exit 1
fi

echo ""
echo "🔗 Registering Debezium Source Connector..."
envsubst < debezium-connector.json.template > generated-connector.json

# Debug: Show generated config
echo "📋 Generated connector config:"
cat generated-connector.json | jq -r '.name'
echo "   Tables: $(cat generated-connector.json | jq -r '.config."table.include.list"')"

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @generated-connector.json)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "409" ]; then
    echo "✅ Source connector registered (HTTP $HTTP_CODE)"
else
    echo "❌ Failed to register source connector (HTTP $HTTP_CODE)"
    echo "$BODY" | jq
    exit 1
fi

echo ""
echo "⏳ Waiting 15 seconds for initial snapshot to start..."
sleep 15

echo ""
echo "🔗 Registering JDBC Sink Connector..."

SINK_TEMPLATES=(
    "jdbc-sink-inventory.json.template"
    "jdbc-sink-productitem.json.template"
)

for TEMPLATE in "${SINK_TEMPLATES[@]}"; do
    if [ ! -f "$TEMPLATE" ]; then
        echo "⚠️  Skipping $TEMPLATE (file not found)"
        continue
    fi
    
    GENERATED_FILE="generated-${TEMPLATE%.template}"
    
    # Generate config from template
    envsubst < "$TEMPLATE" > "$GENERATED_FILE"
    
    CONNECTOR_NAME=$(jq -r '.name' "$GENERATED_FILE")
    TABLE_NAME=$(jq -r '.config."table.name.format"' "$GENERATED_FILE")
    
    echo "📋 Registering: $CONNECTOR_NAME"
    echo "   Table: $TABLE_NAME"
    
    # Register connector
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST http://localhost:8083/connectors \
        -H "Content-Type: application/json" \
        -d @"$GENERATED_FILE")
    
    if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "409" ]; then
        echo "✅ Sink connector registered (HTTP $HTTP_CODE)"
    else
        echo "❌ Failed to register sink connector (HTTP $HTTP_CODE)"
    fi
    
    echo ""
done

echo "⏳ Waiting for initial sync (10 seconds)..."
sleep 10

echo ""
echo "✅ Setup Complete!"
echo ""
echo "📊 Quick Status Check:"
echo ""

SOURCE_STATUS=$(curl -s http://localhost:8083/connectors/${SOURCE_CONNECTOR_NAME}/status)

echo "Source Connector: $(echo $SOURCE_STATUS | jq -r '.connector.state')"
echo "  └─ Task 0: $(echo $SOURCE_STATUS | jq -r '.tasks[0].state // "N/A"')"

echo ""
echo "Sink Connectors:"
for TEMPLATE in "${SINK_TEMPLATES[@]}"; do
    CONNECTOR_NAME=$(jq -r '.name' "$TEMPLATE" | envsubst)
    SINK_STATUS=$(curl -s http://localhost:8083/connectors/${CONNECTOR_NAME}/status 2>/dev/null)
    if [ ! -z "$SINK_STATUS" ]; then
        echo "  ${CONNECTOR_NAME}: $(echo $SINK_STATUS | jq -r '.connector.state')"
        echo "    └─ Task 0: $(echo $SINK_STATUS | jq -r '.tasks[0].state // "N/A"')"
    fi
done

echo ""
echo "📊 Monitoring Commands:"
echo ""
echo "1. Check connector status:"
echo "   curl -s http://localhost:8083/connectors/${SOURCE_CONNECTOR_NAME}/status | jq"
echo "   curl -s http://localhost:8083/connectors/jdbc-sink-inventory/status | jq"
echo "   curl -s http://localhost:8083/connectors/jdbc-sink-productitem/status | jq"
echo ""
echo "2. List all Kafka topics:"
echo "   docker exec market-connector-kafka kafka-topics --list --bootstrap-server localhost:9092"
echo ""
echo "3. Check synced record counts:"
for TABLE in $(echo $TABLE_INCLUDE_LIST | tr ',' ' '); do
    TABLE_NAME=$(echo $TABLE | cut -d'.' -f2)
    echo "   docker exec market-connector-postgres-target psql -U ${TARGET_DB_USER} -d ${TARGET_DB_NAME} -c 'SELECT COUNT(*) FROM \"${TABLE_NAME}\";'"
done
echo ""
echo "4. Watch Kafka messages (first table):"
FIRST_TABLE=$(echo $TABLE_INCLUDE_LIST | cut -d',' -f1)
echo "   docker exec market-connector-kafka kafka-console-consumer \\"
echo "     --bootstrap-server localhost:9092 \\"
echo "     --topic ${TOPIC_PREFIX}.${FIRST_TABLE} \\"
echo "     --from-beginning --max-messages 5"
echo ""
echo "5. View connector logs:"
echo "   docker logs -f market-connector-debezium"
echo ""
echo "6. Connect to target database (DBeaver):"
echo "   Host: localhost"
echo "   Port: 5433"
echo "   Database: ${TARGET_DB_NAME}"
echo "   Username: ${TARGET_DB_USER}"
echo "   Password: (see .env file)"
echo