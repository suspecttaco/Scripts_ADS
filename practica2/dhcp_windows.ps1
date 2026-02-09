# Script DHCP - Windows Server

# Funcion: Separador
function Show-Separator {
    Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
}

# Exito
function Write-Success {
    param([string]$Message)
    Write-Host "[ " -NoNewline
    Write-Host "EXITO" -ForegroundColor Green -NoNewline
    Write-Host " ] " -NoNewline
    Write-Host $Message
}

# Error
function Write-Error-Custom {
    param([string]$Message)
    Write-Host "[ " -NoNewline
    Write-Host "ERROR" -ForegroundColor Red -NoNewline
    Write-Host " ] " -NoNewline
    Write-Host $Message
}

# Info
function Write-Info {
    param([string]$Message)
    Write-Host "[ " -NoNewline
    Write-Host "INFO" -ForegroundColor Blue -NoNewline
    Write-Host " ]  " -NoNewline
    Write-Host $Message
}

# Alert
function Write-Warning-Custom {
    param([string]$Message)
    Write-Host "[ " -NoNewline
    Write-Host "ALERT" -ForegroundColor Yellow -NoNewline
    Write-Host " ] " -NoNewline
    Write-Host $Message
}

# Process
function Write-Process {
    param([string]$Message)
    Write-Host "[  " -NoNewline
    Write-Host "---" -ForegroundColor Magenta -NoNewline
    Write-Host "  ] " -NoNewline
    Write-Host $Message
}

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
        Write-Host "-> " -ForegroundColor Cyan -NoNewline
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
            Write-Success "$Prompt -> $input"
            return $input
        }
        Write-Error-Custom "IP invalida"
    } while ($true)
}

# Verificar e instalar rol DHCP 
function Verify-InstallDHCPRole {
    Write-Process "Verificando rol DHCP..."
    
    # Verificar si el rol ya esta instalado
    $dhcpFeature = Get-WindowsFeature -Name DHCP
    
    if ($dhcpFeature.Installed) {
        Write-Host "[OK] Rol DHCP ya esta instalado"
        return $true
    } else {
        Write-Warning-Custom "Rol DHCP no encontrado. Instalando..."
        Write-Process "Instalando rol DHCP (esto puede tardar unos momentos)..."
        
        try {
            # Instalar rol con herramientas de administracion
            Install-WindowsFeature -Name DHCP -IncludeManagementTools -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
            
            Write-Success "Instalacion completada"
            
            # Configuracion post-instalacion
            Add-DhcpServerSecurityGroup -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null
            Restart-Service dhcpserver -WarningAction SilentlyContinue | Out-Null
            
            return $true
        } catch {
            Write-Error-Custom "Fallo en instalacion: $_"
            return $false
        }
    }
}

