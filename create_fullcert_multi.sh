#!/bin/sh

#
# SSL証明書の発行 (ECC/RSA)
#   マルチドメイン(www.hogehoge.com/www.hogehoge.net)
#
# Author: corokada
#

if [ -z "$1" ]; then
  echo "usage:$0 [domain-name],[domain-name]..."
  exit 1
fi

## 引数のドメイン
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
#マルチドメインの場合はあったらアカン
for DNSs in `echo $DOMAIN | sed 's/,/ /g'`
do
  HTTPCONF=`$HTTPD -S | grep "port 80" | grep "${DNSs}"`
  if [ "$HTTPCONF" != "" ]; then
    echo "'$DOMAIN'のvhost設定があります。該当のvhostを無効にしてください。"
    exit 1
  fi
done

# ドキュメントルート
WEBROOT=`cat /etc/httpd/conf.d/virtualhost.conf | grep DocumentRoot | sed -e 's/"//g' -e "s/'//g" | awk '{print $2}' | uniq`

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

# マルチドメイン設定
TMP=`mktemp -p /tmp -t opensslconf.XXXXXXXXXXXXXXX`
cat /etc/pki/tls/openssl.cnf > $TMP
printf "[SAN]\nsubjectAltName=" >> $TMP
for DNSs in `echo $DOMAIN | sed 's/,/ /g'`
do
    printf "DNS:${DNSs}," >> $TMP
done
sed -i -e 's/,$//g' $TMP

#
# RSA暗号対応
#
# 秘密鍵作成
MULTIDOMAIN=multidomain
RSAKEY="${CERTDIR}${MULTIDOMAIN}.key"
if [ ! -f $RSAKEY ]; then
  openssl genrsa 4096 > $RSAKEY
fi

# CSR作成
RSACSR="${CERTDIR}${MULTIDOMAIN}.csr"
if [ ! -f $RSACSR ]; then
  openssl req -new -sha256 -key $RSAKEY -subj "/" -reqexts SAN -config $TMP > $RSACSR
fi

# RSA証明書発行処理
RSACERT="${CERTDIR}${MULTIDOMAIN}.crt"
RSACA="${CERTDIR}${MULTIDOMAIN}.ca-bundle"
RSAFULLCERT="${CERTDIR}${MULTIDOMAIN}.crt-ca-bundle"
if [ -f $RSAFULLCERT ]; then
  # 発行済みRSA証明書バックアップ
  AFTER=`openssl x509 -noout -text -dates -in $RSAFULLCERT | grep notAfter | cut -d'=' -f2`
  AFTER=`env TZ=JST-9 date --date "$AFTER" +%Y%m%d-%H%M`
  /bin/cp --force -pr $RSAFULLCERT ${RSAFULLCERT}.limit$AFTER
fi
if [ -f $RSACERT ]; then
  # 発行済みRSA証明書バックアップ
  AFTER=`openssl x509 -noout -text -dates -in $RSACERT | grep notAfter | cut -d'=' -f2`
  AFTER=`env TZ=JST-9 date --date "$AFTER" +%Y%m%d-%H%M`
  /bin/cp --force -pr $RSACERT ${RSACERT}.limit$AFTER
fi
cd $CERTDIR
$PYTHON $SIGNPG --account-key $USERKEY --csr $RSACSR --acme-dir ${WEBROOT}/.well-known/acme-challenge/ > $RSAFULLCERT

#
# サーバー証明書とルート証明書を分ける
#
POS=`grep -n "^$" $RSAFULLCERT | cut -d':' -f1`
POS=$(($POS-1))
sed -n "1,${POS}p" $RSAFULLCERT > $RSACERT

SPOS=`grep -n "^$" $RSAFULLCERT | cut -d':' -f1`
SPOS=$(($SPOS+1))
EPOS=`cat $RSAFULLCERT | wc -l`
sed -n "${SPOS},${EPOS}p" $RSAFULLCERT > $RSACA

####
#### 楕円曲線暗号対応
####
###if openssl ecparam -list_curves 2>/dev/null | grep -sq prime256v1; then
###  # 秘密鍵作成
###  ECCKEY="${CERTDIR}${MULTIDOMAIN}-ecc.key"
###  if [ ! -f $ECCKEY ]; then
###    openssl ecparam -name prime256v1 -genkey -out $ECCKEY
###  fi
###
###  # CSR作成
###  ECCCSR="${CERTDIR}${MULTIDOMAIN}-ecc.csr"
###  if [ ! -f $ECCCSR ]; then
###    openssl req -new -sha256 -key $ECCKEY -subj "/" -reqexts SAN -config $TMP > $ECCCSR
###  fi
###
###  # ECC証明書発行処理
###  ECCCERT="${CERTDIR}${MULTIDOMAIN}-ecc.crt"
###  ECCCA="${CERTDIR}${MULTIDOMAIN}-ecc.ca-bundle"
###  ECCFULLCERT="${CERTDIR}${MULTIDOMAIN}-ecc.crt-ca-bundle"
###  if [ -f $ECCFULLCERT ]; then
###    # 発行済みECC証明書バックアップ
###    AFTER=`openssl x509 -noout -text -dates -in $ECCFULLCERT | grep notAfter | cut -d'=' -f2`
###    AFTER=`env TZ=JST-9 date --date "$AFTER" +%Y%m%d-%H%M`
###    /bin/cp --force -pr $ECCFULLCERT ${ECCFULLCERT}.limit$AFTER
###  fi
###  if [ -f $ECCCERT ]; then
###    # 発行済みECC証明書バックアップ
###    AFTER=`openssl x509 -noout -text -dates -in $ECCCERT | grep notAfter | cut -d'=' -f2`
###    AFTER=`env TZ=JST-9 date --date "$AFTER" +%Y%m%d-%H%M`
###    /bin/cp --force -pr $ECCCERT ${ECCCERT}.limit$AFTER
###  fi
###  cd $CERTDIR
###  $PYTHON $SIGNPG --account-key $USERKEY --csr $ECCCSR --acme-dir ${WEBROOT}/.well-known/acme-challenge/ > $ECCFULLCERT
###
###  #
###  # サーバー証明書とルート証明書を分ける
###  #
###  POS=`grep -n "^$" $ECCFULLCERT | cut -d':' -f1`
###  POS=$(($POS-1))
###  sed -n "1,${POS}p" $ECCFULLCERT > $ECCCERT
###
###  SPOS=`grep -n "^$" $ECCFULLCERT | cut -d':' -f1`
###  SPOS=$(($SPOS+1))
###  EPOS=`cat $ECCFULLCERT | wc -l`
###  sed -n "${SPOS},${EPOS}p" $ECCFULLCERT > $ECCCA
###fi

# 不要ファイル削除
rm -rf ${WEBROOT}/.well-known
rm -rf $TMP
