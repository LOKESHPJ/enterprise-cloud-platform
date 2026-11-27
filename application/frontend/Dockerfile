# Frontend image for the ECS track. The SPA is compiled inside the build stage so
# the runtime layer is just nginx serving static files.
FROM node:20-alpine AS build

WORKDIR /app
COPY application/frontend/package.json application/frontend/package-lock.json* ./
RUN npm install --no-audit --no-fund
COPY application/frontend/ ./
ARG VITE_API_BASE_URL=""
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL
RUN npm run build

FROM nginx:1.27-alpine AS runtime

COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
    CMD wget -q --spider http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
