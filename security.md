# `knowledgebase_with_buzz` — Yerel Kurulum Güvenlik Değerlendirmesi

Repo: `ertugerata/knowledgebase_with_buzz` (master)
İncelenen dosyalar: `docker-compose.yaml`, `Caddyfile`, `env-sample.txt`, `scripts/setup-wizard.sh`, `buzz-start`, `*/Dockerfile`, `nextcloud/hooks/*`, `postgres-init/*`, `hermes/mcp_config.json`

Bu proje; Caddy (reverse proxy), Nextcloud, Postgres, Redis, MinIO, Qdrant, browserless/Chromium ve bir "Hermes" LLM ajanını tek bir `docker-compose.yaml` altında birleştiren bir "kişisel bilgi tabanı" yığını. Yerel/ev kullanımı için makul bir tasarım ama birkaç nokta, özellikle **ağınızdaki başka cihazlara veya internete açılırsa** ciddi risk taşıyor.

## Yüksek Öncelikli Bulgular

### 1. Varsayılan / zayıf sırlar `env-sample.txt` içinde
`POSTGRES_PASSWORD`, `REDIS_PASSWORD`, `MINIO_ROOT_PASSWORD`, `NEXTCLOUD_ADMIN_PASSWORD` gibi alanlar `...GizliSifre123!` gibi tahmin edilebilir örnek değerlerle geliyor; `MINIO_ROOT_USER/PASSWORD` ise kod içinde de `minioadmin/minioadmin` varsayılanına düşüyor (`${MINIO_ROOT_USER:-minioadmin}`). Kurulum sihirbazı (`setup-wizard.sh`) boş girişte bu örnek şifreleri (ya da rastgele üretilenleri) `.env`'e yazıyor, dolayısıyla dikkatsiz bir kurulumda bu zayıf/varsayılan kimlik bilgileri prod'a kadar taşınabilir.
**Öneri:** `env-sample.txt`'deki tüm alanları boş bırakın veya `CHANGE_ME` gibi açık placeholder kullanın; wizard'da boş girişe izin vermeyip zorunlu rastgele üretim yapın.

### 2. Buzz relay için kimlik doğrulama varsayılan olarak kapalı
`BUZZ_REQUIRE_AUTH_TOKEN=false` ve `BUZZ_REQUIRE_RELAY_MEMBERSHIP=false` varsayılan değerler. Yani relay, "kapalı" bir yapılandırma yapmadığınız sürece herkesin (ağınıza erişebilen herkesin) auth token'sız bağlanıp mesaj göndermesine izin veriyor. Bu, sadece tek kullanıcılı/izole bir laptop için kabul edilebilir ama Caddy 80/443 portları LAN'a veya internete açıldığı an relay'i açık bir yayın noktasına çeviriyor.
**Öneri:** Tek kullanıcı senaryosu dışında `RELAY_OWNER_PUBKEY` ve `BUZZ_REQUIRE_AUTH_TOKEN=true` ayarlarını zorunlu kılın.

### 3. Caddy host-eşleşmesi sadece `localhost` / `127.0.0.1`
`Caddyfile`'da tanımlı iki site bloğu var: `http://localhost, http://127.0.0.1` ve `{$DOMAIN_NAME:localhost}`. Caddy istekleri **Host header**'a göre eşleştirir; `DOMAIN_NAME` ayarlanmazsa bu ikinci blok da yalnızca "localhost" host header'ını kabul eder. Sonuç: makinenin gerçek LAN IP'si veya Chromebook'taki Linux VM IP'si üzerinden erişmeye çalıştığınızda Host header eşleşmediği için Caddy isteğe cevap vermez (bu, aşağıdaki ChromeOS sorusuyla doğrudan ilgili).
**Not (güvenlik açısı):** Bu aslında yanlışlıkla faydalı bir kısıtlama — TLS/SNI doğrulaması olmadan rastgele Host header'larla erişimi engelliyor. Ancak `DOMAIN_NAME`'i bir alan adına çevirip dışarı açtığınızda, Caddy'nin otomatik HTTPS'i devreye girecek ve sertifika/ACME akışı internetten erişilebilirlik gerektirecektir; bunu bilerek yapılandırmak gerekir.

