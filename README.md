# WordPress Docker Boilerplate

Crea un progetto WordPress locale in 30 secondi con Docker — sicuro, riproducibile, production-ready.

## Prerequisiti

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Windows/Mac/Linux)
- PowerShell 5.1+ (Windows) oppure bash (Mac/Linux)

## Utilizzo

**Windows (PowerShell):**
```powershell
.\new-wp-project.ps1 -ProjectName MioSito
```

**Mac / Linux (bash):**
```bash
chmod +x new-wp-project.sh
./new-wp-project.sh MioSito
```

Dopo qualche minuto hai:

| Servizio | URL |
|---|---|
| WordPress | http://localhost:8080 |
| Admin WP | http://localhost:8080/wp-admin |
| phpMyAdmin | http://localhost:8081 |

## Cosa fa

- Crea container WordPress + MySQL + phpMyAdmin + Redis
- Installa WordPress in italiano con permalink `/%postname%/`
- Attiva tema **Astra** + child theme preconfigurato
- Crea pagine (Home, Chi Siamo, Servizi, Blog, Contatti) e menu
- Abilita Redis object cache, limita tentativi di login
- Blocca XML-RPC, user enumeration, directory browsing
- Disabilita emoji, oembed, shortlink e altri leak dall'head
- Abilita gzip, browser caching, header di sicurezza
- Genera password e chiavi crittografiche casuali

## Parametri

**PowerShell:**
| Parametro | Default | Descrizione |
|---|---|---|
| `-ProjectName` | obbligatorio | Nome del progetto |
| `-Port` | `8080` | Porta WordPress |
| `-DbPort` | `3307` | Porta MySQL |
| `-SkipPlugins` | `$false` | Salta installazione plugin |

**bash:**
```bash
./new-wp-project.sh MioSito [Port] [DbPort]
# Esempio con porte custom:
./new-wp-project.sh MioSito 8080 3307
```

## Struttura progetto

```
MioSito/
├── docker-compose.yml
├── .htaccess
├── .gitignore
├── credentials.txt      # Password generate (gitignorato)
└── wp-content/
    └── themes/astra-child/
```

## Comandi utili

```powershell
# Fermare il progetto
docker compose down

# Fermare e cancellare volume DB
docker compose down -v

# Log dei container
docker compose logs -f

# Eseguire WP-CLI
docker exec NomeProgetto_wp wp plugin list --allow-root
```

## Licenza

MIT
