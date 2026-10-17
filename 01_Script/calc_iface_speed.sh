#!/bin/sh

# ========================================================
# #!/bin/sh 是为了在 Android设备上运行
# #!/bin/bash 是Linux下默认的终端类型
# 查看终端类型通过 echo $0
# ========================================================

# =======================================================================================================
# 日志打印，只输出到终端(带有颜色标识) 
# =======================================================================================================
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

# ========================================================
# Function to calculate TX speed
# ========================================================
calculate_tx_speed() {
    local interface=$1
    local initial_bytes=$(cat /sys/class/net/$interface/statistics/tx_bytes)

    while true; do
        sleep 1  # Wait for 1 second

        # 判断接口已启用
        if ! ip link show "$interface" | grep -q "state UP"; then
            continue
        fi
        
        local current_bytes=$(cat /sys/class/net/$interface/statistics/tx_bytes)
        
        # Calculate bytes transmitted per second
        local tx_bytes=$((current_bytes - initial_bytes))
        
        # Update initial byte count
        initial_bytes=$current_bytes
        
        # Convert units
        local tx_kbps=$((tx_bytes * 8 / 1024))   # Kbps
        local tx_mbps=$((tx_kbps / 1024))         # Mbps
        local tx_kb=$((tx_bytes / 1024))          # KB
        local tx_mb=$((tx_kb / 1024))              # MB

        # Output results
        log_info "$interface TX Speed: $tx_kbps Kbps | $tx_mbps Mbps | $tx_kb KB/s | $tx_mb MB/s"
    done
}

# ========================================================
# Function to calculate RX speed
# ========================================================
calculate_rx_speed() {
    local interface=$1
    local initial_bytes=$(cat /sys/class/net/$interface/statistics/rx_bytes)

    while true; do
        sleep 1  # Wait for 1 second

        # 判断接口已启用
        if ! ip link show "$interface" | grep -q "state UP"; then
            continue
        fi
        
        local current_bytes=$(cat /sys/class/net/$interface/statistics/rx_bytes)
        
        # Calculate bytes received per second
        local rx_bytes=$((current_bytes - initial_bytes))
        
        # Update initial byte count
        initial_bytes=$current_bytes
        
        # Convert units
        local rx_kbps=$((rx_bytes * 8 / 1024))   # Kbps
        local rx_mbps=$((rx_kbps / 1024))         # Mbps
        local rx_kb=$((rx_bytes / 1024))          # KB
        local rx_mb=$((rx_kb / 1024))              # MB

        # Output results
        log_info "$interface RX Speed: $rx_kbps Kbps | $rx_mbps Mbps | $rx_kb KB/s | $rx_mb MB/s"
    done
}

# ========================================================
# Function to calculate TX and RX speed
# ========================================================
calculate_speed() {
    local interface=\$1
    local initial_tx_bytes=$(cat /sys/class/net/$interface/statistics/tx_bytes)
    local initial_rx_bytes=$(cat /sys/class/net/$interface/statistics/rx_bytes)

    while true; do
        sleep 1  # Wait for 1 second

        # 判断接口已启用
        if ! ip link show "$interface" | grep -q "state UP"; then
            continue
        fi

        local current_tx_bytes=$(cat /sys/class/net/$interface/statistics/tx_bytes)
        local current_rx_bytes=$(cat /sys/class/net/$interface/statistics/rx_bytes)
        
        # Calculate bytes transmitted and received per second
        local tx_bytes=$((current_tx_bytes - initial_tx_bytes))
        local rx_bytes=$((current_rx_bytes - initial_rx_bytes))
        
        # Update initial byte counts
        initial_tx_bytes=$current_tx_bytes
        initial_rx_bytes=$current_rx_bytes
        
        # Convert units
        local tx_kbps=$((tx_bytes * 8 / 1024))   # Kbps
        local tx_mbps=$((tx_kbps / 1024))         # Mbps
        local tx_kb=$((tx_bytes / 1024))          # KB
        local tx_mb=$((tx_kb / 1024))              # MB

        local rx_kbps=$((rx_bytes * 8 / 1024))   # Kbps
        local rx_mbps=$((rx_kbps / 1024))         # Mbps
        local rx_kb=$((rx_bytes / 1024))          # KB
        local rx_mb=$((rx_kb / 1024))              # MB

        # Output results
        log_info "$interface TX Speed: $tx_kbps Kbps | $tx_mbps Mbps | $tx_kb KB/s | $tx_mb MB/s"
        log_info "$interface RX Speed: $rx_kbps Kbps | $rx_mbps Mbps | $rx_kb KB/s | $rx_mb MB/s"
    done
}

# ========================================================
# Main function
# 根据需要调用对应的函数
# ========================================================
main() {
    if [ $# -ne 2 ]; then
        echo "Usage: $0 <interface> <tx/rx>"
        exit 1
    fi

    local interface=$1
    local type=$2

    # Start TX or RX speed calculations
    if [[ $type == "tx" ]]; then
        calculate_tx_speed "$interface"
    elif [[ $type == "rx" ]]; then
        calculate_rx_speed "$interface"
    fi
}

# Call the main function
main "$@"
