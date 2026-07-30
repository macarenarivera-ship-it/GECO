# refresh_data.ps1  --  Actualiza radar_cartera_pp.html con datos de HubSpot
# Uso: clic derecho -> "Ejecutar con PowerShell"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $SCRIPT_DIR "config.ps1")
$HTML  = Join-Path $SCRIPT_DIR "radar_cartera_pp.html"
$HOY   = (Get-Date).ToString("yyyy-MM-dd")
$HDR   = @{ Authorization = "Bearer $TOKEN"; "Content-Type" = "application/json" }

# ---------------------------------------------------------------
# Mapa de ejecutivos PP (ID HubSpot -> Nombre)
# Si cambia el equipo, actualiza este mapa manualmente.
# ---------------------------------------------------------------
$OWNERS = @{
    "343593960"  = "Luis Gonzalez"
    "1448104430" = "Luis Gonzalez"
    "82186002"  = "Kevin Galaz"
    "90906274"  = "Cesar Angel"
    "90906246"  = "Rolf Hilliger"
    "273244548" = "Macarena Rivera"
    "81633773"  = "Sofia Rex Gonzalez"
    "92609743"  = "Valentin Monroy"
}
$PP_IDS = @($OWNERS.Keys)

Write-Host ""
Write-Host "======================================================"
Write-Host "  Radar Cartera PP -- Actualizando datos HubSpot"
Write-Host "  Fecha: $HOY"
Write-Host "======================================================"
Write-Host ""

# --- Helpers ---
function hsDias($d) {
    if (-not $d) { return $null }
    try { return [int]([DateTime]::Today - [DateTime]::Parse($d.Substring(0,10))).TotalDays }
    catch { return $null }
}
function hsNiv($dias) {
    if ($dias -eq $null) { return "alto" }
    if ($dias -lt 30)    { return "activa" }
    if ($dias -lt 60)    { return "bajo" }
    if ($dias -lt 90)    { return "medio" }
    return "alto"
}
function hsMat($pag) {
    if (-not $pag) { return "Sin pagador" }
    return (($pag -split ";")[0]).Trim()
}
function hsLong($v) {
    if (-not $v) { return 0 }
    try { return [long][double]$v } catch { return 0 }
}

