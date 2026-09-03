#!/bin/bash
set -e

# Buzz Sistem Kurulum Sihirbazı

echo "=========================================="
echo "    🚀 BUZZ SİSTEMİ KURULUM SİHİRBAZI"
echo "=========================================="
echo "Bu sihirbaz, Buzz ve Hermes ekosistemi için gerekli çevre"
echo "değişkenlerini (.env) yapılandırmanıza yardımcı olur."
echo ""

# Yardımcı: Rastgele şifre üretme
generate_password() {
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24 ; echo
}

# Yardımcı: 64 karakterli hex private key üretme
generate_hex_key() {
    tr -dc 'a-f0-9' </dev/urandom | head -c 64 ; echo
}

# Var olan .env oku
if [ -f ".env" ]; then
    echo "ℹ️  Mevcut .env dosyası tespit edildi, varsayılan değerler buradan yüklenecek."
    source .env
elif [ -f "env-sample.txt" ]; then
    source env-sample.txt
fi

DEFAULT_POSTGRES_USER="${POSTGRES_USER:-buzz_user}"
DEFAULT_POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(generate_password)}"
DEFAULT_REDIS_PASSWORD="${REDIS_PASSWORD:-$(generate_password)}"
DEFAULT_MINIO_ROOT_USER="${MINIO_ROOT_USER:-minioadmin}"
DEFAULT_MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-$(generate_password)}"
DEFAULT_NEXTCLOUD_ADMIN_USER="${NEXTCLOUD_ADMIN_USER:-admin}"
DEFAULT_NEXTCLOUD_ADMIN_PASSWORD="${NEXTCLOUD_ADMIN_PASSWORD:-$(generate_password)}"
DEFAULT_DOMAIN_NAME="${DOMAIN_NAME:-localhost}"
DEFAULT_BUZZ_AUTO_MIGRATE="${BUZZ_AUTO_MIGRATE:-true}"
DEFAULT_BUZZ_REQUIRE_AUTH_TOKEN="${BUZZ_REQUIRE_AUTH_TOKEN:-true}"
DEFAULT_BUZZ_RELAY_PRIVATE_KEY="${BUZZ_RELAY_PRIVATE_KEY:-$(generate_hex_key)}"
DEFAULT_RELAY_OWNER_PUBKEY="${RELAY_OWNER_PUBKEY:-}"
DEFAULT_BUZZ_REQUIRE_RELAY_MEMBERSHIP="${BUZZ_REQUIRE_RELAY_MEMBERSHIP:-false}"
DEFAULT_OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"
DEFAULT_LLM_MODEL="${DEFAULT_MODEL:-openrouter/free}"

echo "--- 1. Veritabanı ve Önbellek Ayarları ---"
read -rp "PostgreSQL Kullanıcı Adı [$DEFAULT_POSTGRES_USER]: " input_pg_user
POSTGRES_USER=${input_pg_user:-$DEFAULT_POSTGRES_USER}

read -rp "PostgreSQL Şifresi [Gizli/Varsayılan Kullanılacak]: " input_pg_pass
POSTGRES_PASSWORD=${input_pg_pass:-$DEFAULT_POSTGRES_PASSWORD}

read -rp "Redis Şifresi [Gizli/Varsayılan Kullanılacak]: " input_redis_pass
REDIS_PASSWORD=${input_redis_pass:-$DEFAULT_REDIS_PASSWORD}

read -rp "MinIO Kullanıcı Adı [$DEFAULT_MINIO_ROOT_USER]: " input_minio_user
MINIO_ROOT_USER=${input_minio_user:-$DEFAULT_MINIO_ROOT_USER}

read -rp "MinIO Şifresi [Gizli/Varsayılan Kullanılacak]: " input_minio_pass
MINIO_ROOT_PASSWORD=${input_minio_pass:-$DEFAULT_MINIO_ROOT_PASSWORD}

echo ""
echo "--- 2. Nextcloud Bulut Depolama Ayarları ---"
read -rp "Nextcloud Yönetici Kullanıcı Adı [$DEFAULT_NEXTCLOUD_ADMIN_USER]: " input_nc_user
NEXTCLOUD_ADMIN_USER=${input_nc_user:-$DEFAULT_NEXTCLOUD_ADMIN_USER}

read -rp "Nextcloud Yönetici Şifresi [Gizli/Varsayılan Kullanılacak]: " input_nc_pass
NEXTCLOUD_ADMIN_PASSWORD=${input_nc_pass:-$DEFAULT_NEXTCLOUD_ADMIN_PASSWORD}

echo ""
echo "--- 3. Etki Alanı (Domain) ve Ağ Ayarları ---"
read -rp "Domain Adı (örn: domaininiz.com veya localhost) [$DEFAULT_DOMAIN_NAME]: " input_domain
DOMAIN_NAME=${input_domain:-$DEFAULT_DOMAIN_NAME}

