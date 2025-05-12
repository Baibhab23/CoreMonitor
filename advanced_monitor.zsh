#!/bin/zsh

LOG_FILE="system_monitor.log"
HISTORY_FILE="usage_history.csv"
JSON_FILE="monitor_data.json"
PORT=8082
SENDER="baibhab.dey@sap.com"
RECIPIENT="baibhabd17@gmail.com"
SMTP_SERVER="smtp.office365.com"  # Have to replace with correct smptp but sincer its company mail just this is a demo
SMTP_PORT="587"
UPDATE_INTERVAL=2
CPU_THRESHOLD=80
MEMORY_THRESHOLD=80
DISK_THRESHOLD=85

trap "echo '🛑 Exiting... Cleaning up...'; pkill -P $$; exit" SIGINT SIGTERM

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

draw_bar() {
    local value=$1
    local bar_length=$((value / 2))
    printf "%3s%% [" "$value"
    for ((i = 0; i < 50; i++)); do
        if (( i < bar_length )); then
            printf "█"
        else
            printf " "
        fi
    done
    echo "]"
}

calculate_health_score() {
    echo $(( 100 - ${CPU%.*} - ${MEM_PERCENT%.*} / 2 - DISK_USAGE / 2 ))
}

check_idle_time() {
    idle=$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000)}')
    if (( idle > 600 )); then
        log_data "🔒 User idle for over 10 minutes."
        say "System idle for ten minutes."
    fi
}

send_email() {
    SUBJECT="Daily System Report"
    BODY="Here is the daily system report:\n\nCPU: $CPU%\nMemory Usage: $MEM_PERCENT%\nDisk Usage: $DISK_USAGE%\n\n$NETWORK_JSON"
    
    echo -e "Subject:$SUBJECT\nFrom:$SENDER\nTo:$RECIPIENT\n\n$BODY" | msmtp \
        --host=smtp.gmail.com \
        --port=587 \
        --from=$SENDER \
        --auth=on \
        --user=$SENDER \
        --passwordeval="echo $PASSWORD" \
        --tls=on \
        --tls-certcheck=off \
        --to=$RECIPIENT
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

        # Calculate Health Score (example: based on thresholds for CPU, memory, and disk usage)
        HEALTH_SCORE=100
        if (( ${CPU%.*} > 80 )); then
            HEALTH_SCORE=$((HEALTH_SCORE - 20))  # Deduct points for high CPU usage
        fi
        if (( ${MEM_PERCENT%.*} > 80 )); then
            HEALTH_SCORE=$((HEALTH_SCORE - 20))  # Deduct points for high memory usage
        fi
        if (( DISK_USAGE > 85 )); then
            HEALTH_SCORE=$((HEALTH_SCORE - 20))  # Deduct points for high disk usage
        fi

        # Save the data to JSON
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
            \"intrusions\": \"$INTRUSIONS\",
            \"health_score\": \"$HEALTH_SCORE\"
        }" > $JSON_FILE

        record_history "$CPU" "$MEM_PERCENT"

        # Generate warnings and suggestions
        if (( ${CPU%.*} > CPU_THRESHOLD )); then
            echo -e "\a"; say "Warning. High CPU usage."
            log_data "⚠️ High CPU usage detected: $CPU%. Try closing unused apps."
        fi
        if (( ${MEM_PERCENT%.*} > MEMORY_THRESHOLD )); then
            echo -e "\a"; say "Warning. High memory usage."
            log_data "⚠️ High Memory usage detected: $MEM_PERCENT%. Consider closing memory-heavy applications."
        fi
        if (( DISK_USAGE > DISK_THRESHOLD )); then
            echo -e "\a"; say "Warning. Disk usage critical."
            log_data "⚠️ High Disk usage detected: $DISK_USAGE%. Consider clearing old files."
        fi

        # Check idle time
        check_idle_time &

        sleep $UPDATE_INTERVAL
    done
}


