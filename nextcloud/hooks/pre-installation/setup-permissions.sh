#!/bin/sh
set -e

# Ensure Nextcloud data directory exists with correct ownership and permissions for www-data
if [ -d "/var/www/html/data" ]; then
    chown -R www-data:www-data /var/www/html/data
    chmod 770 /var/www/html/data
else
    mkdir -p /var/www/html/data
    chown -R www-data:www-data /var/www/html/data
    chmod 770 /var/www/html/data
fi
