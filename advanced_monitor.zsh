#!/bin/zsh

LOG_FILE="system_monitor.log"
HISTORY_FILE="usage_history.csv"
JSON_FILE="monitor_data.json"
UPDATE_INTERVAL=2
CPU_THRESHOLD=80
MEMORY_THRESHOLD=80
DISK_THRESHOLD=85
PORT=8082

# Trap to clean up background processes on Ctrl+C or exit
trap "echo '🛑 Exiting... Cleaning up...'; pkill -P $$; exit" SIGINT SIGTERM

# Kill if port already in use
PID=$(lsof -ti tcp:$PORT)
if [ -n "$PID" ]; then
    kill -9 $PID
fi

log_data() {
    echo "$(date) - $1" >> $LOG_FILE
}

record_history() {
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    echo "$TIMESTAMP,$1,$2" >> $HISTORY_FILE
}

collect_data() {
    while true; do
        TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
        CPU=$(top -l 1 | awk '/CPU usage/ {print $3}' | cut -d'%' -f1)

        MEMORY_USED=$(vm_stat | awk '
            /Pages active/ {active=$3*4096/1024/1024}
            /Pages wired down/ {wired=$3*4096/1024/1024}
            END {printf "%.2f", active + wired}')
        TOTAL_MEMORY=$(sysctl -n hw.memsize)
        TOTAL_MB=$((TOTAL_MEMORY / 1024 / 1024))
        MEM_PERCENT=$(echo "scale=2; ($MEMORY_USED / $TOTAL_MB) * 100" | bc)

        DISK_USAGE=$(df -H / | awk 'NR==2 {print $5}' | sed 's/%//')

        NETWORK_JSON=""
        interfaces=($(networksetup -listallhardwareports | awk '/Device/ {print $2}'))
        for iface in $interfaces; do
            RX=$(netstat -bI $iface 2>/dev/null | awk 'NR==2 {print $7}')
            TX=$(netstat -bI $iface 2>/dev/null | awk 'NR==2 {print $10}')
            [[ -z "$RX" ]] && RX="0"
            [[ -z "$TX" ]] && TX="0"
            NETWORK_JSON="$NETWORK_JSON\"$iface\":{\"rx\":\"$RX bytes\",\"tx\":\"$TX bytes\"},"
        done
        NETWORK_JSON="{${NETWORK_JSON%,}}"

        INTRUSIONS=$(last | grep "invalid" | wc -l)
        UPTIME=$(uptime | awk -F'(up |,  load average: )' '{print $2}')

        echo "{
            \"timestamp\": \"$TIMESTAMP\",
            \"cpu\": \"$CPU\",
            \"memory\": {
                \"percent\": \"$MEM_PERCENT\",
                \"used\": \"$MEMORY_USED\",
                \"total\": \"$TOTAL_MB\"
            },
            \"disk\": \"$DISK_USAGE%\",
            \"network\": $NETWORK_JSON,
            \"uptime\": \"$UPTIME\",
            \"intrusions\": \"$INTRUSIONS\"
        }" > $JSON_FILE

        record_history "$CPU" "$MEM_PERCENT"

        if (( ${CPU%.*} > $CPU_THRESHOLD )); then
            echo -e "\a"
            log_data "⚠️ High CPU usage detected: $CPU%"
        fi
        if (( ${MEM_PERCENT%.*} > $MEMORY_THRESHOLD )); then
            echo -e "\a"
            log_data "⚠️ High Memory usage detected: $MEM_PERCENT%"
        fi
        if (( DISK_USAGE > DISK_THRESHOLD )); then
            echo -e "\a"
            log_data "⚠️ High Disk usage detected: $DISK_USAGE%"
        fi

        sleep $UPDATE_INTERVAL
    done
}

monitor_cpu() {
    while true; do
        clear
        echo "🧠 Monitoring CPU..."
        jq '.cpu' < $JSON_FILE
        sleep $UPDATE_INTERVAL
    done
}

