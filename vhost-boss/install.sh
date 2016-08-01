#!/bin/sh
command -v pip >/dev/null 2>&1 || { echo "Huh? The python-pip package isn't installed. Aborting." >&2; exit 1; }

echo "Installing xkcdpass"
pip -q install xkcdpass

echo "Installing vhost-boss"
groupadd -g 3000 vhosted
mkdir /usr/share/vhost-boss
mkdir /var/lib/vhost-boss
cp -r templates /usr/share/vhost-boss/templates
cp vhost-boss.pl /usr/sbin/vhost-boss
cp logrotate-nginx.conf /etc/logrotate.d/nginx
chmod +x /usr/sbin/vhost-boss
cp -r nginx-recipes /etc/nginx/vhost-boss-recipes

echo "Everything is OK!";
