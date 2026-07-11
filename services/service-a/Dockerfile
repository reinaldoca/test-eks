# Multi-stage Dockerfile for Service A
# Optimized for production with distroless final image

# ============================================
# Stage 1: Builder
# ============================================
FROM node:20-alpine AS builder

# Set working directory
WORKDIR /app

# Install build dependencies
RUN apk add --no-cache python3 make g++

# Copy package files
COPY package*.json ./

# Install dependencies (including devDependencies for build)
RUN npm ci

# Copy source code
COPY tsconfig.json ./
COPY src ./src

# Build TypeScript
RUN npm run build

# Remove devDependencies
RUN npm prune --production

# ============================================
# Stage 2: Production (Distroless)
# ============================================
FROM gcr.io/distroless/nodejs20-debian12

# Set working directory
WORKDIR /app

# Copy built artifacts from builder
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./package.json

# Set non-root user
USER nonroot:nonroot

# Environment variables
ENV NODE_ENV=production \
    PORT=8080 \
    OTEL_SERVICE_NAME=service-a \
    OTEL_SERVICE_VERSION=1.0.0

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["/nodejs/bin/node", "-e", "require('http').get('http://localhost:8080/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"]

# Start application
CMD ["dist/index.js"]
