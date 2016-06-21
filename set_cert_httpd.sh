#!/bin/sh

#
# apacheにSSL証明書の設定
#
# Author: corokada
#

if [ -z "$1" ]; then
  echo "usage:$0 [domain-name]"
  exit 1
fi

# ドメイン設定
DOMAIN=$1

## それぞれ環境に合わせて修正をしてください。
CERTDIR="`dirname $0`/"

# httpdのパス(環境に合わせて修正)
HTTPD="/usr/sbin/httpd"

## 設定する証明書チェック
HTTPDCERT="${CERTDIR}${DOMAIN}.crt"
if [ ! -f $HTTPDCERT ]; then
  echo "'$DOMAIN'のSSL証明書がありません."
  exit 1
fi

## CONF
CONFFILE=`$HTTPD -S 2>/dev/null | grep virtualhost | grep "port 443" | grep " $DOMAIN " | cut -d'(' -f2 | cut -d':' -f1`
if [ "$CONFFILE" == "" ]; then
  echo "'$DOMAIN'のヴァーチャルドメイン設定をしてください."
  exit 1
fi

## SSL証明書は対象のssl-conf-fileと同じ場所に保存
CONFDIR="${CONFFILE%/*}/"

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

## CONFFILEの修正
# RSA
sed -i -e "/SSLCertificateFile/c\    SSLCertificateFile ${CERT}" $CONFFILE
sed -i -e "/SSLCertificateKeyFile/c\    SSLCertificateKeyFile ${KEY}" $CONFFILE
sed -i -e "/SSLCACertificateFile/c\    SSLCACertificateFile ${CA}" $CONFFILE
sed -i -e "s/#SSLVerifyClient/SSLVerifyClient/" $CONFFILE
sed -i -e "s/SSLVerifyClient/#SSLVerifyClient/" $CONFFILE
sed -i -e "s/#SSLVerifyDepth/SSLVerifyDepth/" $CONFFILE
sed -i -e "s/SSLVerifyDepth/#SSLVerifyDepth/" $CONFFILE
# ECC
if [ -f $ECCCERT ]; then
  sed -i -e "/SSLCertificateFile/i\    #ECC" $CONFFILE
  sed -i -e "/SSLCertificateFile/i\    #RSA" $CONFFILE
  sed -i -e "/#ECC/a\    SSLCACertificateFile $ECCCA" $CONFFILE
  sed -i -e "/#ECC/a\    SSLCertificateKeyFile $ECCKEY" $CONFFILE
  sed -i -e "/#ECC/a\    SSLCertificateFile $ECCCERT" $CONFFILE
  sed -i -e "/SSLCipherSuite/c\    SSLCipherSuite ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-ECDSA-AES256-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA:ECDHE-RSA-AES128-SHA:!aNULL:!eNULL:!ADH:!EXPORT:!DES:!RC4:!3DES:!MD5:!PSK" $CONFFILE
fi

## apache再起動
/usr/sbin/apachectl graceful
