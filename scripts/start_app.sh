#!/bin/bash
set -e
cd /app

# 1. Load variables and authenticate with GHCR
if [ -f deploy-env.sh ]; then source deploy-env.sh; fi
if [ -z "$IMAGE_TAG" ]; then exit 1; fi

DB_URL=$(aws ssm get-parameter --name "/gocart/prod/database_url" --with-decryption --query "Parameter.Value" --output text --region ap-south-1)
printf "DATABASE_URL=%s\nIMAGE_TAG=%s\n" "$DB_URL" "$IMAGE_TAG" > /app/.env
chmod 600 /app/.env

GHCR_TOKEN=$(aws ssm get-parameter --name "/github/ghcr/token" --with-decryption --query "Parameter.Value" --output text --region ap-south-1)
echo "$GHCR_TOKEN" | docker login ghcr.io -u lijo-cloud --password-stdin
docker compose pull

# 2. Determine which container slot is currently running on the host
if docker ps --format '{{.Names}}' | grep -q "gocart-green"; then
    TARGET_SLOT="app-blue"
    TARGET_PORT="3000"
    OLD_SLOT="app-green"
else
    TARGET_SLOT="app-green"
    TARGET_PORT="3001"
    OLD_SLOT="app-blue"
fi

echo "🚀 Deploying code to idle slot: $TARGET_SLOT on host port $TARGET_PORT..."

# 3. Create a dynamic runtime compose profile to avoid port conflicts
cat > docker-compose.yml <<EOF
version: '3.8'
services:
  app-blue:
    image: $IMAGE_TAG
    restart: unless-stopped
    ports:
      - "3000:3000"
    env_file: .env
  app-green:
    image: $IMAGE_TAG
    restart: unless-stopped
    ports:
      - "3001:3000"
    env_file: .env
EOF

# 4. Start ONLY the fresh idle slot container
docker compose up -d $TARGET_SLOT

# 5. Wait for the new container instance to clear its health check
echo "⏳ Running health validation on port $TARGET_PORT..."
HEALTHY=false
for i in $(seq 1 15); do
  if curl -f http://localhost:$TARGET_PORT/api/health >/dev/null 2>&1; then 
    HEALTHY=true
    break
  fi
  sleep 5
done

if [ "$HEALTHY" = false ]; then
  echo "🚨 Health check failed! Stopping broken container."
  docker compose stop $TARGET_SLOT
  exit 1
fi

# 6. Zero Downtime Swap: Update local routing config
# (If using an ALB, the ALB target group handles this naturally. If using local Nginx, uncomment below lines)
# sudo sed -i "s/proxy_pass http:\/\/localhost:[0-9]*/proxy_pass http:\/\/localhost:$TARGET_PORT/g" /etc/nginx/sites-available/default
# sudo systemctl reload nginx

# 7. Stop the old application container safely
echo "🛑 Stopping older container slot: $OLD_SLOT"
docker compose stop $OLD_SLOT || true
docker image prune -af --filter "until=24h" || true

echo "✅ Deployment Successful with zero downtime!"
