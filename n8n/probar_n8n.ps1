# Probador del flujo n8n "SIG Minimarket - Alerta de reposicion por correo".
# Hace 3 pruebas contra el webhook, sin necesidad de abrir la app:
#   1) Sin clave            -> n8n debe responder 403 (rechaza a extranos)
#   2) Clave + datos malos  -> n8n debe responder 400 (no manda correo)
#   3) Clave + alerta buena -> n8n debe responder 200 (llega un correo [PRUEBA])
# La clave se escribe oculta y no se guarda en ningun archivo.

param(
  [string]$Url = $env:SIG_N8N_WEBHOOK_URL
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Net.Http

$porDefecto = 'https://sistemas2026usm.app.n8n.cloud/webhook/alerta-reposicion'
if ([string]::IsNullOrWhiteSpace($Url)) { $Url = $porDefecto }

Write-Host ''
Write-Host '=== Probador del flujo n8n (aviso por correo) ===' -ForegroundColor Cyan
Write-Host "Direccion: $Url"
Write-Host ''

$clave = $env:SIG_N8N_TOKEN
if ([string]::IsNullOrWhiteSpace($clave)) {
  $segura = Read-Host 'Escribe la clave secreta (no se vera en pantalla) y pulsa Enter' -AsSecureString
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($segura)
  try { $clave = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
} else {
  Write-Host 'Usando la clave guardada en Windows (SIG_N8N_TOKEN).'
}
if ([string]::IsNullOrWhiteSpace($clave)) {
  Write-Host 'No escribiste ninguna clave. Fin.' -ForegroundColor Red
  exit 1
}

$cliente = New-Object System.Net.Http.HttpClient
$cliente.Timeout = [TimeSpan]::FromSeconds(30)

function Enviar([string]$json, [bool]$conClave) {
  $msg = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, $Url)
  if ($conClave) { [void]$msg.Headers.TryAddWithoutValidation('X-API-Key', $clave) }
  $msg.Content = New-Object System.Net.Http.StringContent($json, [Text.Encoding]::UTF8, 'application/json')
  try {
    $r = $cliente.SendAsync($msg).GetAwaiter().GetResult()
    $texto = $r.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    return @{ codigo = [int]$r.StatusCode; texto = $texto }
  } catch {
    return @{ codigo = 0; texto = $_.Exception.Message }
  }
}

$ahora = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss") + '-03:00'
$alerta = @"
{"evento":"alerta_reposicion","version":1,"prueba":true,"alerta_id":0,"origen":"REVISION",
 "detectada":"$ahora",
 "producto":{"id":0,"codigo_interno":"PRUEBA","codigo_barras":null,"nombre":"Prueba manual del probador n8n"},
 "stock_actual":0,"punto_reposicion":0,"estado_alerta":"BAJO_UMBRAL","metodo_calculo":"MANUAL_RESPALDO",
 "unidades_para_salir_de_alerta":1,"proveedor":null,"unidades_en_pedidos_pendientes":0}
"@

$pruebas = @(
  @{ n = 1; nombre = 'Sin clave (n8n debe rechazar)';              json = $alerta; clave = $false; espera = 403 },
  @{ n = 2; nombre = 'Con clave pero datos incompletos';           json = '{"evento":"alerta_reposicion"}'; clave = $true; espera = 400 },
  @{ n = 3; nombre = 'Con clave y alerta completa (manda correo)'; json = $alerta; clave = $true; espera = 200 }
)

$ok = 0
foreach ($p in $pruebas) {
  $r = Enviar $p.json $p.clave
  $bien = ($r.codigo -eq $p.espera)
  if ($bien) { $ok++; $marca = 'OK   '; $color = 'Green' } else { $marca = 'FALLA'; $color = 'Red' }
  Write-Host ("[{0}] Prueba {1}: {2}" -f $marca, $p.n, $p.nombre) -ForegroundColor $color
  Write-Host ("        esperaba {0}, n8n respondio {1}: {2}" -f $p.espera, $r.codigo, $r.texto)
}

Write-Host ''
if ($ok -eq $pruebas.Count) {
  Write-Host "Resultado: $ok de $($pruebas.Count) pruebas OK. Revisa el correo: debe llegar uno que empieza con [PRUEBA]." -ForegroundColor Green
  exit 0
}
Write-Host "Resultado: $ok de $($pruebas.Count) pruebas OK." -ForegroundColor Yellow
Write-Host 'Si la prueba 1 dio 404: el flujo no esta publicado (Publish) o la direccion esta mal.'
Write-Host 'Si la prueba 2 o 3 dio 403: la clave no es la misma que la de n8n.'
Write-Host 'Si la prueba 3 dio 502: n8n recibio la alerta pero Gmail no pudo enviar (revisar credencial Gmail).'
Write-Host 'Si dio 0: no hay Internet o la direccion no existe.'
exit 1
