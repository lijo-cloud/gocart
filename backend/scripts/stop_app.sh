#!/bin/bash

mkdir -p /home/ubuntu/logs
exec > >(tee -a /home/ubuntu/logs/stop_app.log) 2>&1

echo "Stopping backend container..."

sudo docker rm -f gocart-api || true

echo "Backend stopped"