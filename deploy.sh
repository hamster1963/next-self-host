#!/bin/bash

# Env Vars
POSTGRES_USER="myuser"
POSTGRES_PASSWORD=$(openssl rand -base64 12)  # Generate a random 12-character password
POSTGRES_DB="mydatabase"
SECRET_KEY="my-secret" # for the demo app
NEXT_PUBLIC_SAFE_KEY="safe-key" # for the demo app
DOMAIN_NAME="nextselfhost.dev" # replace with your own
EMAIL="your-email@example.com" # replace with your own

# Script Vars
REPO_URL="https://github.com/leerob/next-self-host.git"
APP_DIR=~/myapp
SWAP_SIZE="1G"  # Swap size of 1GB

# Update package list and upgrade existing packages
sudo apt update && sudo apt upgrade -y

# Add Swap Space
echo "Adding swap space..."
sudo fallocate -l $SWAP_SIZE /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make swap permanent
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Install Docker
sudo apt install apt-transport-https ca-certificates curl software-properties-common -y
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt update
sudo apt install docker-ce -y

# Install Docker Compose
sudo rm -f /usr/local/bin/docker-compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

# Wait for the file to be fully downloaded before proceeding
if [ ! -f /usr/local/bin/docker-compose ]; then
  echo "Docker Compose download failed. Exiting."
  exit 1
fi

sudo chmod +x /usr/local/bin/docker-compose

# Ensure Docker Compose is executable and in path
sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Verify Docker Compose installation
docker-compose --version
if [ $? -ne 0 ]; then
  echo "Docker Compose installation failed. Exiting."
  exit 1
fi

# Ensure Docker starts on boot and start Docker service
sudo systemctl enable docker
sudo systemctl start docker

# Clone the Git repository
if [ -d "$APP_DIR" ]; then
  echo "Directory $APP_DIR already exists. Pulling latest changes..."
  cd $APP_DIR && git pull
else
  echo "Cloning repository from $REPO_URL..."
  git clone $REPO_URL $APP_DIR
  cd $APP_DIR
fi

# Generate DATABASE_URL
DATABASE_URL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:5432/$POSTGRES_DB"

# Create the .env file inside the app directory (~/myapp/.env)
echo "POSTGRES_USERNAME=$POSTGRES_USER" > "$APP_DIR/.env"
echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" >> "$APP_DIR/.env"
echo "POSTGRES_DATABASE=$POSTGRES_DB" >> "$APP_DIR/.env"
echo "DATABASE_URL=$DATABASE_URL" >> "$APP_DIR/.env"
echo "SECRET_KEY=$SECRET_KEY" >> "$APP_DIR/.env"
echo "NEXT_PUBLIC_SAFE_KEY=$NEXT_PUBLIC_SAFE_KEY" >> "$APP_DIR/.env"

# Install Nginx
sudo apt install nginx -y

# Remove default Nginx config if it exists, ignore errors
sudo rm -f /etc/nginx/sites-enabled/default

# Stop Nginx temporarily to allow Certbot to run in standalone mode
sudo systemctl stop nginx

# Obtain SSL certificate using Certbot standalone mode
sudo apt install certbot -y
sudo certbot certonly --standalone -d $DOMAIN_NAME --non-interactive --agree-tos -m $EMAIL

# Ensure SSL files exist or generate them
if [ ! -f /etc/letsencrypt/options-ssl-nginx.conf ]; then
  sudo wget https://raw.githubusercontent.com/certbot/certbot/main/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf -P /etc/letsencrypt/
fi

if [ ! -f /etc/letsencrypt/ssl-dhparams.pem ]; then
  sudo openssl dhparam -out /etc/letsencrypt/ssl-dhparams.pem 2048
fi

# Create Nginx config with HTTP-to-HTTPS redirect and SSL support
sudo cat > /etc/nginx/sites-available/myapp <<EOL
server {
    listen 80;
    server_name $DOMAIN_NAME;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Accel-Buffering no;  # Disable buffering for streaming support
    }

    # Redirect all HTTP requests to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name $DOMAIN_NAME;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Accel-Buffering no;  # Disable buffering for streaming support
    }
}
EOL

# Create symbolic link if it doesn't already exist
if [ ! -L /etc/nginx/sites-enabled/myapp ]; then
  sudo ln -s /etc/nginx/sites-available/myapp /etc/nginx/sites-enabled/
fi

# Restart Nginx to apply the new configuration
sudo systemctl restart nginx

# Build and run the Docker containers from the app directory (~/myapp)
cd $APP_DIR
sudo docker-compose up -d

# Check if Docker Compose started correctly
if ! sudo docker-compose ps | grep "Up"; then
  echo "Docker containers failed to start. Check logs with 'docker-compose logs'."
  exit 1
fi

# Output final message
echo "Deployment complete. Your Next.js app and PostgreSQL database are now running. 
Next.js is available at https://$DOMAIN_NAME, and the PostgreSQL database is accessible from the web service.

The .env file has been created with the following values:
- POSTGRES_USERNAME
- POSTGRES_PASSWORD (randomly generated)
- POSTGRES_DATABASE
- DATABASE_URL
- SECRET_KEY
- NEXT_PUBLIC_SAFE_KEY"
