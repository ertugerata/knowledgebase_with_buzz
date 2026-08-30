# 🐝 Buzz & Hermes Agent Yönetim Sistemi

Bu proje, **Hermes Agent** yapay zeka temsilcisini, **Buzz Relay** mesajlaşma omurgasını, **Nextcloud** WebDAV depolamasını, **Qdrant** vektör veritabanını, **Browserless** headless tarayıcısını ve **Caddy** ters vekil (reverse proxy) sunucusunu tek bir Docker Compose orkestrasyonu altında birleştiren uçtan uca otonom yapay zeka altyapısıdır.

Sistemi kolayca yönetmek, yapılandırmak ve tek tıkla ayağa kaldırmak için `./buzz-start` yönetim betiği ve interaktif kurulum sihirbazı sunulmaktadır.

---

## 📐 Mimari ve Entegre Servisler

Sistem aşağıdaki mikroservislerden ve bileşenlerden oluşmaktadır:

```
                  +--------------------------+
                  |  Caddy (Reverse Proxy)   |
                  |     (Port 80 / 443)      |
                  +------------+-------------+
                               |
         +---------------------+---------------------+
         |                                           |
+--------v-------+                           +-------v--------+
|   Nextcloud    |                           |   Buzz Relay   |
| (WebDAV/Data)  |                           | (WebSocket/WS) |
+----------------+                           +-------+--------+
         ^                                           ^
         |                                           |
+--------+-------------------------------------------+--------+
|                       Hermes Agent                          |
|  - OpenRouter LLM (Gemini 3.1 Flash / Llama 3.3 70B)       |
|  - Qdrant Vector Memory Integration                         |
|  - Browserless Scraping Desteği                            |
|  - MCP Server Protokolleri (Fetch, YouTube Transcript)     |
+----+-----------------------+-----------------------+--------+
     |                       |                       |
+----v-----+            +----v-----+            +----v-----+
| Postgres |            |  Redis   |            |  Qdrant  |
| Database |            | In-Mem DB|            | Vector DB|
+----------+            +----------+            +----------+
```

### Servis Detayları

| Servis | Konteyner Adı | Port | Açıklama |
| :--- | :--- | :--- | :--- |
| **Caddy** | `buzz-caddy` | `80`, `443` | Otomatik SSL/TLS destekli HTTP/HTTPS Reverse Proxy. |
| **Hermes Agent** | `hermes-agent` | Dahili | OpenRouter LLM, RAG hafıza ve MCP yetenekli yapay zeka ajanı. |
| **Buzz Relay** | `buzz-relay` | `3000` (Dahili) | Güvenli WebSocket tabanlı ajan ve servis mesajlaşma omurgası. |
| **Nextcloud** | `nextcloud-app` | `80` (Dahili) | WebDAV ve dosya/bilgi tabanı depolama servisi. |
| **Qdrant** | `buzz-qdrant` | `6333` | Vektör arama ve RAG (Retrieval-Augmented Generation) hafızası. |
| **Browserless** | `buzz-browserless` | `3000` (Dahili) | Headless Chrome/Chromium web scraping altyapısı. |
| **PostgreSQL** | `buzz-postgres` | `5432` (Dahili) | Buzz ve Nextcloud için ilişkisel veritabanı. |
| **Redis** | `buzz-redis` | `6379` (Dahili) | Önbellek, kuyruk ve oturum yönetimi. |

---

## ⚡ Hızlı Başlangıç

### Önkoşullar
- **Docker** ve **Docker Compose** (v2+) yüklü olmalıdır.
- Bağlantı noktaları (`80`, `443`) çakışmamalıdır.

### 1. Kurulum Sihirbazı ile Yapılandırma
Sistemi tek adımda yapılandırmak için Türkçe kurulum sihirbazını çalıştırın:

```bash
./scripts/setup-wizard.sh
```

veya alternatif olarak:

```bash
./buzz-start wizard
```

Sihirbaz sizden şu bilgileri alarak otomatik olarak `.env` dosyasını oluşturacaktır:
- PostgreSQL ve Redis şifreleri (boş bırakırsanız otomatik güvenli şifre üretilir),
- Nextcloud yönetici hesabı bilgileri,
- Etki alanı adınız (`DOMAIN_NAME`),
- OpenRouter API anahtarınız (`OPENROUTER_API_KEY`).

### 2. Sistemi Başlatma
Sihirbaz tamamlandıktan sonra veya doğrudan aşağıdaki komutla tüm sistemi tek tıkla başlatabilirsiniz:

```bash
./buzz-start start
```

---

## 🎮 Yönetim Komutları (`./buzz-start`)

`./buzz-start` betiği tüm sistem süreçlerini kolayca kontrol etmenizi sağlar:

```bash
# Sistemi başlatır (.env yoksa sihirbazı çalıştırır)
./buzz-start start

# Çalışan tüm servislerin durumunu görüntüler
./buzz-start status

# Canlı logları izler (Tüm servisler)
./buzz-start logs

# Belirli bir servisin loglarını izler (Örn: hermes veya nextcloud)
./buzz-start logs hermes

# Servisleri yeniden başlatır
./buzz-start restart

# Servisleri geçici olarak durdurur
./buzz-start stop

# Konteynerleri durdurur ve kaldırır
./buzz-start down

# Yardım menüsünü gösterir
./buzz-start help
```

---

## 📖 Detaylı Kullanım Kılavuzu

Daha ayrıntılı yapılandırma seçenekleri, Caddy SSL/TLS ayarları, Nextcloud WebDAV entegrasyonu, MCP araçları, Qdrant RAG ayarları ve sorun giderme adımları için [USAGE.md](USAGE.md) dosyasını inceleyin.

---

## 📄 Lisans

Bu proje MIT lisansı altında sunulmaktadır.
