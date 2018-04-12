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
      if [ ! -f "$CSR" ]; then
        echo "$CSR not found."
        continue
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
      FULLCERT=${CERT/.crt/.crt-ca-bundle}
      CERTCA=${CERT/.crt/.ca-bundle}
      cd ${CERTDIR}
      $PYTHON $SIGNPG --account-key $USERKEY --csr $CSR --acme-dir ${WEBROOT}/.well-known/acme-challenge/ > $FULLCERT 2>&1
      
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
        mv -f ${CERT}.limit$AFTER $CERT
      fi

      # apache再起動
      /usr/sbin/apachectl graceful
    fi
  done
done
