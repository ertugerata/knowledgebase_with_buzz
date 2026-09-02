# 🐝 Buzz & Hermes Sistem Detaylı Kullanım Kılavuzu (USAGE.md)

Bu kılavuz, **Buzz & Hermes Agent** ekosisteminin kurulumunu, yapılandırmasını, servis bağımlılıklarını, ters vekil (Caddy) ayarlarını, Model Context Protocol (MCP) entegrasyonlarını, vektör hafıza (Qdrant) kullanımını, günlük dosya ve bilgi tabanı kullanımını, mobil/masaüstü erişim adımlarını ve sorun giderme adımlarını kapsamlı bir şekilde sunmaktadır.

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
| `./buzz-start health` / `./buzz-start check` | Her bir konteynerin sağlık durumunu (healthy/starting/unhealthy) detaylı şekilde kontrol eder. |
| `./buzz-start logs [servis_adi]` | Servis loglarını canlı takip eder (örn: `./buzz-start logs hermes` veya tümü için `./buzz-start logs`). |
| `./buzz-start wizard` | Kurulum sihirbazını tekrar çalıştırır. |
| `./buzz-start down` | Servisleri durdurur ve konteynerleri kaldırır. |

---

## 🛡️ 3. Caddy Reverse Proxy & Domain Yapılandırması

Sistemde web trafiği ve SSL yönetimi `caddy:2-alpine` imajı ile sağlanır. `Caddyfile` dosyası etki alanınızı dinamik olarak dinleyecek şekilde konfigüre edilmiştir.

### 📄 `Caddyfile` İçeriği:
```caddy
{$DOMAIN_NAME:localhost} {
    # Nextcloud client ve takvim/rehber senkronizasyonu yönlendirmeleri (.well-known)
    redir /.well-known/carddav /remote.php/dav/ 301
    redir /.well-known/caldav /remote.php/dav/ 301
    redir /.well-known/webfinger /index.php/.well-known/webfinger 301
    redir /.well-known/nodeinfo /index.php/.well-known/nodeinfo 301

    # Buzz Relay WebSocket ve HTTP trafiği yönlendirmesi
    handle /relay* {
        reverse_proxy buzz-relay:3000
    }

    # Nextcloud ana uygulama yönlendirmesi
    handle {
        reverse_proxy nextcloud-app:80
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
- **Default Model:** `openrouter/free` (Ön tanımlı ücretsiz model; `.env` içerisinde `DEFAULT_MODEL` ile dilediğiniz an değiştirebilirsiniz)
- **Deep Research Model:** `meta-llama/llama-3.3-70b-instruct` (Karmaşık araştırmalar ve analizler)

### 🔌 4.2 MCP Konfigürasyonu (`hermes/mcp_config.json`)
Hermes Agent dış dünya ile etkileşimini `hermes/mcp_config.json` dosyası üzerinden sağlar:

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

## 📂 6. Klasör Yapısı ve Düzen

Nextcloud üzerinde varsayılan olarak tanımlanan dosya ve raf mimarisi şu şekildedir:

```text
📁 Bilgi_Tabani/ (Ana Dizin)
├── 📁 01_Haftalik_Web_Takip/  --> Hermes'in dinamik sitelerden haftalık kazıdığı raporlar.
├── 📁 02_Okuma_Listesi/       --> Bilgisayar veya mobilden yüklediğiniz ham PDF / dökümanlar.
└── 📁 03_Akilli_Raflar/        --> Konularına göre otomatik ayrışan arşiv klasörleri.
    ├── 📁 #Yazilim/
    ├── 📁 #Finans/
    ├── 📁 #Saglik/
    └── 📁 #Hukuk/
