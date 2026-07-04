param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectName,
    [int]$Port = 8080,
    [int]$DbPort = 3307,
    [switch]$SkipPlugins
)

$ErrorActionPreference = "Continue"

function New-RandomString {
    param([int]$Length = 20)
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    -join ((1..$Length) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
}

function Invoke-WpCli {
    param([string]$Container, [string]$Command)
    $escaped = $Command -replace '"', '\"'
    $output = docker exec $Container bash -c "wp $escaped --allow-root" 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [WARN] wp $Command -> $LASTEXITCODE" -ForegroundColor Yellow
    }
    return $output.Trim()
}

$RootDir = Join-Path $PSScriptRoot $ProjectName
$env:Path += ";$env:ProgramFiles\Docker\Docker\resources\bin"
$ThemesDir  = Join-Path $RootDir "wp-content\themes"
$PluginsDir = Join-Path $RootDir "wp-content\plugins"
$UploadsDir = Join-Path $RootDir "wp-content\uploads"

Write-Host "Creazione progetto $ProjectName..." -ForegroundColor Cyan

@($RootDir, $ThemesDir, $PluginsDir, $UploadsDir) | ForEach-Object {
    New-Item -ItemType Directory -Path $_ -Force | Out-Null
}

# ---- Generate secrets instead of hardcoding them ----
$DbPassword    = New-RandomString 24
$DbRootPassword = New-RandomString 24
$AdminPassword = New-RandomString 16
$TablePrefix   = "wp_" + (New-RandomString 6).ToLower() + "_"

# ---- Fetch real WordPress secret keys/salts ----
Write-Host "Recupero chiavi di sicurezza da WordPress.org..." -ForegroundColor Cyan
try {
    $salts = Invoke-WebRequest -Uri "https://api.wordpress.org/secret-key/1.1/salt/" -UseBasicParsing -TimeoutSec 10
    $saltLines = $salts.Content -split "`n" | Where-Object { $_ -match "define\('([A-Z_]+)',\s*'(.+)'\);" }
    $saltEnv = @{}
    foreach ($line in $saltLines) {
        if ($line -match "define\('([A-Z_]+)',\s*'(.+)'\);") {
            $saltEnv[$matches[1]] = $matches[2] -replace "'", "\'"
        }
    }
} catch {
    Write-Host "  [WARN] Impossibile scaricare le salt keys, genero valori casuali locali." -ForegroundColor Yellow
    $saltEnv = @{}
    foreach ($k in @('AUTH_KEY','SECURE_AUTH_KEY','LOGGED_IN_KEY','NONCE_KEY','AUTH_SALT','SECURE_AUTH_SALT','LOGGED_IN_SALT','NONCE_SALT')) {
        $saltEnv[$k] = New-RandomString 40
    }
}

$saltEnvYaml = ($saltEnv.GetEnumerator() | ForEach-Object {
    "      WORDPRESS_$($_.Key): '$($_.Value)'"
}) -join "`n"

# ---- docker-compose.yml (pinned versions, Redis, hardened exposure) ----
@"
services:
  wordpress:
    image: wordpress:6.7-php8.3-apache
    container_name: ${ProjectName}_wp
    ports:
      - "127.0.0.1:${Port}:80"
    environment:
      WORDPRESS_DB_HOST: db
      WORDPRESS_DB_USER: wpuser
      WORDPRESS_DB_PASSWORD: '${DbPassword}'
      WORDPRESS_DB_NAME: ${ProjectName}_db
      WORDPRESS_TABLE_PREFIX: ${TablePrefix}
      WORDPRESS_DEBUG: 0
