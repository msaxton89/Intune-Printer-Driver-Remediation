#requires -version 5.1

<#
.SYNOPSIS
    Intune Remediations repair script for stale printer drivers.

.DESCRIPTION
    Portfolio-safe example that removes approved target queues and a stale
    driver package so the organisation's print-management platform can
    redeploy a current driver.

    Safeguards stop the repair when:
      - the required Trusted Publisher certificate is missing;
      - a target queue uses an unexpected driver;
      - another printer uses the same driver;
      - a target queue has pending print jobs; or
      - the installed driver already meets the minimum version.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# -----------------------------
# Configuration
# -----------------------------
$QueueNames = @(
    'Managed Print - Mono',
    'Managed Print - Colour'
)

$ExpectedDriverName = 'Example Universal Print Driver'
$MinimumDriverVersion = [version]'2.5.0.0'

$RequireTrustedPublisherCertificate = $true
$CertificateThumbprint = 'REPLACE_WITH_TRUSTED_PUBLISHER_THUMBPRINT'

function ConvertFrom-PackedDriverVersion {
    param(
        [Parameter(Mandatory)]
        [uint64]$Value
    )

    $major = ($Value -shr 48) -band 0xFFFF
    $minor = ($Value -shr 32) -band 0xFFFF
    $build = ($Value -shr 16) -band 0xFFFF
    $revision = $Value -band 0xFFFF

    [version]"$major.$minor.$build.$revision"
}

function Stop-WithMessage {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Output "$env:COMPUTERNAME | BLOCKED | $Message"
    exit 1
}

try {
    if ($RequireTrustedPublisherCertificate) {
        if ($CertificateThumbprint -eq 'REPLACE_WITH_TRUSTED_PUBLISHER_THUMBPRINT') {
            Stop-WithMessage 'Certificate thumbprint has not been configured'
        }

        $certificatePath = "Cert:\LocalMachine\TrustedPublisher\$CertificateThumbprint"
        if (-not (Test-Path -LiteralPath $certificatePath)) {
            Stop-WithMessage 'Required Trusted Publisher certificate is missing; no changes made'
        }
    }

    $allPrinters = @(Get-Printer -ErrorAction Stop)
    $targetPrinters = @($allPrinters | Where-Object Name -in $QueueNames)

    if ($targetPrinters.Count -eq 0) {
        Write-Output "$env:COMPUTERNAME | NO ACTION | Target queues are not currently installed"
        exit 0
    }

    $unexpectedPrinters = @(
        $targetPrinters | Where-Object DriverName -ne $ExpectedDriverName
    )

    if ($unexpectedPrinters.Count -gt 0) {
        $details = ($unexpectedPrinters | ForEach-Object {
            "$($_.Name)='$($_.DriverName)'"
        }) -join ', '

        Stop-WithMessage "Unexpected driver detected: $details"
    }

    $driver = Get-PrinterDriver -Name $ExpectedDriverName -ErrorAction SilentlyContinue
    if (-not $driver) {
        Stop-WithMessage "Driver package '$ExpectedDriverName' was not found"
    }

    try {
        $installedVersion = ConvertFrom-PackedDriverVersion -Value ([uint64]$driver.DriverVersion)
    }
    catch {
        Stop-WithMessage "Could not read the version of '$ExpectedDriverName'"
    }

    if ($installedVersion -ge $MinimumDriverVersion) {
        Write-Output "$env:COMPUTERNAME | NO ACTION | Driver=$installedVersion | Minimum=$MinimumDriverVersion"
        exit 0
    }

    $otherPrinters = @(
        $allPrinters |
            Where-Object {
                $_.DriverName -eq $ExpectedDriverName -and
                $_.Name -notin $QueueNames
            }
    )

    if ($otherPrinters.Count -gt 0) {
        $otherNames = ($otherPrinters | ForEach-Object Name) -join ', '
        Stop-WithMessage "Driver is also used by another printer: $otherNames"
    }

    $queuesWithJobs = [System.Collections.Generic.List[string]]::new()

    foreach ($printer in $targetPrinters) {
        $jobs = @(Get-PrintJob -PrinterName $printer.Name -ErrorAction SilentlyContinue)

        if ($jobs.Count -gt 0) {
            $queuesWithJobs.Add($printer.Name)
        }
    }

    if ($queuesWithJobs.Count -gt 0) {
        Stop-WithMessage "Pending print jobs on $($queuesWithJobs -join ', '); repair deferred"
    }

    foreach ($printer in $targetPrinters) {
        Remove-Printer -Name $printer.Name -Confirm:$false -ErrorAction Stop
    }

    Restart-Service -Name Spooler -Force -ErrorAction Stop
    Start-Sleep -Seconds 2

    $driverRemoved = $false
    $lastRemovalError = $null

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            # A print-management client may recreate a target queue while the
            # stale package is being removed. Remove only approved queue names.
            $recreatedQueues = @(
                Get-Printer -ErrorAction SilentlyContinue |
                    Where-Object {
                        $_.Name -in $QueueNames -and
                        $_.DriverName -eq $ExpectedDriverName
                    }
            )

            foreach ($printer in $recreatedQueues) {
                Remove-Printer -Name $printer.Name -Confirm:$false -ErrorAction Stop
            }

            Remove-PrinterDriver `
                -Name $ExpectedDriverName `
                -RemoveFromDriverStore `
                -Confirm:$false `
                -ErrorAction Stop

            $driverRemoved = $true
            break
        }
        catch {
            $lastRemovalError = $_.Exception.Message

            if ($attempt -lt 3) {
                Restart-Service -Name Spooler -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }
        }
    }

    if (-not $driverRemoved) {
        Stop-WithMessage "Could not remove stale driver after 3 attempts: $lastRemovalError"
    }

    Write-Output "$env:COMPUTERNAME | REPAIRED | Removed stale driver $installedVersion"
    exit 0
}
catch {
    $message = $_.Exception.Message
    if ($message.Length -gt 500) {
        $message = $message.Substring(0, 500)
    }

    Write-Output "$env:COMPUTERNAME | REMEDIATION ERROR | $message"
    exit 1
}
