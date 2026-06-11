#!/bin/bash

# FIX 1: Write logs to a directory owned by ubuntu instead of system root
mkdir -p /home/ubuntu/logs
exec > >(tee -a /home/ubuntu/logs/stop_app.log) 2>&1

cd /app
echo "Stopping containers..."

# FIX 2: Use sudo so the ubuntu user has permissions to run docker compose commands
sudo docker compose down || true

echo "Stopped"