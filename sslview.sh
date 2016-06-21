#!/bin/sh

#
# ssl certificate view
#
# Author: corokada
#

if [ -z "$1" ]; then
        echo "usage:$0 [private key file/csr file/cert file]"
        exit 0
fi

THISFILE=$1

if grep -sq "BEGIN RSA PRIVATE KEY" $THISFILE; then
  openssl rsa -text -noout -in $THISFILE
elif grep -sq "BEGIN EC PRIVATE KEY" $THISFILE; then
  openssl ec -text -noout -in $THISFILE
elif grep -sq "BEGIN CERTIFICATE REQUEST" $THISFILE; then
  openssl req -text -noout -in $THISFILE
elif grep -sq "BEGIN CERTIFICATE" $THISFILE; then
  openssl x509 -text -noout -in $THISFILE
fi
