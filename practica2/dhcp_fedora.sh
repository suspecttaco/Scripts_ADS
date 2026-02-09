#!/bin/bash

# Script DHCP - Fedora 

# Este script realiza lo siguiente
# - Verifica e instala dhcp de ser necesario
# - Configura servicio
# - Monitorea el servicio

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # Sin color

separator() {
    echo -e "${CYAN}------------------------------------------------------------${NC}"
}

msg_success() {
    echo -e "${NC}[ ${GREEN}EXITO ${NC}] $1"
}

msg_error() {
    echo -e "${NC}[ ${RED}ERROR ${NC}] $1"
}

msg_info() {
    echo -e "${NC}[ ${BLUE}INFO ${NC}]  $1"
}

msg_alert() {
    echo -e "${NC}[ ${YELLOW}ALERT ${NC}] $1"
}

msg_process() {
    echo -e "${NC}[  ${CYAN}---  ${NC}] $1"
}

msg_input() {
    echo -ne "${CYAN}->${NC} $1"
}

# Validar formato de IP
validar_ip() {
    local ip=$1
    
    # Verificar formato (xxx.xxx.xxx.xxx)
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        # Verificar que cada octeto sea <= 255
        IFS='.' read -ra OCTETOS <<< "$ip"
        for octeto in "${OCTETOS[@]}"; do
            if ((octeto > 255)); then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Verificar e instalar DHCP 
verificar_instalar_dhcp() {
    separator
    msg_process "Verificando presencia de dhcp-server..."
    
    # Verificar si el paquete ya esta instalado
    if rpm -q dhcp-server &> /dev/null; then
        msg_success "dhcp-server ya instalado"
        return 0
    else
        msg_alert "dhcp-server no encontrado. Instalando..."
        sudo dnf install -y dhcp-server &> /dev/null
        
        if [ $? -eq 0 ]; then
            msg_success "Instalado correctamente"
            return 0
        else
            msg_error "Fallo en la instalacion"
            return 1
        fi
    fi
}

# Reutilizado de Script de diagnostico
# Listar interfaces disponibles
listar_interfaces() {
    echo ""
    msg_input "Interfaces de red disponibles:"
    echo ""
    ip -o link show | awk -F': ' '{print $2}' | grep -v "lo" | while read interfaz; do
        echo -e "   ${GREEN}<> ${WHITE}$interfaz${NC}"
    done
    echo ""
}

# Configurar servidor DHCP
configurar_dhcp() {
    separator
    echo -e "${WHITE}--- CONFIGURACION DE DHCP ---${NC}"
    echo ""
    
    # Solicitar nombre del scope
    msg_input "Nombre del ambito (scope): "
    read SCOPE_NAME
    
    # Listar interfaces disponibles
    listar_interfaces
    
    # Solicitar interfaz de red
    while true; do
        msg_input "Interfaz de red a usar: " 
        read INTERFAZ
        if ip link show "$INTERFAZ" &> /dev/null; then
            break
        fi
        msg_error "La interfaz '$INTERFAZ' no existe"
    done
    
    echo ""
    separator
    echo -e "${WHITE}Configuracion de Red${NC}"
    echo ""

    # Solicitar ip base
    while true; do
        msg_input "Segmento (ej. 192.168.1.0): " 
        read RED_BASE
        if validar_ip "$RED_BASE"; then
            # Extraer los primeros 3 octetos para construir IPs
            RED_PREFIJO=$(echo $RED_BASE | cut -d. -f1-3)
            break
        fi
        msg_error "IP invalida"
    done
    
    # Solicitar mascara de subred
    while true; do
        msg_input "Mascara de subred [default = 255.255.255.0]: " 
        read MASCARA
        MASCARA=${MASCARA:-255.255.255.0}
        if validar_ip "$MASCARA"; then
            break
        fi
        msg_error "Mascara invalida"
    done
    
    echo ""
    separator
    echo -e "${WHITE}Rango de IPs${NC}"
    echo ""

    # IP de inicio con validacion
    while true; do
        msg_input "IP de inicio [default = ${RED_PREFIJO}.50]: " 
        read IP_INICIO
        IP_INICIO=${IP_INICIO:-${RED_PREFIJO}.50}
        if validar_ip "$IP_INICIO"; then
            break
        fi
        msg_error "IP invalida"
    done
    
    # IP final con validacion
    while true; do
        msg_input "IP final [default = ${RED_PREFIJO}.150]: " 
        read IP_FIN
        IP_FIN=${IP_FIN:-${RED_PREFIJO}.150}
        if validar_ip "$IP_FIN"; then
            break
        fi
        msg_error "IP invalida"
    done

    echo ""
    separator
    echo -e "${WHITE}Parametros de Red${NC}"
    echo ""
    
    # Gateway con validacion
    while true; do
        msg_input "Gateway [default = ${RED_PREFIJO}.1]: " 
        read GATEWAY
        GATEWAY=${GATEWAY:-${RED_PREFIJO}.1}
        if validar_ip "$GATEWAY"; then
            break
        fi
        msg_error "IP invalida"
    done
    
    # DNS con validacion
    while true; do
        msg_input "Servidor DNS [default = ${RED_PREFIJO}.20]: " 
        read DNS_SERVER
        DNS_SERVER=${DNS_SERVER:-${RED_PREFIJO}.20}
        if validar_ip "$DNS_SERVER"; then
            break
        fi
        msg_error "IP invalida"
    done
    
    # Lease time con validacion
    while true; do
        msg_input "Tiempo de concesion en segundos [default = 86400]: " 
        read LEASE_TIME
        LEASE_TIME=${LEASE_TIME:-86400}
        
        if [[ "$LEASE_TIME" =~ ^[0-9]+$ ]]; then
            break
        fi
        msg_error "Debe ser un numero entero"
    done

    echo ""
    separator
    echo -e "${WHITE}Resumen de configuracion${NC}"
    echo ""
    echo ""
    echo -e "  ${CYAN}Scope:${NC}       $SCOPE_NAME"
    echo -e "  ${CYAN}Interfaz:${NC}    $INTERFAZ"
    echo -e "  ${CYAN}Red:${NC}         $RED_BASE/$MASCARA"
    echo -e "  ${CYAN}Rango:${NC}       $IP_INICIO → $IP_FIN"
    echo -e "  ${CYAN}Gateway:${NC}     $GATEWAY"
    echo -e "  ${CYAN}DNS:${NC}         $DNS_SERVER"
    echo -e "  ${CYAN}Lease:${NC}       $LEASE_TIME segundos"
    echo ""
    separator
    echo ""

    echo -ne "${YELLOW}Desea usar esta configuracion? (s/N): ${NC}"
    read CONFIRMAR

    if [[! "$CONFIRMAR" =~ ^[Ss]$ ]]; then
        msg_alert "Configuracion cancelada por el usuario"
        return 1
    fi
    
    # Generar archivo de configuracion
    echo ""
    msg_process "Generando archivo de configuracion..."

    sudo tee /etc/dhcp/dhcpd.conf > /dev/null <<EOF
# Configuracion DHCP - $SCOPE_NAME
# Generado: $(date)
# Interfaz: $INTERFAZ

# Parametros globales
authoritative;
default-lease-time $LEASE_TIME;
max-lease-time $((LEASE_TIME * 2));

# Subred: $RED_BASE/$MASCARA
subnet $RED_BASE netmask $MASCARA {
    # Rango de IPs dinamicas
    range $IP_INICIO $IP_FIN;
    
    # Opciones de red
    option routers $GATEWAY;
    option domain-name-servers $DNS_SERVER;
    option subnet-mask $MASCARA;
}
EOF
    
    msg_success "Archivo de configuracion creado"

    # Validar configuracion
    msg_process "Validando configuracion..."
    sudo dhcpd -t -cf /etc/dhcp/dhcpd.conf
    
    if [ $? -ne 0 ]; then
        msg_error "Error en la configuracion"
        return 1
    else
        msg_success "Configuracion validada correctamente"    
    fi
    
    # Configurar interfaz de escucha
    msg_process "Configurando interfaz de red..."
    echo "DHCPDARGS=\"$INTERFAZ\"" | sudo tee /etc/sysconfig/dhcpd > /dev/null
    msg_success "Interfaz de escucha configurada"
    
    # Configurar firewall
    msg_process "Configurando firewall..."
    
    # Verificar que firewalld este activo
    if ! systemctl is-active --quiet firewalld; then
        msg_process "Iniciando firewalld..."
        sudo systemctl start firewalld
    fi
    
    sudo firewall-cmd --permanent --zone=internal --add-service=dhcp &> /dev/null
    sudo firewall-cmd --reload &> /dev/null
    msg_success "Reglas de firewall aplicadas"
    
    # Habilitar e iniciar servicio
    msg_process "Iniciando DHCP..."
    sudo systemctl enable dhcpd &> /dev/null
    sudo systemctl restart dhcpd
    
    # Verificar estado
    sleep 1
    if systemctl is-active --quiet dhcpd; then
        echo ""
        msg_success "Servidor DHCP configurado y activo"
        echo ""
        return 0
    else
        echo ""
        msg_error "El servicio no pudo iniciarse"
        echo ""
        msg_alert "Logs del servicio:"
        echo ""
        sudo journalctl -u dhcpd -n 20 --no-pager
        return 1
    fi
}

# Monitorear servidor DHCP
monitorear_dhcp() {
    separator
    echo ""
    echo -e "${WHITE}--- ESTADO DE DHCP ---${NC}"
    echo ""
    
    # Estado del servicio
    echo ""
    echo -e "${WHITE}Estado del servicio:${NC}"
    echo ""
    if systemctl is-active --quiet dhcpd; then
        echo -e "  Estado: ${GREEN}ACTIVO${NC}"
        echo -e "  Uptime: $(systemctl show dhcpd --property=ActiveEnterTimestamp --value | awk '{print $2, $3}')"
    else
        echo -e "  Estado: ${RED}INACTIVO${NC}"
    fi
    
    # Mostrar configuracion actual
    echo ""
    echo -e "${WHITE}Configuracion actual:${NC}"
    
    if [ -f /etc/dhcp/dhcpd.conf ]; then
        grep -E "^subnet|^[[:space:]]*range|^[[:space:]]*option" /etc/dhcp/dhcpd.conf | grep -v "^#" | while read linea; do
            echo -e "  ${CYAN}->${NC} $linea"
        done
    fi

    echo ""
    
    # Concesiones activas
    echo ""
    echo -e "${WHITE}Concesiones activas:${NC}"
    echo ""

    if [ -f /var/lib/dhcpd/dhcpd.leases ]; then
        local lease_count=$(grep "^lease" /var/lib/dhcpd/dhcpd.leases 2>/dev/null | wc -l)
        echo -e "  ${CYAN}Total de concesiones:${NC} ${GREEN}$lease_count${NC}"
        echo ""
        
        if [ $lease_count -gt 0 ]; then
            sudo grep -E "lease|client-hostname|ends" /var/lib/dhcpd/dhcpd.leases | grep -v "^#" | sed 's/^/  /'
        else
            msg_info "No hay concesiones activas"
        fi
    else
        msg_alert "No hay archivo de concesiones disponible"
    fi
    
    echo ""

    # Logs recientes
    separator
    echo ""
    echo "Logs:"
    echo ""
    sudo journalctl -u dhcpd -n 10 --no-pager | tail -n +2 | sed 's/^/  /'
    echo ""
    separator
    echo ""
}

# Menu principal
menu() {
    while true; do
        clear
        echo -e "${WHITE}═══ MENÚ PRINCIPAL ═══${NC}"
        echo ""
        echo -e "  ${GREEN}1.${NC} Configurar servidor DHCP"
        echo -e "  ${GREEN}2.${NC} Ver estado y concesiones"
        echo -e "  ${GREEN}3.${NC} Reiniciar servicio"
        echo -e "  ${GREEN}4.${NC} Salir"
        echo ""
        separator
        echo ""
        msg_input "Seleccione una opcion: " 
        read opcion

        sleep 1
        
        case $opcion in
            1)
                clear
                # Verificar/instalar antes de configurar
                if verificar_instalar_dhcp; then
                    configurar_dhcp
                fi
                ;;
            2)
                clear
                monitorear_dhcp
                ;;
            3)
                msg_process "Reiniciando servicio DHCP..."
                sudo systemctl restart dhcpd
                if [ $? -eq 0 ]; then
                    msg_success "Servicio reiniciado"
                else
                    msg_error "No se pudo reiniciar el servicio"
                fi
                ;;
            4)
                msg_info "Saliendo..."
                sleep 3
                exit 0
                ;;
            *)
                msg_error "Opcion invalida"
                ;;
        esac
        
        echo ""
        read -p "Presione ENTER para continuar..."
    done
}

# Verificacion automatica
verificar_instalar_dhcp

# Mostrar menu
menu