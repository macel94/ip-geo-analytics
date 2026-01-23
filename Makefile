# Makefile for Visitor Analytics SRE Operations

.PHONY: help setup dev test clean build deploy health backup monitor

# Default target
help:
	@echo "Visitor Analytics - SRE Operations"
	@echo ""
	@echo "Development:"
	@echo "  make setup         - Initial setup (dependencies, database)"
	@echo "  make dev           - Start development servers"
	@echo "  make test          - Run E2E tests"
	@echo "  make test-headed   - Run E2E tests with browser visible"
	@echo ""
	@echo "Build & Deploy:"
	@echo "  make build         - Build Docker image"
	@echo "  make push          - Push Docker image to registry"
	@echo "  make deploy-azure  - Deploy to Azure (manual trigger)"
	@echo "  make deploy-k8s    - Deploy to Kubernetes"
	@echo ""
	@echo "Operations:"
	@echo "  make health        - Check application health"
	@echo "  make metrics       - View current metrics"
	@echo "  make backup        - Backup database"
	@echo "  make load-test     - Run load test"
	@echo "  make logs          - View application logs"
	@echo ""
	@echo "Infrastructure:"
	@echo "  make db-up         - Start local database"
	@echo "  make db-down       - Stop local database"
	@echo "  make db-migrate    - Run database migrations"
	@echo ""
	@echo "Maintenance:"
	@echo "  make clean         - Clean build artifacts"
	@echo "  make update-deps   - Update dependencies"
	@echo "  make security-scan - Run security scans"

# Development
setup:
	@echo "Setting up local environment..."
	./scripts/setup_local.sh

dev:
	@echo "Starting development servers..."
	./scripts/start_dev.sh

test:
	@echo "Running E2E tests..."
	npm run test:e2e

test-headed:
	@echo "Running E2E tests (headed mode)..."
	npm run test:e2e:headed

test-setup:
	@echo "Setting up test environment..."
	./scripts/test_setup.sh

# Build & Deploy
build:
	@echo "Building Docker image..."
	docker build -t ghcr.io/macel94/ip-geo-analytics:latest .

push: build
	@echo "Pushing Docker image..."
	docker push ghcr.io/macel94/ip-geo-analytics:latest

deploy-azure:
	@echo "Deploying to Azure..."
	cd deploy && ./deploy.sh

deploy-k8s:
	@echo "Deploying to Kubernetes..."
	kubectl apply -f k8s/postgres.yaml
	kubectl apply -f k8s/deployment.yaml
	@echo "Waiting for rollout..."
	kubectl rollout status deployment/visitor-analytics -n visitor-analytics

# Operations
health:
	@echo "Checking application health..."
	@./scripts/automation/health-check.sh || true

metrics:
	@echo "Fetching metrics..."
	@curl -s http://localhost:3000/metrics | grep -v "^#" || echo "Service not running or metrics unavailable"

backup:
	@echo "Creating database backup..."
	@./scripts/automation/backup-database.sh

load-test:
	@echo "Running load test..."
	@./scripts/automation/load-test.sh http://localhost:3000

logs:
	@echo "Viewing application logs (last 100 lines)..."
	@docker-compose logs --tail=100 -f || echo "Docker Compose not running"

# Infrastructure
db-up:
	@echo "Starting database..."
	docker-compose up -d
	@echo "Waiting for database to be ready..."
	@until docker exec ip-geo-postgres pg_isready -U admin -d analytics 2>/dev/null; do \
		echo "Waiting..."; \
		sleep 2; \
	done
	@echo "Database is ready!"

db-down:
	@echo "Stopping database..."
	docker-compose down

db-migrate:
	@echo "Running database migrations..."
	cd server && npx prisma migrate deploy

db-reset:
	@echo "Resetting database..."
	cd server && npx prisma db push --config prisma/prisma.config.ts --force-reset

# Maintenance
clean:
	@echo "Cleaning build artifacts..."
	rm -rf */node_modules
	rm -rf */dist
	rm -rf node_modules
	rm -rf playwright-report
	rm -rf test-results
	rm -f load-test-report.html
	@echo "Clean complete!"

update-deps:
	@echo "Updating dependencies..."
	npm update
	cd server && npm update
	cd client && npm update
	@echo "Dependencies updated!"

security-scan:
	@echo "Running security scans..."
	@echo "1. NPM Audit (root)..."
	npm audit || true
	@echo ""
	@echo "2. NPM Audit (server)..."
	cd server && npm audit || true
	@echo ""
	@echo "3. NPM Audit (client)..."
	cd client && npm audit || true
	@echo ""
	@echo "Security scan complete!"

# Docker operations
docker-logs:
	@echo "Docker container logs..."
	docker-compose logs -f

docker-shell:
	@echo "Opening shell in app container..."
	docker exec -it ip-geo-postgres bash

# Kubernetes operations
k8s-logs:
	@echo "Kubernetes logs..."
	kubectl logs -f deployment/visitor-analytics -n visitor-analytics

k8s-shell:
	@echo "Opening shell in Kubernetes pod..."
	kubectl exec -it deployment/visitor-analytics -n visitor-analytics -- /bin/sh

k8s-status:
	@echo "Kubernetes deployment status..."
	kubectl get all -n visitor-analytics

k8s-delete:
	@echo "Deleting Kubernetes deployment..."
	kubectl delete -f k8s/deployment.yaml
	kubectl delete -f k8s/postgres.yaml

# Azure operations
azure-logs:
	@echo "Fetching Azure Container App logs..."
	@if [ -z "$$AZURE_APP_NAME" ]; then \
		echo "Error: AZURE_APP_NAME not set"; \
		exit 1; \
	fi
	az containerapp logs show \
		--name $$AZURE_APP_NAME \
		--resource-group rg-visitor-analytics \
		--follow

azure-status:
	@echo "Azure deployment status..."
	az containerapp list \
		--resource-group rg-visitor-analytics \
		--output table

azure-scale:
	@echo "Scaling Azure Container App..."
	@if [ -z "$$AZURE_APP_NAME" ] || [ -z "$$REPLICAS" ]; then \
		echo "Error: AZURE_APP_NAME and REPLICAS must be set"; \
		echo "Usage: AZURE_APP_NAME=myapp REPLICAS=3 make azure-scale"; \
		exit 1; \
	fi
	az containerapp update \
		--name $$AZURE_APP_NAME \
		--resource-group rg-visitor-analytics \
		--min-replicas $$REPLICAS \
		--max-replicas $$((REPLICAS * 2))

# Monitoring
monitor-health:
	@echo "Starting continuous health monitoring (Ctrl+C to stop)..."
	@while true; do \
		clear; \
		date; \
		echo ""; \
		make health; \
		sleep 30; \
	done

monitor-metrics:
	@echo "Monitoring metrics (Ctrl+C to stop)..."
	@while true; do \
		clear; \
		date; \
		echo ""; \
		make metrics; \
		sleep 10; \
	done
