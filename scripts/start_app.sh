#!/bin/bash
set -e
exec > >(tee -a /var/log/start_app.log) 2>&1
cd /app

echo "Starting deployment..."

# 1. Load image tags from deployment bundle
source deploy-env.sh

# 2. Fetch DB URL from SSM
DB_URL=$(aws ssm get-parameter \
  --name "/gocart/prod/database_url" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text \
  --region ap-south-1)

# 3. Write .env — both image tags + DB URL
printf "NESTJS_IMAGE_TAG=%s\nNEXTJS_IMAGE_TAG=%s\nDATABASE_URL=%s\nNEXT_PUBLIC_API_URL=/api\n" \
  "$NESTJS_IMAGE_TAG" "$NEXTJS_IMAGE_TAG" "$DB_URL" > .env

# 4. Authenticate with GHCR
aws ssm get-parameter \
  --name "/github/ghcr/token" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text \
  --region ap-south-1 | docker login ghcr.io -u lijo-cloud --password-stdin

# 5. Pull and start both services
docker compose pull
docker compose up -d

echo "Waiting for services..."

# 6. Check NestJS on 3001
HEALTHY=false
for i in $(seq 1 12); do
  if curl -sf http://localhost:3001/api/health > /dev/null 2>&1; then
    HEALTHY=true; break
  fi
  echo "NestJS attempt $i failed, retrying in 10s..."
  sleep 10
done
if [ "$HEALTHY" = false ]; then
  echo "❌ NestJS health check failed — rolling back"
  docker compose down
  exit 1
fi
echo "✅ NestJS healthy"

# 7. Check Next.js on 3000
HEALTHY=false
for i in $(seq 1 12); do
  if curl -sf http://localhost:3000/api/health > /dev/null 2>&1; then
    HEALTHY=true; break
  fi
  echo "Next.js attempt $i failed, retrying in 10s..."
  sleep 10
done
if [ "$HEALTHY" = false ]; then
  echo "❌ Next.js health check failed — rolling back"
  docker compose down
  exit 1
fi
echo "✅ Next.js healthy"

# 8. Cleanup
docker image prune -af --filter "until=24h" || true
echo "✅ Deployment successful"