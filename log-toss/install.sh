#!/bin/sh

aptitude update && aptitude install -y --without-recommends awscli
mkdir /etc/log-toss
cp log-toss.conf /etc/log-toss/log-toss.conf
chmod +x log-toss.sh
cp log-toss.sh /usr/bin/log-toss
