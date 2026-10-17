#!/bin/bash

# --------------------------------------------------------------------------------------
# 全局变量
# --------------------------------------------------------------------------------------
INTERFACE="wlan0"
BACKUP_DIR="/tmp/wifi-backup"

WIRESHARK_PID_FILE="/tmp/sniffer_wireshark.pid"

# 创建备份目录
mkdir -p $BACKUP_DIR

# --------------------------------------------------------------------------------------
# 日志打印
# --------------------------------------------------------------------------------------
# 颜色输出函数
log_info() {
    echo -e "\033[1;32m`date +\"%Y-%m-%d %H:%M:%S\"` [INFO]\033[0m $1"
}

log_error() {
    echo -e "\033[1;31m`date +\"%Y-%m-%d %H:%M:%S\"` [ERROR]\033[0m $1"
}

log_warning() {
    echo -e "\033[1;33m`date +\"%Y-%m-%d %H:%M:%S\"` [WARNING]\033[0m $1"
}

log_success() {
    echo -e "\033[1;36m`date +\"%Y-%m-%d %H:%M:%S\"` [SUCCESS]\033[0m $1"
}

# --------------------------------------------------------------------------------------
# 脚本名称
# --------------------------------------------------------------------------------------
get_script_name()
{
    basename "${BASH_SOURCE[0]}"
}

# --------------------------------------------------------------------------------------
# 无线网卡检查
# --------------------------------------------------------------------------------------
# 检查网卡是否存在
iface_exists() {
    local iface="$1"

    [ -d "/sys/class/net/$iface" ]
}

# 检查是否为无线网卡
is_wireless() {
    local iface="$1"

    [ -d "/sys/class/net/$iface/wireless" ]
}

# 检查网卡状态
iface_status() {
    local iface="$1"

    cat "/sys/class/net/$iface/operstate"
}

check_wireless() {
    local iface="$1"
    if ! iface_exists "$iface"; then
        echo "Error: $iface not found"
        exit 1
    fi

    if ! is_wireless "$iface"; then
        echo "Error: $iface is not wireless"
        exit 1
    fi

    echo "$iface ready"
}


# --------------------------------------------------------------------------------------
# 启动、停止 Wireshark
# --------------------------------------------------------------------------------------
start_wireshark() {
    # 已经启动则直接返回
    if [ -f "$WIRESHARK_PID_FILE" ]; then
        local pid
        pid=$(cat "$WIRESHARK_PID_FILE")

        if kill -0 "$pid" 2>/dev/null; then
            echo "Wireshark is already running (PID=$pid)"
            return 0
        fi

        rm -f "$WIRESHARK_PID_FILE"
    fi

    MONITOR_INTERFACE=$(iwconfig 2>/dev/null | grep "Mode:Monitor" | awk '{print $1}' | head -1)
    sudo bash -c "
        nohup wireshark -k -i "$MONITOR_INTERFACE" >/dev/null 2>&1 &
        echo \$! > '$WIRESHARK_PID_FILE'
    "

    sleep 1

    if [ -f "$WIRESHARK_PID_FILE" ]; then
        echo "Wireshark started (PID=$(cat "$WIRESHARK_PID_FILE"))"
        return 0
    fi

    echo "Failed to start Wireshark"
    return 1
}


stop_wireshark() {
    if [ ! -f "$WIRESHARK_PID_FILE" ]; then
        return 0
    fi

    local pid
    # pid=$(pgrep -f 'wireshark -k -i wlan0mon')
    pid=$(cat "$WIRESHARK_PID_FILE")
    
    # if kill -0 "$pid" 2>/dev/null; then
    #     kill "$pid"
    #     wait "$pid" 2>/dev/null
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
    		rm -f "$WIRESHARK_PID_FILE"
            return 0
            ;;
        *)
            # 默认/用户选 N：优雅退出，仍在跑就 TERM
            log_info "Leaving Wireshark running (no SIGKILL)."
            return 1
            ;;
    esac

}


# --------------------------------------------------------------------------------------
# 备份当前连接状态
# --------------------------------------------------------------------------------------
backup_connection_state() {
    log_info "备份当前连接状态..."
    
    # 保存当前活动连接信息
    nmcli connection show --active | grep $INTERFACE > $BACKUP_DIR/active_wifi_connection 2>/dev/null || true
    
    # 保存当前连接的详细信息
    if nmcli device show $INTERFACE | grep -q "connected"; then
        nmcli device show $INTERFACE > $BACKUP_DIR/device_details
        # 保存当前连接的配置文件名
        nmcli -t -f GENERAL.CONNECTION device show $INTERFACE > $BACKUP_DIR/connection_name 2>/dev/null || true
    fi
    
    # 保存IP配置
    ip addr show $INTERFACE > $BACKUP_DIR/ip_config 2>/dev/null || true
    
    log_info "连接状态备份完成"
}


