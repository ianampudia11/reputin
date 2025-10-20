#!/bin/bash


set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTANCES_DIR="$SCRIPT_DIR/instances"
MIN_APP_PORT=9000
MAX_APP_PORT=9999
MIN_DB_PORT=5432
MAX_DB_PORT=5532

print_header() {
    cat << EOF
${PURPLE}
╔═══════════════════════════════════════════════════════════════╗
║              BotHive Plus - Multi-Instance Deploy          ║
║                                                               ║
║  Deploy multiple isolated instances using production build   ║
║  with automatic port detection and conflict resolution.      ║
╚═══════════════════════════════════════════════════════════════╝
${NC}

EOF
}

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local validator="$4"
    
    while true; do
        if [ -n "$default" ]; then
            echo -n "$prompt [$default]: "
        else
            echo -n "$prompt: "
        fi
        
        read -r input
        if [ -z "$input" ] && [ -n "$default" ]; then
            input="$default"
        fi
        
        if [ -n "$validator" ] && ! $validator "$input"; then
            continue
        fi
        
        eval "$var_name='$input'"
        break
    done
}

validate_instance_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
        print_error "Instance name must start with alphanumeric character and contain only letters, numbers, hyphens, and underscores"
        return 1
    fi
    
    if [ ${#name} -lt 3 ] || [ ${#name} -gt 30 ]; then
        print_error "Instance name must be between 3 and 30 characters"
        return 1
    fi
    
    if [ -d "$INSTANCES_DIR/$name" ]; then
        print_error "Instance '$name' already exists"
        return 1
    fi
    
    return 0
}

validate_email() {
    local email="$1"
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        print_error "Please enter a valid email address"
        return 1
    fi
    return 0
}

validate_port() {
    local port="$1"
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
        print_error "Port must be a number between 1024 and 65535"
        return 1
    fi
    return 0
}

is_port_available() {
    local port="$1"
    ! netstat -tuln 2>/dev/null | grep -q ":$port " && \
    ! docker ps --format "table {{.Ports}}" 2>/dev/null | grep -q ":$port->" && \
    ! ss -tuln 2>/dev/null | grep -q ":$port "
}

find_available_port() {
    local start_port="$1"
    local max_port="$2"
    
    for ((port=start_port; port<=max_port; port++)); do
        if is_port_available "$port"; then
            echo "$port"
            return 0
        fi
    done
    
    print_error "No available ports found in range $start_port-$max_port"
    return 1
}

generate_session_secret() {
    openssl rand -base64 32 2>/dev/null | tr -d "=+/" | cut -c1-32
}

generate_encryption_key() {
    openssl rand -hex 32 2>/dev/null
}

generate_password() {
    openssl rand -base64 16 2>/dev/null | tr -d "=+/" | cut -c1-16
}

check_prerequisites() {
    print_step "Checking prerequisites..."
    
    local missing_deps=()
    
    if ! command -v docker &> /dev/null; then
        missing_deps+=("Docker")
    fi
    
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        missing_deps+=("Docker Compose")
    fi
    
    if ! command -v openssl &> /dev/null; then
        missing_deps+=("OpenSSL")
    fi
    
    if ! command -v node &> /dev/null; then
        missing_deps+=("Node.js")
    fi
    
    if ! command -v npm &> /dev/null; then
        missing_deps+=("npm")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        echo
        echo "Please install the missing dependencies:"
        echo "  - Docker: https://docs.docker.com/get-docker/"
        echo "  - Docker Compose: https://docs.docker.com/compose/install/"
        echo "  - Node.js & npm: https://nodejs.org/"
        echo "  - OpenSSL: Usually pre-installed on most systems"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running. Please start Docker first."
        exit 1
    fi
    
    print_success "All prerequisites are met"
}

install_dependencies() {
    print_step "Installing production dependencies..."
    
    if [ ! -f "package.json" ]; then
        print_error "package.json not found. Please run this script from the share directory."
        exit 1
    fi
    
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        print_status "Installing dependencies (attempt $attempt/$max_attempts)..."
        
        if npm install --production --no-audit --no-fund --prefer-offline; then
            print_success "Dependencies installed successfully"
            return 0
        else
            print_warning "Installation attempt $attempt failed"
            
            if [ $attempt -eq $max_attempts ]; then
                print_error "Failed to install dependencies after $max_attempts attempts"
                echo
                echo "Troubleshooting steps:"
                echo "1. Check your internet connection"
                echo "2. Clear npm cache: npm cache clean --force"
                echo "3. Try with different registry: npm config set registry https://registry.npmjs.org/"
                echo "4. Install manually: npm install --production"
                exit 1
            fi
            
            sleep 5
            ((attempt++))
        fi
    done
}

verify_deployment_files() {
    print_step "Verifying deployment files..."
    
    local required_files=(
        "dist/index.js"
        "package.json"
        "start.js"
        "migrations"
        "scripts/migrate.js"
    )
    
    local missing_files=()
    
    for file in "${required_files[@]}"; do
        if [ ! -e "$file" ]; then
            missing_files+=("$file")
        fi
    done
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        print_error "Missing required files: ${missing_files[*]}"
        echo
        echo "This script must be run from the BotHive Plus share directory"
        echo "containing the pre-compiled production build."
        exit 1
    fi
    
    if [ ! -s "dist/index.js" ]; then
        print_error "dist/index.js is empty. Please ensure you have a valid production build."
        exit 1
    fi
    
    print_success "All required files are present"
}

collect_instance_config() {
    print_step "Configuring new BotHive Plus instance..."
    echo

    prompt_with_default "Instance name (3-30 chars, alphanumeric, hyphens, underscores)" "" INSTANCE_NAME validate_instance_name

    local default_db_name=$(echo "$INSTANCE_NAME" | tr '-' '_' | tr '[:upper:]' '[:lower:]')
    prompt_with_default "Database name" "${default_db_name}_db" DATABASE_NAME

    prompt_with_default "Company/Organization name" "My Company" COMPANY_NAME

    prompt_with_default "Admin email address" "admin@${INSTANCE_NAME}.com" ADMIN_EMAIL validate_email
    prompt_with_default "Admin username" "$ADMIN_EMAIL" ADMIN_USERNAME
    prompt_with_default "Admin full name" "Super Admin" ADMIN_FULL_NAME

    local generated_password=$(generate_password)
    prompt_with_default "Admin password" "$generated_password" ADMIN_PASSWORD

    local suggested_app_port=$(find_available_port $MIN_APP_PORT $MAX_APP_PORT)
    local suggested_db_port=$(find_available_port $MIN_DB_PORT $MAX_DB_PORT)

    prompt_with_default "Application port" "$suggested_app_port" APP_PORT validate_port
    prompt_with_default "Database port" "$suggested_db_port" DB_PORT validate_port

    if ! is_port_available "$APP_PORT"; then
        print_error "Port $APP_PORT is no longer available"
        exit 1
    fi

    if ! is_port_available "$DB_PORT"; then
        print_error "Port $DB_PORT is no longer available"
        exit 1
    fi

    SESSION_SECRET=$(generate_session_secret)
    ENCRYPTION_KEY=$(generate_encryption_key)
    DB_PASSWORD=$(generate_password)

    echo
    print_status "Configuration Summary:"
    echo "  Instance Name: $INSTANCE_NAME"
    echo "  Database Name: $DATABASE_NAME"
    echo "  Company Name: $COMPANY_NAME"
    echo "  Admin Email: $ADMIN_EMAIL"
    echo "  Admin Username: $ADMIN_USERNAME"
    echo "  Application Port: $APP_PORT"
    echo "  Database Port: $DB_PORT"
    echo "  Secure secrets: Generated automatically"
    echo
}

confirm_deployment() {
    echo -n "Deploy this BotHive Plus instance? (Y/n): "
    read -r confirm
    if [[ $confirm =~ ^[Nn]$ ]]; then
        print_status "Deployment cancelled by user."
        exit 0
    fi
}

create_instance_files() {
    print_step "Creating instance files..."

    mkdir -p "$INSTANCES_DIR/$INSTANCE_NAME"
    local instance_dir="$INSTANCES_DIR/$INSTANCE_NAME"

    cat > "$instance_dir/.env" << EOF

DATABASE_URL=postgresql://powerchat:$DB_PASSWORD@postgres-$INSTANCE_NAME:5432/$DATABASE_NAME
POSTGRES_DB=$DATABASE_NAME
POSTGRES_USER=powerchat
POSTGRES_PASSWORD=$DB_PASSWORD
PGSSLMODE=disable

NODE_ENV=production
PORT=9000
APP_PORT=$APP_PORT
DB_PORT=$DB_PORT

SESSION_SECRET=$SESSION_SECRET
ENCRYPTION_KEY=$ENCRYPTION_KEY
FORCE_INSECURE_COOKIE=true

ADMIN_EMAIL=$ADMIN_EMAIL
ADMIN_USERNAME=$ADMIN_USERNAME
ADMIN_FULL_NAME=$ADMIN_FULL_NAME
ADMIN_PASSWORD=$ADMIN_PASSWORD

COMPANY_NAME=$COMPANY_NAME

ENABLE_RUNTIME_PROTECTION=true
ENABLE_CLIENT_PROTECTION=true
ENABLE_CONSOLE_PROTECTION=false
DISABLE_CSP=true

LOG_LEVEL=INFO

INSTANCE_NAME=$INSTANCE_NAME
CREATED_DATE=$(date -Iseconds)
EOF

    cat > "$instance_dir/docker-compose.yml" << EOF
services:
  postgres-$INSTANCE_NAME:
    image: postgres:16.1-alpine
    container_name: powerchat-postgres-$INSTANCE_NAME
    restart: unless-stopped
    environment:
      POSTGRES_DB: $DATABASE_NAME
      POSTGRES_USER: powerchat
      POSTGRES_PASSWORD: $DB_PASSWORD
      POSTGRES_INITDB_ARGS: "--encoding=UTF-8 --lc-collate=C --lc-ctype=C"
    volumes:
      - postgres_data_$INSTANCE_NAME:/var/lib/postgresql/data
      - ../../init-db.sql:/docker-entrypoint-initdb.d/init-db.sql:ro
    ports:
      - "$DB_PORT:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U powerchat -d $DATABASE_NAME"]
      interval: 10s
      timeout: 5s
      retries: 5

  app-$INSTANCE_NAME:
    build:
      context: ../../
      dockerfile: Dockerfile.simple
    container_name: powerchat-app-$INSTANCE_NAME
    restart: unless-stopped
    depends_on:
      postgres-$INSTANCE_NAME:
        condition: service_healthy
    env_file:
      - .env
    ports:
      - "$APP_PORT:9000"
    volumes:
      - app_uploads_$INSTANCE_NAME:/app/uploads
      - app_public_$INSTANCE_NAME:/app/public/media
      - app_logs_$INSTANCE_NAME:/app/logs
      - app_backups_$INSTANCE_NAME:/app/backups
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

# Use shared network to avoid subnet exhaustion
networks:
  default:
    external: true
    name: powerchat-shared-network

volumes:
  postgres_data_$INSTANCE_NAME:
    driver: local
    name: powerchat-postgres-data-$INSTANCE_NAME
  app_uploads_$INSTANCE_NAME:
    driver: local
    name: powerchat-app-uploads-$INSTANCE_NAME
  app_public_$INSTANCE_NAME:
    driver: local
    name: powerchat-app-public-$INSTANCE_NAME
  app_logs_$INSTANCE_NAME:
    driver: local
    name: powerchat-app-logs-$INSTANCE_NAME
  app_backups_$INSTANCE_NAME:
    driver: local
    name: powerchat-app-backups-$INSTANCE_NAME
EOF

    cat > "$instance_dir/manage.sh" << 'EOF'

INSTANCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTANCE_NAME="$(basename "$INSTANCE_DIR")"

case "${1:-status}" in
    "start")
        echo "Starting instance $INSTANCE_NAME..."
        docker-compose -f "$INSTANCE_DIR/docker-compose.yml" up -d
        ;;
    "stop")
        echo "Stopping instance $INSTANCE_NAME..."
        docker-compose -f "$INSTANCE_DIR/docker-compose.yml" down
        ;;
    "restart")
        echo "Restarting instance $INSTANCE_NAME..."
        docker-compose -f "$INSTANCE_DIR/docker-compose.yml" restart
        ;;
    "logs")
        docker-compose -f "$INSTANCE_DIR/docker-compose.yml" logs -f
        ;;
    "status")
        docker-compose -f "$INSTANCE_DIR/docker-compose.yml" ps
        ;;
    "clean")
        echo "WARNING: This will remove all data for instance $INSTANCE_NAME"
        read -p "Are you sure? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            docker-compose -f "$INSTANCE_DIR/docker-compose.yml" down -v --rmi all
            echo "Instance $INSTANCE_NAME cleaned"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|logs|status|clean}"
        exit 1
        ;;