$saltEnvYaml
      WORDPRESS_CONFIG_EXTRA: |
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
    container_name: ${ProjectName}_db
    ports:
      - "127.0.0.1:${DbPort}:3306"
    environment:
      MYSQL_DATABASE: ${ProjectName}_db
      MYSQL_USER: wpuser
      MYSQL_PASSWORD: '${DbPassword}'
      MYSQL_ROOT_PASSWORD: '${DbRootPassword}'
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
    container_name: ${ProjectName}_redis
    restart: unless-stopped
    command: redis-server --maxmemory 128mb --maxmemory-policy allkeys-lru

  phpmyadmin:
    image: phpmyadmin:5.2
    container_name: ${ProjectName}_pma
    ports:
      - "127.0.0.1:$($Port + 1):80"
    environment:
      PMA_HOST: db
      PMA_USER: wpuser
      PMA_PASSWORD: '${DbPassword}'
    depends_on:
      - db
    restart: unless-stopped

volumes:
  db_data:
"@ | Set-Content -Path (Join-Path $RootDir "docker-compose.yml") -Encoding UTF8

# ---- .htaccess: security headers, gzip, browser caching, block sensitive files ----
@"
# BEGIN WordPress
RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
# END WordPress

# --- Security hardening ---
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

# --- Performance: gzip compression ---
<IfModule mod_deflate.c>
    AddOutputFilterByType DEFLATE text/html text/css text/plain text/xml application/xml application/javascript application/json
</IfModule>

# --- Performance: browser caching for static assets ---
<IfModule mod_expires.c>
    ExpiresActive On
    ExpiresByType image/jpg "access plus 1 year"
    ExpiresByType image/jpeg "access plus 1 year"
    ExpiresByType image/png "access plus 1 year"
    ExpiresByType image/webp "access plus 1 year"
    ExpiresByType text/css "access plus 1 month"
    ExpiresByType application/javascript "access plus 1 month"
</IfModule>
"@ | Set-Content -Path (Join-Path $RootDir ".htaccess") -Encoding UTF8

# ---- .gitignore so credentials/db data never get committed ----
@"
wp-content/uploads/
db_data/
credentials.txt
*.log
"@ | Set-Content -Path (Join-Path $RootDir ".gitignore") -Encoding UTF8

Write-Host "Avvio container..." -ForegroundColor Cyan
Set-Location -Path $RootDir
docker compose up -d

Write-Host "Attendo che WordPress sia pronto..." -ForegroundColor Yellow
$maxRetries = 30
$ready = $false
for ($i = 0; $i -lt $maxRetries; $i++) {
    Start-Sleep -Seconds 3
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:$Port/wp-admin/install.php" -TimeoutSec 5 -UseBasicParsing
        if ($response.StatusCode -eq 200) { $ready = $true; break }
    } catch {}
}
if (-not $ready) {
    Write-Host "Timeout: WordPress non risponde. Verifica manualmente con 'docker compose logs'." -ForegroundColor Red
    exit 1
}

# Install WP-CLI inside container
docker exec "${ProjectName}_wp" bash -c "curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && chmod +x wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp"

Write-Host "Installazione WordPress..." -ForegroundColor Cyan
Invoke-WpCli "${ProjectName}_wp" "core install --url=http://localhost:$Port --title=`"$ProjectName`" --admin_user=admin --admin_password=`"$AdminPassword`" --admin_email=admin@example.com"

# Italian language
Invoke-WpCli "${ProjectName}_wp" "language core install it_IT"
Invoke-WpCli "${ProjectName}_wp" "site switch-language it_IT"

# Pretty permalinks (performance + SEO, off by default)
Invoke-WpCli "${ProjectName}_wp" "rewrite structure '/%postname%/'"
Invoke-WpCli "${ProjectName}_wp" "rewrite flush --hard"

# Delete default sample content
Invoke-WpCli "${ProjectName}_wp" "post delete 1 2 3 --force"

# Create child theme
$ChildDir = Join-Path $ThemesDir "astra-child"
New-Item -ItemType Directory -Path $ChildDir -Force | Out-Null
@"
/*
Theme Name: Astra Child
Template: astra
Version: 1.0.0
*/
"@ | Set-Content -Path (Join-Path $ChildDir "style.css") -Encoding UTF8

@"
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

