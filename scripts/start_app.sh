#!/bin/bash
set -euo pipefail

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

exec > /var/log/start_app.log 2>&1

cd /app

echo "Starting deployment..."

if [ ! -f deploy-env.sh ]; then
  echo "Missing deploy-env.sh"
  exit 1
fi

source deploy-env.sh

if [ -z "${IMAGE_TAG:-}" ]; then
  echo "IMAGE_TAG missing"
  exit 1
fi

DB_URL=$(aws ssm get-parameter \
  --name "/gocart/prod/database_url" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text \
  --region ap-south-1)

printf "DATABASE_URL=%s\nIMAGE_TAG=%s\n" "$DB_URL" "$IMAGE_TAG" > .env

GHCR_TOKEN=$(aws ssm get-parameter \
  --name "/github/ghcr/token" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text \
  --region ap-south-1 || true)

if [ -z "$GHCR_TOKEN" ]; then
  echo "GHCR token missing"
  exit 1
fi

echo "$GHCR_TOKEN" | docker login ghcr.io -u lijo-cloud --password-stdin

docker compose down || true
docker compose pull || true
docker compose up -d

echo "Waiting for health check..."

for i in $(seq 1 30); do
  if curl -f http://localhost:3000/api/health >/dev/null 2>&1; then
    echo "Deployment successful"
    exit 0
  fi
  sleep 5
done

echo "Health check failed"
exit 1