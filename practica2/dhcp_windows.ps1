# Script DHCP - Windows Server


# Validar formato IPv4
function Test-IPv4Address {
    param([string]$IP)
    
    # Verificar formato basico
    $pattern = '^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    if ($IP -match $pattern) {
        # Verificar que cada octeto sea <= 255
        $octets = $IP.Split('.')
        foreach ($octet in $octets) {
            if ([int]$octet -gt 255) {
                return $false
            }
        }
        return $true
    }
    return $false
}

# Solicitar IP con validacion
function Get-ValidatedIP {
    param(
        [string]$Prompt,
        [string]$Default = ""
    )
    
    do {
        # Mostrar prompt con valor default si existe
        if ($Default) {
            $input = Read-Host "$Prompt [$Default]"
            if ([string]::IsNullOrWhiteSpace($input)) {
                $input = $Default
            }
        } else {
            $input = Read-Host $Prompt
        }
        
        # Validar formato
        if (Test-IPv4Address $input) {
            return $input
        }
        Write-Host "[ERROR] IP invalida"
    } while ($true)
}

# Verificar e instalar rol DHCP 
function Verify-InstallDHCPRole {
    Write-Host "[*] Verificando rol DHCP..."
    
    # Verificar si el rol ya esta instalado
    $dhcpFeature = Get-WindowsFeature -Name DHCP
    
    if ($dhcpFeature.Installed) {
        Write-Host "[OK] Rol DHCP ya esta instalado"
        return $true
    } else {
        Write-Host "[*] Rol DHCP no encontrado. Instalando..."
        
        try {
            # Instalar rol con herramientas de administracion
            Install-WindowsFeature -Name DHCP -IncludeManagementTools -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
            
            Write-Host "[OK] Instalacion completada"
            
            # Configuracion post-instalacion
            Add-DhcpServerSecurityGroup -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null
            Restart-Service dhcpserver -WarningAction SilentlyContinue | Out-Null
            
            return $true
        } catch {
            Write-Host "[ERROR] Fallo en instalacion: $_"
            return $false
        }
    }
}

