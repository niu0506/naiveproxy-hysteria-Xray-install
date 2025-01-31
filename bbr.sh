#!/bin/bash

# ========================
# 📌 常量定义
# ========================
declare -A SYSCTL_SETTINGS=(
    # TCP接收缓冲区的最小、默认、最大值（单位：字节）
    ["net.ipv4.tcp_rmem"]="4096 87380 6291456"
    # TCP发送缓冲区的最小、默认、最大值
    ["net.ipv4.tcp_wmem"]="4096 87380 6291456"
    # 接收缓冲区的最大大小
    ["net.core.rmem_max"]=33554432
    # 发送缓冲区的最大大小
    ["net.core.wmem_max"]=33554432
    # FIN超时时间（秒），减少TIME_WAIT状态持续时间
    ["net.ipv4.tcp_fin_timeout"]=20
    # 允许重用TIME_WAIT状态的连接
    ["net.ipv4.tcp_tw_reuse"]=1
    # 启用TCP窗口缩放以支持高延迟高带宽连接
    ["net.ipv4.tcp_window_scaling"]=1
    # 默认流量队列规则，使用公平队列(fq)
    ["net.core.default_qdisc"]="fq"
    # 使用BBR拥塞控制算法
    ["net.ipv4.tcp_congestion_control"]="bbr"
    # 启用TCP Fast Open（3=客户端+服务端）
    ["net.ipv4.tcp_fastopen"]=3
    # Keepalive检测空闲连接间隔（秒）
    ["net.ipv4.tcp_keepalive_time"]=300
    # Keepalive探测间隔（秒）
    ["net.ipv4.tcp_keepalive_intvl"]=75
    # Keepalive探测次数
    ["net.ipv4.tcp_keepalive_probes"]=9
    # 启用SYN Cookies防御洪水攻击
    ["net.ipv4.tcp_syncookies"]=1
    # SYN队列最大长度
    ["net.ipv4.tcp_max_syn_backlog"]=8192
    # SYN-ACK最大重试次数
    ["net.ipv4.tcp_synack_retries"]=2
    # 本地端口范围
    ["net.ipv4.ip_local_port_range"]="1024 65535"
)

CONFIG_FILE="/etc/sysctl.d/99-bbr.conf"
MODULES=("tcp_bbr")  # BBR依赖的内核模块

# ========================
# 📌 工具函数
# ========================
die() {
    printf "\033[31m[错误] %s\033[0m\n" "$*" >&2
    exit 1
}

info() {
    printf "\033[34m[信息] %s\033[0m\n" "$*"
}

check_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        die "未找到命令: $1 (尝试安装: ${2:-unknown})"
    fi
}

check_root() {
    [ "$(id -u)" -eq 0 ] || die "该脚本必须以 root 权限运行！"
}

validate_setting() {
    local key=$1
    local expected=$2
    local actual
    actual=$(sysctl -n "$key" 2>/dev/null | xargs)
    expected=$(echo "$expected" | xargs)

    if [ "$actual" != "$expected" ]; then
        die "$key 设置失败 (当前: '${actual}', 期望: '${expected}')"
    fi
}

# 检查内核模块是否可用（已加载或内置）
module_available() {
    local module=$1
    grep -qw "^${module}" /proc/modules || [ -d "/sys/module/${module}" ]
}

# ========================
# 📌 主逻辑
# ========================
main() {
    # 预检
    check_root
    check_command sysctl procps
    check_command modprobe kmod

    # 检查内核版本 ≥ 4.9
    local kernel_ver
    kernel_ver=$(uname -r | awk -F. '{ printf("%d%02d", $1,$2) }')
    if [ "$kernel_ver" -lt 409 ]; then
        die "需要 Linux 内核 ≥ 4.9 (当前: $(uname -r))"
    fi

    # 检查BBR是否可用
    if ! grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control; then
        die "当前内核不支持 BBR 拥塞控制算法。"
    fi

    # 加载必要内核模块
    for module in "${MODULES[@]}"; do
        if ! module_available "$module"; then
            info "正在加载内核模块: ${module}..."
            if ! modprobe "$module" 2>/dev/null; then
                die "无法加载模块 ${module}，请检查内核配置。"
            fi
        fi
    done

    # 设置并验证sysctl参数
    info "正在优化系统网络参数..."
    for key in "${!SYSCTL_SETTINGS[@]}"; do
        sysctl -w "$key=${SYSCTL_SETTINGS[$key]}" >/dev/null
        validate_setting "$key" "${SYSCTL_SETTINGS[$key]}"
    done

    # 持久化配置（自动备份旧文件）
    info "正在保存配置到 ${CONFIG_FILE}..."
    if [ -f "$CONFIG_FILE" ]; then
        local backup="${CONFIG_FILE}.bak-$(date +%s)"
        cp -v "$CONFIG_FILE" "$backup"
    fi
    {
        echo "# Generated by $(basename "$0") at $(date)"
        for key in "${!SYSCTL_SETTINGS[@]}"; do
            echo "${key}=${SYSCTL_SETTINGS[$key]}"
        done
    } > "$CONFIG_FILE"
    chmod 644 "$CONFIG_FILE"

    # 应用配置
    if ! sysctl -p "$CONFIG_FILE"; then
        die "持久化配置应用失败，请检查 ${CONFIG_FILE} 内容。"
    fi

    # 重启systemd-sysctl服务（如果存在）
    if systemctl is-active systemd-sysctl &>/dev/null; then
        info "正在重启 systemd-sysctl 服务..."
        systemctl restart systemd-sysctl
    fi

    # 最终验证
    info "关键参数验证:"
    local cc_result
    cc_result=$(sysctl -n net.ipv4.tcp_congestion_control)
    if [ "$cc_result" = "bbr" ]; then
        printf "\033[32m[成功] TCP拥塞控制算法已设置为 BBR。\033[0m\n"
    else
        die "TCP拥塞控制算法设置失败，当前为 ${cc_result}。"
    fi

    local qdisc_result
    qdisc_result=$(sysctl -n net.core.default_qdisc)
    [ "$qdisc_result" = "fq" ] || die "默认队列规则设置失败，当前为 ${qdisc_result}。"

    printf "\n\033[32m✅ 所有优化已成功应用！\033[0m\n"
}

main "$@"