# --------------------------------------------------------------------------------------
# 恢复正常上网模式 (精准恢复版)
# --------------------------------------------------------------------------------------
restore_normal_mode() {
    log_info "恢复正常上网模式..."
    INTERFACE=$1
    
    # 1. 停止抓包相关进程
    log_info "停止抓包相关进程..."
    pkill -f "airodump-ng" 2>/dev/null || true
    pkill -f "aireplay-ng" 2>/dev/null || true
    pkill -f "aircrack-ng" 2>/dev/null || true
    stop_wireshark
    
    # 2. 检查并停止monitor模式
    MONITOR_IF=$(iwconfig 2>/dev/null | grep "Mode:Monitor" | awk '{print $1}' | head -1)
    if [ ! -z "$MONITOR_IF" ]; then
        log_info "停止monitor模式: $MONITOR_IF"
        airmon-ng stop $MONITOR_IF 2>/dev/null || true
        sleep 1
    fi
    
    # 3. 停止热点相关服务
    log_info "停止热点相关服务..."
    pkill -f "hostapd" 2>/dev/null || true
    pkill -f "dnsmasq" 2>/dev/null || true
    
    # 4. 清理网络配置
    log_info "清理网络配置..."
    # 清理IP地址（保留环回接口）
    ip addr flush dev $INTERFACE 2>/dev/null || true
    # 清理iptables规则
    iptables -t nat -D POSTROUTING -o $(ip route | grep default | awk '{print $5}' | head -1) -j MASQUERADE 2>/dev/null || true
    iptables -F FORWARD 2>/dev/null || true
    
    # 5. 确保接口处于正确状态
    log_info "重置网卡接口..."
    ip link set $INTERFACE down 2>/dev/null || true
    sleep 1
    ip link set $INTERFACE up 2>/dev/null || true
    
    # 6. 重新让NetworkManager管理wlan0 (关键步骤)
    log_info "将 $INTERFACE 重新交给NetworkManager管理..."
    nmcli device set $INTERFACE managed yes
    
    # 7. 等待NetworkManager接管设备
    log_info "等待NetworkManager接管设备..."
    sleep 5
    
    if ! nmcli device show $INTERFACE | grep -q "connected"; then
        # 8. 重新扫描WiFi网络
        log_info "重新扫描WiFi网络..."
        nmcli device wifi rescan
        sleep 2
        
        # 9. 尝试自动连接到之前的网络
        if [ -f "$BACKUP_DIR/connection_name" ]; then
            CONNECTION_NAME=$(cat $BACKUP_DIR/connection_name | cut -d: -f2)
            if [ ! -z "$CONNECTION_NAME" ] && [ "$CONNECTION_NAME" != "--" ]; then
                log_info "尝试连接到之前的网络: $CONNECTION_NAME"
                nmcli connection up "$CONNECTION_NAME" 2>/dev/null || true
                sleep 3
            fi
        fi
    fi
    
    # 10. 验证连接状态
    if nmcli device show $INTERFACE | grep -q "connected"; then
        IP_ADDR=$(ip addr show $INTERFACE | grep "inet " | awk '{print $2}' | head -1)
        SSID=$(iwconfig $INTERFACE 2>/dev/null | grep "ESSID" | cut -d'"' -f2)
        log_success "网络连接已恢复！"
        [ ! -z "$SSID" ] && log_info "已连接到: $SSID"
        [ ! -z "$IP_ADDR" ] && log_info "IP地址: $IP_ADDR"
    else
        log_warning "自动连接失败，显示可用网络供手动连接："
        echo ""
        nmcli device wifi list | head -8
        echo ""
        log_info "手动连接命令示例："
        echo "nmcli device wifi connect \"WiFi名称\" password \"密码\""
    fi
}

