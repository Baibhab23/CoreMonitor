#!/bin/zsh

LOG_FILE="system_monitor.log"
CPU_THRESHOLD=80  # CPU usage alert threshold
MEMORY_THRESHOLD=80  # Memory usage alert threshold
HISTORY_FILE="usage_history.csv"

# Function to log data
log_data() {
    echo "$(date) - $1" >> $LOG_FILE
}

# Function to record usage history
record_history() {
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    CPU_LOAD=$(top -l 1 | awk '/CPU usage/ {print $3}' | cut -d'%' -f1)
    MEMORY_USED=$(vm_stat | awk '
    /Pages active/ {active=$3*4096/1024/1024}
    /Pages wired down/ {wired=$3*4096/1024/1024}
    END {printf "%.2f", active + wired}')
    
    TOTAL_MEMORY=$(sysctl -n hw.memsize)
    TOTAL_MEMORY_MB=$((TOTAL_MEMORY / 1024 / 1024))
    MEMORY_PERCENT=$(echo "scale=2; ($MEMORY_USED / $TOTAL_MEMORY_MB) * 100" | bc)
    
    echo "$TIMESTAMP,$CPU_LOAD,$MEMORY_PERCENT" >> $HISTORY_FILE
}

# Function to monitor CPU & detect high usage
monitor_cpu() {
    echo "🔹 Monitoring CPU Usage..."
    CPU_LOAD=$(top -l 1 | awk '/CPU usage/ {print $3}' | cut -d'%' -f1)
    echo "CPU Usage: $CPU_LOAD%"
    
    if (( $(echo "$CPU_LOAD > $CPU_THRESHOLD" | bc -l) )); then
        echo "⚠️ High CPU Usage Detected ($CPU_LOAD%)"
        log_data "High CPU usage detected: $CPU_LOAD%"
    fi
}

# Function to monitor memory & detect high usage
monitor_memory() {
    echo "🔹 Monitoring Memory Usage..."
    MEMORY_USED=$(vm_stat | awk '
    /Pages active/ {active=$3*4096/1024/1024}
    /Pages wired down/ {wired=$3*4096/1024/1024}
    END {printf "%.2f", active + wired}')
    
    TOTAL_MEMORY=$(sysctl -n hw.memsize)
    TOTAL_MEMORY_MB=$((TOTAL_MEMORY / 1024 / 1024))
    MEMORY_PERCENT=$(echo "scale=2; ($MEMORY_USED / $TOTAL_MEMORY_MB) * 100" | bc)
    
    echo "Memory Usage: $MEMORY_PERCENT% ($MEMORY_USED MB / $TOTAL_MEMORY_MB MB)"
    
    if (( $(echo "$MEMORY_PERCENT > $MEMORY_THRESHOLD" | bc -l) )); then
        echo "⚠️ High Memory Usage Detected ($MEMORY_PERCENT%)"
        log_data "High Memory usage detected: $MEMORY_PERCENT%"
    fi
}

# Function to detect suspicious processes
detect_suspicious_processes() {
    echo "🔹 Checking for Suspicious Processes..."
    ps aux | awk '$3 > 50 {print "⚠️ High CPU Process:", $2, $11, "- CPU:", $3"%"}'
}

# Function to monitor network traffic
monitor_network() {
    echo "🔹 Monitoring Network Traffic..."
    netstat -ib | awk 'NR>1 {print $1, "RX:", $7, "bytes | TX:", $10, "bytes"}' | uniq
}

# Function to detect intrusion attempts
detect_intrusions() {
    echo "🔹 Checking for Unauthorized Login Attempts..."
    last | grep "invalid" | tail -n 5
}

# Function to provide system optimization suggestions
suggest_optimizations() {
    echo "🔹 Optimization Suggestions:"
    echo "→ Close unused applications to free up memory."
    echo "→ Reduce browser tabs to decrease RAM usage."
    echo "→ Use Activity Monitor to check for background processes."
    echo "→ Enable macOS power-saving mode to extend battery life."
}

# Function to display historical usage trends
show_usage_trends() {
    echo "🔹 CPU & Memory Usage Trends:"
    tail -n 10 $HISTORY_FILE | column -t -s ','
}

# Function to serve system stats via a simple web API
serve_web_dashboard() {
    echo "🔹 Starting Web Dashboard... (Ctrl+C to stop)"
    python3 -m http.server 8080 &
    echo "Access system stats at: http://localhost:8080"
}

# Function to monitor everything
monitor_all() {
    echo "\n🖥️ Advanced System Monitoring\n"
    monitor_cpu
    echo ""
    monitor_memory
    echo ""
    detect_suspicious_processes
    echo ""
    monitor_network
    echo ""
    detect_intrusions
    echo ""
    show_usage_trends
    echo ""
    suggest_optimizations
}

# Menu to select monitoring options
show_menu() {
    while true; do
        echo "\nSelect what you want to monitor:"
        echo "1) CPU Usage & Alerts"
        echo "2) Memory Usage & Alerts"
        echo "3) Suspicious Processes"
        echo "4) Network Stats"
        echo "5) Intrusion Detection"
        echo "6) Usage Trends"
        echo "7) System Optimization Suggestions"
        echo "8) Start Web Dashboard"
        echo "9) Show Everything"
        echo "10) Exit"
        
        echo -n "Enter your choice: "; read choice

        case $choice in
            1) monitor_cpu ;;
            2) monitor_memory ;;
            3) detect_suspicious_processes ;;
            4) monitor_network ;;
            5) detect_intrusions ;;
            6) show_usage_trends ;;
            7) suggest_optimizations ;;
            8) serve_web_dashboard ;;
            9) monitor_all ;;
            10) echo "Exiting..."; exit 0 ;;
            *) echo "Invalid option, please try again." ;;
        esac

        echo "\n----------------------------"
        record_history  # Record system stats after every selection
    done
}

# Run the menu
show_menu