// Disable XML-RPC (common brute-force vector)
add_filter('xmlrpc_enabled', '__return_false');

// Remove author archive user enumeration via ?author=1
add_action('template_redirect', function () {
    if (is_author()) {
        wp_redirect(home_url(), 301);
        exit;
    }
});
"@ | Set-Content -Path (Join-Path $ChildDir "functions.php") -Encoding UTF8

"" | Set-Content -Path (Join-Path $ChildDir "custom.css") -Encoding UTF8

# Install and activate Astra + Child
Invoke-WpCli "${ProjectName}_wp" "theme install astra --activate"
Invoke-WpCli "${ProjectName}_wp" "theme activate astra-child"

# Create pages (track IDs by slug)
$pageIds = @{}
$pages = @{
    "Home" = "home"
    "Chi Siamo" = "chi-siamo"
    "Servizi" = "servizi"
    "Blog" = "blog"
    "Contatti" = "contatti"
}
foreach ($title in $pages.Keys) {
    $slug = $pages[$title]
    $output = Invoke-WpCli "${ProjectName}_wp" "post create --post_type=page --post_title=`"$title`" --post_name=$slug --post_status=publish --post_author=1"
    if ($output -match 'Created post (\d+)') {
        $pageIds[$slug] = $matches[1]
    }
}

# Set homepage and blog page
Invoke-WpCli "${ProjectName}_wp" "option update show_on_front page"
Invoke-WpCli "${ProjectName}_wp" "option update page_on_front $($pageIds['home'])"
Invoke-WpCli "${ProjectName}_wp" "option update page_for_posts $($pageIds['blog'])"

# Create and assign menu
Invoke-WpCli "${ProjectName}_wp" "menu create `"Menu Principale`""
Invoke-WpCli "${ProjectName}_wp" "menu location assign `"Menu Principale`" primary"
Invoke-WpCli "${ProjectName}_wp" "menu location assign `"Menu Principale`" mobile_menu"

foreach ($slug in $pages.Values) {
    Invoke-WpCli "${ProjectName}_wp" "menu item add-post `"Menu Principale`" $($pageIds[$slug])"
}

# ---- Security & performance plugins ----
if (-not $SkipPlugins) {
    Write-Host "Installazione plugin di sicurezza e performance..." -ForegroundColor Cyan
    Invoke-WpCli "${ProjectName}_wp" "plugin install redis-cache --activate"
    Invoke-WpCli "${ProjectName}_wp" "config set WP_REDIS_HOST redis --type=constant"
    Invoke-WpCli "${ProjectName}_wp" "redis enable"
    Invoke-WpCli "${ProjectName}_wp" "plugin install limit-login-attempts-reloaded --activate"
    Invoke-WpCli "${ProjectName}_wp" "plugin delete hello akismet"
}

# ---- Save credentials locally (gitignored) instead of printing weak defaults ----
$credsPath = Join-Path $RootDir "credentials.txt"
@"
Progetto:        $ProjectName
URL:             http://localhost:$Port
Admin user:      admin
Admin password:  $AdminPassword
DB name:         ${ProjectName}_db
DB user:         wpuser
DB password:     $DbPassword
DB root password:$DbRootPassword
Table prefix:    $TablePrefix
phpMyAdmin:      http://localhost:$($Port + 1)

NON committare questo file. E' incluso in .gitignore.
"@ | Set-Content -Path $credsPath -Encoding UTF8

Write-Host "`nCompletato!" -ForegroundColor Green
Write-Host "WordPress:  http://localhost:$Port" -ForegroundColor Cyan
Write-Host "Admin:      http://localhost:$Port/wp-admin  (admin / $AdminPassword)" -ForegroundColor Cyan
Write-Host "phpMyAdmin: http://localhost:$($Port + 1)" -ForegroundColor Cyan
Write-Host "Credenziali salvate in: $credsPath" -ForegroundColor Cyan
Write-Host "`nStop: docker compose down (nella cartella $RootDir)" -ForegroundColor Yellow