#!/bin/bash
#
# log-toss
# MIT License
# @doublecompile
# Backs up logs to an S3 bucket

shopt -s extglob

CONFIG_FILE="/etc/log-toss/log-toss.conf"

if [ ! -f $CONFIG_FILE ]; then
    echo "Configuration file not found" >&2;
    exit 1;
fi

while IFS='= ' read lhs rhs
do
    if [[ ! $lhs =~ ^\ *# && -n $lhs ]]; then
        rhs="${rhs%%\#*}"    # Del in line right comments
        rhs="${rhs%%*( )}"   # Del trailing spaces
        rhs="${rhs%\"*}"     # Del opening string quotes 
        rhs="${rhs#\"*}"     # Del closing string quotes 
        declare $lhs="$rhs"
    fi
done < $CONFIG_FILE

if [ ! -d $log_dir ]; then
    echo "Logs directory not found" >&2;
    exit 1;
fi

if [[ -z "$s3_bucket" ]]; then
    echo "No S3 bucket is configured" >&2;
    exit 1;
fi

command -v aws >/dev/null 2>&1 || { echo "Huh? awscli isn't installed. Aborting." >&2; exit 1; }

ts=`date +%s`
MY_TMP_DIR="/tmp/log-toss-$ts-$BASHPID"

for file in `find $log_dir -type f -name "*.log*.gz"`
do
    owner=`stat -c %U $file`
    mkdir -p "$MY_TMP_DIR/$owner"
    cp $file "$MY_TMP_DIR/$owner/"
done

aws s3 sync $MY_TMP_DIR "s3://$s3_bucket/$s3_dir"
rm -rf $MY_TMP_DIR
