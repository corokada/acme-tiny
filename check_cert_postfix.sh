#!/bin/sh

#
# SSL証明書の更新チェック for postfix/dovecot
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

# 有効期限を取り出す
AFTER=`openssl x509 -noout -text -dates -in $FULLCERT | grep notAfter | cut -d'=' -f2`
AFTER=`env TZ=JST-9 date --date "$AFTER" +%s`

# 実行タイミングとの残日数を計算する
NOW=`env TZ=JST-9 date +%s`
CNT=`echo "$AFTER $NOW" | awk '{printf("%d",(($1-$2)/86400)+0.5)}'`
echo "============================"
echo "$FULLCERT:$CNT"