# Funcion: Configurar servidor DHCP
function Configure-DHCPServer {
    Write-Host ""
    Write-Host "CONFIGURACION DE DHCP"
    Write-Host ""
    
    # Solicitar nombre del scope
    $scopeName = Read-Host "Nombre del ambito (scope)"
    
    # Solicitar red base
    do {
        $redBase = Read-Host "IP base (ej. 192.168.1.0)"
    } while (-not (Test-IPv4Address $redBase))
    
    # Extraer prefijo (primeros 3 octetos)
    $redPrefijo = ($redBase -split '\.')[0..2] -join '.'
    
    # Solicitar mascara de subred
    $mascara = Get-ValidatedIP "Mascara de subred" "255.255.255.0"
    
    # Solicitar parametros
    $ipInicio = Get-ValidatedIP "IP de inicio" "${redPrefijo}.50"
    $ipFin = Get-ValidatedIP "IP final" "${redPrefijo}.150"
    $gateway = Get-ValidatedIP "Gateway" "${redPrefijo}.1"
    $dnsServer = Get-ValidatedIP "Servidor DNS" "${redPrefijo}.10"
    
    # Lease time con validacion
    do {
        $leaseInput = Read-Host "Tiempo de concesion en dias [1]"
        if ([string]::IsNullOrWhiteSpace($leaseInput)) {
            $leaseDays = 1
            break
        }
        
        if ($leaseInput -match '^\d+$') {
            $leaseDays = [int]$leaseInput
            break
        }
        Write-Host "[ERROR] Debe ser un numero entero"
    } while ($true)
    
    # Verificar si ya existe un scope en esta red
    $existingScope = Get-DhcpServerv4Scope -ScopeId $redBase -ErrorAction SilentlyContinue
    
    if ($existingScope) {
        Write-Host "[ADVERTENCIA] Ya existe un scope en $redBase"
        $respuesta = Read-Host "¿Eliminar y reconfigurar? (S/n)"
        
        if ($respuesta -match '^[Ss]?$') {
            Remove-DhcpServerv4Scope -ScopeId $redBase -Force
        } else {
            Write-Host "Operacion cancelada"
            return
        }
    }
    
    # Crear scope
    try {
        Write-Host "[*] Creando scope DHCP..."
        
        Add-DhcpServerv4Scope `
            -Name $scopeName `
            -StartRange $ipInicio `
            -EndRange $ipFin `
            -SubnetMask $mascara `
            -LeaseDuration (New-TimeSpan -Days $leaseDays) `
            -State Active `
            -ErrorAction Stop
        
        Write-Host "[OK] Scope creado"
        
        # Configurar opciones de red
        Write-Host "[*] Configurando opciones de red..."
        
        Set-DhcpServerv4OptionValue `
            -ScopeId $redBase `
            -Router $gateway `
            -DnsServer $dnsServer `
            -ErrorAction Stop
        
        Write-Host "[OK] Opciones configuradas"
        
        # Configurar regla de firewall
        Write-Host "[*] Configurando firewall..."
        
        $firewallRule = Get-NetFirewallRule -DisplayName "DHCP Server (UDP-In)" -ErrorAction SilentlyContinue
        
        if (-not $firewallRule) {
            New-NetFirewallRule `
                -DisplayName "DHCP Server (UDP-In)" `
                -Direction Inbound `
                -Protocol UDP `
                -LocalPort 67 `
                -Action Allow `
                -ErrorAction Stop | Out-Null
            
            Write-Host "[OK] Regla de firewall creada"
        } else {
            Write-Host "[OK] Regla de firewall ya existe"
        }
        
        Write-Host ""
        Write-Host "[OK] Servidor DHCP configurado correctamente"
        Write-Host ""
        Write-Host "Resumen de configuracion:"
        Write-Host "  Scope: $scopeName"
        Write-Host "  Red: $redBase/$mascara"
        Write-Host "  Rango: $ipInicio - $ipFin"
        Write-Host "  Gateway: $gateway"
        Write-Host "  DNS: $dnsServer"
        Write-Host "  Lease time: $leaseDays dia(s)"
        
    } catch {
        Write-Host "[ERROR] Fallo en configuracion: $_"
    }
}

# Funcion: Monitorear servidor DHCP
function Monitor-DHCPServer {
    Write-Host ""
    Write-Host "ESTADO DE DHCP"
    Write-Host ""
    
    # Estado del servicio
    Write-Host "Estado del servicio:"
    $service = Get-Service dhcpserver
    
    if ($service.Status -eq 'Running') {
        Write-Host "  Estado: ACTIVO"
    } else {
        Write-Host "  Estado: INACTIVO"
    }
    
    # Configuracion de scopes
    Write-Host ""
    Write-Host "Scopes configurados:"
    $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
    if ($scopes) {
        $scopes | Format-Table -AutoSize
        
        # Mostrar opciones de cada scope
        foreach ($scope in $scopes) {
            Write-Host ""
            Write-Host "Opciones del scope $($scope.ScopeId):"
            Get-DhcpServerv4OptionValue -ScopeId $scope.ScopeId -ErrorAction SilentlyContinue |
                Select-Object OptionId, Name, Value | Format-Table -AutoSize
        }
    } else {
        Write-Host "  No hay scopes configurados"
    }
    
    # Concesiones activas
    Write-Host ""
    Write-Host "Concesiones activas:"
    
    if ($scopes) {
        foreach ($scope in $scopes) {
            $leases = Get-DhcpServerv4Lease -ScopeId $scope.ScopeId -ErrorAction SilentlyContinue
            
            if ($leases) {
                Write-Host ""
                Write-Host "Scope: $($scope.ScopeId)"
                $leases | Select-Object IPAddress, ClientId, HostName, LeaseExpiryTime | Format-Table -AutoSize
            }
        }
    } else {
        Write-Host "  No hay concesiones activas"
    }
    
    # Estadisticas
    Write-Host ""
    Write-Host "Estadisticas:"
    
    if ($scopes) {
        foreach ($scope in $scopes) {
            $stats = Get-DhcpServerv4ScopeStatistics -ScopeId $scope.ScopeId -ErrorAction SilentlyContinue
            
            if ($stats) {
                Write-Host ""
                Write-Host "Scope: $($scope.ScopeId)"
                Write-Host "  IPs en uso: $($stats.AddressesInUse)"
                Write-Host "  IPs disponibles: $($stats.AddressesFree)"
                Write-Host "  Porcentaje de uso: $($stats.PercentageInUse)%"
            }
        }
    }
}

# Menu principal
function Show-Menu {
    while ($true) {
        Clear-Host
        Write-Host ""
        Write-Host "Gestion de DHCP - Windows"
        Write-Host 
        Write-Host "1. Configurar DHCP"
        Write-Host "2. Ver estado y concesiones"
        Write-Host "3. Reiniciar servicio"
        Write-Host "4. Salir"
        Write-Host ""
        
        $opcion = Read-Host "Seleccione una opcion"
        
        switch ($opcion) {
            1 {
                # Verificar/instalar antes de configurar
                if (Verify-InstallDHCPRole) {
                    Configure-DHCPServer
                }
            }
            2 {
                Monitor-DHCPServer
            }
            3 {
                Write-Host "[*] Reiniciando servicio DHCP..."
                try {
                    Restart-Service dhcpserver -ErrorAction Stop
                    Write-Host "[OK] Servicio reiniciado"
                } catch {
                    Write-Host "[ERROR] No se pudo reiniciar: $_"
                }
            }
            4 {
                Write-Host "Saliendo..."
                exit 0
            }
            default {
                Write-Host "[ERROR] Opcion invalida"
            }
        }
        
        Write-Host ""
        Read-Host "Presione ENTER para continuar"
    }
}

# Punto de entrada
# Verificar que se ejecute como Administrador
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "[ERROR] Este script requiere privilegios de administrador"
    pause
    exit 1
}

# Verificacion automatica al inicio
Verify-InstallDHCPRole

# Mostrar menu
Show-Menu