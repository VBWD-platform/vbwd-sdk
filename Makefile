.PHONY: up down up-build rebuild-backend rebuild-admin rebuild-user logs ps clean npm-install

# Install npm dependencies for all frontend packages
npm-install:
	@echo "Installing npm dependencies..."
	cd vbwd-fe-core && npm install
	cd vbwd-fe-user && npm install
	cd vbwd-fe-admin && npm install
	@echo "Building core shared library..."
	cd vbwd-fe-core && npm run build
	@echo "All npm dependencies installed and core library built"

# Start all containers (backend + frontend)
up:
	cd vbwd-backend && docker compose up api postgres -d --build
	cd vbwd-fe-user && docker compose build dev nginx --no-cache && docker compose up dev nginx -d
	cd vbwd-fe-admin && docker compose build dev nginx --no-cache && docker compose up dev nginx -d
	@echo "All services started"

# Start with rebuild
rebuild-backend:
	cd vbwd-backend && docker compose build --no-cache  && docker compose up -d
	@echo "All services rebuilt and started"

# Rebuild and restart only the admin frontend
rebuild-admin:
	cd vbwd-fe-admin && npm install
	cd vbwd-fe-admin && npm run build
	cd vbwd-fe-admin && docker compose down -v
	cd vbwd-fe-admin && docker compose build dev nginx --no-cache
	cd vbwd-fe-admin && docker compose up dev nginx -d
	@echo "Admin frontend rebuilt and restarted at http://localhost:8081"

rebuild-user:
	cd vbwd-fe-admin && npm install
	cd vbwd-fe-user && npm run build
	cd vbwd-fe-user && docker compose down -v
	cd vbwd-fe-user && docker compose build dev nginx --no-cache
	cd vbwd-fe-user && docker compose up dev nginx -d
	@echo "User frontend rebuilt and restarted at http://localhost:8080"

rebuild-core:
	cd vbwd-fe-core && npm install && npm run build

# Stop all containers
down:
	cd vbwd-fe-admin && docker compose down nginx dev -v
	cd vbwd-fe-user && docker compose down nginx dev -v
	cd vbwd-backend && docker compose down
	@echo "All services stopped"

# View logs from all services
be-logs:
	cd vbwd-backend && docker compose logs -f

# Show status of all containers
ps:
	@echo "=== Backend ===" && cd vbwd-backend && docker compose ps
	@echo "=== Frontend User ===" && cd vbwd-fe-user && docker compose ps
	@echo "=== Frontend Admin ===" && cd vbwd-fe-admin && docker compose ps

migrations:
	cd vbwd-backend && docker compose exec api alembic upgrade head

reset-db:
	cd vbwd-backend && ./bin/reset-database.sh
	cd vbwd-backend/plugins/taro && ./bin/populate-db.sh
	cd vbwd-backend/plugins/cms && ./bin/populate-db.sh