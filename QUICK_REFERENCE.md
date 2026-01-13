# 🚀 Quick Reference - Market Connector Demo


## 🔧 Common Commands

### Start/Stop
```bash
# Start everything
cd ~/Documents/GitHub/market-connector-demo/docker
./setup.sh

# Stop everything
docker-compose down

# Stop and delete all data
./cleanup.sh
```

### Check Status
```bash
# All containers
docker-compose ps

# Connectors
curl -s http://localhost:8083/connectors | jq
curl -s http://localhost:8083/connectors/pos-inventory-connector/status | jq
curl -s http://localhost:8083/connectors/jdbc-sink-inventory/status | jq

# Record count
docker exec -it market-connector-postgres-target \
  psql -U integration_user -d integration_db \
  -c "SELECT COUNT(*) FROM inventory_cache;"
```

### View Logs
```bash
# All services
docker-compose logs -f

# Specific service
docker logs -f market-connector-debezium
docker logs -f market-connector-kafka
docker logs -f market-connector-postgres-target
```

### Troubleshooting
```bash
# Restart connector
curl -X POST http://localhost:8083/connectors/pos-inventory-connector/restart

# Delete connector
curl -X DELETE http://localhost:8083/connectors/pos-inventory-connector

# Re-register connector
cd ~/Documents/GitHub/market-connector-demo/docker
export $(grep -v '^#' .env | xargs)
envsubst < debezium-connector.json.template > generated-connector.json
curl -X POST http://localhost:8083/connectors -H "Content-Type: application/json" -d @generated-connector.json
```