### 4. MinIO ve Qdrant için kimlik doğrulama/ağ izolasyonu eksik
- `qdrant` servisi `6333:6333` ile doğrudan host'a açılmış ve Qdrant'ın API'si varsayılan olarak **kimlik doğrulamasız**dır (API key ayarlanmadıkça). Bu container'a erişebilen herkes tüm vektör koleksiyonlarını okuyup silebilir.
- `createbuckets` adımı `mc anonymous set download myminio/buzz-media` çalıştırıyor; yani `buzz-media` bucket'ı **herkese açık okunabilir** hale geliyor. Bucket içeriğine (medya/ekler) kim erişebiliyorsa (ağ + port açıksa) kimlik doğrulamasız indirme yapabilir.
**Öneri:** Qdrant'a `QDRANT__SERVICE__API_KEY` tanımlayın ve host'a port yayınlamayın (yalnız `buzz_network` üzerinden erişilsin); MinIO bucket'ını gerçekten herkese açık medya barındırma amaçlı değilse `anonymous set none` yapın veya imzalı URL'ler kullanın.

### 5. Hermes ajanına harici komut/URL çekme yeteneği veriliyor
`mcp_config.json`, `mcp-server-fetch` (rastgele URL getirme) ve `browserless` (headless Chromium, "Instagram/X scraping" için) araçlarını LLM ajanına tanımlıyor; ayrıca Nextcloud WebDAV kimlik bilgileri (`WEBDAV_USER`/`WEBDAV_PASSWORD`) ortam değişkeni olarak Hermes container'ına veriliyor. Bir LLM ajanına hem "serbestçe web'den içerik çek" hem de "bulut depolamana WebDAV ile yaz" yetkisi vermek, prompt injection yoluyla veri sızdırma/manipülasyon riski taşır (ör. taranan bir web sayfası ajana gizli talimat enjekte edip Nextcloud'daki dosyaları okuyup dışarı göndermesini sağlayabilir).
**Öneri:** Fetch/browserless araçlarının çıktısını güvenilmeyen veri olarak ele alan bir sistem promptu/filtre katmanı olduğundan emin olun; WebDAV kimlik bilgilerini mümkünse salt-okunur veya sınırlı bir alt dizine kısıtlayın.

## Orta Öncelikli Bulgular

### 6. Postgres init script'i `CURRENT_USER`'a geniş yetki veriyor
`postgres-init/init-nextcloud-db.sql`, `nextcloud` veritabanını oluşturup tüm yetkileri (`GRANT ALL`, şema sahipliği dahil) bağlanan kullanıcıya (`buzz_user`) veriyor. Tek-kullanıcı senaryoda sorun değil, ama aynı Postgres örneğinde başka servisler/uygulamalar barındırırsanız, `buzz_user`'ın diğer veritabanlarına da bu denli geniş yetkiyle bağlanmadığından emin olun (SQL burada sadece `nextcloud` DB'sine yetki veriyor, bu iyi; ama `buzz` DB'sinin izinleri `docker-compose.yaml` içindeki `POSTGRES_DB=buzz` ile örtük olarak oluşuyor ve ayrıca sınırlandırılmamış).

### 7. `.env` dosya izinleri sadece wizard tarafından korunuyor
`setup-wizard.sh` `.env` dosyasını `chmod 600` ile oluşturuyor (iyi). Ancak `buzz-start`'ın "wizard'ı atla, `env-sample.txt`'yi `.env` olarak kopyala" yolunda (`cp env-sample.txt .env`) hiçbir `chmod` çağrılmıyor — bu durumda `.env` dosyası, umask'a bağlı olarak diğer yerel kullanıcılar tarafından okunabilir izinlerde kalabilir.
**Öneri:** Bu kopyalama adımından hemen sonra `chmod 600 .env` ekleyin.

