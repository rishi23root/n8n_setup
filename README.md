# n8n Docker Compose Setup with SSL

A production-ready Docker Compose setup for [n8n](https://n8n.io/) workflow automation platform with PostgreSQL database, Nginx reverse proxy, and automatic SSL certificate management using Let's Encrypt.

## Features

- 🚀 **n8n** - Workflow automation platform
- 🐘 **PostgreSQL 16** - Persistent database storage
- 🔒 **Nginx** - Reverse proxy with SSL/TLS termination
- 📜 **Let's Encrypt** - Automatic SSL certificate management
- 🔄 **Auto-restart** - All services configured with restart policies
- 🛡️ **Security** - Trust proxy configuration for rate limiting
- 📁 **Volume Management** - Persistent data storage for n8n and PostgreSQL

## Prerequisites

- Linux server (Ubuntu/Debian recommended)
- Domain name pointing to your server's IP address
- Ports 80 and 443 open and accessible from the internet
- Docker and Docker Compose installed (or the script will install them)
- Sudo access

## Quick Start

### 1. Clone or Download the Project

```bash
git clone <your-repo-url> n8n-compose
cd n8n-compose
```

### 2. Create Environment File

Copy the example environment file and edit it with your values:

```bash
cp .env.example .env
nano .env  # or use your preferred editor
```

Edit the following required variables in `.env`:
- `DOMAIN_NAME` - Your domain name (e.g., `example.com`)
- `SUBDOMAIN` - Subdomain for n8n (e.g., `n8n`)
- `EMAIL` - Your email for Let's Encrypt notifications
- `DB_POSTGRESDB_PASSWORD` - Strong password for PostgreSQL database

Optional variables (with defaults):
- `DB_POSTGRESDB_USER` - Defaults to `n8n`
- `DB_POSTGRESDB_DATABASE` - Defaults to `n8n`
- `GENERIC_TIMEZONE` - Timezone (e.g., `America/New_York`)
- `EXTERNAL_IP` - Auto-detected if not set

### 3. Run the Setup Script

The `run.sh` script will:
- Install Docker and Docker Compose (if not already installed)
- Detect your external IP address
- Obtain SSL certificates from Let's Encrypt
- Start all services

```bash
chmod +x run.sh
./run.sh
```

**Note:** The script requires sudo access for Docker installation and certificate management.

### 4. Access n8n

Once the setup completes, access n8n at:
```
https://<subdomain>.<domain-name>
```

For example: `https://n8n.example.com`

## Manual Setup (Alternative)

If you prefer to set up manually:

### 1. Create `.env` file

```bash
cp .env.example .env
nano .env  # Edit with your values
```

See `.env.example` for all available variables and their descriptions.

### 2. Obtain SSL Certificate

```bash
# Stop nginx if running
docker compose stop nginx

# Run certbot to obtain certificate
docker run --rm \
  --name certbot_initial \
  -p 80:80 \
  -v "$(pwd)/letsencrypt:/etc/letsencrypt" \
  certbot/certbot certonly --standalone \
  --agree-tos --non-interactive \
  --preferred-challenges http \
  -d <subdomain>.<domain-name> -m <your-email>
```

### 3. Start Services

```bash
docker compose up -d
```

## Project Structure

```
n8n-compose/
├── docker-compose.yml      # Main Docker Compose configuration
├── run.sh                  # Automated setup script
├── .env.example            # Environment variables template
├── .env                    # Environment variables (create from .env.example)
├── nginx/
│   ├── nginx.conf          # Main Nginx configuration
│   ├── conf.d/
│   │   └── default.conf    # Nginx server blocks
│   └── entrypoint.sh       # Nginx entrypoint script
├── letsencrypt/            # SSL certificates (auto-generated)
│   ├── live/               # Current certificates
│   └── www/                # Webroot for ACME challenges
└── local-files/            # Local file storage for n8n
```

## Configuration

### Environment Variables

All environment variables are configured in the `.env` file. Copy `.env.example` to `.env` and edit with your values:

```bash
cp .env.example .env
nano .env
```

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DOMAIN_NAME` | Yes | - | Your domain name (e.g., `example.com`) |
| `SUBDOMAIN` | Yes | - | Subdomain for n8n (e.g., `n8n`) |
| `EMAIL` | Yes | - | Email for Let's Encrypt notifications |
| `DB_POSTGRESDB_PASSWORD` | Yes | - | PostgreSQL database password |
| `DB_POSTGRESDB_USER` | No | `n8n` | PostgreSQL username |
| `DB_POSTGRESDB_DATABASE` | No | `n8n` | PostgreSQL database name |
| `GENERIC_TIMEZONE` | No | - | Timezone for n8n (e.g., `America/New_York`) |
| `EXTERNAL_IP` | No | Auto-detected | Server's external IP address |

See `.env.example` for detailed comments and examples for each variable.

### n8n Configuration

The n8n service is configured with the following environment variables:
- `N8N_HOST` - Set to your full domain
- `N8N_PROTOCOL` - Set to `https`
- `N8N_TRUST_PROXY` - Enabled for proper rate limiting behind reverse proxy
- `N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS` - Enabled for security
- `WEBHOOK_URL` - Set to your HTTPS URL

## Usage

### View Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f n8n
docker compose logs -f postgres
docker compose logs -f nginx
```

### Stop Services

```bash
docker compose stop
```

### Start Services

```bash
docker compose start
```

### Restart Services

```bash
docker compose restart
```

### Stop and Remove Containers

```bash
docker compose down
```

**Warning:** This will stop containers but preserve volumes (data).

### Remove Everything (Including Volumes)

```bash
docker compose down -v
```

**Warning:** This will delete all data including workflows and database!

## SSL Certificate Renewal

SSL certificates from Let's Encrypt are valid for 90 days. The setup script handles initial certificate issuance. For renewal, you can:

1. **Manual Renewal:**
   ```bash
   docker run --rm \
     -v "$(pwd)/letsencrypt:/etc/letsencrypt" \
     certbot/certbot renew
   docker compose restart nginx
   ```

2. **Automatic Renewal:** Set up a cron job or systemd timer to run the renewal command periodically.

## Troubleshooting

### Port 80 Already in Use

If port 80 is already in use, the certificate issuance will fail. Free port 80 before running the setup:

```bash
# Check what's using port 80
sudo netstat -tuln | grep :80
# or
sudo lsof -i :80

# Stop the conflicting service
sudo systemctl stop <service-name>
```

### Certificate Issues

- Ensure your domain DNS points to your server's IP
- Verify ports 80 and 443 are accessible from the internet
- Check firewall settings
- Review certbot logs: `docker compose logs certbot`

### n8n Not Accessible

1. Check if all services are running:
   ```bash
   docker compose ps
   ```

2. Check nginx logs:
   ```bash
   docker compose logs nginx
   ```

3. Verify SSL certificate paths in `nginx/conf.d/default.conf` match your domain

4. Ensure `N8N_TRUST_PROXY=true` is set (already configured)

### Database Connection Issues

- Verify PostgreSQL is healthy:
  ```bash
  docker compose ps postgres
  ```

- Check database logs:
  ```bash
  docker compose logs postgres
  ```

- Verify environment variables in `.env` file

### Rate Limiting Warning

If you see warnings about `X-Forwarded-For` header and trust proxy:
- This is already fixed with `N8N_TRUST_PROXY=true` in the configuration
- Restart n8n if you see the warning: `docker compose restart n8n`

## Backup and Restore

### Backup

```bash
# Backup database
docker compose exec postgres pg_dump -U n8n n8n > backup_$(date +%Y%m%d).sql

# Backup n8n data
docker compose exec n8n tar czf /tmp/n8n_backup.tar.gz /home/node/.n8n
docker compose cp n8n:/tmp/n8n_backup.tar.gz ./n8n_backup_$(date +%Y%m%d).tar.gz
```

### Restore

```bash
# Restore database
cat backup_YYYYMMDD.sql | docker compose exec -T postgres psql -U n8n n8n

# Restore n8n data
docker compose cp ./n8n_backup_YYYYMMDD.tar.gz n8n:/tmp/
docker compose exec n8n tar xzf /tmp/n8n_backup_YYYYMMDD.tar.gz -C /
```

## Security Considerations

- Change default database passwords
- Keep Docker and images updated
- Regularly renew SSL certificates
- Review nginx security headers in `nginx/conf.d/default.conf`
- Consider firewall rules to restrict access
- Use strong passwords for n8n user accounts
- Enable two-factor authentication in n8n settings

## Updating

### Update n8n

```bash
docker compose pull n8n
docker compose up -d n8n
```

### Update All Services

```bash
docker compose pull
docker compose up -d
```

## Support

For issues related to:
- **n8n**: Check [n8n documentation](https://docs.n8n.io/)
- **Docker**: Check [Docker documentation](https://docs.docker.com/)
- **Let's Encrypt**: Check [Certbot documentation](https://eff-certbot.readthedocs.io/)

## License

This project is provided as-is. n8n itself is licensed under [Sustainable Use License](https://github.com/n8n-io/n8n/blob/master/LICENSE.md).

## Contributing

Feel free to submit issues and enhancement requests!

