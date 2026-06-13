#!/bin/bash

mkdir -p /home/ubuntu/logs
exec > >(tee -a /home/ubuntu/logs/stop_app.log) 2>&1

echo "Stopping frontend container..."

sudo docker rm -f gocart-web || true

echo "Frontend stopped"