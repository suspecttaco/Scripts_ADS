#!/bin/bash

# Script DHCP - Fedora 

# Este script realiza lo siguiente
# - Verifica e instala dhcp de ser necesario
# - Configura servicio
# - Monitorea el servicio

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
    echo "[*] Verificando presencia de dhcp-server..."
    
    # Verificar si el paquete ya esta instalado
    if rpm -q dhcp-server &> /dev/null; then
        echo "[OK] dhcp-server ya instalado"
        return 0
    else
        echo "[*] dhcp-server no encontrado. Instalando..."
        sudo dnf install -y dhcp-server &> /dev/null
        
        if [ $? -eq 0 ]; then
            echo "[OK] Instalado correctamente"
            return 0
        else
            echo "[ERROR] Fallo en la instalacion"
            return 1
        fi
    fi
}

# Reutilizado de Script de diagnostico
# Listar interfaces disponibles
listar_interfaces() {
    echo ""
    echo "Interfaces de red disponibles:"
    ip -o link show | awk -F': ' '{print "  - " $2}' | grep -v "lo"
    echo ""
}

# Configurar servidor DHCP
configurar_dhcp() {
    echo ""
    echo " CONFIGURACION DE DHCP "
    echo ""
    
    # Solicitar nombre del scope
    read -p "Nombre del ambito (scope): " SCOPE_NAME
    
    # Listar interfaces disponibles
    listar_interfaces
    
    # Solicitar interfaz de red
    while true; do
        read -p "Interfaz de red a usar: " INTERFAZ
        if ip link show "$INTERFAZ" &> /dev/null; then
            break
        fi
        echo "[ERROR] La interfaz '$INTERFAZ' no existe"
    done
    
    # Solicitar ip base
    while true; do
        read -p "IP base (ej. 192.168.1.0): " RED_BASE
        if validar_ip "$RED_BASE"; then
            # Extraer los primeros 3 octetos para construir IPs
            RED_PREFIJO=$(echo $RED_BASE | cut -d. -f1-3)
            break
        fi
        echo "[ERROR] IP invalida"
    done
    
    # Solicitar mascara de subred
    while true; do
        read -p "Mascara de subred [255.255.255.0]: " MASCARA
        MASCARA=${MASCARA:-255.255.255.0}
        if validar_ip "$MASCARA"; then
            break
        fi
        echo "[ERROR] Mascara invalida"
    done
    
    # IP de inicio con validacion
    while true; do
        read -p "IP de inicio [${RED_PREFIJO}.50]: " IP_INICIO
        IP_INICIO=${IP_INICIO:-${RED_PREFIJO}.50}
        if validar_ip "$IP_INICIO"; then
            break
        fi
        echo "[ERROR] IP invalida"
    done
    
    # IP final con validacion
    while true; do
        read -p "IP final [${RED_PREFIJO}.150]: " IP_FIN
        IP_FIN=${IP_FIN:-${RED_PREFIJO}.150}
        if validar_ip "$IP_FIN"; then
            break
        fi
        echo "[ERROR] IP invalida"
    done
    
    # Gateway con validacion
    while true; do
        read -p "Gateway [${RED_PREFIJO}.1]: " GATEWAY
        GATEWAY=${GATEWAY:-${RED_PREFIJO}.1}
        if validar_ip "$GATEWAY"; then
            break
        fi
        echo "[ERROR] IP invalida"
    done
    
    # DNS con validacion
    while true; do
        read -p "Servidor DNS [${RED_PREFIJO}.10]: " DNS_SERVER
        DNS_SERVER=${DNS_SERVER:-${RED_PREFIJO}.10}
        if validar_ip "$DNS_SERVER"; then
            break
        fi
        echo "[ERROR] IP invalida"
    done
    
    # Lease time con validacion
    while true; do
        read -p "Tiempo de concesion en segundos [86400]: " LEASE_TIME
        LEASE_TIME=${LEASE_TIME:-86400}
        
        if [[ "$LEASE_TIME" =~ ^[0-9]+$ ]]; then
            break
        fi
        echo "[ERROR] Debe ser un numero entero"
    done
    
    # Generar archivo de configuracion
    echo "[*] Generando archivo de configuracion..."
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
    
    # Validar configuracion
    echo "[*] Validando configuracion..."
    sudo dhcpd -t -cf /etc/dhcp/dhcpd.conf
    
    if [ $? -ne 0 ]; then
        echo "[ERROR] Error en la configuracion"
        return 1
    fi
    
    # Configurar interfaz de escucha
    echo "[*] Configurando interfaz de red..."
    echo "DHCPDARGS=\"$INTERFAZ\"" | sudo tee /etc/sysconfig/dhcpd > /dev/null
    
    # Configurar firewall
    echo "[*] Configurando firewall..."
    
    # Verificar que firewalld este activo
    if ! systemctl is-active --quiet firewalld; then
        echo "[*] Iniciando firewalld..."
        sudo systemctl start firewalld
    fi
    
    sudo firewall-cmd --permanent --zone=internal --add-service=dhcp &> /dev/null
    sudo firewall-cmd --reload &> /dev/null
    
    # Habilitar e iniciar servicio
    echo "[*] Iniciando DHCP..."
    sudo systemctl enable dhcpd &> /dev/null
    sudo systemctl restart dhcpd
    
    # Verificar estado
    if systemctl is-active --quiet dhcpd; then
        echo "[OK] Servidor DHCP configurado y activo"
        echo ""
        echo "Resumen de configuracion:"
        echo "--Scope: $SCOPE_NAME"
        echo "--Interfaz: $INTERFAZ"
        echo "--Red: $RED_BASE/$MASCARA"
        echo "--Rango: $IP_INICIO - $IP_FIN"
        echo "--Gateway: $GATEWAY"
        echo "--DNS: $DNS_SERVER"
        echo "--Lease time: $LEASE_TIME segundos"
        return 0
    else
        echo "[ERROR] El servicio no pudo iniciarse"
        echo "Logs del servicio:"
        sudo journalctl -u dhcpd -n 20 --no-pager
        return 1
    fi
}