```

---

## 📱 7. Döküman ve PDF Yükleme Yöntemleri

Hermes Agent'ın PDF belgelerini okuyup akademik düzeyde Türkçe özet çıkarabilmesi ve ilgili akıllı rafa kategorize edebilmesi için belgelerin `02_Okuma_Listesi/` klasörüne yüklenmesi gerekir.

| Platform | Yöntem | İşlem Adımları |
| :--- | :--- | :--- |
| **Masaüstü (Win / Mac / Linux)** | Nextcloud İstemcisi | Yerel `Bilgi_Tabani/02_Okuma_Listesi/` klasörüne sürükleyip bırakın. |
| **Masaüstü (Tarayıcı)** | Nextcloud Web | Web arayüzünden `02_Okuma_Listesi/` dizinine girip Yükle butonunu kullanın. |
| **Mobil (iOS / Android)** | Nextcloud Mobil App | Mobil cihazdaki PDF'i açıp **Paylaş > Nextcloud > 02_Okuma_Listesi** yolunu seçin. |
| **Mobil (iOS / Android)** | Dosya Yöneticisi | Mobil dosya yöneticisine ekli Nextcloud sürücüsünden doğrudan klasöre taşıyın. |

---

## 🤖 8. Otomatik Arka Plan İş Akışları (Cron Jobs)

Sistemde iki temel otomasyon senaryosu tanımlıdır:

### 🔻 Senaryo A: PDF Analizi ve Akıllı Raf Transferi (Her Gece 23:00)
- Hermes Agent saat 23:00'te `02_Okuma_Listesi/` dizinini kontrol eder.
- Yeni eklenen PDF'leri derin araştırma modeli (Llama 3.3 70B) ile analiz eder.
- İçeriğin akademik düzeyde Türkçe özetini hazırlar ve önemli çıkarımları listeler.
- Dökümanın konusuna göre `03_Akilli_Raflar/` altında uygun klasörü seçer (yoksa oluşturur).
- Orijinal PDF'i ve oluşturduğu `.md` uzantılı Türkçe özet raporunu bu akıllı rafa taşır.
- İşlem tamamlandığında `02_Okuma_Listesi/` klasörünü temizler.

### 🔻 Senaryo B: Dinamik Web Sayfası Takibi (Her Pazar 00:00)
- Hermes Agent her Pazar gece yarısı 00:00'da Buzz kanalı üzerindeki `#web-takip-listesi` başlığındaki URL'leri tarar.
- Sayfalardaki değişiklikleri veya yeni eklenen bilgileri tespit ettiğinde bir Derin Araştırma Raporu oluşturur.
- Çıkan raporu `01_Haftalik_Web_Takip/` klasörüne o günün tarihiyle (örn: `haftalik-rapor-2026-08-30.md`) kaydeder.

---

## 📲 9. Cihazlardan Erişim ve Kullanım Senaryoları

### 💬 9.1 Buzz Platformu (Nostr Protokolü)
- **Mobil Web (PWA):** Tarayıcınızdan `https://buzz.domaininiz.com` adresine girip **Ana Ekrana Ekle** seçeneğini kullanabilirsiniz.
- **Nostr İstemcileri:** iOS ve Android cihazlarda NIP-29 / NIP-42 destekli istemcilere (Primal, Amethyst, Damus vb.) `wss://buzz.domaininiz.com/relay` adresinizi ekleyebilirsiniz.
- **Soru-Cevap & Etkileşim:** Buzz kanalı üzerinden Hermes'e doğrudan mesaj atarak arşivdeki dökümanlarınız hakkında soru sorabilirsiniz (Örn: *"Hermes, geçen hafta yüklediğim rapordaki maliyet tablolarını özetler misin?"*).

### ☁️ 9.2 Nextcloud & WebDAV Entegrasyonu
- **Resmî Mobil / Masaüstü Uygulaması:** Mobil ve masaüstü Nextcloud istemcileri ile tüm klasörlerinizi eşzamanlı tutabilirsiniz.
- **WebDAV Dijital Kütüphane:** Zotero, Readdle Documents veya PDF Expert gibi uygulamalara aşağıdaki WebDAV bağlantısını ekleyebilirsiniz:
  ```text
  https://domaininiz.com/remote.php/dav/files/ADMIN_KULLANICI/Bilgi_Tabani/
  ```

