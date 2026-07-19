#!/bin/bash

# Hysteria2 节点信息显示脚本 - 支持自定义节点名称

# ==================== 自定义节点名称功能 ====================

# 获取自定义节点名称
get_custom_node_name() {
    local default_name="Hysteria2-Server"
    local name_file="/etc/hysteria/node-name.conf"
    
    if [[ -f "$name_file" ]]; then
        cat "$name_file" | tr -d '\n\r'
    else
        echo "$default_name"
    fi
}

# 设置自定义节点名称
set_custom_node_name() {
    local name="$1"
    local name_file="/etc/hysteria/node-name.conf"
    mkdir -p "$(dirname "$name_file")"
    echo "$name" > "$name_file"
    echo -e "${GREEN}✅ 节点名称已设置为: $name${NC}"
}

# ==================== 配置解析 ====================

parse_config_info() {
    local config_file="$CONFIG_PATH"
    
    if [[ ! -f "$config_file" ]]; then
        echo "配置文件不存在"
        return 1
    fi
    
    local port=$(grep -E "^listen:" "$config_file" | awk '{print $2}' | sed 's/://' | head -1)
    [[ -z "$port" ]] && port="443"
    
    local auth_password=$(grep -A 2 "^auth:" "$config_file" | grep "password:" | awk '{print $2}' | tr -d '"')
    
    local obfs_password=""
    if grep -q "^obfs:" "$config_file"; then
        obfs_password=$(grep -A 3 "^obfs:" "$config_file" | grep "password:" | awk '{print $2}' | tr -d '"')
    fi
    
    local masquerade_url=$(grep -A 3 "masquerade:" "$config_file" | grep "url:" | awk '{print $2}')
    local sni_domain=""
    if [[ -n "$masquerade_url" ]]; then
        sni_domain=$(echo "$masquerade_url" | sed 's|https\?://||' | sed 's|/.*||')
    fi
    
    local cert_type="ACME"
    local insecure="false"
    if grep -q "^tls:" "$config_file"; then
        cert_type="自签名"
        insecure="true"
    fi
    
    echo "$port|$auth_password|$obfs_password|$sni_domain|$cert_type|$insecure"
}

get_server_domain() {
    if [[ -f "/etc/hysteria/server-domain.conf" ]]; then
        cat "/etc/hysteria/server-domain.conf"
    else
        echo ""
    fi
}