esac
EOF

    chmod +x "$instance_dir/manage.sh"

    print_success "Instance files created in $instance_dir"
}

# Function to create shared network
create_shared_network() {
    local network_name="powerchat-shared-network"

    # Check if shared network exists
    if ! docker network inspect "$network_name" >/dev/null 2>&1; then
        print_status "Creating shared BotHive network..."
        docker network create "$network_name" --driver bridge --subnet=172.20.0.0/16 2>/dev/null || {
            print_warning "Failed to create network with custom subnet, trying default..."
            docker network create "$network_name" --driver bridge 2>/dev/null || {
                print_error "Failed to create shared network. Trying cleanup first..."
                docker network prune -f 2>/dev/null || true
                docker network create "$network_name" --driver bridge || {
                    print_error "Cannot create shared network. Please run: docker network prune -f"
                    return 1
                }
            }
        }
        print_success "Shared network created: $network_name"
    else
        print_status "Using existing shared network: $network_name"
    fi
}

# Function to clean up unused Docker resources
cleanup_docker_resources() {
    print_status "Cleaning up unused Docker resources to free up network space..."

    # Stop any exited containers first
    docker container prune -f 2>/dev/null || true

    # Remove unused networks (this is the key fix)
    print_status "Removing unused Docker networks..."
    docker network prune -f 2>/dev/null || true

    # Remove any orphaned BotHive networks that might be stuck
    print_status "Removing orphaned BotHive networks..."
    docker network ls --format "{{.Name}}" | grep -E "(powerchat-network-|_default)" | while read network; do
        # Skip the shared network
        if [ "$network" != "powerchat-shared-network" ]; then
            # Check if network is actually in use
            if ! docker network inspect "$network" --format "{{.Containers}}" 2>/dev/null | grep -q "."; then
                print_status "Removing unused network: $network"
                docker network rm "$network" 2>/dev/null || true
            fi
        fi
    done

    # Remove unused images to free up space
    docker image prune -f 2>/dev/null || true

    print_status "Docker cleanup completed"
}

