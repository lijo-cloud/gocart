#!/bin/bash
set -e

exec > /var/log/start_app.log 2>&1

cd /app

echo "Starting deployment..."

# Validate image tag
if [ ! -f deploy-env.sh ]; then
  echo "Missing deploy-env.sh"
  exit 1
fi

source deploy-env.sh

if [ -z "$IMAGE_TAG" ]; then
  echo "IMAGE_TAG missing"
  exit 1
fi

# DB
DB_URL=$(aws ssm get-parameter \
  --name "/gocart/prod/database_url" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text \
  --region ap-south-1)

printf "DATABASE_URL=%s\nIMAGE_TAG=%s\n" "$DB_URL" "$IMAGE_TAG" > .env

# GHCR login
aws ssm get-parameter \
  --name "/github/ghcr/token" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text \
  --region ap-south-1 | docker login ghcr.io -u lijo-cloud --password-stdin

# deploy
docker compose down || true
docker compose pull || true
docker compose up -d

# health check
sleep 20
curl -f http://localhost:3000/api/health || exit 1

echo "Deployment successful"