get_current_server_ip() {
    local ip=""
    ip=$(curl -s --connect-timeout 5 ipv4.icanhazip.com 2>/dev/null) || \
    ip=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null) || \
    ip=$(curl -s --connect-timeout 5 ip.sb 2>/dev/null) || \
    ip=$(curl -s --connect-timeout 5 checkip.amazonaws.com 2>/dev/null)
    
    if [[ -n "$ip" && "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "$ip"
    else
        ip=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+')
        echo "${ip:-127.0.0.1}"
    fi
}

get_server_address() {
    local configured_domain=$(get_server_domain)
    if [[ -n "$configured_domain" ]]; then
        echo "$configured_domain"
    else
        get_current_server_ip
    fi
}

get_port_hopping_info() {
    if [[ -f "/etc/hysteria/port-hopping.conf" ]]; then
        source "/etc/hysteria/port-hopping.conf" 2>/dev/null
        echo "${START_PORT:-20000}-${END_PORT:-50000}"
    else
        echo "未配置"
    fi
}

# ==================== 生成链接 ====================

generate_node_link() {
    local server_ip="$1"
    local port="$2"
    local auth_password="$3"
    local obfs_password="$4"
    local sni_domain="$5"
    local insecure="$6"
    
    local node_name=$(get_custom_node_name)
    
    local link="hysteria2://$auth_password@$server_ip:$port"
    local params=""
    
    if [[ -n "$sni_domain" ]]; then
        params="${params}&sni=$sni_domain"
    fi
    
    if [[ "$insecure" == "true" ]]; then
        params="${params}&insecure=1"
    fi
    
    if [[ -n "$obfs_password" ]]; then
        params="${params}&obfs=salamander&obfs-password=$obfs_password"
    fi
    
    params="${params#&}"
    
    if [[ -n "$params" ]]; then
        link="${link}?${params}"
    fi
    
    link="${link}#${node_name}"
    echo "$link"
}

# ==================== 配置生成函数 ====================

generate_clash_config() {
    local server_address="$1"
    local port="$2"
    local auth_password="$3"
    local obfs_password="$4"
    local sni_domain="$5"
    local insecure="$6"
    local port_hopping="$7"
    local node_name=$(get_custom_node_name)

    cat << EOF
# Clash 配置片段 (Hysteria2)
proxies:
  - name: "$node_name"
    type: hysteria2
    server: $server_address
    port: $port
    password: $auth_password
EOF

    if [[ -n "$port_hopping" && "$port_hopping" != "未配置" ]]; then
        local port_range=$(echo "$port_hopping" | grep -oE '[0-9]+-[0-9]+' | head -1)
        if [[ -n "$port_range" ]]; then
            cat << EOF
    ports: $port_range
EOF
        fi
    fi

    if [[ -n "$obfs_password" ]]; then
        cat << EOF
    obfs: salamander
    obfs-password: "$obfs_password"
EOF
    fi

    if [[ -n "$sni_domain" ]]; then
        cat << EOF
    sni: $sni_domain
EOF
    fi

    if [[ "$insecure" == "true" ]]; then
        cat << EOF
    skip-cert-verify: true
EOF
    fi

    cat << EOF
    alpn:
      - h3
EOF
}

generate_singbox_config() {
    local server_address="$1"
    local port="$2"
    local auth_password="$3"
    local obfs_password="$4"
    local sni_domain="$5"
    local insecure="$6"
    local node_name=$(get_custom_node_name)

    cat << EOF
{
  "type": "hysteria2",
  "tag": "$node_name",
  "server": "$server_address",
  "server_port": $port,
  "password": "$auth_password",
EOF

    if [[ -n "$obfs_password" ]]; then
        cat << EOF
  "obfs": {
    "type": "salamander",
    "password": "$obfs_password"
  },
EOF
    fi

    cat << EOF
  "tls": {
    "enabled": true,
EOF

    if [[ -n "$sni_domain" ]]; then
        cat << EOF
    "server_name": "$sni_domain",
EOF
    fi

    if [[ "$insecure" == "true" ]]; then
        cat << EOF
    "insecure": true,
EOF
    else
        cat << EOF
    "insecure": false,
EOF
    fi

    cat << EOF
    "alpn": ["h3"]
  }
}
EOF
}

generate_client_config() {
    local server_address="$1"
    local port="$2"
    local auth_password="$3"
    local obfs_password="$4"
    local sni_domain="$5"
    local insecure="$6"

    cat << EOF
# Hysteria2 官方客户端配置
server: $server_address:$port
auth: $auth_password

tls:
  sni: $sni_domain
  insecure: $insecure

EOF

    if [[ -n "$obfs_password" ]]; then
        cat << EOF
obfs:
  type: salamander
  salamander:
    password: $obfs_password
EOF
    fi

    cat << EOF
socks5:
  listen: 127.0.0.1:1080

http:
  listen: 127.0.0.1:8080
EOF
}

# ==================== 显示函数 ====================

show_node_links() {
    local node_link="$1"
    clear
    echo -e "${CYAN}=== 节点链接 ===${NC}"
    echo ""
    echo -e "${YELLOW}Hysteria2 节点链接:${NC}"
    echo "$node_link"
    echo ""
}

show_subscription_info() {
    local node_link="$1"
    local server_address="$2"
    local port="$3"
    local auth_password="$4"
    local obfs_password="$5"
    local sni_domain="$6"
    local insecure="$7"
    
    clear
    echo -e "${CYAN}=== 订阅信息 ===${NC}"
    echo ""
    echo -e "${GREEN}节点链接已生成（使用自定义名称）${NC}"
    echo "$node_link"
    echo ""
}

show_client_configs() {
    local server_address="$1"
    local port="$2"
    local auth_password="$3"
    local obfs_password="$4"
    local sni_domain="$5"
    local insecure="$6"
    
    while true; do
        clear
        echo -e "${CYAN}=== 客户端配置 ===${NC}"
        echo ""
        echo -e "${GREEN}1.${NC} Hysteria2 官方客户端配置"
        echo -e "${GREEN}2.${NC} Clash 配置"
        echo -e "${GREEN}3.${NC} SingBox 配置"
        echo -e "${RED}0.${NC} 返回"
        echo -n -e "${BLUE}请选择: ${NC}"
        read -r choice
        
        case $choice in
            1)
                generate_client_config "$server_address" "$port" "$auth_password" "$obfs_password" "$sni_domain" "$insecure"
                ;;
            2)
                local port_hopping=$(get_port_hopping_info)
                generate_clash_config "$server_address" "$port" "$auth_password" "$obfs_password" "$sni_domain" "$insecure" "$port_hopping"
                ;;
            3)
                generate_singbox_config "$server_address" "$port" "$auth_password" "$obfs_password" "$sni_domain" "$insecure"
                ;;
            0) break ;;
            *) echo "无效选项" ;;
        esac
        echo ""
        read -p "按回车继续..."
    done
}

