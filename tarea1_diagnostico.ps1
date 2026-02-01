# Mostrar Hostname, IP y Espacio en el disco
Clear-Host

$hostname = $env:COMPUTERNAME

Write-Host "Host: $hostname"
Write-Host ""
Write-Host "IP's : "
Get-NetIPAddress -AddressFamily IPv4 | Select-Object InterfaceAlias, IPAddress
Write-Host ""
Write-Host "Espacio en el disco:"
Get-Volume