# --------------------------------------------------------------------------------------
# 进入Monitor模式 (精准控制版)
# --------------------------------------------------------------------------------------
enter_monitor_mode() {
    local BAND="${1:-2.4}"  # 默认2.4GHz，可选5
    
    if [ ! -z "$2" ]; then
        INTERFACE="$2"
    fi

    check_wireless $INTERFACE
    
    log_info "进入Monitor模式（抓包模式）..."
    
    # 验证频段参数
    if [ "$BAND" != "2.4" ] && [ "$BAND" != "5" ]; then
        log_error "无效的频段参数: $BAND (支持: 2.4 或 5)"
        exit 1
    fi
    
    # 检查网卡是否支持指定频段
    if [ "$BAND" = "5" ]; then
        if ! iw list 2>/dev/null | grep -A 20 "Frequencies:" | grep -q "5[0-9][0-9][0-9] MHz"; then
            log_error "网卡不支持5GHz频段"
            exit 1
        fi
        log_info "将在5GHz频段进行抓包"
    else
        log_info "将在2.4GHz频段进行抓包"
    fi
    
    # 1. 备份当前连接状态
    backup_connection_state
    
    # 2. 将wlan0从NetworkManager管理中移除 (关键步骤)
    log_info "将 $INTERFACE 从NetworkManager管理中移除..."
    nmcli device set $INTERFACE managed no
    
    # 3. 等待NetworkManager释放控制权
    sleep 2
    
    # 4. 精确停止wlan0相关的网络进程
    log_info "停止 $INTERFACE 相关的网络进程..."
    
    # 现代Ubuntu中，NetworkManager管理WiFi时通常不会有独立的wpa_supplicant进程
    # 而是通过NetworkManager内部集成的wpa_supplicant
    # 检查是否有独立的wpa_supplicant进程
    WPA_PID=$(pgrep -f "wpa_supplicant" | head -1)
    if [ ! -z "$WPA_PID" ]; then
        # 检查这个wpa_supplicant是否在使用我们的接口
        if lsof -p $WPA_PID 2>/dev/null | grep -q $INTERFACE; then
            log_info "停止使用 $INTERFACE 的wpa_supplicant进程 (PID: $WPA_PID)"
            kill $WPA_PID
            sleep 1
        fi
    fi

    # 现代Ubuntu使用systemd-networkd或NetworkManager内置DHCP客户端
    # dhclient进程可能不存在，检查其他可能的DHCP客户端
    for dhcp_client in "dhclient" "dhcpcd" "udhcpc"; do
        DHCP_PID=$(pgrep -f "$dhcp_client.*$INTERFACE" | head -1)
        if [ ! -z "$DHCP_PID" ]; then
            log_info "停止 $dhcp_client 进程 (PID: $DHCP_PID)"
            kill $DHCP_PID
            sleep 1
            break
        fi
    done

    # 额外检查：确保接口从NetworkManager断开
    log_info "确保 $INTERFACE 从NetworkManager断开连接..."
    nmcli device disconnect $INTERFACE 2>/dev/null || true
    sleep 1

    # 5. 启动monitor模式
    log_info "启动monitor模式..."
    airmon-ng start $INTERFACE

    # 6. 验证monitor模式是否成功启动
    sleep 2
    MONITOR_INTERFACE=$(iwconfig 2>/dev/null | grep "Mode:Monitor" | awk '{print $1}' | head -1)

    if [ -z "$MONITOR_INTERFACE" ]; then
        # 尝试常见的monitor接口名
        for possible_name in "${INTERFACE}mon" "mon0" "wlan0mon"; do
            if iwconfig $possible_name 2>/dev/null | grep -q "Mode:Monitor"; then
                MONITOR_INTERFACE=$possible_name
                break
            fi
        done
    fi

    if [ ! -z "$MONITOR_INTERFACE" ] && iwconfig $MONITOR_INTERFACE 2>/dev/null | grep -q "Mode:Monitor"; then
        log_success "Monitor模式启动成功！"
        log_info "Monitor接口: $MONITOR_INTERFACE"
        log_info "抓包频段: ${BAND}GHz"
        log_info ""
        log_info "=== 接口[$MONITOR_INTERFACE]状态 ==="
        echo "`iwconfig $MONITOR_INTERFACE`"
        log_info ""
        log_info "=== 常用抓包命令 ==="

        if [ "$BAND" = "5" ]; then
            echo "# 扫描5GHz所有信道："
            echo "sudo airodump-ng --band a $MONITOR_INTERFACE"
            echo ""
            echo "# 抓取5GHz特定信道 (如36信道)："
            echo "sudo airodump-ng --band a $MONITOR_INTERFACE -c 36 -w /tmp/capture "
            echo ""
            echo "# 抓取5GHz特定AP："
            echo "sudo airodump-ng --band a $MONITOR_INTERFACE -c 36 --bssid AA:BB:CC:DD:EE:FF -w /tmp/capture"
            echo ""
            echo "# 5GHz常用信道: 36, 40, 44, 48, 149, 153, 157, 161"
        else
            echo "# 扫描2.4GHz所有信道："
            echo "sudo airodump-ng $MONITOR_INTERFACE"
            echo "  或"
            echo "sudo airodump-ng --band bg $MONITOR_INTERFACE"
            echo ""
            echo "# 抓取2.4GHz特定信道 (如6信道)："
            echo "sudo airodump-ng $MONITOR_INTERFACE -c 6 -w /tmp/capture"
            echo ""
            echo "# 抓取2.4GHz特定AP："
            echo "sudo airodump-ng $MONITOR_INTERFACE -c 6 --bssid AA:BB:CC:DD:EE:FF -w /tmp/capture"
            echo ""
            echo "# 2.4GHz常用信道: 1, 6, 11"
        fi

        echo ""
        echo "# 抓包完成后执行恢复："
        echo "sudo $(get_script_name) normal"
        echo ""

        log_info "Start Wireshark"
        start_wireshark
        echo "========================================================"
    else
        log_error "Monitor模式启动失败！"
        log_error "可能的原因："
        echo "  1. 网卡不支持monitor模式"
        echo "  2. 驱动程序问题"
        echo "  3. 其他进程占用网卡"
        log_info "尝试恢复正常模式..."
        restore_normal_mode
        exit 1
    fi
}