### 8. Sağlık kontrolleri ve dahili servisler arasında düz metin sırlar
Redis şifresi, Postgres şifresi, MinIO anahtarları vb. tüm servislere ortam değişkeni olarak düz metin geçiliyor (bu docker-compose için normaldir, ancak `docker inspect`/`docker compose config` çıktısı veya container loglarına yanlışlıkla sızabilir). Container'lara host üzerinde erişimi olan başka kullanıcılar `docker inspect` ile bu sırları kolayca görebilir.
**Öneri:** Çok kullanıcılı bir host'ta çalıştırıyorsanız Docker secrets veya harici bir secret manager değerlendirin.

### 9. `redis` şifresiz veri klasörü, `postgres_data`/`nextcloud_data` host'a bind-mount
Veritabanı ve Nextcloud verileri repo dizini altında düz klasörlere (`./postgres_data`, `./nextcloud_data`) mount ediliyor. Bu klasörlerin izinleri repo'yu klonlayan kullanıcının umask'ına bağlı; paylaşımlı bir makinede (örn. ChromeOS Linux/Crostini konteyneri paylaşan bir kullanıcı grubu) başka yerel kullanıcılar bu verilere erişebilir.

## Düşük Öncelikli / Bilgi Amaçlı

- `nextcloud/hooks/pre-installation/setup-permissions.sh` betiği `chmod 770` kullanıyor — makul, `www-data` dışına yazma izni vermiyor.
- `browserless/chromium` container'ı `--no-sandbox` gibi bayraklarla mı çalıştırılıyor kontrol edilmedi (Dockerfile'da görünmüyor, muhtemelen imajın varsayılanı); headless tarayıcı ile rastgele siteleri (Instagram/X scraping) taramak SSRF ve iç ağ keşfi riski taşır çünkü `buzz_network` içindeki diğer servislere (`postgres:5432`, `redis:6379` vb.) container üzerinden erişilebilir olabilir.
- `OPENROUTER_API_KEY` internet üzerinden bir LLM sağlayıcısına gönderiliyor; Nextcloud'daki özel belgeler Hermes tarafından bu bulut LLM'e bağlam olarak gönderiliyorsa, bu verilerin üçüncü tarafa (OpenRouter ve seçilen model sağlayıcısı) gittiğini unutmayın.

## Özet Tablo

| # | Bulgu | Risk | Öncelik |
|---|-------|------|---------|
| 1 | Zayıf/varsayılan örnek şifreler | Kimlik bilgisi tahmini | Yüksek |
| 2 | Relay auth/membership varsayılan kapalı | Yetkisiz erişim | Yüksek |
| 3 | Caddy sadece `localhost` host eşleşmesi | Yanlış yapılandırma riski (dışarı açarken) | Bilgi/Orta |
| 4 | Qdrant açık port + MinIO herkese açık bucket | Veri sızıntısı | Yüksek |
| 5 | LLM ajanına fetch+WebDAV yetkisi | Prompt injection / veri sızıntısı | Yüksek |
| 6 | Geniş Postgres yetkileri | Yatay hareket (çok servisli host'ta) | Orta |
| 7 | `.env` izin eksikliği (fallback yolda) | Yerel bilgi ifşası | Orta |
| 8 | Sırların ortam değişkeninde düz metin olması | Yerel bilgi ifşası | Orta |
| 9 | Veri klasörlerinin bind-mount izinleri | Yerel bilgi ifşası | Düşük/Orta |

---

## Ek: ChromeOS + Docker'da neden `localhost`'a ulaşamıyorsunuz?

ChromeOS'ta Docker'ı doğrudan çalıştıramazsınız — Docker, **Crostini (Linux için ChromeOS)** adı verilen ayrı bir Linux sanal makinesi (VM) içinde çalışır. Bu, üç ayrı ağ katmanı olduğu anlamına gelir:

1. **ChromeOS'un kendisi** (tarayıcının çalıştığı katman)
2. **Crostini/Termina Linux VM'i** (Docker daemon'ın içinde çalıştığı yer)
3. **Docker container'ları** (`buzz-caddy`, `nextcloud-app` vb.)

