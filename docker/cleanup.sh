#!/bin/bash

echo "🧹 Cleaning up Market Connector Infrastructure..."
echo ""

# Stop all containers
echo "⏹️  Stopping containers..."
docker-compose down

# Remove all volumes (this deletes all data)
echo "🗑️  Removing volumes and data..."
docker-compose down -v

# Remove generated files
echo "📄 Removing generated configuration files..."
rm -f generated-connector.json
rm -f generated-jdbc-sink.json

# Optional: Remove all related Docker images to force fresh download
read -p "🔄 Do you want to remove Docker images too? (forces re-download) [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️  Removing Docker images..."
    docker-compose down --rmi all
fi

# Optional: Prune unused Docker resources
read -p "🧹 Do you want to prune unused Docker resources? (recommended) [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️  Pruning Docker system..."
    docker system prune -f
fi

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "🚀 To start fresh, run:"
echo "   ./setup.sh"
