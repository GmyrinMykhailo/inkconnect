$ErrorActionPreference = "Stop"

$ProjectRoot = "C:\Inkconnect"
$FlutterProject = Join-Path $ProjectRoot "flutter_client"
$BackendExe = Join-Path $ProjectRoot "inkconnect-api.exe"
$BackendLog = Join-Path $ProjectRoot "backend-local.log"
$BackendErrLog = Join-Path $ProjectRoot "backend-local.err.log"
$GoExe = "C:\Program Files\Go\bin\go.exe"
$FlutterExe = "C:\flutter\flutter\bin\flutter.bat"

Write-Host ""
Write-Host "InkConnect local start"
Write-Host "1/4 Building backend..."

Set-Location $ProjectRoot
& $GoExe build -o $BackendExe ./cmd/api

Write-Host "2/4 Stopping old backend if it is running..."
Get-Process | Where-Object { $_.ProcessName -eq "inkconnect-api" } | Stop-Process -Force -ErrorAction SilentlyContinue

Write-Host "3/4 Starting backend on http://127.0.0.1:18080 ..."
$backendProcess = Start-Process `
  -FilePath $BackendExe `
  -WorkingDirectory $ProjectRoot `
  -RedirectStandardOutput $BackendLog `
  -RedirectStandardError $BackendErrLog `
  -PassThru

Start-Sleep -Seconds 3

try {
  $health = Invoke-WebRequest -Uri "http://127.0.0.1:18080/healthz" -UseBasicParsing
  Write-Host "Backend is up: $($health.StatusCode)"
} catch {
  Write-Host "Backend did not answer yet. Check:"
  Write-Host "  $BackendLog"
  Write-Host "  $BackendErrLog"
  throw
}

Write-Host "4/4 Launching Flutter Web in Chrome..."
Write-Host "When you want to stop everything, close Flutter and run scripts\\stop-local.ps1"
Write-Host ""

Set-Location $FlutterProject
& $FlutterExe run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:18080
