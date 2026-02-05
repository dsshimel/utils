#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Monitors internet connectivity and reconnects to a specified WiFi network if the connection drops.

.PARAMETER SSID
    The WiFi network name to reconnect to. Defaults to "Fractal Tech".

.PARAMETER IntervalSeconds
    How often to check connectivity, in seconds. Defaults to 10.

.PARAMETER PingTarget
    Host to ping for connectivity checks. Defaults to "8.8.8.8".

.PARAMETER PingTimeoutMs
    Ping timeout in milliseconds. Defaults to 3000.

.PARAMETER FailThreshold
    Number of consecutive ping failures before triggering a reconnect. Defaults to 3.

.EXAMPLE
    .\wifi-watchdog.ps1
    .\wifi-watchdog.ps1 -SSID "Fractal Tech" -IntervalSeconds 5
#>

param(
    [string]$SSID = "Fractal Tech",
    [int]$IntervalSeconds = 10,
    [string]$PingTarget = "8.8.8.8",
    [int]$PingTimeoutMs = 3000,
    [int]$FailThreshold = 3
)

$consecutiveFailures = 0
$reconnectCount = 0

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        "OK"    { "Green" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Test-Internet {
    $result = ping -n 1 -w $PingTimeoutMs $PingTarget 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Get-CurrentSSID {
    try {
        $output = netsh wlan show interfaces
        $line = $output | Select-String "^\s+SSID\s+:" | Select-Object -First 1
        if ($line) {
            return ($line -replace '^\s+SSID\s+:\s+', '').Trim()
        }
    } catch {}
    return $null
}

function Connect-WiFi {
    param([string]$NetworkSSID)

    Write-Log "Attempting to reconnect to '$NetworkSSID'..." "WARN"

    # First, check if a profile exists for this network
    $profiles = netsh wlan show profiles
    $profileExists = $profiles | Select-String ([regex]::Escape($NetworkSSID))

    if (-not $profileExists) {
        Write-Log "No saved profile found for '$NetworkSSID'. Cannot auto-connect." "ERROR"
        Write-Log "Connect to '$NetworkSSID' manually first so Windows saves the profile." "ERROR"
        return $false
    }

    # Disconnect current connection
    netsh wlan disconnect | Out-Null
    Start-Sleep -Seconds 2

    # Reconnect using the saved profile
    $result = netsh wlan connect name="$NetworkSSID" ssid="$NetworkSSID" 2>&1
    if ($result -match "Connection request was completed successfully") {
        Start-Sleep -Seconds 5
        if (Test-Internet) {
            return $true
        }
        Write-Log "Connected to WiFi but internet is not reachable yet." "WARN"
        # Give it a bit more time
        Start-Sleep -Seconds 5
        return (Test-Internet)
    } else {
        Write-Log "netsh connect failed: $result" "ERROR"
        return $false
    }
}

# --- Main loop ---

Write-Host ""
Write-Host "=== WiFi Watchdog ===" -ForegroundColor Cyan
Write-Host "  Network:        $SSID"
Write-Host "  Check interval: ${IntervalSeconds}s"
Write-Host "  Ping target:    $PingTarget"
Write-Host "  Fail threshold: $FailThreshold consecutive failures"
Write-Host "  Press Ctrl+C to stop."
Write-Host ""

$currentSSID = Get-CurrentSSID
if ($currentSSID) {
    Write-Log "Currently connected to: '$currentSSID'" "OK"
} else {
    Write-Log "Not currently connected to any WiFi network." "WARN"
}

while ($true) {
    if (Test-Internet) {
        if ($consecutiveFailures -gt 0) {
            Write-Log "Connection restored. (was failing for $consecutiveFailures check(s))" "OK"
        } else {
            Write-Log "Ping OK" "OK"
        }
        $consecutiveFailures = 0
    } else {
        $consecutiveFailures++
        Write-Log "Ping failed ($consecutiveFailures/$FailThreshold)" "WARN"

        if ($consecutiveFailures -ge $FailThreshold) {
            $currentSSID = Get-CurrentSSID
            Write-Log "Connection lost. Current SSID: $(if ($currentSSID) { "'$currentSSID'" } else { 'None' })" "ERROR"

            $success = Connect-WiFi -NetworkSSID $SSID
            if ($success) {
                $reconnectCount++
                Write-Log "Reconnected to '$SSID' successfully. (Total reconnects: $reconnectCount)" "OK"
            } else {
                Write-Log "Reconnection failed. Will retry on next cycle." "ERROR"
            }
            $consecutiveFailures = 0
        }
    }

    Start-Sleep -Seconds $IntervalSeconds
}