monitor_health() {
    while true; do
        clear
        echo "❤️ System Health Overview"
        source <(jq -r '.cpu as $cpu | .memory.percent as $mem | .disk as $disk | "CPU=\($cpu)\nMEM_PERCENT=\($mem)\nDISK_USAGE=\($disk | sub("%";""))"' $JSON_FILE)

        draw_bar ${CPU%.*}
        draw_bar ${MEM_PERCENT%.*}
        draw_bar $DISK_USAGE

        score=$(calculate_health_score)
        echo "\n🧮 Health Score: $score/100"

        echo "\n⏳ Press [Enter] to stop monitoring or wait to continue..."
        read -t 2 back
        [[ $? -eq 0 ]] && echo "🛑 Stopping Health Monitor." && break

        sleep $UPDATE_INTERVAL
    done
}
analyze_trends() {
    if [[ ! -f "$HISTORY_FILE" ]]; then
        echo "📉 No history file found to analyze."
        return
    fi

    echo "\n📊 Analyzing Trends (Last 30 Entries)..."
    local recent_data=$(tail -n 30 "$HISTORY_FILE")
    local avg_cpu=$(echo "$recent_data" | awk -F',' '{sum+=$2} END {if (NR > 0) printf "%.2f", sum/NR; else print "0"}')
    local avg_mem=$(echo "$recent_data" | awk -F',' '{sum+=$3} END {if (NR > 0) printf "%.2f", sum/NR; else print "0"}')

    local max_cpu=$(echo "$recent_data" | awk -F',' 'BEGIN{max=0} {if($2>max) max=$2} END{print max}')
    local max_mem=$(echo "$recent_data" | awk -F',' 'BEGIN{max=0} {if($3>max) max=$3} END{print max}')

    echo "🧠 Average CPU Usage: $avg_cpu%"
    echo "💾 Average Memory Usage: $avg_mem%"
    echo "🔺 Peak CPU Usage: $max_cpu%"
    echo "🔺 Peak Memory Usage: $max_mem%"

    # Optional: alert if trends are high
    if (( ${avg_cpu%.*} > CPU_THRESHOLD )); then
        echo "⚠️ Warning: Average CPU usage above threshold!"
    fi
    if (( ${avg_mem%.*} > MEMORY_THRESHOLD )); then
        echo "⚠️ Warning: Average Memory usage above threshold!"
    fi

    echo ""
    sleep $UPDATE_INTERVAL
}

monitor_cpu() {
    while true; do
        clear
        echo "🧠 Monitoring CPU..."
        jq '.cpu' < "$JSON_FILE"

        echo "\n⏳ Press [Enter] to stop monitoring or wait to continue..."
        read -t 2 back  
        if [[ $? -eq 0 ]]; then
            echo "🛑 Stopping CPU monitor."
            break
        fi

        sleep $UPDATE_INTERVAL
    done
}

monitor_memory() {
    while true; do
        clear
        echo "💾 Monitoring Memory..."
        jq '.memory' < $JSON_FILE

        echo "\n⏳ Press [Enter] to stop monitoring or wait to continue..."
        read -t 2 back
        if [[ $? -eq 0 ]]; then
            echo "🛑 Stopping Memory monitor."
            break
        
        fi

        sleep $UPDATE_INTERVAL
    done
}

monitor_network() {
    while true; do
        clear
        echo "🌐 Monitoring Network..."
        jq '.network' < $JSON_FILE

        echo "\n⏳ Press [Enter] to stop monitoring or wait to continue..."
        read -t 2 back
        if [[ $? -eq 0 ]]; then
            echo "🛑 Stopping Network monitor."
            break
        fi

        sleep $UPDATE_INTERVAL
    done
}

monitor_disk() {
    while true; do
        clear
        echo "📀 Monitoring Disk..."
        jq '.disk' < "$JSON_FILE"

        echo "\n⏳ Press [Enter] to stop monitoring or wait to continue..."
        read -t 2 back
        if [[ $? -eq 0 ]]; then
            echo "🛑 Stopping Disk monitor."
            break
        fi

        sleep $UPDATE_INTERVAL
    done
}
# monitor_heaviest_process() {
#     clear
#     echo "🔍 Detecting the most resource-consuming process..."

#     # Get process with highest CPU usage
#     top_cpu=$(ps -e -o pid,comm,%cpu,%mem --sort=-%cpu | awk 'NR==2')
#     cpu_pid=$(echo $top_cpu | awk '{print $1}')
#     cpu_name=$(echo $top_cpu | awk '{print $2}')
#     cpu_usage=$(echo $top_cpu | awk '{print $3}')