deploy_instance() {
    print_step "Deploying BotHive Plus instance '$INSTANCE_NAME'..."

    local instance_dir="$INSTANCES_DIR/$INSTANCE_NAME"

    # Clean up Docker resources first to free up networks
    cleanup_docker_resources

    # Create shared network for all instances
    create_shared_network

    print_status "Building Docker image..."
    cd "$instance_dir"

    if [ ! -f "../../Dockerfile.simple" ]; then
        print_error "Dockerfile.simple not found. Please ensure it exists in the share directory."
        return 1
    fi

    if [ ! -d "../../node_modules" ]; then
        print_error "node_modules not found. Dependencies should have been installed earlier."
        return 1
    fi

    if docker-compose build --no-cache; then
        print_success "Docker image built successfully"
    else
        print_error "Failed to build Docker image"
        return 1
    fi

    print_status "Starting services..."
    if docker-compose up -d; then
        print_success "Services started successfully"
    else
        print_error "Failed to start services"
        return 1
    fi

    print_status "Waiting for services to be ready..."
    local max_wait=2
    local wait_time=0

    while [ $wait_time -lt $max_wait ]; do
        if docker-compose ps | grep -q "Up (healthy)"; then
            print_success "Services are healthy and ready"
            break
        fi

        echo -n "."
        sleep 5
        ((wait_time+=5))
    done

    if [ $wait_time -ge $max_wait ]; then
        print_warning "Services may still be starting. Check logs if needed."
    fi

    print_status "Running database migrations..."
    sleep 10  # Give database extra time to be ready

    if docker-compose exec -T app-$INSTANCE_NAME node scripts/migrate.js run; then
        print_success "Database migrations completed"
    else
        print_warning "Migration may have failed. Check logs: docker-compose logs app-$INSTANCE_NAME"
    fi

    cd "$SCRIPT_DIR"
}