# --- Descargar empresas (Cliente + Fugado del equipo PP) ---
Write-Host "[1/3] Descargando empresas desde HubSpot (Cliente + Fugado)..."
$props = @("name","estado_pp","fecha_ultimo_operacion_pp","propietario_pp","pagadores","recent_deal_amount")
$all   = @()
$after = $null
do {
    $body = @{
        filterGroups = @(@{
            filters = @(
                @{ propertyName = "propietario_pp"; operator = "IN"; values = $PP_IDS },
                @{ propertyName = "estado_pp"; operator = "IN"; values = @("Cliente","Fugado") }
            )
        })
        properties = $props
        limit      = 100
    }
    if ($after) { $body["after"] = $after }
    try {
        $r = Invoke-RestMethod -Uri "https://api.hubapi.com/crm/v3/objects/companies/search" `
             -Method POST -Headers $HDR -Body ($body | ConvertTo-Json -Depth 10)
    } catch {
        Write-Host "ERROR al descargar empresas: $_"
        Read-Host "Presiona Enter para cerrar"
        exit 1
    }
    $all  += $r.results
    $after = if ($r.paging -and $r.paging.next) { $r.paging.next.after } else { $null }
    Write-Host "   -> $($all.Count) de $($r.total) empresas..."
} while ($after)
Write-Host "   -> Descarga completada: $($all.Count) empresas."

# --- Procesar datos ---
Write-Host "[2/3] Procesando datos..."

$carteraList = New-Object System.Collections.ArrayList
$riesgoList  = New-Object System.Collections.ArrayList
$universo    = @{}

foreach ($c in $all) {
    $p    = $c.properties
    $ep   = if ($p.estado_pp)   { [string]$p.estado_pp }   else { $null }
    $oid  = if ($p.propietario_pp) { [string]$p.propietario_pp } else { $null }
    $fuoRaw = if ($p.fecha_ultimo_operacion_pp) { [string]$p.fecha_ultimo_operacion_pp } else { $null }
    $fuo  = if ($fuoRaw -and $fuoRaw.Length -ge 10) { $fuoRaw.Substring(0,10) } else { $null }
    $dias = hsDias $fuo
    $niv  = hsNiv $dias
    $mon  = hsLong $p.recent_deal_amount
    $pag  = if ($p.pagadores) { [string]$p.pagadores } else { "" }
    $mat  = hsMat $pag
    $id   = [long]$c.id
    $nom  = if ($p.name) { [string]$p.name } else { "Sin nombre" }

    # Universo: conteo por ejecutivo
    if ($oid) {
        if (-not $universo.ContainsKey($oid)) { $universo[$oid] = @{ cliente=0; fugado=0 } }
        if ($ep -eq "Cliente") { $universo[$oid].cliente++ }
        if ($ep -eq "Fugado")  { $universo[$oid].fugado++  }
    }

    # Cartera: todos (Cliente y Fugado)
    if ($oid) {
        $item = [ordered]@{ id=$id; n=$nom; e=$oid; fuo=$fuo; monto=$mon; matriz=$mat; dias=$dias; niv=$niv; ep=$ep }
        $null = $carteraList.Add($item)
    }

    # Lista accionable:
    #   Clientes con 30+ dias sin operar (riesgo de fuga)
    #   Fugados recientes (menos de 180 dias)
    if ($ep -eq "Cliente" -and $dias -ne $null -and $dias -ge 30) {
        $item = [ordered]@{ n=$nom; e=$oid; f=$fuo; ff=$fuo; monto=$mon; pag=$pag; matriz=$mat; id=$id; fugado=$false }
        $null = $riesgoList.Add($item)
    } elseif ($ep -eq "Fugado" -and $dias -ne $null -and $dias -lt 180) {
        $item = [ordered]@{ n=$nom; e=$oid; f=$fuo; ff=$fuo; monto=$mon; pag=$pag; matriz=$mat; id=$id; fugado=$true }
        $null = $riesgoList.Add($item)
    }
}

$carteraArr = @($carteraList | Sort-Object { -[long]$_.monto })
$riesgoArr  = @($riesgoList  | Sort-Object { -[long]$_.monto })

Write-Host "   -> Cartera: $($carteraArr.Count) empresas"
Write-Host "   -> Lista accionable: $($riesgoArr.Count) empresas"

# --- Actualizar HTML ---
Write-Host "[3/3] Actualizando el archivo HTML..."

$DATA = [ordered]@{
    snapshot = $HOY
    owners   = $OWNERS
    universo = $universo
    riesgo   = $riesgoArr
    cartera  = $carteraArr
}
$newJson = ($DATA | ConvertTo-Json -Depth 10 -Compress).Replace("</", "<\/")

$src = [System.IO.File]::ReadAllText($HTML, [System.Text.Encoding]::UTF8)

$marker = "const DATA = {"
$idx    = $src.IndexOf($marker)
if ($idx -lt 0) {
    Write-Host "ERROR: No se encontro 'const DATA' en el HTML."
    Read-Host "Presiona Enter para cerrar"
    exit 1
}

$braceStart = $src.IndexOf("{", $idx)
$depth = 0
$pos   = $braceStart
while ($pos -lt $src.Length) {
    $ch = $src[$pos]
    if    ($ch -eq "{") { $depth++ }
    elseif ($ch -eq "}") {
        $depth--
        if ($depth -eq 0) { break }
    }
    $pos++
}
$endPos = $pos + 1
if ($endPos -lt $src.Length -and $src[$endPos] -eq ";") { $endPos++ }

$out = $src.Substring(0, $idx) + "const DATA = " + $newJson + ";" + $src.Substring($endPos)
[System.IO.File]::WriteAllText($HTML, $out, [System.Text.Encoding]::UTF8)

Write-Host ""
Write-Host "======================================================"
Write-Host "  LISTO! Snapshot: $HOY"
Write-Host "  Cartera:          $($carteraArr.Count) empresas (Cliente + Fugado)"
Write-Host "  Lista accionable: $($riesgoArr.Count) empresas"
Write-Host "======================================================"
Write-Host ""
Write-Host "Abriendo GECO en el navegador..."
Write-Host ""
Start-Process $HTML
Read-Host "Presiona Enter para cerrar"
