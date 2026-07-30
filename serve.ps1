$port = 8080
$root = $PSScriptRoot

# IP de esta maquina en la red local
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch '^(127\.|169\.)' } | Select-Object -First 1).IPAddress

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://+:$port/")
try {
    $listener.Start()
} catch {
    Write-Host ""
    Write-Host "ERROR: No se pudo iniciar el servidor en la red."
    Write-Host "Ejecuta primero setup_red.ps1 como Administrador."
    Write-Host ""
    Read-Host "Presiona Enter para cerrar"
    exit 1
}

Write-Host ""
Write-Host "======================================================"
Write-Host "  GECO - Servidor activo"
Write-Host "  Tu PC:    http://localhost:$port"
if ($ip) {
    Write-Host "  Red:      http://${ip}:$port   <-- comparte este link"
}
Write-Host ""
Write-Host "  Mantener esta ventana abierta mientras se usa GECO."
Write-Host "  Ctrl+C para detener el servidor."
Write-Host "======================================================"
Write-Host ""

# Mapa de tipos MIME
$mime = @{
    '.html' = 'text/html; charset=utf-8'
    '.js'   = 'application/javascript'
    '.css'  = 'text/css'
    '.json' = 'application/json'
    '.png'  = 'image/png'
    '.ico'  = 'image/x-icon'
}

while ($listener.IsListening) {
    $ctx  = $listener.GetContext()
    $req  = $ctx.Request
    $res  = $ctx.Response
    $path = $req.Url.LocalPath.TrimStart('/')
    if ($path -eq '' -or $path -eq '/') { $path = 'radar_cartera_pp.html' }
    $file = Join-Path $root $path

    if (Test-Path $file -PathType Leaf) {
        $bytes = [System.IO.File]::ReadAllBytes($file)
        $ext   = [System.IO.Path]::GetExtension($file).ToLower()
        $res.ContentType     = if ($mime[$ext]) { $mime[$ext] } else { 'application/octet-stream' }
        $res.ContentLength64 = $bytes.Length
        $res.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
        $res.StatusCode = 404
    }
    $res.OutputStream.Close()
}
