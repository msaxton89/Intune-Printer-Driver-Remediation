# Intune Printer Driver Remediation

A portfolio-safe Microsoft Intune Remediations example for detecting and repairing stale Windows printer drivers.

> **Portfolio note:** This repository is a sanitised recreation of a real-world endpoint problem I worked on. Organisation-specific names, printer models, certificate details and production values have been removed or replaced.

## The problem

Managed Windows endpoints can retain an older printer driver even after the print-management platform has been updated. This can create inconsistent behaviour across the estate and lead to repeated support tickets.

The aim of this project is to:

- detect whether approved print queues are using the expected driver;
- compare the installed driver version with a configured minimum;
- verify a trusted publisher certificate where required;
- remediate only when it is safe to do so;
- produce clear output that can be reviewed from Microsoft Intune.

## How it works

The project contains two PowerShell scripts designed for **Microsoft Intune Remediations**:

- `Detect-PrinterDriver.ps1`  
  Checks the target queues, driver name, driver version and optional Trusted Publisher certificate.

- `Remediate-PrinterDriver.ps1`  
  Removes only approved target queues and the stale driver package, allowing the organisation's print-management platform to redeploy the current driver.

## Safety controls

The remediation deliberately stops without making changes if:

- the required Trusted Publisher certificate is missing;
- a target queue is using an unexpected driver;
- another printer is using the same driver package;
- a target queue contains pending print jobs;
- the installed driver already meets the required minimum version.

It also retries driver removal rather than immediately failing if the Windows print spooler still has the package locked.

## Example workflow

```text
Intune detection runs
        |
        v
Are target queues installed?
   |             |
  No            Yes
   |             |
   v             v
No action    Check driver
                 |
                 v
         Version below minimum?
            |           |
           No          Yes
            |           |
            v           v
          Compliant   Run remediation
                         |
                         v
                 Perform safety checks
                         |
                         v
                 Remove stale package
                         |
                         v
                 Print platform redeploys
```

## Configuration

Update the configuration block at the top of **both** scripts:

```powershell
$QueueNames = @(
    'Managed Print - Mono',
    'Managed Print - Colour'
)

$ExpectedDriverName = 'Example Universal Print Driver'
$MinimumDriverVersion = [version]'2.5.0.0'

$RequireTrustedPublisherCertificate = $true
$CertificateThumbprint = 'REPLACE_WITH_TRUSTED_PUBLISHER_THUMBPRINT'
```

The detection and remediation scripts must use matching values.

## Intune deployment

In Microsoft Intune:

1. Go to **Devices > Scripts and remediations**.
2. Create a remediation package.
3. Upload `Detect-PrinterDriver.ps1` as the detection script.
4. Upload `Remediate-PrinterDriver.ps1` as the remediation script.
5. Run in **64-bit PowerShell**.
6. Run using **system context**, not the signed-in user's credentials.
7. Pilot on a small device group before wider deployment.
8. Review detection and remediation output before expanding the assignment.

See [`docs/Deployment-Guide.md`](docs/Deployment-Guide.md) for a fuller deployment approach.

## Example output

```text
PC-001 | OK | Queues=Managed Print - Mono, Managed Print - Colour | Minimum=2.5.0.0
PC-014 | ISSUE | Managed Print - Mono: driver 2.3.0.0 is below minimum 2.5.0.0
PC-014 | REPAIRED | Removed stale driver 2.3.0.0
PC-022 | BLOCKED | Pending print jobs on Managed Print - Colour; repair deferred
```

## What this demonstrates

This project is intended to demonstrate practical experience with:

- Microsoft Intune Remediations;
- PowerShell automation;
- Windows print management;
- endpoint health detection;
- defensive scripting and failure handling;
- staged deployment and change control;
- clear technical documentation.

## Testing approach

I would not deploy a remediation like this directly to a full estate.

A typical rollout would be:

1. validate the scripts on a disposable Windows test VM;
2. pilot against a small group of managed endpoints;
3. confirm expected detection output;
4. deliberately test blocked conditions, such as pending jobs;
5. confirm the print-management platform successfully redeploys the current driver;
6. expand the assignment in stages;
7. monitor remediation results after deployment.

## Disclaimer

This repository is provided as a technical portfolio example. The configuration values are placeholders and should be reviewed and tested before use in any production environment.
