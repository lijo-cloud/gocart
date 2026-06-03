#!/bin/bash
set -e

# exec > /var/log/start_app.log 2>&1
exec > >(tee -a /var/log/start_app.log) 2>&1
cd /app

echo "Starting deployment..."

# 1. Load the target image tag from the deployment bundle
source deploy-env.sh

# 2. Fetch runtime database configuration string
DB_URL=$(aws ssm get-parameter \
  --name "/gocart/prod/database_url" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text \
  --region ap-south-1)

# 3. Construct the .env workspace (Docker Compose automatically reads this)
printf "DATABASE_URL=%s\nIMAGE_TAG=%s\n" "$DB_URL" "$IMAGE_TAG" > .env

# 4. Authenticate with GHCR using enterprise parameters
aws ssm get-parameter \
  --name "/github/ghcr/token" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text \
  --region ap-south-1 | docker login ghcr.io -u lijo-cloud --password-stdin

# 🛑 REMOVED: The 'cat > docker-compose.yml' block is gone.
# Your repository's docker-compose.yml file is now safely preserved!

# 5. Lifecycle execution management
docker compose down || true
docker compose pull
docker compose up -d

echo "Waiting for app..."

# ✅ Retry loop + rollback on failure
HEALTHY=false
for i in $(seq 1 12); do
  if curl -sf http://localhost:3000/api/health; then
    HEALTHY=true; break
  fi
  echo "Attempt $i failed, retrying in 10s..."
  sleep 10
done

if [ "$HEALTHY" = false ]; then
  echo "Health check failed — rolling back"
  docker compose down
  exit 1   # CodeDeploy sees non-zero exit and triggers auto-rollback
fi

# 6. Disk optimization cleanup step
docker image prune -af --filter "until=24h" || true

echo "Deployment successful"