# Funcion: Configurar servidor DHCP
function Configure-DHCPServer {
    Write-Host ""
    Write-Host "--- CONFIGURACION DE DHCP ---" -ForegroundColor White
    Write-Host ""
    
    # Solicitar nombre del scope
    Write-Host "-> " -ForegroundColor Cyan -NoNewline
    $scopeName = Read-Host "Nombre del ambito (scope): "

    Write-Host ""
    Show-Separator
    Write-Host "Configuracion de Red" -ForegroundColor White
    Write-Host ""
    
    # Solicitar red base
    do {
        Write-Host "-> " -ForegroundColor Cyan -NoNewline
        $redBase = Read-Host "Segmento (ej. 192.168.1.0): "
    } while (-not (Test-IPv4Address $redBase))

    Write-Success "Segmento: $redBase"
    
    # Extraer prefijo (primeros 3 octetos)
    $redPrefijo = ($redBase -split '\.')[0..2] -join '.'
    
    # Solicitar mascara de subred
    $mascara = Get-ValidatedIP "Mascara de subred" "255.255.255.0"

    Write-Host ""
    Show-Separator
    Write-Host "Rango de IPs" -ForegroundColor White
    Write-Host ""
    
    # Solicitar parametros
    $ipInicio = Get-ValidatedIP "IP de inicio" "${redPrefijo}.50"
    $ipFin = Get-ValidatedIP "IP final" "${redPrefijo}.150"

    Write-Host ""
    Show-Separator
    Write-Host "Parametros de Red" -ForegroundColor White
    Write-Host ""

    $gateway = Get-ValidatedIP "Gateway" "${redPrefijo}.1"
    $dnsServer = Get-ValidatedIP "Servidor DNS" "${redPrefijo}.10"
    
    # Lease time con validacion
    do {
        Write-Host "-> " -ForegroundColor Cyan -NoNewline
        $leaseInput = Read-Host "Tiempo de concesion en dias [1]"
        if ([string]::IsNullOrWhiteSpace($leaseInput)) {
            $leaseDays = 1
            break
        }
        
        if ($leaseInput -match '^\d+$') {
            $leaseDays = [int]$leaseInput
            break
        }
        Write-Error-Custom "Debe ser un numero entero"
    } while ($true)

    Write-Success "Lease time: $leaseDays dia(s)"

    Write-Host ""
    Show-Separator
    Write-Host "Resumen de Configuracion" -ForegroundColor White
    Write-Host ""
    Write-Host "  Scope:       " -ForegroundColor Cyan -NoNewline
    Write-Host $scopeName
    Write-Host "  Segmento:    " -ForegroundColor Cyan -NoNewline
    Write-Host "$redBase/$mascara"
    Write-Host "  Rango:       " -ForegroundColor Cyan -NoNewline
    Write-Host "$ipInicio -> $ipFin"
    Write-Host "  Gateway:     " -ForegroundColor Cyan -NoNewline
    Write-Host $gateway
    Write-Host "  DNS:         " -ForegroundColor Cyan -NoNewline
    Write-Host $dnsServer
    Write-Host "  Lease:       " -ForegroundColor Cyan -NoNewline
    Write-Host "$leaseDays dia(s)"
    Write-Host ""
    Show-Separator
    Write-Host ""

    $respuesta = Read-Host "Desea aplicar esta configuracion? (S/n): "
    
    if ($respuesta -notmatch '^[Ss]?$') {
        Write-Warning-Custom "Configuracion cancelada por el usuario"
        return
    }
    
    # Verificar si ya existe un scope en esta red
    $existingScope = Get-DhcpServerv4Scope -ScopeId $redBase -ErrorAction SilentlyContinue
    
    if ($existingScope) {
        Write-Host ""
        Write-Warning-Custom "Ya existe un scope en $redBase"
        $respuesta = Read-Host "Eliminar y reconfigurar? (S/n)"
        
        if ($respuesta -match '^[Ss]?$') {
            Remove-DhcpServerv4Scope -ScopeId $redBase -Force
            Write-Success "Scope anterior eliminado"
        } else {
            Write-Warning-Custom "Operacion cancelada"
            return
        }
    }
    
    # Crear scope
    try {
        Write-Host ""
        Write-Process "Creando scope DHCP..."
        
        Add-DhcpServerv4Scope `
            -Name $scopeName `
            -StartRange $ipInicio `
            -EndRange $ipFin `
            -SubnetMask $mascara `
            -LeaseDuration (New-TimeSpan -Days $leaseDays) `
            -State Active `
            -ErrorAction Stop
        
        Write-Success "Scope creado"
        
        # Configurar opciones de red
        Write-Process "Configurando opciones de red..."
        
        Set-DhcpServerv4OptionValue `
            -ScopeId $redBase `
            -Router $gateway `
            -DnsServer $dnsServer `
            -ErrorAction Stop
        
        Write-Success "Opciones de red configuradas"
        
        # Configurar regla de firewall
        Write-Process "Configurando firewall..."
        
        $firewallRule = Get-NetFirewallRule -DisplayName "DHCP Server (UDP-In)" -ErrorAction SilentlyContinue
        
        if (-not $firewallRule) {
            New-NetFirewallRule `
                -DisplayName "DHCP Server (UDP-In)" `
                -Direction Inbound `
                -Protocol UDP `
                -LocalPort 67 `
                -Action Allow `
                -ErrorAction Stop | Out-Null
            
            Write-Success "Regla de firewall creada"
        } else {
            Write-Success "Regla de firewall ya existe"
        }
        
        Write-Host ""
        Write-Success "Servidor DHCP configurado correctamente"
        Write-Host ""
        
    } catch {
        Write-Error-Custom "Fallo en configuracion: $_"
    }
}

# Funcion: Monitorear servidor DHCP
function Monitor-DHCPServer {
    Write-Host ""
    Write-Host "--- ESTADO DE DHCP ---" -ForegroundColor White
    Write-Host ""
    
    # Estado del servicio
    Show-Separator
    Write-Host "Estado del servicio" -ForegroundColor White
    Write-Host ""
    $service = Get-Service dhcpserver
    
    if ($service.Status -eq 'Running') {
        Write-Host "  Estado: " -NoNewline
        Write-Host "ACTIVO" -ForegroundColor Green
    } else {
        Write-Host "  Estado: " -NoNewline
        Write-Host "INACTIVO" -ForegroundColor Red
    }
    
    # Configuracion de scopes
    Write-Host ""
    Show-Separator
    Write-Host "Scopes configurados:" -ForegroundColor White
    Write-Host ""

    $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
    if ($scopes) {
        $scopes | Format-Table Name, ScopeId, StartRange, EndRange, State -AutoSize
        
        # Mostrar opciones de cada scope
        foreach ($scope in $scopes) {
            Write-Host "  Opciones del scope $($scope.ScopeId):" -ForegroundColor Cyan
            Get-DhcpServerv4OptionValue -ScopeId $scope.ScopeId -ErrorAction SilentlyContinue |
                Select-Object OptionId, Name, Value | 
                Format-Table -AutoSize | Out-String | 
                ForEach-Object { $_.Split("`n") | ForEach-Object { if ($_.Trim()) { Write-Host "    $_" } } }
        }
    } else {
        Write-Info "No hay scopes configurados"
    }
    
    # Concesiones activas
    Write-Host ""
    Show-Separator
    Write-Host "Concesiones activas" -ForegroundColor White
    Write-Host ""
    
    if ($scopes) {
        $totalLeases = 0
        foreach ($scope in $scopes) {
            $leases = Get-DhcpServerv4Lease -ScopeId $scope.ScopeId -ErrorAction SilentlyContinue
            
            if ($leases) {
                $totalLeases += ($leases | Measure-Object).Count
                Write-Host "  Scope: $($scope.ScopeId)" -ForegroundColor Cyan
                $leases | Select-Object IPAddress, ClientId, HostName, LeaseExpiryTime | 
                    Format-Table -AutoSize | Out-String |
                    ForEach-Object { $_.Split("`n") | ForEach-Object { if ($_.Trim()) { Write-Host "    $_" } } }
            }
        }
        
        if ($totalLeases -eq 0) {
            Write-Info "No hay concesiones activas"
        } else {
            Write-Host "  Total de concesiones: " -ForegroundColor Cyan -NoNewline
            Write-Host $totalLeases -ForegroundColor Green
        }
    }
    
    # Estadisticas
    Write-Host ""
    Show-Separator
    Write-Host "Estadisticas"
    Write-Host ""
    
    if ($scopes) {
        foreach ($scope in $scopes) {
            $stats = Get-DhcpServerv4ScopeStatistics -ScopeId $scope.ScopeId -ErrorAction SilentlyContinue
            
            if ($stats) {
                Write-Host "  Scope: $($scope.ScopeId)" -ForegroundColor Cyan
                Write-Host "    IPs en uso:        " -NoNewline
                Write-Host $stats.AddressesInUse -ForegroundColor Green
                Write-Host "    IPs disponibles:   " -NoNewline
                Write-Host $stats.AddressesFree -ForegroundColor Yellow
                Write-Host "    Porcentaje de uso: " -NoNewline
                Write-Host "$($stats.PercentageInUse)%" -ForegroundColor Cyan
                Write-Host ""
            }
        }
    }
    
    Show-Separator
    Write-Host ""
}

