# setup_red.ps1 -- Ejecutar UNA VEZ como Administrador
# Habilita GECO en la red local para que el equipo acceda desde sus PCs

$port = 8080

Write-Host ""
Write-Host "======================================================"
Write-Host "  GECO - Configuracion de red (una sola vez)"
Write-Host "======================================================"
Write-Host ""

# Registrar URL para que serve.ps1 pueda escuchar sin ser admin
$urlAcl = "http://+:$port/"
Write-Host "[1/2] Registrando permiso de URL: $urlAcl"
$result = netsh http add urlacl url=$urlAcl user=Everyone 2>&1
Write-Host "      $result"

# Abrir puerto en el firewall de Windows
Write-Host "[2/2] Abriendo puerto $port en el firewall de Windows..."
$fw = Get-NetFirewallRule -DisplayName "GECO Servidor $port" -ErrorAction SilentlyContinue
if ($fw) {
    Write-Host "      Regla ya existe, omitiendo."
} else {
    New-NetFirewallRule -DisplayName "GECO Servidor $port" -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow | Out-Null
    Write-Host "      Puerto $port habilitado."
}

# Mostrar IP de la maquina
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch '^(127\.|169\.)' } | Select-Object -First 1).IPAddress
Write-Host ""
Write-Host "======================================================"
Write-Host "  LISTO. Configuracion completada."
Write-Host "  IP de esta maquina: $ip"
Write-Host "  El equipo accede en: http://${ip}:$port"
Write-Host ""
Write-Host "  Ahora ejecuta serve.ps1 normalmente (sin admin)."
Write-Host "======================================================"
Write-Host ""
Read-Host "Presiona Enter para cerrar"
