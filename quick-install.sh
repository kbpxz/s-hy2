#!/bin/bash
# Hysteria2 配置管理脚本一键安装脚本
# 使用方法: curl -fsSL https://raw.githubusercontent.com/kbpxz/s-hy2/main/quick-install.sh | sudo bash

# 检查是否启用调试模式
if [[ "$1" == "--debug" ]]; then
    set -x # 启用调试输出
    DEBUG_MODE=true
else
    DEBUG_MODE=false
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 日志函数
log_debug() {
    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $1"
    fi
}
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}
log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}
log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 脚本信息 - 使用你的 fork
SCRIPT_NAME="s-hy2"
INSTALL_DIR="/opt/$SCRIPT_NAME"
BIN_DIR="/usr/local/bin"
REPO_URL="https://github.com/kbpxz/s-hy2"
RAW_URL="https://raw.githubusercontent.com/kbpxz/s-hy2/main"   # 改为 main

# 打印标题
print_header() {
    clear
    echo -e "${CYAN}================================================${NC}"
    echo -e "${CYAN}    Hysteria2 配置管理脚本一键安装${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo ""
}

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 此脚本需要 root 权限运行${NC}"
        echo "请使用 sudo 运行此脚本"
        return 1
    fi
    return 0
}

# 检测系统类型
detect_system() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS=$ID
        VER=$VERSION_ID
        echo -e "${BLUE}检测到系统: $PRETTY_NAME${NC}"
        return 0
    else
        echo -e "${RED}无法检测系统类型${NC}"
        return 1
    fi
}

# 安装依赖
install_dependencies() {
    echo -e "${BLUE}安装必要依赖...${NC}"
    case $OS in
        ubuntu|debian)
            echo "更新软件包列表..."
            apt update -qq
            echo "安装依赖包..."
            apt install -y curl wget git openssl net-tools iptables
            ;;
        centos|rhel|fedora)
            if command -v dnf &> /dev/null; then
                dnf install -y curl wget git openssl net-tools iptables
            else
                yum install -y curl wget git openssl net-tools iptables
            fi
            ;;
        *)
            echo -e "${YELLOW}未知系统，跳过依赖安装...${NC}"
            ;;
    esac
    echo -e "${GREEN}依赖安装完成${NC}"
}

# 下载单个文件
download_file() {
    local url="$1"
    local output="$2"
    local description="$3"
    echo "  下载 $description..."
    if ! curl -fsSL "$url" -o "$output"; then
        echo -e "${RED}  失败: 无法下载 $description${NC}"
        return 1
    fi
    return 0
}

# 下载脚本文件
download_scripts() {
    echo -e "${BLUE}下载 Hysteria2 配置管理脚本...${NC}"
    
    if ! mkdir -p "$INSTALL_DIR" "$INSTALL_DIR/scripts" "$INSTALL_DIR/templates"; then
        echo -e "${RED}错误: 无法创建安装目录${NC}"
        exit 1
    fi
    
    cd "$INSTALL_DIR" || {
        echo -e "${RED}错误: 无法进入安装目录${NC}"
        exit 1
    }
    
    # 下载主脚本
    download_file "$RAW_URL/hy2-manager.sh" "hy2-manager.sh" "主脚本" || exit 1
    download_file "$RAW_URL/install.sh" "install.sh" "主安装脚本" || exit 1
    
    # 下载功能模块
    echo "下载功能模块..."
    local scripts=(
        "common.sh:公共库脚本"
        "config.sh:配置脚本"
        "service.sh:服务管理脚本"
        "domain-test.sh:域名测试脚本"
        "node-info.sh:节点信息脚本"
        "firewall-manager.sh:防火墙管理模块"
        "outbound-manager.sh:出站管理模块"
    )
    for script_info in "${scripts[@]}"; do
        IFS=':' read -r script_name script_desc <<< "$script_info"
        download_file "$RAW_URL/scripts/$script_name" "scripts/$script_name" "$script_desc"
    done
    
    # 下载配置模板
    echo "下载配置模板..."
    local templates=(
        "acme-config.yaml:ACME配置模板"
        "self-cert-config.yaml:自签名配置模板"
        "client-config.yaml:客户端配置模板"
    )
    for template_info in "${templates[@]}"; do
        IFS=':' read -r template_name template_desc <<< "$template_info"
        download_file "$RAW_URL/templates/$template_name" "templates/$template_name" "$template_desc"
    done
    
    # 设置执行权限
    echo "设置执行权限..."
    chmod +x hy2-manager.sh scripts/*.sh
    
    echo -e "${GREEN}脚本文件下载完成${NC}"
}

# 创建符号链接
create_symlink() {
    echo -e "${BLUE}创建命令行快捷方式...${NC}"
    ln -sf "$INSTALL_DIR/hy2-manager.sh" "$BIN_DIR/hy2-manager"
    ln -sf "$INSTALL_DIR/hy2-manager.sh" "$BIN_DIR/s-hy2"
    echo -e "${GREEN}已创建命令行快捷方式:${NC}"
    echo "  hy2-manager"
    echo "  s-hy2"
}

# 显示安装完成信息
show_completion() {
    echo ""
    echo -e "${CYAN}================================================${NC}"
    echo -e "${CYAN}    Hysteria2 配置管理脚本安装完成!${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo ""
    echo -e "${GREEN}安装位置:${NC} $INSTALL_DIR"
    echo -e "${GREEN}命令快捷方式:${NC} s-hy2, hy2-manager"
    echo ""
    echo -e "${YELLOW}使用方法:${NC}"
    echo "  sudo s-hy2"
    echo ""
    echo -e "${BLUE}现在可以运行 'sudo s-hy2' 开始使用!${NC}"
}

# 主函数
main() {
    print_header
    echo -e "${YELLOW}即将安装 Hysteria2 配置管理脚本${NC}"
    echo ""
    echo -e "${BLUE}此脚本将会:${NC}"
    echo "• 检测系统环境"
    echo "• 安装必要依赖"
    echo "• 下载脚本文件"
    echo "• 创建快捷命令 's-hy2'"
    echo "• 设置执行权限"
    echo ""
    echo -n -e "${YELLOW}是否继续安装? [Y/n]: ${NC}"
    read -r confirm
    if [[ $confirm =~ ^[Nn]$ ]]; then
        echo -e "${BLUE}取消安装${NC}"
        exit 0
    fi
    echo ""
    echo -e "${BLUE}开始安装...${NC}"
    
    check_root || exit 1
    detect_system
    install_dependencies
    download_scripts
    create_symlink
    show_completion
}

main "$@"
