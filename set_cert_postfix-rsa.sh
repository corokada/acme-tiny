#!/bin/sh

#
# postfix/dovecotにSSL証明書の設定
#
# Author: corokada
#

#
# 【利用条件】
# SSL証明書と秘密鍵ファイル名が同一
#             かつ
# 同一ディレクトに存在している時
# のみ利用可能
#   秘密鍵         ：hogehoge.com.key
#   証明書+CA証明書：hogehoge.com.crt-ca-bundle
#

if [ -z "$1" ]; then
  echo "usage:$0 [domain-name]"
  exit 1
fi

# ドメイン設定
DOMAIN=$1

## それぞれ環境に合わせて修正をしてください。
CERTDIR="`dirname $0`/"

# postfixCONFフルパス
CONFDIR="`/usr/sbin/postconf -n | grep config_directory | sed -e "s/ //g" | cut -d'=' -f2`/"

# postfix用証明書フルパス
FULLCERT="${CONFDIR}${DOMAIN}.crt-ca-bundle"

# バックアップ
## RSA証明書チェック
CERT="${CONFDIR}${DOMAIN}.crt-ca-bundle"
if [ -f $CERT ]; then
  AFTER=`openssl x509 -noout -text -dates -in $CERT | grep notAfter | cut -d'=' -f2`
  AFTER=`env TZ=JST-9 date --date "$AFTER" +%Y%m%d-%H%M`
  /bin/cp --force -pr $CERT ${CERT}.limit$AFTER
else
  AFTER=`env TZ=JST-9 date +%Y%m%d-%H%M`
fi
CSR="${CONFDIR}${DOMAIN}.csr"
if [ -f $CSR ]; then
  /bin/cp --force -pr $CSR ${CSR}.limit$AFTER
fi
KEY="${CONFDIR}${DOMAIN}.key"
if [ -f $KEY ]; then
  /bin/cp --force -pr $KEY ${KEY}.limit$AFTER
fi

## 証明書etcをコピーする
/bin/cp --force -pr ${CERTDIR}${DOMAIN}.{crt,crt-ca-bundle,csr,key} ${CONFDIR}

# conf修正(postfix)
sed -i -e "/smtpd_tls_cert_file/c\smtpd_tls_cert_file = ${FULLCERT}" /etc/postfix/main.cf
sed -i -e "/smtpd_tls_key_file/c\smtpd_tls_key_file = ${KEY}" /etc/postfix/main.cf

# conf修正(dovecot)
sed -i -e "/ssl_cert /c\ssl_cert = <${FULLCERT}" /etc/dovecot/conf.d/10-ssl.conf
sed -i -e "/ssl_key /c\ssl_key = <${KEY}" /etc/dovecot/conf.d/10-ssl.conf

# サービス再起動
/etc/init.d/postfix reload
/etc/init.d/dovecot reload
