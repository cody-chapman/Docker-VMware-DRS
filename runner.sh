#!/bin/bash
# Path to your input files
DOMAINS="/data/domains.txt"
EMAIL_FILE="/data/email.txt"
EMAIL_ADDRESS="/data/emailaddress.txt"

cd /data || exit 1

echo -e "\n" > /data/grade.log

while IFS= read -r line; do
    # Skip empty lines in domains.txt
    [[ -z "$line" ]] && continue

    echo -e "\n" >> /data/grade.log
    echo -n "$line: " >> /data/grade.log
    # Run testssl, grep for the grade line, then print only the last field (the grade)
    testssl --quiet --color 0 "$line" | grep "Overall Grade" | awk '{print $NF}' >> /data/grade.log

    TIMESTAMP=$(date +%Y%m%d_%H%M)
    echo "Scan completed at $TIMESTAMP for $line" >> /data/cron_history.log

done < "$DOMAINS"


cat /data/email.txt /data/grade.log > /data/emailout.log

/usr/sbin/ssmtp "$(cat $EMAIL_ADDRESS)" < /data/emailout.log
