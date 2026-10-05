#requires -version 5.1

<#
.SYNOPSIS
    Intune Remediations detection script for stale printer drivers.

.DESCRIPTION
    Portfolio-safe example that checks selected managed print queues, verifies
    an expected driver name and minimum version, and optionally checks for a
    Trusted Publisher certificate.

    Exit 0 = compliant / no remediation required
    Exit 1 = issue detected / remediation should run
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

# Set to $false if certificate validation is not required in your environment.
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

try {
    $issues = [System.Collections.Generic.List[string]]::new()

    if ($RequireTrustedPublisherCertificate) {
        if ($CertificateThumbprint -eq 'REPLACE_WITH_TRUSTED_PUBLISHER_THUMBPRINT') {
            $issues.Add('Certificate thumbprint has not been configured')
        }
        else {
            $certificatePath = "Cert:\LocalMachine\TrustedPublisher\$CertificateThumbprint"
            if (-not (Test-Path -LiteralPath $certificatePath)) {
                $issues.Add('Required Trusted Publisher certificate is missing')
            }
        }
    }

    $allPrinters = @(Get-Printer -ErrorAction Stop)
    $targetPrinters = @($allPrinters | Where-Object Name -in $QueueNames)

    if ($targetPrinters.Count -eq 0) {
        if ($issues.Count -gt 0) {
            Write-Output "$env:COMPUTERNAME | ISSUE | $($issues -join '; ')"
            exit 1
        }

        Write-Output "$env:COMPUTERNAME | OK | Target queues are not currently installed"
        exit 0
    }

    foreach ($printer in $targetPrinters) {
        if ($printer.DriverName -ne $ExpectedDriverName) {
            $issues.Add("$($printer.Name): unexpected driver '$($printer.DriverName)'")
            continue
        }

        $driver = Get-PrinterDriver -Name $printer.DriverName -ErrorAction SilentlyContinue
        if (-not $driver) {
            $issues.Add("$($printer.Name): driver package not found")
            continue
        }

        try {
            $installedVersion = ConvertFrom-PackedDriverVersion -Value ([uint64]$driver.DriverVersion)
        }
        catch {
            $issues.Add("$($printer.Name): could not read driver version")
            continue
        }

        if ($installedVersion -lt $MinimumDriverVersion) {
            $issues.Add("$($printer.Name): driver $installedVersion is below minimum $MinimumDriverVersion")
        }
    }

    if ($issues.Count -gt 0) {
        Write-Output "$env:COMPUTERNAME | ISSUE | $($issues -join '; ')"
        exit 1
    }

    $queueSummary = ($targetPrinters | ForEach-Object Name) -join ', '
    Write-Output "$env:COMPUTERNAME | OK | Queues=$queueSummary | Minimum=$MinimumDriverVersion"
    exit 0
}
catch {
    $message = $_.Exception.Message
    if ($message.Length -gt 500) {
        $message = $message.Substring(0, 500)
    }

    Write-Output "$env:COMPUTERNAME | DETECTION ERROR | $message"
    exit 1
}
