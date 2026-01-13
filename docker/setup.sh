#!/bin/bash
# note run 'chmod +x setup.sh' to make this executable
# 1. Load variables
export $(grep -v '^#' .env | xargs)

echo "🚀 Starting Market Connector Infrastructure..."
docker-compose up -d

echo "⏳ Waiting for Debezium to be ready (usually 30-45s)..."
until curl -s http://localhost:8083/ > /dev/null; do
  sleep 5
  echo "...still waiting..."
done

echo "🔗 Registering Debezium Connector..."
# This command swaps the ${VAR} in the template with actual values from .env
envsubst < debezium-connector.json.template > generated-connector.json

curl -i -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @generated-connector.json

echo "✅ Setup Complete! You can now watch logs with: docker-compose logs -f or docker exec -it market-connector-kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic pos.public.inventory \
  --from-beginning"