#!/bin/bash
set -e

# FIX 1: Write logs to a directory owned by ubuntu (or use sudo for /var/log)
mkdir -p /home/ubuntu/logs
exec > >(tee -a /home/ubuntu/logs/start_app.log) 2>&1

# FIX 2: Ensure /app exists and is fully owned by the ubuntu user
sudo mkdir -p /app
sudo chown -R ubuntu:ubuntu /app
cd /app

echo "Starting deployment..."

# 3. Load image tags from deployment bundle
# CodeDeploy extracts files to the deployment-archive directory. 
# We reference the bundle's absolute path to find deploy-env.sh safely.
BUNDLE_DIR=$(dirname "$(readlink -f "$0")")/..
source "$BUNDLE_DIR/deploy-env.sh"

# 4. Fetch DB URL from SSM
DB_URL=$(aws ssm get-parameter \
  --name "/gocart/prod/database_url" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text \
  --region ap-south-1)

# 5. Write .env (Now safe since ubuntu owns /app)
# printf "NESTJS_IMAGE_TAG=%s\nNEXTJS_IMAGE_TAG=%s\nDATABASE_URL=%s\nNEXT_PUBLIC_API_URL=/api\n" \
#   "$NESTJS_IMAGE_TAG" "$NEXTJS_IMAGE_TAG" "$DB_URL" > .env

# Update the printf block in scripts/start_app.sh to include INTERNAL_BACKEND_URL
printf "NESTJS_IMAGE_TAG=%s\nNEXTJS_IMAGE_TAG=%s\nDATABASE_URL=%s\nNEXT_PUBLIC_API_URL=/api\nINTERNAL_BACKEND_URL=http://localhost:3001/api/health\n" \
  "$NESTJS_IMAGE_TAG" "$NEXTJS_IMAGE_TAG" "$DB_URL" > .env


# Copy the docker-compose.yml from the bundle to the /app directory
cp "$BUNDLE_DIR/docker-compose.yml" /app/

# 6. Authenticate with GHCR
aws ssm get-parameter \
  --name "/github/ghcr/token" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text \
  --region ap-south-1 | sudo docker login ghcr.io -u lijo-cloud --password-stdin

# 7. Pull and start both services
# FIX: Added 'sudo' to allow the ubuntu user to access the docker daemon socket
sudo docker compose pull
sudo docker compose up -d

echo "Waiting for services..."

# 8. Check NestJS on 3001
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

# 9. Check Next.js on 3000
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

# 10. Cleanup
sudo docker image prune -af --filter "until=24h" || true
echo "✅ Deployment successful"