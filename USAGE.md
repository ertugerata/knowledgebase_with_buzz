# 🐝 Buzz & Hermes Sistem Detaylı Kullanım Kılavuzu (USAGE.md)

Bu kılavuz, **Buzz & Hermes Agent** ekosisteminin kurulumunu, yapılandırmasını, servis bağımlılıklarını, ters vekil (Caddy) ayarlarını, Model Context Protocol (MCP) entegrasyonlarını, vektör hafıza (Qdrant) kullanımını ve sorun giderme adımlarını kapsamlı bir şekilde sunmaktadır.

---

## 🚀 1. Başlangıç ve Sistem Kurulumu

Proje, tüm servisleri izole Docker ağında (`buzz_network`) çalıştıran optimize edilmiş bir `docker-compose.yaml` altyapısına sahiptir.

### 🧙‍♂️ 1.1 İnteraktif Kurulum Sihirbazı (`./scripts/setup-wizard.sh`)

Sistemi yapılandırmanın en pratik ve güvenli yolu interaktif kurulum sihirbazını kullanmaktır:

```bash
./buzz-start wizard
# veya
bash scripts/setup-wizard.sh
```

Sihirbaz sırasıyla şu yapılandırma adımlarını tamamlar:

1. **Veritabanı ve Önbellek Kimlik Bilgileri:**
   - PostgreSQL kullanıcı adı ve güvenli şifre belirleme.
   - Redis güvenli bağlantı şifresi belirleme.
2. **Nextcloud Bulut Depolama Ayarları:**
   - Yönetici (admin) kullanıcı adı ve şifresi belirleme.
3. **Ağ ve Etki Alanı (Domain) Ayarları:**
   - Caddy sunucusunun SSL/TLS sertifikası alacağı alan adı (`DOMAIN_NAME`, örn: `buzz.example.com` veya `localhost`).
4. **OpenRouter LLM API Anahtarı:**
   - Hermes Agent'ın Gemini 3.1 Flash ve Llama 3.3 70B modellerini çağırmak için kullanacağı `OPENROUTER_API_KEY` tanımı.

Yapılandırma tamamlandığında proje kökünde güvenli haklara sahip (chmod 600) bir `.env` dosyası otomatik olarak yazılır.

---

## ⚙️ 2. Sistem Yönetim Betiği (`./buzz-start`)

Sistemi başlatmak, durdurmak ve izlemek için tek bir komut arayüzü (`./buzz-start`) bulunur:

| Komut | Açıklama |
| :--- | :--- |
| `./buzz-start start` | `.env` dosyasını kontrol eder, eksikse sihirbazı başlatır ve servisleri ayağa kaldırır (`docker compose up -d`). |
| `./buzz-start stop` | Çalışan tüm servisleri veri kaybı olmadan durdurur. |
| `./buzz-start restart` | Tüm servisleri sırasıyla yeniden başlatır. |
| `./buzz-start status` / `./buzz-start ps` | Servislerin aktif/pasif durumunu ve port eşleşmelerini gösterir. |
| `./buzz-start logs [servis_adi]` | Servis loglarını canlı takip eder (örn: `./buzz-start logs hermes` veya tümü için `./buzz-start logs`). |
| `./buzz-start wizard` | Kurulum sihirbazını tekrar çalıştırır. |
| `./buzz-start down` | Servisleri durdurur ve konteynerleri kaldırır. |

---

## 🛡️ 3. Caddy Reverse Proxy & Domain Yapılandırması

Sistemde web trafiği ve SSL yönetimi `caddy:2-alpine` imajı ile sağlanır. `Caddyfile` dosyası etki alanınızı dinamik olarak dinleyecek şekilde konfigüre edilmiştir.

### 📄 `Caddyfile` İçeriği:
```caddy
{$DOMAIN_NAME} {
    reverse_proxy nextcloud-app:80

    handle /relay* {
        reverse_proxy buzz-relay:3000
    }
}
```

- **Ana Web Trafiği (`/`):** Doğrudan Nextcloud uygulamasına yönlendirilir.
- **WebSocket / Relay Trafiği (`/relay*`):** `buzz-relay` (Port 3000) servisine yönlendirilir.
- **Otomatik SSL:** Gerçek bir domain kullanıldığında Caddy otomatik Let's Encrypt / ZeroSSL sertifikası alır.

---

## 🧠 4. Hermes Agent ve Model Context Protocol (MCP)

Hermes Agent, OpenRouter bulut LLM sağlayıcısını kullanarak yüksek akıl yürütme ve görev icra etme yeteneğine sahiptir.

### 🤖 4.1 Kullanılan LLM Modelleri
- **Default Model:** `google/gemini-3.1-flash` (Hızlı yanıt ve genel görev icrası)
- **Deep Research Model:** `meta-llama/llama-3.3-70b-instruct` (Karmaşık araştırmalar ve analizler)

### 🔌 4.2 MCP Konfigürasyonu (`mcp_config.json`)
Hermes Agent dış dünya ile etkileşimini `mcp_config.json` dosyası üzerinden sağlar:

```json
{
  "mcpServers": {
    "fetch": {
      "command": "uvx",
      "args": [
        "mcp-server-fetch"
      ]
    },
    "youtube-transcript": {
      "command": "npx",
      "args": [
        "-y",
        "@mcp/youtube-transcript"
      ]
    }
  }
}
```

- **`fetch`:** Web sayfalarını içerik çekmek üzere işler.
- **`youtube-transcript`:** YouTube videolarının altyazı ve transkriptlerini otomatik çeker.

---

## 📦 5. Nextcloud WebDAV Entegrasyonu & Hafıza Yönetimi

Hermes Agent, uzun süreli hafıza ve bilgi tabanı dosyalarını Nextcloud üzerindeki WebDAV protokolü ile senkronize tutar.

- **WebDAV Endpoint:** `http://nextcloud-app:80/remote.php/dav/files/${NEXTCLOUD_ADMIN_USER}/Bilgi_Tabani/`
- **Vektör Hafıza (Qdrant):** `http://qdrant:6333` adresi üzerinde çalışır. Belgelerin vektör gömmeleri (embeddings) Qdrant vektör veritabanında saklanır.
- **Headless Browser (Browserless):** `ws://browserless:3000` adresi üzerinden X (Twitter), Instagram veya JavaScript tabanlı dinamik sitelerin kazınmasını (scraping) üstlenir.

---

## 🔍 6. Sorun Giderme ve Teşhis (Troubleshooting)

### ❓ 1. Servisler Başlamıyor veya Hata Veriyor
- Port çatışması olup olmadığını kontrol edin (`80`, `443`, `6333`).
- Logları inceleyin:
  ```bash
  ./buzz-start logs
  ```

### ❓ 2. Nextcloud WebDAV Bağlantı Hatası
- Nextcloud ilk açılışta veritabanı kurulumunu tamamlıyor olabilir. Birkaç dakika bekleyip `./buzz-start status` ile servis durumunu teyit edin.
- `.env` dosyasındaki `NEXTCLOUD_ADMIN_USER` ve `NEXTCLOUD_ADMIN_PASSWORD` değerlerinin doğru girildiğinden emin olun.

### ❓ 3. OpenRouter API Hatası
- `.env` dosyasındaki `OPENROUTER_API_KEY` değerinizin geçerli ve bakiyeli olduğunu teyit edin.
