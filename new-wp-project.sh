#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="${1:?Usage: $0 <ProjectName> [Port] [DbPort]}"
PORT="${2:-8080}"
DB_PORT="${3:-3307}"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)/$PROJECT_NAME"
THEMES_DIR="$ROOT_DIR/wp-content/themes"
PLUGINS_DIR="$ROOT_DIR/wp-content/plugins"
UPLOADS_DIR="$ROOT_DIR/wp-content/uploads"

echo "Creazione progetto $PROJECT_NAME..."

mkdir -p "$THEMES_DIR" "$PLUGINS_DIR" "$UPLOADS_DIR"

# ---- Generate secrets ----
rand() { openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c "$1"; }
DB_PASS=$(rand 24)
DB_ROOT_PASS=$(rand 24)
ADMIN_PASS=$(rand 16)
TABLE_PREFIX="wp_$(rand 6 | tr '[:upper:]' '[:lower:]')_"

# ---- Fetch WordPress salt keys ----
echo "Recupero chiavi di sicurezza da WordPress.org..."
SALT_ENV=""
SALT_KEYS=$(curl -sf https://api.wordpress.org/secret-key/1.1/salt/ 2>/dev/null || true)
if [ -n "$SALT_KEYS" ]; then
    while IFS= read -r line; do
        if [[ "$line" =~ define\(\'([A-Z_]+)\',\s*\'(.+)\'\) ]]; then
            key="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
            SALT_ENV+="      WORDPRESS_${key}: '${val}'"$'\n'
        fi
    done <<< "$SALT_KEYS"
else
    echo "  [WARN] Impossibile scaricare le salt keys, genero valori casuali."
    for k in AUTH_KEY SECURE_AUTH_KEY LOGGED_IN_KEY NONCE_KEY AUTH_SALT SECURE_AUTH_SALT LOGGED_IN_SALT NONCE_SALT; do
        SALT_ENV+="      WORDPRESS_${k}: '$(rand 40)'"$'\n'
    done
fi

# ---- docker-compose.yml ----
cat > "$ROOT_DIR/docker-compose.yml" <<YAML
services:
  wordpress:
    image: wordpress:6.7-php8.3-apache
    container_name: ${PROJECT_NAME}_wp
    ports:
      - "127.0.0.1:${PORT}:80"
    environment:
      WORDPRESS_DB_HOST: db
      WORDPRESS_DB_USER: wpuser
      WORDPRESS_DB_PASSWORD: '${DB_PASS}'
      WORDPRESS_DB_NAME: ${PROJECT_NAME}_db
      WORDPRESS_TABLE_PREFIX: ${TABLE_PREFIX}
      WORDPRESS_DEBUG: 0
${SALT_ENV}      WORDPRESS_CONFIG_EXTRA: |
        define('DISALLOW_FILE_EDIT', true);
        define('WP_AUTO_UPDATE_CORE', 'minor');
        define('WP_POST_REVISIONS', 5);
        define('AUTOSAVE_INTERVAL', 120);
        define('EMPTY_TRASH_DAYS', 14);
    volumes:
      - ./wp-content/themes:/var/www/html/wp-content/themes
      - ./wp-content/plugins:/var/www/html/wp-content/plugins
      - ./wp-content/uploads:/var/www/html/wp-content/uploads
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/wp-login.php"]
      interval: 15s
      timeout: 5s
      retries: 10

  db:
    image: mysql:8.0.40
    container_name: ${PROJECT_NAME}_db
    ports:
      - "127.0.0.1:${DB_PORT}:3306"
    environment:
      MYSQL_DATABASE: ${PROJECT_NAME}_db
      MYSQL_USER: wpuser
      MYSQL_PASSWORD: '${DB_PASS}'
      MYSQL_ROOT_PASSWORD: '${DB_ROOT_PASS}'
    command: --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci
    volumes:
      - db_data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  redis:
    image: redis:7.4-alpine
    container_name: ${PROJECT_NAME}_redis
    restart: unless-stopped
    command: redis-server --maxmemory 128mb --maxmemory-policy allkeys-lru

  phpmyadmin:
    image: phpmyadmin:5.2
    container_name: ${PROJECT_NAME}_pma
    ports:
      - "127.0.0.1:$((PORT + 1)):80"
    environment:
      PMA_HOST: db
      PMA_USER: wpuser
      PMA_PASSWORD: '${DB_PASS}'
    depends_on:
      - db
    restart: unless-stopped

volumes:
  db_data:
YAML

# ---- .htaccess ----
cat > "$ROOT_DIR/.htaccess" <<'HTACCESS'
# BEGIN WordPress
RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
# END WordPress

# --- Security ---
Options -Indexes
ServerSignature Off

<Files wp-config.php>
    Order deny,allow
    Deny from all
</Files>

<Files xmlrpc.php>
    Order deny,allow
    Deny from all
</Files>

<FilesMatch "\.(htaccess|htpasswd|ini|log|sh|sql|conf)$">
    Order allow,deny
    Deny from all
</FilesMatch>

<IfModule mod_headers.c>
    Header set X-Content-Type-Options "nosniff"
    Header set X-Frame-Options "SAMEORIGIN"
    Header set Referrer-Policy "strict-origin-when-cross-origin"
    Header unset X-Powered-By
</IfModule>

# --- Performance ---
<IfModule mod_deflate.c>
    AddOutputFilterByType DEFLATE text/html text/css text/plain text/xml application/xml application/javascript application/json
</IfModule>

<IfModule mod_expires.c>
    ExpiresActive On
    ExpiresByType image/jpg "access plus 1 year"
    ExpiresByType image/jpeg "access plus 1 year"
    ExpiresByType image/png "access plus 1 year"
    ExpiresByType image/webp "access plus 1 year"
    ExpiresByType text/css "access plus 1 month"
    ExpiresByType application/javascript "access plus 1 month"
</IfModule>
HTACCESS

# ---- .gitignore ----
cat > "$ROOT_DIR/.gitignore" <<'GITIGNORE'
wp-content/uploads/
db_data/
credentials.txt
*.log
GITIGNORE

echo "Avvio container..."
cd "$ROOT_DIR"
docker compose up -d

# ---- Wait for WordPress ----
echo "Attendo che WordPress sia pronto..."
for i in $(seq 1 30); do
    sleep 3
    if curl -sf "http://localhost:$PORT/wp-admin/install.php" >/dev/null 2>&1; then
        break
    fi
done

# Install WP-CLI
docker exec "${PROJECT_NAME}_wp" bash -c "curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && chmod +x wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp"

wp() { docker exec "${PROJECT_NAME}_wp" wp "$@" --allow-root; }

echo "Installazione WordPress..."
wp core install --url="http://localhost:$PORT" --title="$PROJECT_NAME" --admin_user=admin --admin_password="$ADMIN_PASS" --admin_email=admin@example.com

wp language core install it_IT
wp site switch-language it_IT
wp rewrite structure '/%postname%/'
wp rewrite flush --hard
wp post delete 1 2 3 --force

# ---- Child theme ----
CHILD_DIR="$THEMES_DIR/astra-child"
mkdir -p "$CHILD_DIR"

cat > "$CHILD_DIR/style.css" <<'CSS'
/*
Theme Name: Astra Child
Template: astra
Version: 1.0.0
*/
CSS

cat > "$CHILD_DIR/functions.php" <<'PHP'
<?php
add_action('wp_enqueue_scripts', function() {
    wp_enqueue_style('astra-child-style',
        get_stylesheet_directory_uri() . '/custom.css',
        ['astra-theme-css'],
        wp_get_theme()->get('Version')
    );
});
remove_action('wp_head', 'print_emoji_detection_script', 7);
remove_action('wp_print_styles', 'print_emoji_styles');
remove_action('wp_head', 'wp_oembed_add_discovery_links');
remove_action('wp_head', 'wp_shortlink_wp_head');
remove_action('wp_head', 'rsd_link');
remove_action('wp_head', 'wlwmanifest_link');
remove_action('wp_head', 'wp_generator');

add_filter('xmlrpc_enabled', '__return_false');

add_action('template_redirect', function () {
    if (is_author()) {
        wp_redirect(home_url(), 301);
        exit;
    }
});
PHP

touch "$CHILD_DIR/custom.css"

# ---- Astra theme ----
wp theme install astra --activate
wp theme activate astra-child

# ---- Create pages ----
declare -A PAGES
PAGES[Home]="home"
PAGES[Chi Siamo]="chi-siamo"
PAGES[Servizi]="servizi"
PAGES[Blog]="blog"
PAGES[Contatti]="contatti"

for title in "${!PAGES[@]}"; do
    wp post create --post_type=page --post_title="$title" --post_name="${PAGES[$title]}" --post_status=publish --post_author=1
done

# ---- Homepage & blog page ----
HOME_ID=$(wp post list --post_type=page --post_name=home --format=ids)
BLOG_ID=$(wp post list --post_type=page --post_name=blog --format=ids)
wp option update show_on_front page
wp option update page_on_front "$HOME_ID"
wp option update page_for_posts "$BLOG_ID"

# ---- Menu ----
wp menu create "Menu Principale"
wp menu location assign "Menu Principale" primary
wp menu location assign "Menu Principale" mobile_menu

for slug in "${PAGES[@]}"; do
    PAGE_ID=$(wp post list --post_type=page --post_name="$slug" --format=ids)
    wp menu item add-post "Menu Principale" "$PAGE_ID"
done

# ---- Plugins ----
echo "Installazione plugin..."
wp plugin install redis-cache --activate
wp redis enable
wp plugin install limit-login-attempts-reloaded --activate
wp plugin delete hello akismet

# ---- Credentials ----
cat > "$ROOT_DIR/credentials.txt" <<CRED
Progetto:        $PROJECT_NAME
URL:             http://localhost:$PORT
Admin user:      admin
Admin password:  $ADMIN_PASS
DB name:         ${PROJECT_NAME}_db
DB user:         wpuser
DB password:     $DB_PASS
DB root password:$DB_ROOT_PASS
Table prefix:    $TABLE_PREFIX
phpMyAdmin:      http://localhost:$((PORT + 1))

NON committare questo file. E' incluso in .gitignore.
CRED

echo ""
echo "Completato!"
echo "WordPress:  http://localhost:$PORT"
echo "Admin:      http://localhost:$PORT/wp-admin  (admin / $ADMIN_PASS)"
echo "phpMyAdmin: http://localhost:$((PORT + 1))"
echo "Credenziali salvate in: $ROOT_DIR/credentials.txt"
echo ""
echo "Stop: docker compose down (nella cartella $ROOT_DIR)"
