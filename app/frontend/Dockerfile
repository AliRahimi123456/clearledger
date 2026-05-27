FROM nginx:1.27-alpine

# Upgrade all Alpine OS packages to pull latest security patches
RUN apk update && apk upgrade --no-cache

# Security: run as non-root
RUN addgroup -S appuser && adduser -S appuser -G appuser

COPY nginx.conf /etc/nginx/nginx.conf
COPY src/ /usr/share/nginx/html/

# nginx needs to write to these paths even as non-root
RUN chown -R appuser:appuser /usr/share/nginx/html \
    /var/cache/nginx \
    /var/log/nginx \
    /etc/nginx/conf.d && \
    touch /var/run/nginx.pid && \
    chown appuser:appuser /var/run/nginx.pid

USER appuser

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget -q --spider http://localhost:8080/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