#     # Get process with highest Memory usage
#     top_mem=$(ps -e -o pid,comm,%cpu,%mem --sort=-%mem | awk 'NR==2')
#     mem_pid=$(echo $top_mem | awk '{print $1}')
#     mem_name=$(echo $top_mem | awk '{print $2}')
#     mem_usage=$(echo $top_mem | awk '{print $4}')

#     echo "\n🔥 Top CPU-Consuming Process:"
#     echo "   Name: $cpu_name"
#     echo "   PID:  $cpu_pid"
#     echo "   CPU:  $cpu_usage%"

#     echo "\n💾 Top Memory-Consuming Process:"
#     echo "   Name: $mem_name"
#     echo "   PID:  $mem_pid"
#     echo "   Memory: $mem_usage%"

#     echo "\n📋 Optimization Tips for '$cpu_name' (if high CPU):"
#     echo "----------------------------------------------------"
#     echo "🔸 Check if '$cpu_name' is stuck or looping unnecessarily."
#     echo "🔸 Restart it: 'kill -9 $cpu_pid' or use Activity Monitor."
#     echo "🔸 If it's a browser/editor, close unused tabs/projects."
#     echo "🔸 Update the app if it's buggy."

#     echo "\n📋 Optimization Tips for '$mem_name' (if high Memory):"
#     echo "-------------------------------------------------------"
#     echo "🔸 Inspect '$mem_name' for memory leaks or large data handling."
#     echo "🔸 Close and reopen the app to clear memory."
#     echo "🔸 Use a lighter alternative if available."
#     echo "🔸 If a background service, consider restarting with limits."

#     echo "\n⏳ Press [Enter] to return to main menu..."
#     read
# }

monitor_all() {
    while true; do
        clear
        # Collect data and show the system stats
        CPU=$(jq -r '.cpu' $JSON_FILE)
        MEM_USED=$(jq -r '.memory.used' $JSON_FILE)
        MEM_TOTAL=$(jq -r '.memory.total' $JSON_FILE)
        MEM_PERCENT=$(jq -r '.memory.percent' $JSON_FILE)
        DISK=$(jq -r '.disk' $JSON_FILE)
        UPTIME=$(jq -r '.uptime' $JSON_FILE)
        INTRUSIONS=$(jq -r '.intrusions' $JSON_FILE)

        echo "🧠 CPU Usage: $CPU%"
        draw_bar ${CPU%.*}
        echo "💾 Memory: $MEM_USED MB / $MEM_TOTAL MB ($MEM_PERCENT%)"
        draw_bar ${MEM_PERCENT%.*}
        echo "📀 Disk Usage: $DISK"
        draw_bar ${DISK%\%}
        echo "🕒 Uptime: $UPTIME"
        echo "🚨 Intrusions: $INTRUSIONS"

        # Network status
        echo "🌐 Network:"
        jq -r '.network | to_entries[] | "   \(.key): RX=\(.value.rx), TX=\(.value.tx)"' $JSON_FILE

        echo "⏳ Press [Enter] to stop monitoring or wait to continue..."
        read -t 2 back
        [[ $? -eq 0 ]] && echo "🛑 Stopping All Resources monitor." && break

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

        echo "\n⏳ Press [Enter] to stop monitoring or wait to continue..."
        read -t 2 back
        if [[ $? -eq 0 ]]; then
            echo "🛑 Stopping Process monitor."
            break
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
input(){
    timeout 2 read choice
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
    echo "4) Monitor Disk"
    echo "5) Start Web Dashboard"
    echo "6) Optimization Tips"
    echo "7) Monitor Specific Process"
    echo "8) Monitor Health Score + Graphs"
    echo "9) Analyze CPU/Memory Trends"
    echo "10) Show All"
    echo "11) Exit"
    echo -n "Enter choice: "; read choice

    case $choice in
        1) monitor_cpu ;;
        2) monitor_memory ;;
        3) monitor_network ;;
        4) monitor_disk ;;
        5) serve_web_dashboard ;;
        6) show_optimization_tips ;;
        7) monitor_process ;;
        8) monitor_health ;;
        9) analyze_trends ;;
        10) monitor_all ;;
        11) echo "👋 Exiting..."; pkill -P $$; pkill -f advanced_monitor.zsh; exit 0 ;;
        *) echo "❌ Invalid option." ;;
    esac
done

}

show_menu