# Monitorear servidor DHCP
monitorear_dhcp() {
    echo ""
    echo "ESTADO DE DHCP"
    echo ""
    
    # Estado del servicio
    echo "Estado del servicio:"
    if systemctl is-active --quiet dhcpd; then
        echo "  Estado: ACTIVO"
    else
        echo "  Estado: INACTIVO"
    fi
    
    # Mostrar configuracion actual
    echo ""
    echo "Configuracion actual:"
    if [ -f /etc/dhcp/dhcpd.conf ]; then
        grep -E "^subnet|^[[:space:]]*range|^[[:space:]]*option" /etc/dhcp/dhcpd.conf | grep -v "^#"
    fi
    
    # Concesiones activas
    # Concesiones activas (Versión filtrada)
    echo ""
    echo "Concesiones activas:"
    if [ -f /var/lib/dhcpd/dhcpd.leases ]; then
        sudo grep -E "lease|client-hostname|ends" /var/lib/dhcpd/dhcpd.leases | grep -v "^#"
    else
        echo "  No hay archivo de concesiones"
    fi
    
    # Logs recientes
    echo ""
    echo "Logs recientes:"
    sudo journalctl -u dhcpd -n 10 --no-pager
}

# Menu principal
menu() {
    while true; do
        clear
        echo "Gestion de DHCP"
        echo ""
        echo "1. Configurar servidor"
        echo "2. Ver estado y concesiones"
        echo "3. Reiniciar servicio"
        echo "4. Salir"
        echo ""
        read -p "Seleccione una opcion: " opcion
        
        case $opcion in
            1)
                # Verificar/instalar antes de configurar
                if verificar_instalar_dhcp; then
                    configurar_dhcp
                fi
                ;;
            2)
                monitorear_dhcp
                ;;
            3)
                echo "[*] Reiniciando servicio DHCP..."
                sudo systemctl restart dhcpd
                if [ $? -eq 0 ]; then
                    echo "[OK] Servicio reiniciado"
                else
                    echo "[ERROR] No se pudo reiniciar el servicio"
                fi
                ;;
            4)
                echo "Saliendo..."
                exit 0
                ;;
            *)
                echo "[ERROR] Opcion invalida"
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