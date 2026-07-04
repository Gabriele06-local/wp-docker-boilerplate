# WordPress Docker Boilerplate

Crea un progetto WordPress locale in 30 secondi con Docker — sicuro, riproducibile, production-ready.

## Prerequisiti

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Windows/Mac/Linux)
- PowerShell 5.1+ (Windows) o bash (Mac/Linux)

## Utilizzo

```powershell
.\new-wp-project.ps1 -ProjectName MioSito
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

| Parametro | Default | Descrizione |
|---|---|---|
| `-ProjectName` | obbligatorio | Nome del progetto / cartella |
| `-Port` | `8080` | Porta per WordPress |
| `-DbPort` | `3307` | Porta per MySQL |
| `-SkipPlugins` | `$false` | Salta installazione plugin |

## Struttura progetto

```
NomeProgetto/
├── docker-compose.yml      # Container definition
├── .htaccess               # Sicurezza e performance
├── .gitignore              # Esclude uploads, db_data, credenziali
├── credentials.txt         # Password generate (gitignorato)
└── wp-content/
    ├── themes/astra-child/ # Tema child preconfigurato
    ├── plugins/
    └── uploads/
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
