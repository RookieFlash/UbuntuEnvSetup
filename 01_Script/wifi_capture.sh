#!/bin/bash

#----------------------------------------------------------------------------
# WiFi Capture Tool v0.1
# Features:
# 1. Automatic wireless interface detection
# 2. Channel selection support
# 3. Comprehensive error handling
# 4. Dependency checking
# Usage: 
#   wifi_capture.sh start [channel]  # default channel is 36
#   wifi_capture.sh stop
#----------------------------------------------------------------------------


#----------------------------------------------------------------------------
# Global Variables
#----------------------------------------------------------------------------
DEFAULT_CHANNEL=36
REQUIRED_TOOLS=("airmon-ng" "iwconfig" "ifconfig" "wireshark")
INTERFACE="wlan0"
MON_INTERFACE="${INTERFACE}mon"


#----------------------------------------------------------------------------
# Logging Functions (Improved with log levels)
#----------------------------------------------------------------------------
log_info()
{
    # echo -e "\e[33m [Info] : \e[36m[`date +\"%Y-%m-%d %H:%M:%S\"` | $1 ] \e[0m" | tee -a "$log_dir/$log_file"
    echo -e "\e[36m[`date +\"%Y-%m-%d %H:%M:%S\"`]\e[33m [Info] | $1 \e[0m"
}

log_warn()
{
    echo -e "\e[36m[`date +\"%Y-%m-%d %H:%M:%S\"`]\e[35m [Warning] | $1 \e[0m"
}

log_error()
{
    echo -e "\e[36m[`date +\"%Y-%m-%d %H:%M:%S\"`]\e[41;37m [Error] | $1 \e[0m"
}

#----------------------------------------------------------------------------
# Check if running as root - Helper Functions
#----------------------------------------------------------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

#----------------------------------------------------------------------------
# Check for required tools - Helper Functions
#----------------------------------------------------------------------------
check_dependencies() {
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool $tool is not installed"
            exit 1
        fi
    done
}

#----------------------------------------------------------------------------
# Find wireless interface - Helper Functions
#----------------------------------------------------------------------------
detect_wireless_interface() {
    # Try common interface names
    local interfaces=("wlan0" "wlan1" "wlp2s0" "wlp3s0")
    
    for iface in "${interfaces[@]}"; do
        if ip link show "$iface" &> /dev/null; then
            INTERFACE="$iface"
            MON_INTERFACE="${iface}mon"
            return 0
        fi
    done
    
    log_error "No wireless interface found"
    exit 1
}

#----------------------------------------------------------------------------
# Show help - Helper Functions
#----------------------------------------------------------------------------
show_help() {
    echo "Usage: $0 [start [channel]|stop]"
    echo "  start [channel]  Start capture on specified channel (default: 36)"
    echo "  stop             Stop capture and restore network"
    echo "Options:"
    echo "  -h, --help       Show this help message"
}

stop_wireshark() {
    # pid=$(ps -ef | grep -v grep | grep 'wireshark -k -i ${MON_INTERFACE}' | awk -F ' ' '{print $2}')
    pid=$(pgrep -f "wireshark -k -i ${MON_INTERFACE}")
    # if [ $pid -ne 0 ]; then
    #     kill -9 $pid
    # fi
    ans="n"
    if [ -c /dev/tty ]; then
        # 倒计时询问：每秒刷新剩余秒数，按任意键即返回
        for ((i=10; i>0; i--)); do
            printf '\rKill Wireshark (PID %s)? [y/N] — %2ds left: ' "$pid" "$i" >&2
            if IFS= read -r -t 1 -n 1 ans </dev/tty; then
                printf '\n' >&2
                break
            fi
            ans=""          # 本秒未输入，清空，进入下一轮
        done
        if [ -z "$ans" ]; then
            printf '\n' >&2
            log_warn "No answer within 10s -> defaulting to N (keep running)."
            ans="n"
        fi
    else
        log_warn "Non-interactive environment -> defaulting to N."
        ans="n"
    fi

    case "$ans" in
        y|Y|yes|YES)
            kill -9 $pid 2>/dev/null
            log_info "Wireshark killed (SIGKILL)."
            return 0
            ;;
        *)
            # 默认/用户选 N：优雅退出，仍在跑就 TERM
            log_info "Leaving Wireshark running (no SIGKILL)."
            return 1
            ;;
    esac
}

#----------------------------------------------------------------------------
# Cleanup on exit
#----------------------------------------------------------------------------
cleanup() {
    log_info "Performing cleanup..."
    
    stop_wireshark

    if ip link show "$MON_INTERFACE" &> /dev/null; then
        airmon-ng stop "$MON_INTERFACE" > /dev/null 2>&1
    fi
    systemctl restart NetworkManager > /dev/null 2>&1
    log_info "Performing cleanup completed"
}

#----------------------------------------------------------------------------
# Capture Functions (With Error Handling)
#----------------------------------------------------------------------------
start_capture() {
    local channel=${1:-$DEFAULT_CHANNEL}
    
    log_info "Starting capture on channel $channel"
    # Kill conflicting processes
    if ! airmon-ng check kill > /dev/null 2>&1; then
        log_warn "Failed to kill conflicting processes"
    fi

    # Bring interface up
    if ! ifconfig "$INTERFACE" up; then
        log_error "Failed to bring up $INTERFACE"
        exit 1
    fi

    # Start monitor mode
    if ! airmon-ng start "$INTERFACE" > /dev/null 2>&1; then
        log_error "Failed to start monitor mode on $INTERFACE"
        exit 1
    fi

    # Set channel
    if ! iwconfig "$MON_INTERFACE" channel "$channel"; then
        log_error "Failed to set channel $channel on $MON_INTERFACE"
        cleanup
        exit 1
    fi

    log_info "Starting Wireshark on $MON_INTERFACE..."
    wireshark -k -i "$MON_INTERFACE" &

    log_info "Capture started successfully on $MON_INTERFACE channel $channel"
    log_info "Press Ctrl+C to stop capture"
    
    # Wait for interruptCleanup on exit
    trap cleanup EXIT
    wait
}

#----------------------------------------------------------------------------
# Stop Capture
#----------------------------------------------------------------------------
stop_capture()
{
    log_info "Stopping capture..."
    cleanup
    log_info "Capture stopped successfully"
}

#----------------------------------------------------------------------------
# Main Function (With Argument Parsing)
#----------------------------------------------------------------------------
main() {
    # Check dependencies first
    check_dependencies
    
    case "$1" in
        start)
            detect_wireless_interface
            check_root
            start_capture "$2"
            ;;
        stop)
            detect_wireless_interface
            check_root
            stop_capture
            ;;
        -h|--help|help|h)
            show_help
            ;;
        *)
            log_warn "Invalid command: $1"
            show_help
            exit 1
            ;;
    esac
}

#----------------------------------------------------------------------------
# Entry point
#----------------------------------------------------------------------------
main $@

