#!/bin/sh

#
# SSL証明書の発行 (ECC/RSA)
#   (hogehoge.com)
#
# Author: corokada
#

if [ -z "$1" ]; then
  echo "usage:$0 [domain-name]"
  exit 1
fi

DOMAIN=$1

## それぞれ環境に合わせて修正をしてください。
CERTDIR="`dirname $0`/"

# httpdのパス
HTTPD="/usr/sbin/httpd"

# pythonのパス
PYTHON="/usr/bin/python"

# 発行プログラムのパス
SIGNPG="${CERTDIR}acme_tiny.py"

#CONF
CONFFILE=`$HTTPD -S 2>/dev/null | grep "port 80" | grep " $DOMAIN" | tr -d ' ' | cut -d'(' -f2 | cut -d':' -f1`
if [ "$CONFFILE" == "" ]; then
  echo "'$DOMAIN'のヴァーチャルドメイン設定をしてください."
  exit 1
fi

# ドキュメントルート
WEBROOT=`cat $CONFFILE | grep DocumentRoot | sed -e 's/"//g' -e "s/'//g" | awk '{print $2}' | uniq`

## ディレクトリ作成
mkdir -p $WEBROOT/.well-known/acme-challenge/

## BASIC認証回避
echo "Satisfy any"      >> ${WEBROOT}/.well-known/acme-challenge/.htaccess
echo "order allow,deny" >> ${WEBROOT}/.well-known/acme-challenge/.htaccess
echo "allow from all"   >> ${WEBROOT}/.well-known/acme-challenge/.htaccess

# ユーザー認証情報
USERKEY="${CERTDIR}user.key"
if [ ! -f $USERKEY ]; then
  openssl genrsa 4096 > $USERKEY
fi

#
# 楕円曲線暗号対応
#
if openssl ecparam -list_curves 2>/dev/null | grep -sq prime256v1; then
  # 秘密鍵作成
  ECCKEY="${CERTDIR}${DOMAIN}-ecc.key"
  if [ ! -f $ECCKEY ]; then
    openssl ecparam -name prime256v1 -genkey -out $ECCKEY
  fi

  # CSR作成
  ECCCSR="${CERTDIR}${DOMAIN}-ecc.csr"
  if [ ! -f $ECCCSR ]; then
    openssl req -new -key $ECCKEY -sha256 -nodes -subj "/CN=$DOMAIN" > $ECCCSR
  fi

  # 発行済みECC証明書バックアップ
  ECCCERT="${CERTDIR}${DOMAIN}-ecc.crt"
  if [ -f $ECCCERT ]; then
    AFTER=`openssl x509 -noout -text -dates -in $ECCCERT | grep notAfter | cut -d'=' -f2`
    AFTER=`env TZ=JST-9 date --date "$AFTER" +%Y%m%d-%H%M`
    /bin/cp --force -pr $ECCCERT ${ECCCERT}.limit$AFTER
  fi

  # ECC証明書発行処理
  cd $CERTDIR
  $PYTHON $SIGNPG --account-key $USERKEY --csr $ECCCSR --acme-dir ${WEBROOT}/.well-known/acme-challenge/ > $ECCCERT

  # ECC CA証明書
  ECCCA="${CERTDIR}${DOMAIN}-ecc.ca-bundle"
  if [ -f $ECCCA ]; then
    mv $ECCCA ${ECCCA}.limit$AFTER
  fi
  wget --no-check-certificate -q -O - https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.pem.txt > $ECCCA
fi

#
# RSA暗号対応
#
# 秘密鍵作成
RSAKEY="${CERTDIR}${DOMAIN}.key"
if [ ! -f $RSAKEY ]; then
  openssl genrsa 4096 > $RSAKEY
fi

# CSR作成
RSACSR="${CERTDIR}${DOMAIN}.csr"
if [ ! -f $RSACSR ]; then
  openssl req -new -key $RSAKEY -sha256 -nodes -subj "/CN=$DOMAIN" > $RSACSR
fi

# 発行済みRSA証明書バックアップ
RSACERT="${CERTDIR}${DOMAIN}.crt"
if [ -f $RSACERT ]; then
  AFTER=`openssl x509 -noout -text -dates -in $RSACERT | grep notAfter | cut -d'=' -f2`
  AFTER=`env TZ=JST-9 date --date "$AFTER" +%Y%m%d-%H%M`
  /bin/cp --force -pr $RSACERT ${RSACERT}.limit$AFTER
fi

# RSA証明書発行処理
cd $CERTDIR
$PYTHON $SIGNPG --account-key $USERKEY --csr $RSACSR --acme-dir ${WEBROOT}/.well-known/acme-challenge/ > $RSACERT

# RSA CA証明書
RSACA="${CERTDIR}${DOMAIN}.ca-bundle"
if [ -f $RSACA ]; then
  mv $RSACA ${RSACA}.limit$AFTER
fi
wget --no-check-certificate -q -O - https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.pem.txt > $RSACA

# 不要ファイル削除
rm -rf ${WEBROOT}/.well-known