`localhost`, her katmanda **o katmanın kendisini** ifade eder; bir katmandaki `localhost` diğerine otomatik olarak yönlenmez. Yani:

- Container içindeki `localhost` → yalnızca o container'ın kendisi.
- Linux VM'in `localhost`'u → Docker'ın `-p 80:80` ile yayınladığı portları görür (çünkü Docker aynı VM'de çalışıyor).
- **ChromeOS tarayıcısının `localhost`'u ise ChromeOS'un kendisidir — Crostini VM'i değil.** Chromebook'unuzdaki Chrome'da `http://localhost` yazdığınızda bu istek hiçbir zaman Linux VM'ine ulaşmaz.

### Bunu nasıl çözersiniz

1. **VM'in IP adresini kullanın.** Crostini terminalinde şunu çalıştırın:
   ```bash
   ip addr show eth0 | grep "inet "
   ```
   Genelde `100.115.92.x` gibi bir adres görürsünüz. Chrome'da `http://localhost` yerine `http://100.115.92.x` yazmayı deneyin.

2. **Ama bu repo'da bu tek başına yetmez** — yukarıdaki 3. maddede açıklandığı gibi, `Caddyfile` yalnızca `Host: localhost` veya `Host: 127.0.0.1` header'ını kabul ediyor. VM IP'sine gittiğinizde Caddy'ye ulaşan istek `Host: 100.115.92.x` header'ı taşır ve **hiçbir site bloğuyla eşleşmez**, bu yüzden bağlantı "reddedilmiş" gibi değil ama "boş/hiçbir şey dönmüyor" gibi davranabilir. Çözüm: `.env`'de `DOMAIN_NAME` değişkenini o VM IP'sine (veya `nip.io` gibi bir wildcard DNS servisiyle `100-115-92-x.nip.io` gibi bir adrese) ayarlayıp container'ları yeniden başlatın; ya da geçici test için Caddyfile'a `http://100.115.92.x` gibi bir site bloğu ekleyin.

3. **Alternatif: `ports:` blokları ChromeOS'a kadar port yönlendirmesi yapmıyor olabilir.** Crostini varsayılan olarak Linux konteynerindeki bazı portları otomatik olarak ChromeOS'a yönlendirir (port forwarding), ama bu **manuel olarak etkinleştirilmesi gereken** bir ayardır: ChromeOS Ayarlar → Gelişmiş → Geliştiriciler → Linux geliştirme ortamı → **Bağlantı noktaları** kısmından 80 (ve gerekirse 443) portu için "Bağlantı noktası yönlendirme" eklemeniz gerekir. Bu yapılmadan Chrome'daki `localhost` isteği Linux VM'ine hiç ulaşmaz.

4. **HTTPS/443 için ekstra zorluk:** Caddy, `DOMAIN_NAME` "localhost" değilse otomatik HTTPS/ACME sertifika almaya çalışır ve bunun için genel internetten erişilebilir bir alan adı gerekir; salt yerel IP ile bunu tetiklerseniz sertifika alma başarısız olabilir. Yerel test için `DOMAIN_NAME=localhost` bırakıp Caddy'nin dahili self-signed sertifikasını kullanmak veya port yönlendirmesini gerçek `localhost` üzerinden yapmak daha basittir.

**Özetle sıralama:**
1. ChromeOS Ayarlar'dan 80/443 portları için port yönlendirmesini açın (bu, Linux VM'indeki gerçek `localhost:80`'i ChromeOS'un `localhost:80`'ine bağlar — bu durumda Caddy'nin `Host: localhost` eşleşmesi de sorunsuz çalışır).
2. Port yönlendirmesi açıksa ve hâlâ ulaşamıyorsanız, `docker compose ps` ile `buzz-caddy` container'ının gerçekten "healthy" ve `0.0.0.0:80->80/tcp` olarak port yayınladığını doğrulayın.
3. Hâlâ sorun varsa VM'in IP'sini deneyin ve `DOMAIN_NAME`'i buna göre güncelleyin (madde 2, üstte).
