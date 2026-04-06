# Task 02: Container Configurations

**Priority:** High
**Status:** Pending
**Estimated Effort:** Medium

---

## Objective

Create individual Dockerfiles and configurations for each container in `./container/`.

---

## Tasks

### 2.1 Create container/python/Dockerfile

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    default-libmysqlclient-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY api/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY api/ .

# Create logs directory
RUN mkdir -p /app/logs

# Expose port
EXPOSE 5000

# Run with Gunicorn
CMD ["gunicorn", "--config", "gunicorn.conf.py", "src:create_app()"]
```

### 2.2 Create container/python/gunicorn.conf.py

```python
bind = '0.0.0.0:5000'
workers = 4
worker_class = 'sync'
timeout = 120
keepalive = 5
max_requests = 1000
max_requests_jitter = 50

# Logging
accesslog = '/app/logs/access.log'
errorlog = '/app/logs/error.log'
loglevel = 'info'

# For development with reload
reload = True
```

### 2.3 Create container/frontend/Dockerfile

```dockerfile
# Build stage
FROM node:20-alpine AS build

WORKDIR /app

# Copy package files
COPY user/vue/package*.json ./user/
COPY admin/vue/package*.json ./admin/

# Install dependencies
RUN cd user && npm ci
RUN cd admin && npm ci

# Copy source and build
COPY user/vue/ ./user/
COPY admin/vue/ ./admin/

RUN cd user && npm run build
RUN cd admin && npm run build

# Production stage
FROM nginx:alpine

# Copy built files
COPY --from=build /app/user/dist /usr/share/nginx/html/user
COPY --from=build /app/admin/dist /usr/share/nginx/html/admin

# Copy nginx config
COPY ../container/frontend/nginx.conf /etc/nginx/nginx.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
```

### 2.4 Create container/frontend/nginx.conf

```nginx
events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent"';

    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log;

    sendfile on;
    keepalive_timeout 65;

    # Gzip compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript;

    server {
        listen 80;
        server_name localhost;

        # User app (default)
        location / {
            root /usr/share/nginx/html/user;
            index index.html;
            try_files $uri $uri/ /index.html;
        }

        # Admin app
        location /admin {
            alias /usr/share/nginx/html/admin;
            index index.html;
            try_files $uri $uri/ /admin/index.html;
        }

        # API proxy
        location /api {
            proxy_pass http://python:5000;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_cache_bypass $http_upgrade;
        }

        # WebSocket proxy
        location /socket.io {
            proxy_pass http://python:5000;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
        }
    }
}
```

### 2.5 Create container/mysql/init.sql

```sql
-- Initial database setup
CREATE DATABASE IF NOT EXISTS vbwd CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE vbwd;

-- Submissions table
CREATE TABLE IF NOT EXISTS submissions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(255) NOT NULL,
    status ENUM('pending', 'processing', 'completed', 'failed') DEFAULT 'pending',
    images_data JSON,
    comments TEXT,
    consent_given BOOLEAN DEFAULT FALSE,
    consent_timestamp DATETIME,
    result JSON,
    error TEXT,
    loopai_execution_id VARCHAR(255),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_email (email),
    INDEX idx_status (status),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB;

-- Admin users table
CREATE TABLE IF NOT EXISTS admin_users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_login DATETIME
) ENGINE=InnoDB;
```

---

## Directory Structure After Completion

```
container/
├── frontend/
│   ├── Dockerfile
│   └── nginx.conf
├── python/
│   ├── Dockerfile
│   └── gunicorn.conf.py
└── mysql/
    └── init.sql
```

---

## Acceptance Criteria

- [ ] Each container builds successfully
- [ ] Python container runs Gunicorn with 4 workers
- [ ] Frontend serves both user and admin apps
- [ ] Nginx proxies /api and /socket.io to Python
- [ ] MySQL initializes with schema

---

## Dependencies

- Task 01 (docker-compose.yaml)

---

## Next Task

- `03-python-api-structure.md`
