#!/bin/bash
set -e

exec > /var/log/start_app.log 2>&1

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

docker compose down --remove-orphans || true
docker compose pull
docker compose up -d --force-recreate

echo "Waiting for app..."

sleep 20

curl -f http://localhost:3000/api/health

echo "Deployment successful"