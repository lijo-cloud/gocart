#!/bin/bash
set -e

mkdir -p /home/ubuntu/logs
exec > >(tee -a /home/ubuntu/logs/start_app.log) 2>&1

sudo mkdir -p /app
sudo chown -R ubuntu:ubuntu /app

cd /app

echo "Starting frontend deployment..."

BUNDLE_DIR=$(dirname "$(readlink -f "$0")")/..

source "$BUNDLE_DIR/deploy-env.sh"

aws ssm get-parameter \
  --name "/github/ghcr/token" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text \
  --region ap-south-1 | \
  sudo docker login ghcr.io -u lijo-cloud --password-stdin

echo "Pulling frontend image..."

sudo docker pull "$NEXTJS_IMAGE_TAG"

echo "Removing old frontend container..."

sudo docker rm -f gocart-web || true

echo "Starting frontend container..."

sudo docker run -d \
  --name gocart-web \
  --restart unless-stopped \
  -p 3000:3000 \
  -e NEXT_PUBLIC_API_URL="/api" \
  "$NEXTJS_IMAGE_TAG"

echo "Waiting for frontend health check..."

HEALTHY=false

for i in $(seq 1 18); do
  if curl -sf http://localhost:3000/api/health >/dev/null 2>&1; then
    HEALTHY=true
    break
  fi

  echo "Frontend attempt $i failed, retrying..."
  sleep 10
done

if [ "$HEALTHY" = false ]; then
  echo "Frontend health check failed"
  sudo docker logs gocart-web || true
  exit 1
fi

echo "Frontend healthy"

sudo docker image prune -af --filter "until=24h" || true

echo "Frontend deployment successful"