monitor_memory() {
    while true; do
        clear
        echo "💾 Monitoring Memory..."
        jq '.memory' < $JSON_FILE
        sleep $UPDATE_INTERVAL
    done
}

monitor_network() {
    while true; do
        clear
        echo "🌐 Monitoring Network..."
        jq '.network' < $JSON_FILE
        sleep $UPDATE_INTERVAL
    done
}

monitor_all() {
    while true; do
        clear
        echo "🖥️ Monitoring All..."
        jq < $JSON_FILE
        sleep $UPDATE_INTERVAL
    done
}

monitor_process() {
    echo -n "🔍 Enter process name to watch: "; read pname

    while true; do
        clear
        echo "🔎 Monitoring process: $pname"
        matches=$(ps -e -o pid,comm,%cpu,%mem | grep -i "$pname" | grep -v "grep")

        if [[ -z "$matches" ]]; then
            echo "❌ No process named '$pname' is currently running."
        else
            echo "PID    COMMAND           CPU%   MEM%"
            echo "$matches" | while read pid command cpu mem; do
                printf "%-6s %-16s %-6s %-6s\n" "$pid" "$command" "$cpu" "$mem"

                # Optional alerts
                cpu_int=${cpu%.*}
                mem_int=${mem%.*}
                if (( cpu_int > CPU_THRESHOLD )); then
                    echo -e "\a⚠️ High CPU usage: $cpu% by $command"
                    log_data "⚠️ $command using high CPU: $cpu%"
                fi
                if (( mem_int > MEMORY_THRESHOLD )); then
                    echo -e "\a⚠️ High Memory usage: $mem% by $command"
                    log_data "⚠️ $command using high Memory: $mem%"
                fi
            done
        fi

        sleep $UPDATE_INTERVAL
    done
}

serve_web_dashboard() {
    echo "🔹 Starting Web Dashboard..."
    cd "$(dirname "$0")"
    python3 -m http.server $PORT > /dev/null 2>&1 &
    echo "📡 Web server started at: http://localhost:$PORT"
    echo "🖥️ Dashboard at: http://localhost:$PORT/dashboard.html"
    sleep 2
}

show_optimization_tips() {
    echo "\n📋 Suggested Measures to Optimize Resource Usage:"
    echo "--------------------------------------------------"
    echo "🧠 CPU:"
    echo "  - Close unused applications or browser tabs."
    echo "  - Identify high CPU tasks with 'top' or 'htop'."
    echo "  - Restart heavy apps, reduce animations."
    echo ""
    echo "💾 Memory:"
    echo "  - Close memory-hungry apps (e.g., IDEs, browsers)."
    echo "  - Use Activity Monitor to spot hogs."
    echo "  - Consider system restart if memory pressure is high."
    echo ""
    echo "📀 Disk:"
    echo "  - Clear cache and logs using CleanMyMac or manual commands."
    echo "  - Remove unused apps and files in Downloads."
    echo ""
    echo "🌐 Network:"
    echo "  - Use 'nettop' or 'lsof -i' to see active connections."
    echo "  - Stop large downloads or background sync apps."
    echo "  - Switch to a better network or use Ethernet."
    echo "--------------------------------------------------"
}

show_menu() {
    collect_data &

    while true; do
        echo "\nSelect what you want to monitor:"
        echo "1) Monitor CPU"
        echo "2) Monitor Memory"
        echo "3) Monitor Network"
        echo "4) Monitor All"
        echo "5) Start Web Dashboard"
        echo "6) Optimization Tips"
        echo "7) Show All"
        echo "8) Monitor Specific Process"
        echo "9) Exit"
        echo -n "Enter choice: "; read choice

        case $choice in
            1) monitor_cpu ;;
            2) monitor_memory ;;
            3) monitor_network ;;
            4|7) monitor_all ;;  # 7 is an alias for 4
            5) serve_web_dashboard ;;
            6) show_optimization_tips ;;
            8) monitor_process ;;
            9) echo "👋 Exiting..."; pkill -P $$; exit 0 ;;
            *) echo "❌ Invalid option." ;;
        esac
    done
}

show_menu
