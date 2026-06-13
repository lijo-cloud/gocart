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



# ==============================================================================
# AUTOMATED PRODUCTION MONITORING DEPLOYMENT (GRAFANA ALLOY - FRONTEND)
# ==============================================================================
echo "Initializing centralized monitoring layer for Frontend..."

# 1. Register the official Grafana package repository keys securely
sudo mkdir -p /etc/apt/keyrings/
wget -q -O - https://grafana.com | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list

# 2. Update cache and install Grafana Alloy agent engine
sudo apt-get update -y
sudo apt-get install -y alloy

# 3. Define the Staging Monitoring Server host coordinate
MONITORING_HOST_IP="12.0.3.22"

# 4. Write the clean pipeline monitoring configurations
sudo cat <<EOF > /etc/alloy/config.alloy
logging {
  level  = "info"
  format = "logfmt"
}

// Infrastructure Hardware Scraper (Host CPU, Memory, Disk Metrics)
prometheus.exporter.unix "local" {}

prometheus.scrape "metrics" {
  targets    = prometheus.exporter.unix.local.targets
  forward_to = [prometheus.remote_write.central.receiver]
}

prometheus.remote_write "central" {
  endpoint {
    url = "http://${MONITORING_HOST_IP}:9090/api/v1/write"
  }
}

// Automated Container Output Collector streaming logs directly to Loki
loki.source.docker "containers" {
  host       = "unix:///var/run/docker.sock"
  forward_to = [loki.write.central.receiver]
}

loki.write "central" {
  endpoint {
    url = "http://${MONITORING_HOST_IP}:3100/loki/api/v1/push"
  }
}
EOF

# 5. Refresh system controllers and execute the Alloy engine service
sudo systemctl daemon-reload
sudo systemctl enable alloy
sudo systemctl restart alloy

echo "Frontend telemetry stream successfully routed to ${MONITORING_HOST_IP}"
# ==============================================================================