show_deployment_results() {
    print_step "Deployment completed successfully!"

    cat << EOF

${GREEN}🎉 BotHive Plus instance '$INSTANCE_NAME' deployed successfully!${NC}

${BLUE}Access Information:${NC}
  🌐 Application URL: ${YELLOW}http://localhost:$APP_PORT${NC}
  🗄️  Database: ${YELLOW}localhost:$DB_PORT${NC}
  📁 Admin Panel: ${YELLOW}http://localhost:$APP_PORT/admin${NC}

${BLUE}Admin Credentials:${NC}
  📧 Email: ${YELLOW}$ADMIN_EMAIL${NC}
  👤 Username: ${YELLOW}$ADMIN_USERNAME${NC}
  🔑 Password: ${YELLOW}$ADMIN_PASSWORD${NC}

${BLUE}Instance Management:${NC}
  📊 Status: ${YELLOW}$INSTANCES_DIR/$INSTANCE_NAME/manage.sh status${NC}
  📋 Logs: ${YELLOW}$INSTANCES_DIR/$INSTANCE_NAME/manage.sh logs${NC}
  🔄 Restart: ${YELLOW}$INSTANCES_DIR/$INSTANCE_NAME/manage.sh restart${NC}
  🛑 Stop: ${YELLOW}$INSTANCES_DIR/$INSTANCE_NAME/manage.sh stop${NC}

${BLUE}Next Steps:${NC}
1. Wait 1-2 minutes for the application to fully start
2. Open ${YELLOW}http://localhost:$APP_PORT${NC} in your browser
3. Login with the admin credentials above
4. Configure your WhatsApp and other channels
5. Create your first chatbot flow

${BLUE}Deploy Additional Instances:${NC}
  ${YELLOW}./multi-instance-deploy.sh${NC}

${GREEN}Happy chatting! 🚀${NC}

EOF
}

