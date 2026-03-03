# Start a local NATS server for development and integration testing.
#
# Usage:
#   .\scripts\start-nats.ps1              # Plain core NATS + JetStream
#   .\scripts\start-nats.ps1 -Auth        # Token auth (token: mytoken) on port 4223
#   .\scripts\start-nats.ps1 -Port 4333   # Custom port
#
# Monitoring UI: http://localhost:8222
# Stop: Ctrl+C in the terminal window, or kill the process.

[CmdletBinding()]
param(
    [int]$Port = 4222,
    [int]$HttpPort = 8222,
    [switch]$Auth,
    [string]$AuthToken = 'mytoken'
)

# Locate the nats-server binary
$searchPaths = @(
    "$env:USERPROFILE\nats-server",
    "$env:ProgramFiles\nats-server",
    "$env:USERPROFILE\scoop\shims"
)

$exe = $null
foreach ($path in $searchPaths) {
    $found = Get-ChildItem -Path $path -Filter "nats-server.exe" -Recurse -ErrorAction SilentlyContinue |
             Select-Object -First 1 -ExpandProperty FullName
    if ($found) { $exe = $found; break }
}

# Fall back to PATH
if (-not $exe) {
    $exe = (Get-Command nats-server -ErrorAction SilentlyContinue)?.Source
}

if (-not $exe) {
    Write-Error "nats-server not found. Download from https://github.com/nats-io/nats-server/releases"
    exit 1
}

$storeDir = "$env:TEMP\nats-data"
$args = @(
    "--jetstream"
    "--store_dir", $storeDir
    "--port", $Port
    "--http_port", $HttpPort
)

if ($Auth) {
    $args += "--auth", $AuthToken
    Write-Host "Token auth enabled  — token: $AuthToken  port: $Port"
} else {
    Write-Host "Starting NATS (no auth)  port: $Port  monitoring: http://localhost:$HttpPort"
}

Write-Host "Binary : $exe"
Write-Host "Data   : $storeDir"
Write-Host ""

& $exe @args