# Menu principal
function Show-Menu {
    while ($true) {
        Clear-Host
        Write-Host ""
        Write-Host "--- Gestion de DHCP - Windows ---" -ForegroundColor White
        Write-Host ""
        Write-Host "  1. " -ForegroundColor Cyan -NoNewline
        Write-Host "Configurar DHCP"
        Write-Host "  2. " -ForegroundColor Cyan -NoNewline
        Write-Host "Ver estado y concesiones"
        Write-Host "  3. " -ForegroundColor Cyan -NoNewline
        Write-Host "Reiniciar servicio"
        Write-Host "  4. " -ForegroundColor Cyan -NoNewline
        Write-Host "Salir"
        Write-Host ""
        Show-Separator
        Write-Host ""
        Write-Host "-> " -ForegroundColor Cyan -NoNewline
        
        $opcion = Read-Host "Seleccione una opcion"
        
        switch ($opcion) {
            1 {
                # Verificar/instalar antes de configurar
                if (Verify-InstallDHCPRole) {
                    Write-Host ""
                    Configure-DHCPServer
                }
            }
            2 {
                Monitor-DHCPServer
            }
            3 {
                Write-Host ""
                Write-Process "Reiniciando servicio DHCP..."
                try {
                    Restart-Service dhcpserver -ErrorAction Stop
                    Write-Success "Servicio reiniciado correctamente"
                } catch {
                    Write-Error-Custom "No se pudo reiniciar: $_"
                }
            }
            4 {
                Write-Host ""
                Write-Info "Saliendo del script..."
                Write-Host ""
                exit 0
            }
            default {
                Write-Host ""
                Write-Error-Custom "Opcion invalida. Intente nuevamente."
            }
        }
        
        Write-Host ""
        Write-Host "Presione ENTER para continuar..." -ForegroundColor Yellow
        Read-Host
    }
}

# Punto de entrada
# Verificar que se ejecute como Administrador
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Clear-Host
    Write-Host ""
    Write-Error-Custom "Este script requiere privilegios de administrador"
    Write-Info "Ejecute PowerShell como Administrador"
    Write-Host ""
    pause
    exit 1
}

# Verificacion automatica al inicio
Verify-InstallDHCPRole
Write-Host ""
Write-Host "Presione ENTER para continuar al menu..." -ForegroundColor Yellow
Read-Host

# Mostrar menu
Show-Menu