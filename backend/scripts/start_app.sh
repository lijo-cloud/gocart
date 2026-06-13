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

# ==============================================================================
# 1. INITIALIZE MONITORING FIRST (MOVED TO TOP TO CATCH CRASHES)
# ==============================================================================
echo "Initializing centralized monitoring layer..."

# 1. Clean out any previous broken keys or legacy files to avoid cache lockups
sudo rm -f /etc/apt/keyrings/grafana.gpg
sudo rm -f /etc/apt/sources.list.d/grafana.list

# 2. Create the keyring folder if missing
sudo mkdir -p /etc/apt/keyrings/

# 3. Modern, clean binary key download safe for Ubuntu 24.04 (No apt-key hacks)
sudo curl -fsSL https://apt.grafana.com/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/grafana.gpg

# 4. Bind the source library listing with the direct binary keyring link
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list

# 5. Execute system cache update and pull Alloy
sudo apt-get update -y
sudo apt-get install -y alloy

# Inject Staging Server Private IP address
MONITORING_HOST_IP="12.0.3.22"

# Generate the Alloy configuration profile
sudo cat << 'EOF' > /etc/alloy/config.alloy
logging {
  level  = "info"
  format = "logfmt"
}

/* Host Hardware Metrics Scraper */
prometheus.exporter.unix "local" {}

prometheus.scrape "metrics" {
  targets    = prometheus.exporter.unix.local.targets
  forward_to = [prometheus.remote_write.central.receiver]
}

prometheus.remote_write "central" {
  endpoint {
    url = "http://12.0.3"
  }
}

/* Automated Docker Container Log Collector */
loki.source.docker "containers" {
  host       = "unix:///var/run/docker.sock"
  forward_to = [loki.write.central.receiver]
}

loki.write "central" {
  endpoint {
    url = "http://12.0.3"
  }
}

/* Open OTLP Trace Receivers Matrix */
otelcol.receiver.otlp "default" {
  grpc { endpoint = "0.0.0.0:4317" }
  http { endpoint = "0.0.0.0:4318" }
  output {
    traces  = [otelcol.exporter.otlp.tempo.input]
  }
}

otelcol.exporter.otlp "tempo" {
  client {
    endpoint = "12.0.3.22:4317"
    tls { insecure = true }
  }
}
EOF

# Activate and start the Alloy service engine
sudo systemctl daemon-reload
sudo systemctl enable alloy
sudo systemctl restart alloy

echo "Centralized infrastructure monitoring successfully linked to ${MONITORING_HOST_IP}"

# ==============================================================================
# 2. APPLICATION RUN MANAGEMENT
# ==============================================================================

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
# Docker pull 
# ----------------------------
echo "Pulling backend image..."
sudo env NESTJS_IMAGE_TAG="$NESTJS_IMAGE_TAG" docker pull "$NESTJS_IMAGE_TAG"

# ----------------------------
# Stop old container
# ----------------------------
echo "Removing old backend container..."
sudo docker rm -f gocart-api || true

# ----------------------------
# Start container (WITH NETWORK INJECTION WORKAROUND)
# ----------------------------
echo "Starting backend container..."

sudo env NESTJS_IMAGE_TAG="$NESTJS_IMAGE_TAG" docker run -d \
  --name gocart-api \
  --restart unless-stopped \
  -p 3001:3001 \
  -e DATABASE_URL="$DB_URL" \
  --add-host="api:13.232.80.25" \
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
