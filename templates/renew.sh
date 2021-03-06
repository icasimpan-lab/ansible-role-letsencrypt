#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

cd {{ letsencrypt_dir }}/{{ item.name }}

# do nothing if certificate is valid for more than 30 days (30*24*60*60)
[ -s signed.crt ] && openssl x509 -noout -in signed.crt -checkend 2592000 > /dev/null && exit

if ! lsof -i:80 > /dev/null; then
    mkdir -p serve/.well-known
    ln -sf "{{ letsencrypt_challenge_dir }}" serve/.well-known/acme-challenge
    cd serve
    python3 -m http.server 80 > /dev/null &
    cd ..
fi

python ../acme-tiny/acme_tiny.py --account-key account.key --csr domain.csr --acme-dir {{ letsencrypt_challenge_dir }} > signed.crt
cat signed.crt ../lets-encrypt-x3-cross-signed.pem > chained.crt
cat chained.crt domain.key > chained_cert+key.pem

pkill -f -9 "python3 -m http.server 80" || true
rm -rf serve

if [ -s /etc/init.d/apache2 ]; then
    ansible --connection=local -i localhost, -m service -a "name=apache2 state=reloaded" localhost > /dev/null
fi

if [ -s /etc/init.d/dovecot ]; then
    ansible --connection=local -i localhost, -m service -a "name=dovecot state=reloaded" localhost > /dev/null
fi

if [ -s /etc/init.d/postfix ]; then
    ansible --connection=local -i localhost, -m service -a "name=postfix state=reloaded" localhost > /dev/null
fi
