# --- Build Stage ---
FROM node:22-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
ENV NEXT_PRIVATE_STANDALONE=true
RUN npm run build

# --- Production Runner Stage ---
FROM node:22-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

# Security: Run container as non-root
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# 🚀 FIX: Pre-create cache and build paths with correct nextjs permissions
RUN mkdir -p /app/static_cache /app/.next && chown -R nextjs:nodejs /app

# Copy application assets
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static /app/.next/static
COPY --from=builder --chown=nextjs:nodejs /app/public ./public

# # Copy standalone app and ensure .next/static is available
# COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
# COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
# # Copy public folder for static assets
# COPY --from=builder --chown=nextjs:nodejs /app/public ./public

# ✅ Extended health check for Docker and ALB - increased start period to 60s
HEALTHCHECK --interval=10s --timeout=5s --start-period=60s --retries=5 \
  CMD node -e "require('http').get('http://localhost:3000/api/health', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

USER nextjs
EXPOSE 3000

# Run the standalone Next.js server
# CMD ["node", "server.js"]

# 🚀 FIX: Copy assets to the mounted cache volume, then start Next.js
CMD ["sh", "-c", "cp -r /app/.next/static/. /app/static_cache/ 2>/dev/null || true; node server.js"]