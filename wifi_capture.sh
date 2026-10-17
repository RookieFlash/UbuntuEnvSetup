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
    ans=""
    if [ -t 0 ] || [ -c /dev/tty ]; then
        # -t 10: 超时 10 秒；读 /dev/tty 保证 trap 场景下也能读
        read -r -t 10 -p "Kill Wireshark? [y/N] (10s timeout, default N): " ans </dev/tty
        local rc=$?
        if [ $rc -ne 0 ]; then
            echo    # 超时/EOF 后补个换行，免得提示符错位
            log_warn "No response within 10s (or input aborted) -> defaulting to N."
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

