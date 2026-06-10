#!/bin/bash
exec > >(tee -a /var/log/stop_app.log) 2>&1
cd /app
echo "Stopping containers..."
docker compose down || true
echo "Stopped"