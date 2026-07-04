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

## Perché ogni scelta

### Tema Astra (non Divi, non Avada)

Astra pesa ~50KB, è compatibile con WooCommerce e page builder, ma funziona benissimo anche da solo con Gutenberg. Un tema multipurpose pesante (Avada, Divi) aggiunge decine di migliaia di righe di CSS/JS inutilizzate. Con un child theme le modifiche manuali sopravvivono agli aggiornamenti del tema padre.

### Nessun page builder di default

Elementor, Beaver Builder e simili sono plugin da installare solo se servono. Partire senza ti dà un sito più veloce, e decidi dopo se serve. Gutenberg nativo (l'editor di WordPress) oggi copre già la maggior parte dei casi d'uso, landing page incluse.

### Redis, non solo MySQL

WordPress usa MySQL per tutto, incluse le sessioni e la cache degli oggetti. Redis accelera le query ripetute tenendo i dati in RAM invece di leggere sempre dal disco. Su hosting condiviso spesso non è disponibile; in Docker è un container in più e si attiva con una riga.

### Password generate, non hardcodate

Ogni progetto ha credenziali diverse, generate casualmente e salvate in `credentials.txt` (gitignorato). Nessuna password tipo "admin123" committata nel repo pubblico. Le chiavi di sicurezza (salts) sono prese dall'API ufficiale di WordPress, non generate in locale con un PRNG debole.

### Plugin minimi (solo sicurezza + cache)

- **redis-cache**: necessario per usare Redis, senza non serve a nulla
- **limit-login-attempts-reloaded**: blocchi di forza bruta gratis, non richiede configurazione

Nessun plugin "all-in-one" SEO o security page builder: si installano dopo se servono. Ogni plugin in più è superficie d'attacco e peso in pagina.

### Versioni pinned (6.7, 8.0.40, 5.2, 7.4)

`latest` si rompe quando esce una major. Pinnare le versioni garantisce che oggi funzioni e tra 6 mesi funzioni uguale. Quando vuoi aggiornare cambi un numero in modo esplicito e controllato.

### .htaccess generato, non vuoto

WordPress scrive da solo le regole di rewrite in `.htaccess`, ma non crea il file se non esiste. Lo script lo pre-crea così `wp rewrite flush --hard` non fallisce. Le regole di sicurezza (gzip, caching, blocchi) sono aggiunte dopo.

### Permalink /%postname%/

L'URL di default `?p=123` è orribile per SEO e leggibilità. `/%postname%/` produce URL puliti (`/chi-siamo/` invece di `/?page_id=5`). WordPress non lo imposta di default per retrocompatibilità, ma per un progetto nuovo non ha senso tenere gli ID nell'URL.

### Child theme per il codice custom

Le modifiche a `functions.php` o ai template di Astra si perdono all'aggiornamento del tema. Con un child theme il codice custom resta separato e non si sovrascrive mai. Il child theme creato include già la pulizia dell'head (emoji, oembed, shortlink, RSD, generator tag) e il redirect da pagine autore a homepage (anti-user-enumeration).

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
