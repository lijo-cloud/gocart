# --- Build Stage ---
FROM node:22-alpine AS builder
WORKDIR /app

# 1. Copy package files and install dependencies
COPY package*.json ./
RUN npm ci

# 2. Copy Prisma folder and generate the engine binaries
COPY prisma ./prisma/
RUN npx prisma generate

# 3. Copy the rest of the application files after the engine is ready
COPY . .

# 4. Set environment and run NextJS build
ENV NEXT_PRIVATE_STANDALONE=true
RUN npm run build


# --- Production Runner Stage ---
FROM node:22-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=builder --chown=nextjs:nodejs /app/public ./public

HEALTHCHECK --interval=10s --timeout=5s --start-period=60s --retries=5 \
  CMD node -e "require('http').get('http://localhost:3000/api/health', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

USER nextjs
EXPOSE 3000

CMD ["node", "server.js"]