# ==================== 主函数 ====================

display_node_info() {
    echo -e "${BLUE}Hysteria2 节点信息${NC}"
    echo ""
    
    if ! systemctl is-active --quiet hysteria-server.service; then
        echo -e "${RED}警告: Hysteria2 服务未运行${NC}"
        return
    fi
    
    if [[ ! -f "$CONFIG_PATH" ]]; then
        echo -e "${RED}错误: 配置文件不存在${NC}"
        return
    fi
    
    local server_address=$(get_server_address)
    local config_info=$(parse_config_info)
    IFS='|' read -r port auth_password obfs_password sni_domain cert_type insecure <<< "$config_info"
    local node_name=$(get_custom_node_name)
    
    echo -e "${CYAN}当前节点名称: ${YELLOW}$node_name${NC}"
    echo ""
    
    while true; do
        echo -e "${CYAN}=== 选项 ===${NC}"
        echo -e "${GREEN}1.${NC} 查看节点链接"
        echo -e "${GREEN}2.${NC} 查看订阅信息"
        echo -e "${GREEN}3.${NC} 查看客户端配置"
        echo -e "${GREEN}4.${NC} 设置节点名称"
        echo -e "${RED}0.${NC} 返回"
        echo -n -e "${BLUE}请选择 [0-4]: ${NC}"
        read -r choice
        
        case $choice in
            1)
                local link=$(generate_node_link "$server_address" "$port" "$auth_password" "$obfs_password" "$sni_domain" "$insecure")
                show_node_links "$link"
                ;;
            2)
                local link=$(generate_node_link "$server_address" "$port" "$auth_password" "$obfs_password" "$sni_domain" "$insecure")
                show_subscription_info "$link" "$server_address" "$port" "$auth_password" "$obfs_password" "$sni_domain" "$insecure"
                ;;
            3)
                show_client_configs "$server_address" "$port" "$auth_password" "$obfs_password" "$sni_domain" "$insecure"
                ;;
            4)
                echo -e "${BLUE}当前名称: $node_name${NC}"
                echo -n "输入新名称: "
                read -r new_name
                if [[ -n "$new_name" ]]; then
                    set_custom_node_name "$new_name"
                fi
                ;;
            0) break ;;
            *) echo -e "${RED}无效选项${NC}" ;;
        esac
        echo ""
        read -p "按回车继续..."
    done
}

# 如果直接运行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    display_node_info
fi
