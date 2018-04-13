#!/bin/sh

#
# SSL証明書の更新 for postfix/dovecot
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

## それぞれ環境に合わせて修正をしてください。
CERTDIR="`dirname $0`/"

# httpdのパス
HTTPD="/usr/sbin/httpd"

# pythonのパス
PYTHON="/usr/bin/python"

# 発行プログラムのパス
SIGNPG="${CERTDIR}acme_tiny.py"

# ユーザー認証情報
USERKEY="${CERTDIR}user.key"
if [ ! -f $USERKEY ]; then
  openssl genrsa 4096 > $USERKEY
fi

# postfixCONFフルパス
CONFDIR="`/usr/sbin/postconf -n | grep config_directory | sed -e "s/ //g" | cut -d'=' -f2`/"

# 証明書のフルパス
FULLCERT=`/usr/sbin/postconf -n | grep smtpd_tls_cert_file | grep -v localhost | sed -e "s/ //g" | cut -d'=' -f2`
if [ -z "$FULLCERT" ]; then
    exit 0
fi
if [ ! -f $FULLCERT ]; then
    exit 0
fi

# 有効期限を取り出す
AFTER=`openssl x509 -noout -text -dates -in $FULLCERT | grep notAfter | cut -d'=' -f2`
AFTER=`env TZ=JST-9 date --date "$AFTER" +%s`

# 実行タイミングとの残日数を計算する
NOW=`env TZ=JST-9 date +%s`
CNT=`echo "$AFTER $NOW" | awk '{printf("%d",(($1-$2)/86400)+0.5)}'`
echo "============================"
echo "$FULLCERT:$CNT"

# 有効期限30日以内
if [ "$CNT" -le 30 ]; then
  # 設定を取り出す
  DOMAIN=`openssl x509 -noout -text -in $FULLCERT | grep "Subject: CN" | cut -d'=' -f2`
  HTTPCONF=`$HTTPD -S | grep "port 80" | grep $DOMAIN | tr -d ' ' | cut -d'(' -f2 | cut -d':' -f1`
  if [ "$HTTPCONF" = "" ]; then
      echo "'$DOMAIN'のヴァーチャルドメイン設定がありません。"
      exit 1
  fi
  # ドキュメントルート
  WEBROOT=`cat $HTTPCONF | grep DocumentRoot | awk '{print $2}' | uniq`

  # 秘密鍵設定
  KEY="${CONFDIR}${DOMAIN}.key"
  if [ ! -f $KEY ]; then
    echo "'$KEY'がありません。"
    exit 1
  fi

  # CSR設定
  CSR="${CONFDIR}${DOMAIN}.csr"
  # CSRが無い場合は、作成する
  if [ ! -f "$CSR" ]; then
    if openssl x509 -noout -text -in $FULLCERT | grep DNS | grep -sq ","; then
      # デュアルアクセス設定
      tmp=`mktemp -p /tmp -t opensslconf.XXXXXXXXXXXXXXX`
      cat /etc/pki/tls/openssl.cnf > $tmp
      printf "[SAN]\nsubjectAltName=DNS:${DOMAIN},DNS:www.${DOMAIN}" >> $tmp

      # CSR作成
      openssl req -new -key $KEY -sha256 -nodes -subj "/" -reqexts SAN -config $tmp > $CSR

      # 一時ファイル削除
      rm -rf $tmp
    else
      #シングルドメイン
      openssl req -new -key $KEY -sha256 -nodes -subj "/CN=$DOMAIN" > $CSR
    fi
  fi

  # 証明書設定
  CERT="${CONFDIR}${DOMAIN}.crt"
  CERTCA="${CONFDIR}${DOMAIN}.ca-bundle"

  # バックアップ
  AFTER=`openssl x509 -noout -text -dates -in $FULLCERT | grep notAfter | cut -d'=' -f2`
  AFTER=`env TZ=JST-9 date --date "$AFTER" +%Y%m%d-%H%M`
  cp -pr $FULLCERT ${FULLCERT}.limit$AFTER
  cp -pr $CERT ${CERT}.limit$AFTER

  # ディレクトリ作成
  mkdir -p ${WEBROOT}/.well-known/acme-challenge

  # BASIC認証回避
  echo "Satisfy any"      >> ${WEBROOT}/.well-known/acme-challenge/.htaccess
  echo "order allow,deny" >> ${WEBROOT}/.well-known/acme-challenge/.htaccess
  echo "allow from all"   >> ${WEBROOT}/.well-known/acme-challenge/.htaccess

  # 証明書発行処理
  cd ${CERTDIR}
  $PYTHON $SIGNPG --account-key $USERKEY --csr $CSR --acme-dir ${WEBROOT}/.well-known/acme-challenge/ > $FULLCERT 2>/dev/null

  # 認証用ディレクトリ削除
  rm -rf ${WEBROOT}/.well-known

  # 発行状況確認
  if grep -sq "\-BEGIN CERTIFICATE-" $FULLCERT; then
    # 出力
    echo "renew ok."

    #
    # サーバー証明書とルート証明書を分ける
    #
    POS=`grep -n "^$" $FULLCERT | cut -d':' -f1`
    POS=$(($POS-1))
    sed -n "1,${POS}p" $FULLCERT > $CERT

    SPOS=`grep -n "^$" $FULLCERT | cut -d':' -f1`
    SPOS=$(($SPOS+1))
    EPOS=`cat $FULLCERT | wc -l`
    sed -n "${SPOS},${EPOS}p" $FULLCERT > $CERTCA
  else
    # エラー出力
    cat $FULLCERT

    # バックアップを戻す
    mv -f ${FULLCERT}.limit$AFTER $FULLCERT
    mv -f ${CERT}.limit$AFTER $CERT
  fi
  # サービス再起動
  /etc/init.d/postfix reload
  /etc/init.d/dovecot reload
fi
