#!/bin/bash
# Extract UART output from simulation log and format it
# Usage: ./extract_uart.sh <logfile>

if [ $# -eq 0 ]; then
    echo "Usage: $0 <logfile>" >&2
    exit 1
fi

logfile="$1"

if [ ! -f "$logfile" ]; then
    echo "Error: File '$logfile' not found" >&2
    exit 1
fi

grep "UART: Received byte" "$logfile" | while read -r line; do
    if echo "$line" | grep -q "('\(.\)')"; then
        char=$(echo "$line" | sed -n "s/.*UART: Received byte 0x.. ('\(.\)').*/\1/p")
        printf "%s" "$char"
    else
        if echo "$line" | grep -q "0x0a"; then
            printf "\n"
        elif echo "$line" | grep -q "0x09"; then
            printf "\t"
        else
            printf "."
        fi
    fi
done

echo
