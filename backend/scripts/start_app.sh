#!/bin/bash
set -e

# ----------------------------
# Logging
# ----------------------------
mkdir -p /home/ubuntu/logs
exec > >(tee -a /home/ubuntu/logs/start_app.log) 2>&1

echo "Starting backend deployment..."

# ----------------------------
# Paths
# ----------------------------
BUNDLE_DIR=$(dirname "$(readlink -f "$0")")/..
source "$BUNDLE_DIR/deploy-env.sh"

# ----------------------------
# Safety checks
# ----------------------------
if [ -z "$NESTJS_IMAGE_TAG" ]; then
  echo "ERROR: NESTJS_IMAGE_TAG is NOT set"
  exit 1
fi

echo "Using image: $NESTJS_IMAGE_TAG"

# ----------------------------
# Fetch secrets
# ----------------------------
DB_URL=$(aws ssm get-parameter \
  --name "/gocart/prod/database_url" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text \
  --region ap-south-1)

aws ssm get-parameter \
  --name "/github/ghcr/token" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text \
  --region ap-south-1 | \
  sudo docker login ghcr.io -u lijo-cloud --password-stdin

# ----------------------------
# Docker pull (FIXED)
# ----------------------------
echo "Pulling backend image..."
sudo env NESTJS_IMAGE_TAG="$NESTJS_IMAGE_TAG" docker pull "$NESTJS_IMAGE_TAG"

# ----------------------------
# Stop old container
# ----------------------------
echo "Removing old backend container..."
sudo docker rm -f gocart-api || true

# ----------------------------
# Start container (FIXED)
# ----------------------------
echo "Starting backend container..."

sudo env NESTJS_IMAGE_TAG="$NESTJS_IMAGE_TAG" docker run -d \
  --name gocart-api \
  --restart unless-stopped \
  -p 3001:3001 \
  -e DATABASE_URL="$DB_URL" \
  "$NESTJS_IMAGE_TAG"

# ----------------------------
# Health check
# ----------------------------
echo "Waiting for backend health check..."

HEALTHY=false

for i in $(seq 1 18); do
  if curl -sf http://localhost:3001/api/health >/dev/null 2>&1; then
    HEALTHY=true
    break
  fi

  echo "Backend attempt $i failed, retrying..."
  sleep 10
done

if [ "$HEALTHY" = false ]; then
  echo "Backend health check failed"
  sudo docker logs gocart-api || true
  exit 1
fi

echo "Backend healthy"

# ----------------------------
# Cleanup
# ----------------------------
sudo docker image prune -af --filter "until=24h" || true

echo "Backend deployment successful"