echo ""
echo "--- 4. Buzz Relay Ayarları ---"
read -rp "Relay Sahibi Pubkey (64-char hex, kapalı relay için isteğe bağlı) [$DEFAULT_RELAY_OWNER_PUBKEY]: " input_relay_owner
RELAY_OWNER_PUBKEY=${input_relay_owner:-$DEFAULT_RELAY_OWNER_PUBKEY}

if [ -n "$RELAY_OWNER_PUBKEY" ]; then
    CALCULATED_REQUIRE_MEMBERSHIP="true"
else
    CALCULATED_REQUIRE_MEMBERSHIP="false"
fi
read -rp "Relay Üyelik Zorunluluğu (true/false) [${DEFAULT_BUZZ_REQUIRE_RELAY_MEMBERSHIP:-$CALCULATED_REQUIRE_MEMBERSHIP}]: " input_require_membership
BUZZ_REQUIRE_RELAY_MEMBERSHIP=${input_require_membership:-${DEFAULT_BUZZ_REQUIRE_RELAY_MEMBERSHIP:-$CALCULATED_REQUIRE_MEMBERSHIP}}
BUZZ_AUTO_MIGRATE="${DEFAULT_BUZZ_AUTO_MIGRATE}"

read -rp "Relay Auth Token Zorunluluğu (true/false) [$DEFAULT_BUZZ_REQUIRE_AUTH_TOKEN]: " input_require_auth
BUZZ_REQUIRE_AUTH_TOKEN=${input_require_auth:-$DEFAULT_BUZZ_REQUIRE_AUTH_TOKEN}

read -rp "Relay Private Key (64-char hex) [Gizli/Varsayılan Kullanılacak]: " input_relay_privkey
BUZZ_RELAY_PRIVATE_KEY=${input_relay_privkey:-$DEFAULT_BUZZ_RELAY_PRIVATE_KEY}

echo ""
echo "--- 5. Yapay Zeka (LLM) API Ayarları ---"
read -rp "OpenRouter API Key [$DEFAULT_OPENROUTER_API_KEY]: " input_openrouter
OPENROUTER_API_KEY=${input_openrouter:-$DEFAULT_OPENROUTER_API_KEY}

read -rp "Varsayılan LLM Modeli [$DEFAULT_LLM_MODEL]: " input_model
DEFAULT_MODEL=${input_model:-$DEFAULT_LLM_MODEL}

# .env dosyasına yaz
cat <<EOF > .env
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}
MINIO_ROOT_USER=${MINIO_ROOT_USER}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
NEXTCLOUD_ADMIN_USER=${NEXTCLOUD_ADMIN_USER}
NEXTCLOUD_ADMIN_PASSWORD=${NEXTCLOUD_ADMIN_PASSWORD}
DOMAIN_NAME=${DOMAIN_NAME}
BUZZ_AUTO_MIGRATE=${BUZZ_AUTO_MIGRATE}
BUZZ_REQUIRE_RELAY_MEMBERSHIP=${BUZZ_REQUIRE_RELAY_MEMBERSHIP}
BUZZ_REQUIRE_AUTH_TOKEN=${BUZZ_REQUIRE_AUTH_TOKEN}
BUZZ_RELAY_PRIVATE_KEY=${BUZZ_RELAY_PRIVATE_KEY}
RELAY_OWNER_PUBKEY=${RELAY_OWNER_PUBKEY}
OPENROUTER_API_KEY=${OPENROUTER_API_KEY}
DEFAULT_MODEL=${DEFAULT_MODEL}
EOF

chmod 600 .env

echo ""
echo "=========================================="
echo "✅ .env dosyası başarıyla oluşturuldu/güncellendi!"
echo "=========================================="
echo "Yapılandırma özeti:"
echo "  - Domain: $DOMAIN_NAME"
echo "  - Postgres User: $POSTGRES_USER"
echo "  - Nextcloud User: $NEXTCLOUD_ADMIN_USER"
echo "  - LLM Model: $DEFAULT_MODEL"
echo ""

read -rp "Sistemi şimdi başlatmak ister misiniz? (y/N): " confirm_start
if [[ "$confirm_start" =~ ^[Yy]$ ]]; then
    if command -v docker &> /dev/null; then
        echo "🚀 Docker Compose ile servisler başlatılıyor..."
        docker compose up -d
        echo "🎉 Sistem başlatıldı!"
        echo "🌐 Arayüze erişim: http://$DOMAIN_NAME (veya https://$DOMAIN_NAME)"
    else
        echo "⚠️ Docker komutu bulunamadı. Lütfen Docker'ı kurduktan sonra './buzz-start start' veya 'docker compose up -d' komutunu çalıştırın."
    fi
else
    echo "İşlem tamamlandı. İstediğiniz zaman './buzz-start start' veya 'docker compose up -d' ile başlatabilirsiniz."
fi