# --------------------------------------------------------------------------------------
# 显示当前状态
# --------------------------------------------------------------------------------------
show_status() {
    echo "==================== WiFi网卡状态信息 ===================="
    echo ""

    if [ ! -z "$1" ]; then
        INTERFACE="$1"
    fi

    # 基本接口信息
    echo "【接口基本信息】"
    ip link show $INTERFACE 2>/dev/null || echo "$INTERFACE 接口不存在"
    echo ""

    # WiFi模式和连接状态
    echo "【WiFi模式和状态】"
    MODE=$(iwconfig $INTERFACE 2>/dev/null | grep "Mode:" | awk -F'Mode:' '{print $2}' | awk '{print $1}')
    ESSID=$(iwconfig $INTERFACE 2>/dev/null | grep "ESSID" | cut -d'"' -f2)
    echo "当前模式: ${MODE:-Unknown}"
    if [ ! -z "$ESSID" ] && [ "$ESSID" != "off/any" ]; then
        echo "连接SSID: $ESSID"
    fi
    echo ""

    # NetworkManager管理状态
    echo "【NetworkManager管理状态】"
    NM_MANAGED=$(nmcli device show $INTERFACE 2>/dev/null | grep "GENERAL.STATE" | awk '{print $2}')
    echo "管理状态: ${NM_MANAGED:-Unknown}"
    if nmcli device show $INTERFACE 2>/dev/null | grep -q "connected"; then
        CONNECTION=$(nmcli -t -f GENERAL.CONNECTION device show $INTERFACE 2>/dev/null | cut -d: -f2)
        echo "活动连接: $CONNECTION"
    fi
    echo ""

    # IP地址信息
    echo "【IP地址信息】"
    IP_INFO=$(ip addr show $INTERFACE 2>/dev/null | grep "inet " | awk '{print $2}')
    if [ ! -z "$IP_INFO" ]; then
        echo "IP地址: $IP_INFO"
    else
        echo "IP地址: 未分配"
    fi
    echo ""

    # 相关进程状态
    echo "【相关进程状态】"
    echo "NetworkManager: $(systemctl is-active NetworkManager)"
    
    # 检查wpa_supplicant进程
    WPA_PID=$(pgrep -f "wpa_supplicant" | head -1)
    if [ ! -z "$WPA_PID" ]; then
        # 检查是否与当前接口相关
        if lsof -p $WPA_PID 2>/dev/null | grep -q $INTERFACE || \
           ps -p $WPA_PID -o args --no-headers | grep -q $INTERFACE; then
            echo "wpa_supplicant: 运行中，管理 $INTERFACE (PID: $WPA_PID)"
        else
            echo "wpa_supplicant: 运行中，但未管理 $INTERFACE (PID: $WPA_PID)"
        fi
    else
        echo "wpa_supplicant: 未运行 (可能由NetworkManager内置管理)"
    fi

    # 检查DHCP客户端
    DHCP_FOUND=false
    for dhcp_client in "dhclient" "dhcpcd" "udhcpc"; do
        DHCP_PID=$(pgrep -f "$dhcp_client.*$INTERFACE" | head -1)
        if [ ! -z "$DHCP_PID" ]; then
            echo "$dhcp_client: 运行中 (PID: $DHCP_PID)"
            DHCP_FOUND=true
            break
        fi
    done
    if [ "$DHCP_FOUND" = false ]; then
        echo "DHCP客户端: 未运行 (可能由NetworkManager内置管理)"
    fi
    
    if pgrep -f "hostapd.*$INTERFACE" > /dev/null; then
        echo "hostapd: 运行中 (PID: $(pgrep -f "hostapd.*$INTERFACE"))"
    else
        echo "hostapd: 未运行"
    fi
    
    if pgrep -f "airodump-ng.*$INTERFACE" > /dev/null; then
        echo "airodump-ng: 运行中 (PID: $(pgrep -f "airodump-ng.*$INTERFACE"))"
    else
        echo "airodump-ng: 未运行"
    fi
    echo ""

    # Monitor接口检查
    MONITOR_IF=$(iwconfig 2>/dev/null | grep "Mode:Monitor" | awk '{print $1}' | head -1)
    if [ ! -z "$MONITOR_IF" ]; then
        echo "【Monitor接口】"
        echo "Monitor接口: $MONITOR_IF"
        echo ""
    fi

    echo "========================================================="
}

