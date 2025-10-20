FROM node:20-slim

WORKDIR /app

# Install PostgreSQL client and other dependencies
RUN apt-get update && apt-get install -y lsb-release curl gnupg \
    # Download and add the PostgreSQL GPG key
    && curl -sSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg > /dev/null \
    # Add the PostgreSQL APT repository for Debian Bookworm (node:20-slim base)
    && echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" | tee /etc/apt/sources.list.d/pgdg.list \
    # Update apt-get again to recognize the new repository
    && apt-get update \
    # Install the specific PostgreSQL 16 client
    && apt-get install -y postgresql-client-16 \
    # Clean up apt caches to keep the image size down
    && rm -rf /var/lib/apt/lists/*

# Default environment variables (can be overridden)
ENV PGUSER=postgres
ENV PGPASSWORD=root
ENV PGHOST=postgres
ENV PGDATABASE=powerchat
ENV APP_PORT=5000

# Copy package files and install dependencies
COPY package*.json ./
RUN npm ci

# Copy the rest of the application
COPY . .

# Create migrations directory (will be overridden by instance-specific migrations)
RUN mkdir -p /app/migrations

# Copy and make entrypoint script executable
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Build arguments for instance customization
ARG ADMIN_EMAIL="admin@powerchatapp.net"
ARG COMPANY_NAME="BotHive"
ARG INSTANCE_NAME="default"

# Build the application
RUN npm run build

# Perform string replacements in built files
RUN find dist -type f \( -name "*.js" -o -name "*.html" -o -name "*.css" \) -exec sed -i "s/admin@powerchatapp\.net/${ADMIN_EMAIL}/g" {} \; && \
    find dist -type f \( -name "*.js" -o -name "*.html" -o -name "*.css" \) -exec sed -i "s/BotHive/${COMPANY_NAME}/g" {} \; && \
    find client/dist -type f \( -name "*.js" -o -name "*.html" -o -name "*.css" \) -exec sed -i "s/admin@powerchatapp\.net/${ADMIN_EMAIL}/g" {} \; 2>/dev/null || true && \
    find client/dist -type f \( -name "*.js" -o -name "*.html" -o -name "*.css" \) -exec sed -i "s/BotHive/${COMPANY_NAME}/g" {} \; 2>/dev/null || true

# Create directories for instance-specific data
RUN mkdir -p /app/data/uploads /app/data/whatsapp-sessions /app/data/backups

# Expose configurable port
EXPOSE $APP_PORT

ENTRYPOINT ["docker-entrypoint.sh"]

CMD ["node", "dist/index.js"]