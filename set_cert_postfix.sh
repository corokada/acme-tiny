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
#   証明書         ：hogehoge.com.crt
#   秘密鍵         ：hogehoge.com.key
#   CA証明書       ：hogehoge.com.ca-bundle
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

# 存在確認
if [ "$FULLCERT" = "" ]; then
  exit 0
fi

# バックアップ
## ECC証明書チェック
ECCCERT="${CONFDIR}${DOMAIN}-ecc.crt"
if [ -f $ECCCERT ]; then
  AFTER=`openssl x509 -noout -text -dates -in $ECCCERT | grep notAfter | cut -d'=' -f2`
  AFTER=`env TZ=JST-9 date --date "$AFTER" +%Y%m%d-%H%M`
  /bin/cp --force -pr $ECCCERT ${ECCCERT}.limit$AFTER
else
  AFTER=`env TZ=JST-9 date +%Y%m%d-%H%M`
fi
ECCCSR="${CONFDIR}${DOMAIN}-ecc.csr"
if [ -f $ECCCSR ]; then
  /bin/cp --force -pr $ECCCSR ${ECCCSR}.limit$AFTER
fi
ECCKEY="${CONFDIR}${DOMAIN}-ecc.key"
if [ -f $ECCKEY ]; then
  /bin/cp --force -pr $ECCKEY ${ECCKEY}.limit$AFTER
fi
ECCCA="${CONFDIR}${DOMAIN}-ecc.ca-bundle"
if [ -f $ECCCA ]; then
  /bin/cp --force -pr $ECCCA ${ECCCA}.limit$AFTER
fi

## RSA証明書チェック
CERT="${CONFDIR}${DOMAIN}.crt"
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
CA="${CONFDIR}${DOMAIN}.ca-bundle"
if [ -f $CA ]; then
  /bin/cp --force -pr $CA ${CA}.limit$AFTER
fi

## 証明書etcをコピーする
/bin/cp --force -pr ${CERTDIR}${DOMAIN}{,-ecc}.{ca-bundle,crt,csr,key} ${CONFDIR}
cat ${CERTDIR}${DOMAIN}.{crt,ca-bundle} > ${FULLCERT}

# conf修正(postfix)
sed -i -e "/smtpd_tls_cert_file/c\smtpd_tls_cert_file = ${FULLCERT}" /etc/postfix/main.cf
sed -i -e "/smtpd_tls_key_file/c\smtpd_tls_key_file = ${KEY}" /etc/postfix/main.cf

# conf修正(dovecot)
sed -i -e "/ssl_cert /c\ssl_cert = <${FULLCERT}" /etc/dovecot/conf.d/10-ssl.conf
sed -i -e "/ssl_key /c\ssl_key = <${KEY}" /etc/dovecot/conf.d/10-ssl.conf

# サービス再起動
/etc/init.d/postfix reload
/etc/init.d/dovecot reload