# --------------------------------------------------------------------------------------
# 清理函数 - 用于强制清理所有状态
# --------------------------------------------------------------------------------------
force_cleanup() {
    log_warning "执行强制清理..."

    # 停止所有相关进程
    pkill -f "airodump-ng" 2>/dev/null || true
    pkill -f "hostapd.*$INTERFACE" 2>/dev/null || true
    pkill -f "dnsmasq.*$INTERFACE" 2>/dev/null || true

    # 停止所有monitor接口
    for iface in $(iwconfig 2>/dev/null | grep "Mode:Monitor" | awk '{print $1}'); do
        airmon-ng stop $iface 2>/dev/null || true
    done

    # 重置接口
    ip link set $INTERFACE down 2>/dev/null || true
    ip addr flush dev $INTERFACE 2>/dev/null || true
    ip link set $INTERFACE up 2>/dev/null || true

    # 清理iptables
    iptables -t nat -F 2>/dev/null || true
    iptables -F FORWARD 2>/dev/null || true

    # 重新让NetworkManager管理
    nmcli device set $INTERFACE managed yes

    log_info "强制清理完成，请检查网络状态"
}

# --------------------------------------------------------------------------------------
# 主菜单 / Main Function (With Argument Parsing)
# --------------------------------------------------------------------------------------
main() {
    case "$1" in
        "monitor"|"m")
            # 支持频段参数: 2.4 或 5
            BAND="${2:-2.4}"
            IFACE="${3:wlan0}"
            enter_monitor_mode "$BAND" $IFACE
            ;;
        "normal"|"n"|"restore")
            IFACE="${2:wlan0}"
            restore_normal_mode $IFACE
            ;;
        "status"|"s")
            IFACE="${2:wlan0}"
            show_status $IFACE
            ;;
        "cleanup"|"clean"|"c")
            force_cleanup
            ;;
        *)
            echo "============== WiFi网卡多模式管理工具 =============="
            echo "用法: $0 {命令} [参数]"
            echo ""
            echo "命令选项："
            echo "  monitor|m [频段] [iface]                     - 进入Monitor模式（抓包模式）"
            echo "    频段: 2.4 (默认) 或 5"
            echo "  normal|n                                    - 恢复正常上网模式"
            echo "  status|s [iface]                            - 显示当前详细状态"
            echo "  cleanup|c                                   - 强制清理所有状态"
            echo ""
            echo "使用示例："
            echo "  # Monitor模式示例"
            echo "  sudo $0 monitor                             - 2.4GHz抓包（默认）"
            echo "  sudo $0 monitor 2.4 [iface]                 - 2.4GHz抓包"
            echo "  sudo $0 monitor 5 [iface]                   - 5GHz抓包"
            echo ""
            echo "  # 其他示例"
            echo "  sudo $0 normal                              - 恢复正常上网"
            echo "  sudo $0 status [iface]                      - 查看状态"
            echo ""
            echo "频段和信道说明："
            echo "  2.4GHz频段:"
            echo "    - 可用信道: 1-13"
            echo "    - 推荐信道: 1, 6, 11 (互不干扰)"
            echo "    - 适用场景: 穿墙性能好，兼容性强"
            echo ""
            echo "  5GHz频段:"
            echo "    - 可用信道: 36, 40, 44, 48, 149, 153, 157, 161"
            echo "    - 推荐信道: 36, 149"
            echo "    - 适用场景: 速度快，干扰少，但穿墙性能较差"
            echo "================================================="
            exit 1
            ;;
    esac
}


#----------------------------------------------------------------------------
# Entry point
#----------------------------------------------------------------------------
main $@

