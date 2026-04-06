# Task 01: Docker Compose Setup

**Priority:** High
**Status:** Pending
**Estimated Effort:** Medium

---

## Objective

Create the main `docker-compose.yaml` file that orchestrates all containers.

---

## Tasks

### 1.1 Create docker-compose.yaml

```yaml
version: '3.8'

services:
  frontend:
    build:
      context: ./frontend
      dockerfile: ../container/frontend/Dockerfile
    ports:
      - "8080:80"
    volumes:
      - ./frontend:/app
      - ./data/frontend/logs:/var/log/nginx
    depends_on:
      - python
    networks:
      - vbwd-network

  python:
    build:
      context: ./python
      dockerfile: ../container/python/Dockerfile
    ports:
      - "5000:5000"
    volumes:
      - ./python:/app
      - ./data/python/logs:/app/logs
    environment:
      - FLASK_ENV=development
      - DATABASE_URL=mysql://vbwd:vbwd@mysql:3306/vbwd
    depends_on:
      - mysql
    networks:
      - vbwd-network

  mysql:
    image: mysql:8.0
    ports:
      - "3306:3306"
    volumes:
      - ./data/mysql:/var/lib/mysql
      - ./container/mysql/init.sql:/docker-entrypoint-initdb.d/init.sql
    environment:
      - MYSQL_ROOT_PASSWORD=root
      - MYSQL_DATABASE=vbwd
      - MYSQL_USER=vbwd
      - MYSQL_PASSWORD=vbwd
    networks:
      - vbwd-network

networks:
  vbwd-network:
    driver: bridge
```

### 1.2 Create .env.example

```env
# Database
MYSQL_ROOT_PASSWORD=root
MYSQL_DATABASE=vbwd
MYSQL_USER=vbwd
MYSQL_PASSWORD=vbwd

# Flask
FLASK_ENV=development
FLASK_SECRET_KEY=change-me-in-production

# LoopAI Integration
LOOPAI_API_URL=http://loopai-web:5000
LOOPAI_API_KEY=

# Email
SMTP_HOST=
SMTP_PORT=587
SMTP_USER=
SMTP_PASSWORD=
```

### 1.3 Create .gitignore additions

```gitignore
# Environment
.env
*.env.local

# Data volumes
data/mysql/
data/python/logs/
data/frontend/logs/

# IDE
.idea/
.vscode/

# Python
__pycache__/
*.pyc
.pytest_cache/
venv/

# Node
node_modules/
dist/
```

---

## Acceptance Criteria

- [ ] `docker-compose up` starts all 3 containers
- [ ] Containers can communicate via `vbwd-network`
- [ ] **Frontend → Backend**: Nginx can proxy requests to Python container (`http://python:5000`)
- [ ] **Backend → Database**: Flask can connect to MySQL container (`mysql:3306`)
- [ ] MySQL data persists in `./data/mysql/`
- [ ] Logs are written to `./data/*/logs/`
- [ ] Environment variables loaded correctly

### Container Communication Test

```bash
# Verify frontend can reach backend
docker-compose exec frontend curl -s http://python:5000/health

# Verify backend can reach database
docker-compose exec python python -c "
from sqlalchemy import create_engine
engine = create_engine('mysql+pymysql://vbwd:vbwd@mysql:3306/vbwd')
conn = engine.connect()
print('Database connection: OK')
conn.close()
"
```

---

## Dependencies

- None (first task)

---

## Next Task

- `02-container-configs.md`