---

## 🔄 10. Google Drive Senkronizasyonu (İsteğe Bağlı)

Google Drive üzerindeki belirli bir klasörün Nextcloud ile canlı senkronize kalması için sunucu tarafında `rclone` ve `cron` kullanılabilir:

```bash
# 1. Google Drive klasörünü Nextcloud dizinine senkronize etme
rclone sync gdrive:HedefKlasor /mnt/storagebox/nextcloud_data/admin/files/Bilgi_Tabani/Google_Sync/

# 2. Senkronizasyon sonrası Nextcloud dosya indeksini tarama
docker exec -u www-data nextcloud-app php occ files:scan admin
```

---

## 💡 11. Örnek Günlük Kullanım Senaryosu

1. **Gün İçi:** Mobil telefonunuzda okuduğunuz bir araştırma veya teknik makaleyi (PDF) **Paylaş > Nextcloud > 02_Okuma_Listesi** klasörüne gönderin.
2. **Gece (23:00):** Hermes arka planda çalışarak belgeyi analiz eder, Türkçe markdown özetini hazırlar ve her iki dosyayı `03_Akilli_Raflar/#Yazilim/` klasörüne taşır.
3. **Ertesi Gün:** Nextcloud veya WebDAV okuyucunuz üzerinden 2 dakikada belgenin Türkçe özetini okuyabilir veya Buzz üzerinden Hermes'e detaylı sorular yöneltebilirsiniz.

---

## 🔍 12. Sorun Giderme ve Teşhis (Troubleshooting)

### ❓ 1. Servisler Başlamıyor veya Hata Veriyor
- Port çatışması olup olmadığını kontrol edin (`80`, `443`, `6333`).
- Logları inceleyin:
  ```bash
  ./buzz-start logs
  ```

### ❓ 2. PostgreSQL "password authentication failed for user buzz_user" Hatası
`buzz-relay` loglarında `password authentication failed for user "buzz_user"` hatası alıyorsanız iki durumdan biri söz konusudur:
1. **Şifre Değişikliği:** PostgreSQL veritabanı konteyneri ilk kez başlatıldığında `.env` içindeki `POSTGRES_PASSWORD` şifresiyle veritabanı birimini (volume) oluşturur. Daha sonra `.env` içindeki şifre değiştirilirse, PostgreSQL mevcut veritabanı birimindeki eski şifreyi korur.
2. **Özel Karakterler:** Şifrede `@`, `#`, `%`, `&`, `?`, `/`, `:` gibi URL ayrıştırıcısını bozan özel karakterler varsa `DATABASE_URL` bağlantısı başarısız olur.

**Çözüm Adımları:**
- `.env` dosyanızdaki `POSTGRES_PASSWORD` ve `REDIS_PASSWORD` değerlerinin yalnızca alfa-nümerik (`A-Za-z0-9`) karakterlerden oluştuğundan emin olun (veya `./buzz-start wizard` sihirbazını tekrar çalıştırın).
- PostgreSQL birimini sıfırlayarak yeni şifreyle yeniden başlatmak için:
  ```bash
  ./buzz-start down
  docker volume rm app_postgres_data postgres_data 2>/dev/null || true
  ./buzz-start start
  ```

### ❓ 2. Nextcloud WebDAV Bağlantı Hatası
- Nextcloud ilk açılışta veritabanı kurulumunu tamamlıyor olabilir. Birkaç dakika bekleyip `./buzz-start status` ile servis durumunu teyit edin.
- `.env` dosyasındaki `NEXTCLOUD_ADMIN_USER` ve `NEXTCLOUD_ADMIN_PASSWORD` değerlerinin doğru girildiğinden emin olun.

### ❓ 3. OpenRouter API Hatası
- `.env` dosyasındaki `OPENROUTER_API_KEY` değerinizin geçerli ve bakiyeli olduğunu teyit edin.
