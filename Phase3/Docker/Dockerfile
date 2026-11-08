# Pinned base image (reproducible). Alpine = small attack surface.
FROM nginx:1.27-alpine

LABEL description="SysAdmin health dashboard (NGINX)" \
      course="CMPS4232" \
      project="phase3"

# Default environment variables; override at runtime with: docker run -e NAME=value
ENV DASHBOARD_ENV=production \
    SERVER_NAME=localhost

# Config template: variables are filled in at container start
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template

# Landing page
COPY html/ /usr/share/nginx/html/

# Mount point for the host's metrics folder
RUN mkdir -p /usr/share/nginx/html/metrics

# Documentation only: the container listens on 80 (publishing happens with -p)
EXPOSE 80

# Docker marks the container "healthy"/"unhealthy" using this command.
# 127.0.0.1 is used (not "localhost") to avoid IPv6 resolution problems in Alpine.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1/health || exit 1

# CMD is inherited from the base image (nginx -g 'daemon off;')
