#!/bin/bash
set -e

# exec > /var/log/start_app.log 2>&1
exec > >(tee -a /var/log/start_app.log) 2>&1
cd /app

echo "Starting deployment..."

source deploy-env.sh

DB_URL=$(aws ssm get-parameter \
  --name "/gocart/prod/database_url" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text \
  --region ap-south-1)

printf "DATABASE_URL=%s\nIMAGE_TAG=%s\n" "$DB_URL" "$IMAGE_TAG" > .env

aws ssm get-parameter \
  --name "/github/ghcr/token" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text \
  --region ap-south-1 | docker login ghcr.io -u lijo-cloud --password-stdin

cat > docker-compose.yml <<EOF
services:
  app:
    image: $IMAGE_TAG
    restart: unless-stopped
    ports:
      - "3000:3000"
    env_file:
      - .env
EOF

docker compose down || true
docker compose pull
docker compose up -d

echo "Waiting for app..."

# 
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

echo "Deployment successful"