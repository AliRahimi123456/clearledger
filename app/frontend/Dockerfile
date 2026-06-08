FROM nginx:1.27-alpine

# Alpine security patches; pin libxml2 for CVE-2026-6732 (2.13.9-r0 → r1)
RUN apk update && \
    apk upgrade --no-cache && \
    apk add --no-cache libxml2=2.13.9-r1

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
