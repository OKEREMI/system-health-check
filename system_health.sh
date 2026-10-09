#!/bin/bash
# system_health.sh
# Checks CPU, memory, disk, network and services.
# Prints a report in the terminal and saves every line to a log file
# with a timestamp.
#
# Usage:  sudo ./system_health.sh

# ---------- Settings (change these if you want) ----------
LOG_FILE="${LOG_FILE:-/var/log/system_health.log}"
DISK_THRESHOLD="${DISK_THRESHOLD:-80}"      # warn above this percent
SERVICES="sshd apache2 nginx docker cron"   # services to check
PING_TARGET="google.com"

# ---------- Make sure we can write the log file ----------
if ! touch "$LOG_FILE" 2>/dev/null; then
    echo "Cannot write to $LOG_FILE (try: sudo ./system_health.sh)."
    echo "Saving to ./system_health.log instead."
    LOG_FILE="./system_health.log"
    touch "$LOG_FILE"
fi

# ---------- Helper functions ----------
# out "text": print on screen AND save to the log with a timestamp
out() {
    printf '%s\n' "$1"
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
}

# out_block: same thing, but for many lines coming from a pipe
out_block() {
    while IFS= read -r line; do
        out "$line"
    done
}

# ---------- Report starts here ----------
out "===== SYSTEM HEALTH REPORT ====="
out "Date: $(date)"
out ""

# 1. System info
out "--- 1. System Info ---"
out "Hostname: $(hostname)"
if command -v lsb_release >/dev/null 2>&1; then
    OS_NAME=$(lsb_release -ds | tr -d '"')
else
    OS_NAME=$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
fi
out "OS: $OS_NAME"
out "Kernel: $(uname -r)"
out "Uptime: $(uptime -p | sed 's/^up //')"
out ""

# 2. CPU and memory
out "--- 2. CPU and Memory ---"
CPU_IDLE=$(LC_ALL=C top -bn1 | grep -i "cpu(s)" | sed 's/.*, *\([0-9.]*\) *id.*/\1/')
if [ -n "$CPU_IDLE" ]; then
    CPU_USED=$(awk "BEGIN {printf \"%.0f\", 100 - $CPU_IDLE}")
    out "CPU Usage: ${CPU_USED}%"
else
    out "CPU Usage: could not be read"
fi
out "Memory Usage: $(free -h | awk '/^Mem:/ {print $3 " used / " $2 " total"}')"
out "Top 5 CPU processes:"
ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu | head -6 | out_block
out ""

# 3. Disk usage
out "--- 3. Disk Usage ---"
df -hP -x tmpfs -x devtmpfs -x squashfs -x overlay | tail -n +2 | \
while read -r fs size used avail use mount; do
    percent=${use%\%}
    out "Disk: $fs $use used (mounted on $mount)"
    if [ "$percent" -gt "$DISK_THRESHOLD" ]; then
        out "WARNING: $mount is above ${DISK_THRESHOLD}% full ($use used)"
    fi
done
out ""

# 4. Network
out "--- 4. Network ---"
out "IP addresses:"
ip a 2>/dev/null | grep "inet " | awk '{print "  " $2 " on " $NF}' | out_block

IP_ADDR=$(hostname -I 2>/dev/null | awk '{print $1}')
[ -z "$IP_ADDR" ] && IP_ADDR="no IP found"

if ! command -v ping >/dev/null 2>&1; then
    NET_STATUS="unknown (ping is not installed)"
elif ping -c 2 -W 2 "$PING_TARGET" >/dev/null 2>&1; then
    NET_STATUS="OK (ping success)"
else
    NET_STATUS="FAILED (cannot reach $PING_TARGET)"
fi
out "Network: $IP_ADDR - $NET_STATUS"
out ""

# 5. Running services
out "--- 5. Services ---"
service_state() {
    if ! command -v systemctl >/dev/null 2>&1; then
        echo "unknown (no systemctl)"
    elif [ "$(systemctl show -p LoadState --value "$1" 2>/dev/null)" != "loaded" ]; then
        echo "not installed"
    else
        systemctl is-active "$1"
    fi
}

SERVICE_SUMMARY=""
for svc in $SERVICES; do
    state=$(service_state "$svc")
    # On some Ubuntu versions the SSH service is called "ssh", not "sshd"
    if [ "$svc" = "sshd" ] && [ "$state" = "not installed" ]; then
        state=$(service_state ssh)
    fi
    SERVICE_SUMMARY="${SERVICE_SUMMARY}${svc} ${state}, "
done
out "Services: ${SERVICE_SUMMARY%, }"
out ""

out "Report saved to $LOG_FILE"
out "================================"
