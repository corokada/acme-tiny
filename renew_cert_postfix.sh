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

  # RSA-SSL証明書
  CERT="${CONFDIR}${DOMAIN}.crt"

  if [ ! -f $CERT ]; then
    echo "'$CERT'がありません。"
    exit 1
  fi

  # 秘密鍵設定
  KEY="${CONFDIR}${DOMAIN}.key"
  if [ ! -f $KEY ]; then
    echo "'$KEY'がありません。"
    exit 1
  fi

  # CSR設定
  CSR=${KEY/.key/.csr}
  # CSRが無い場合は、作成する
  if [ ! -f "$CSR" ]; then
    if openssl x509 -noout -text -in $CERT | grep DNS | grep -sq ","; then
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

  # バックアップ
  AFTER=`openssl x509 -noout -text -dates -in $CERT | grep notAfter | cut -d'=' -f2`
  AFTER=`env TZ=JST-9 date --date "$AFTER" +%Y%m%d-%H%M`
  cp -pr $CERT ${CERT}.limit$AFTER

  # ディレクトリ作成
  mkdir -p ${WEBROOT}/.well-known/acme-challenge

  # BASIC認証回避
  echo "Satisfy any"      >> ${WEBROOT}/.well-known/acme-challenge/.htaccess
  echo "order allow,deny" >> ${WEBROOT}/.well-known/acme-challenge/.htaccess
  echo "allow from all"   >> ${WEBROOT}/.well-known/acme-challenge/.htaccess

  # 証明書発行処理
  cd ${CERTDIR}
  $PYTHON $SIGNPG --account-key $USERKEY --csr $CSR --acme-dir ${WEBROOT}/.well-known/acme-challenge/ > $CERT 2>/dev/null

  # 認証用ディレクトリ削除
  rm -rf ${WEBROOT}/.well-known

  # 発行状況確認
  if grep -sq "\-BEGIN CERTIFICATE-" $CERT; then
    # 出力
    echo "renew ok."

    #CA証明書確認
    CA1=`openssl x509 -noout -text -in $CERT | grep Issuers`
    CA2=`openssl x509 -noout -text -in ${CERT}.limit$AFTER | grep Issuers`

    # CA証明書設定
    CA=${CERT/.crt/.ca-bundle}

    # CA証明書が違う場合
    if [ "$CA1" != "$CA2" ]; then

      # バックアップ
      if [ -f $CA ]; then
        mv $CA ${CA}.limit$AFTER
      fi

      # CA証明書ダウンロード
      wget -q -O - https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.pem.txt > $CA
    fi

    # CA証明書が無い場合
    if [ ! -f "$CA" ]; then
      wget -q -O - https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.pem.txt > $CA
    fi

    # バックアップ
    AFTER=`openssl x509 -noout -text -dates -in $FULLCERT | grep notAfter | cut -d'=' -f2`
    AFTER=`env TZ=JST-9 date --date "$AFTER" +%Y%m%d-%H%M`
    cp -pr $FULLCERT ${FULLCERT}.limit$AFTER
    if [ "$FULLCERT" = "$CERT" ]; then
      cat ${CA} >> ${FULLCERT}
    else
      cat ${CONFDIR}${DOMAIN}.{crt,ca-bundle} > ${FULLCERT}
    fi

    # サービス再起動
    /etc/init.d/postfix reload
    /etc/init.d/dovecot reload
    
    # vpopmailでSSL証明書を利用している時
    if [ -f /var/qmail/control/servercert.pem ]; then
        # バックアップ
        AFTER=`openssl x509 -noout -text -dates -in /var/qmail/control/servercert.pem | grep notAfter | cut -d'=' -f2`
        AFTER=`env TZ=JST-9 date --date "$AFTER" +%Y%m%d-%H%M`
        cp -pr /var/qmail/control/servercert.pem /var/qmail/control/servercert.pem.limit$AFTER

        # コピー
        cat ${CONFDIR}${DOMAIN}.{key,crt,ca-bundle} > /var/qmail/control/servercert.pem
        chown qmaild.qmail /var/qmail/control/servercert.pem

        # サービス再起動
        /etc/init.d/qmail stop > /dev/null 2> /dev/null
        /etc/init.d/qmail start > /dev/null 2> /dev/null
    fi
  else
    # エラー出力
    cat $CERT

    # バックアップを戻す
    mv -f ${CERT}.limit$AFTER $CERT
  fi
fi