list_instances() {
    print_step "Listing BotHive Plus instances..."

    if [ ! -d "$INSTANCES_DIR" ] || [ -z "$(ls -A "$INSTANCES_DIR" 2>/dev/null)" ]; then
        print_status "No instances found."
        echo
        echo "Deploy your first instance with: ./multi-instance-deploy.sh"
        return 0
    fi

    echo
    printf "%-20s %-10s %-10s %-15s %-30s\n" "INSTANCE" "APP_PORT" "DB_PORT" "STATUS" "URL"
    printf "%-20s %-10s %-10s %-15s %-30s\n" "--------" "--------" "-------" "------" "---"

    for instance_dir in "$INSTANCES_DIR"/*; do
        if [ -d "$instance_dir" ]; then
            local instance_name=$(basename "$instance_dir")
            local env_file="$instance_dir/.env"

            if [ -f "$env_file" ]; then
                local app_port=$(grep "^APP_PORT=" "$env_file" | cut -d'=' -f2)
                local db_port=$(grep "^DB_PORT=" "$env_file" | cut -d'=' -f2)

                local status="Stopped"
                if docker-compose -f "$instance_dir/docker-compose.yml" ps | grep -q "Up"; then
                    status="Running"
                fi

                local url="http://localhost:$app_port"

                printf "%-20s %-10s %-10s %-15s %-30s\n" "$instance_name" "$app_port" "$db_port" "$status" "$url"
            fi
        fi
    done
    echo
}

main() {
    print_header

    cd "$SCRIPT_DIR"

    check_prerequisites
    verify_deployment_files
    install_dependencies
    collect_instance_config
    confirm_deployment

    create_instance_files
    deploy_instance
    show_deployment_results

    print_success "Multi-instance deployment completed! 🎉"
}

case "${1:-}" in
    "help"|"-h"|"--help")
        cat << EOF
BotHive Plus Multi-Instance Docker Deployment

Usage: $0 [command]

Commands:
  (no args)  Deploy a new instance (interactive)
  list       List all deployed instances
  status     Show status of all instances
  logs       Show logs for all instances
  stop       Stop all instances
  clean      Remove all instances and data
  help       Show this help message

Examples:
  $0                    # Deploy new instance
  $0 list              # List all instances
  $0 status            # Show instance status

Instance Management:
  Each instance can be managed individually:
  ./instances/INSTANCE_NAME/manage.sh {start|stop|restart|logs|status|clean}

EOF
        exit 0
        ;;
    "list")
        list_instances
        exit 0
        ;;
    "status")
        print_step "Showing status of all instances..."
        if [ ! -d "$INSTANCES_DIR" ] || [ -z "$(ls -A "$INSTANCES_DIR" 2>/dev/null)" ]; then
            print_status "No instances found."
        else
            for instance_dir in "$INSTANCES_DIR"/*; do
                if [ -d "$instance_dir" ]; then
                    local instance_name=$(basename "$instance_dir")
                    echo
                    print_status "Instance: $instance_name"
                    docker-compose -f "$instance_dir/docker-compose.yml" ps
                fi
            done
        fi
        exit 0
        ;;
    "logs")
        print_step "Showing logs of all instances..."
        if [ ! -d "$INSTANCES_DIR" ] || [ -z "$(ls -A "$INSTANCES_DIR" 2>/dev/null)" ]; then
            print_status "No instances found."
        else
            echo "Press Ctrl+C to stop following logs"
            echo
            local compose_files=()
            for instance_dir in "$INSTANCES_DIR"/*; do
                if [ -d "$instance_dir" ]; then
                    compose_files+=("-f" "$instance_dir/docker-compose.yml")
                fi
            done
            if [ ${#compose_files[@]} -gt 0 ]; then
                docker-compose "${compose_files[@]}" logs -f
            fi
        fi
        exit 0
        ;;
    "stop")
        print_step "Stopping all BotHive Plus instances..."
        if [ ! -d "$INSTANCES_DIR" ] || [ -z "$(ls -A "$INSTANCES_DIR" 2>/dev/null)" ]; then
            print_status "No instances found."
        else
            for instance_dir in "$INSTANCES_DIR"/*; do
                if [ -d "$instance_dir" ]; then
                    local instance_name=$(basename "$instance_dir")
                    print_status "Stopping instance: $instance_name"
                    docker-compose -f "$instance_dir/docker-compose.yml" down
                fi
            done
            print_success "All instances stopped"
        fi
        exit 0
        ;;
    "clean")
        print_warning "This will remove ALL BotHive Plus instances and their data!"
        echo "This action cannot be undone."
        echo
        if [ ! -d "$INSTANCES_DIR" ] || [ -z "$(ls -A "$INSTANCES_DIR" 2>/dev/null)" ]; then
            print_status "No instances found."
            exit 0
        fi
        echo "Instances to be removed:"
        for instance_dir in "$INSTANCES_DIR"/*; do
            if [ -d "$instance_dir" ]; then
                local instance_name=$(basename "$instance_dir")
                echo "  - $instance_name"
            fi
        done
        echo
        echo -n "Are you absolutely sure? Type 'DELETE ALL' to confirm: "
        read -r confirm
        if [ "$confirm" != "DELETE ALL" ]; then
            print_status "Cleanup cancelled."
            exit 0
        fi
        print_step "Removing all instances..."
        for instance_dir in "$INSTANCES_DIR"/*; do
            if [ -d "$instance_dir" ]; then
                local instance_name=$(basename "$instance_dir")
                print_status "Removing instance: $instance_name"
                docker-compose -f "$instance_dir/docker-compose.yml" down -v --rmi all 2>/dev/null || true
                rm -rf "$instance_dir"
            fi
        done
        if [ -d "$INSTANCES_DIR" ] && [ -z "$(ls -A "$INSTANCES_DIR" 2>/dev/null)" ]; then
            rmdir "$INSTANCES_DIR"
        fi
        print_success "All instances removed"
        exit 0
        ;;
    "")
        main
        ;;
    *)
        print_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac
