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


# ==============================================================================
# AUTOMATED PRODUCTION MONITORING DEPLOYMENT (GRAFANA ALLOY)
# ==============================================================================
echo "Initializing centralized monitoring layer..."

# 1. Register the official Grafana package repository keys (FIXED URL)
sudo mkdir -p /etc/apt/keyrings/
wget -q -O - https://grafana.com | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list

# 2. Update cache and install Grafana Alloy
sudo apt-get update -y
sudo apt-get install -y alloy

# 3. Inject your Staging Server Private IP address as the monitoring core target
MONITORING_HOST_IP="12.0.3.22"

# 4. Generate the Alloy configuration file
sudo cat <<EOF > /etc/alloy/config.alloy
logging {
  level  = "info"
  format = "logfmt"
}

// System Resource Engine Scraping (Host CPU, Memory, Disk Metrics)
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

// Automated Docker Container Runtime Log Shipping
loki.source.docker "containers" {
  host       = "unix:///var/run/docker.sock"
  forward_to = [loki.write.central.receiver]
}

loki.write "central" {
  endpoint {
    url = "http://${MONITORING_HOST_IP}:3100/loki/api/v1/push"
  }
}

// Open OTLP Receiver Matrix to listen for local NestJS Traces
otelcol.receiver.otlp "default" {
  grpc { endpoint = "0.0.0.0:4317" }
  http { endpoint = "0.0.0.0:4318" }
  output {
    traces  = [otelcol.exporter.otlp.tempo.input]
  }
}

otelcol.exporter.otlp "tempo" {
  client {
    endpoint = "${MONITORING_HOST_IP}:4317"
    tls { insecure = true }
  }
}
EOF

# 5. Lock down access permissions and ignite the engine
sudo systemctl daemon-reload
sudo systemctl enable alloy
sudo systemctl restart alloy

echo "Centralized infrastructure monitoring successfully linked to ${MONITORING_HOST_IP}"
# ==============================================================================
