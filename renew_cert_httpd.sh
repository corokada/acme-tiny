#!/bin/sh

#
# SSL証明書の更新 for apache
#
# Author: corokada
#

#
# 【利用条件】
# SSL証明書と秘密鍵ファイル名が同一
#             かつ
# 同一ディレクトに存在している時
# のみ利用可能
#   証明書  ：hogehoge.com.crt
#   秘密鍵  ：hogehoge.com.key
#   CA証明書：hogehoge.com.ca-bundle
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

# conf一覧取り出し
for CONFFILE in `$HTTPD -S 2>/dev/null | grep namevhost | grep "port 443" | tr -d ' ' | cut -d'(' -f2 | cut -d':' -f1 | sort | uniq | grep virtualhost`
do
  #証明書ループ
  for CERT in `grep -v "#" $CONFFILE | grep SSLCertificateFile | grep -v "pki" | sed -e 's/"//g' -e "s/'//g" | awk '{print $2}' | sort | uniq`
  do
    # 有効期限を取り出す
    AFTER=`openssl x509 -noout -text -dates -in $CERT | grep notAfter | cut -d'=' -f2`
    AFTER=`env TZ=JST-9 date --date "$AFTER" +%s`

    # 実行タイミングとの残日数を計算する
    NOW=`env TZ=JST-9 date +%s`
    CNT=`echo "$AFTER $NOW" | awk '{printf("%d",(($1-$2)/86400)+0.5)}'`
    echo "============================"
    echo "$CERT:$CNT"

    # 有効期限30日以内
    if [ "$CNT" -le 30 ]; then
      # 該当ドメイン取り出し
      DOMAIN=`cat $CONFFILE | grep -v "#" | grep ServerName | awk '{print $2}' | grep -v ":"`

      # ドキュメントルート
      WEBROOT=`cat $CONFFILE | grep DocumentRoot | sed -e 's/"//g' -e "s/'//g" | awk '{print $2}' | uniq`

      # 秘密鍵設定
      KEY=${CERT/.crt/.key}
      if [ ! -f "$KEY" ]; then
        echo "$KEY not found."
        continue
      fi

      # CSR設定
      CSR=${CERT/.crt/.csr}

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
      $PYTHON $SIGNPG --account-key $USERKEY --csr $CSR --acme-dir ${WEBROOT}/.well-known/acme-challenge/ > $CERT 2>&1

      # 認証用ディレクトリ削除
      rm -rf ${WEBROOT}/.well-known

      # 発行状況確認
      if grep -sq "\-BEGIN CERTIFICATE-" $CERT; then
        # 出力
        echo "renew ok."

        # 不要な行を削除
        GYO=`grep -n "\-BEGIN CERTIFICATE-" $CERT | cut -d':' -f1`
        GYO=$((${GYO}-1))
        sed -i "1,${GYO}d" $CERT

        #CA証明書確認
        CA1=`openssl x509 -noout -text -in $CERT | grep Issuers`
        CA2=`openssl x509 -noout -text -in ${CERT}.limit$AFTER | grep Issuers`

        # CA証明書が違う場合
        if [ "$CA1" != "$CA2" ]; then
          # CA証明書設定
          CA=${CERT/.crt/.ca-bundle}

          # バックアップ
          if [ -f $CA ]; then
            mv $CA ${CA}.limit$AFTER
          fi

          # CA証明書ダウンロード
          wget -q -O - https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.pem.txt > $CA
        fi
      else
        # エラー出力
        cat $CERT

        # バックアップを戻す
        mv -f ${CERT}.limit$AFTER $CERT
      fi

      # apache再起動
      /usr/sbin/apachectl graceful
    fi
  done
done
