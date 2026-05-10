FROM node:20-alpine AS builder

WORKDIR /app

COPY package.json package-lock.json* yarn.lock* pnpm-lock.yaml* ./
RUN npm ci --ignore-scripts 2>/dev/null \
    || yarn install --frozen-lockfile 2>/dev/null \
    || pnpm install --frozen-lockfile 2>/dev/null

COPY . .
RUN npm run build

FROM node:20-alpine

WORKDIR /app

COPY --from=builder /app/package.json ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/public ./public

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD wget -qO- http://localhost:3000/ || exit 1

CMD ["npm", "run", "start"]
