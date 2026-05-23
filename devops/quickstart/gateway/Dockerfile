# ── gateway (nginx) ───────────────────────────────────────────────────────────
# Public-facing reverse proxy. Forwards HTTP traffic to the iii engine.
# This is the ONLY container with a public-facing port.
# ------------------------------------------------------------------------------

FROM nginx:1.27-alpine

# Remove default config
RUN rm /etc/nginx/conf.d/default.conf

# Copy our proxy config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Only port 80 is exposed publicly
# TLS termination (443) can be added here via certbot/Let's Encrypt in production
EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
