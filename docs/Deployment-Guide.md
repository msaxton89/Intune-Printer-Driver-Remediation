# Deployment Guide

## Purpose

This document shows how I would deploy the example remediation in a controlled way through Microsoft Intune.

## 1. Prepare the scripts

Update the configuration block in both scripts so that the queue names, expected driver, minimum version and certificate settings match the target environment.

Keep the configuration identical between detection and remediation.

## 2. Validate in a test environment

Before uploading to Intune:

- use a disposable Windows test VM where possible;
- confirm `Get-Printer`, `Get-PrinterDriver` and `Get-PrintJob` return the expected data;
- test a compliant driver;
- test an outdated driver;
- test an unexpected driver name;
- test with a pending print job;
- test with the certificate missing if certificate validation is enabled.

The remediation should refuse to make changes when a safeguard is triggered.

## 3. Create the Intune remediation

In the Intune admin centre:

1. Open **Devices > Scripts and remediations**.
2. Create a new remediation package.
3. Upload `Detect-PrinterDriver.ps1`.
4. Upload `Remediate-PrinterDriver.ps1`.
5. Use system context.
6. Run in 64-bit PowerShell.

## 4. Pilot first

Assign the package to a small device pilot group.

A useful pilot would include:

- at least one known healthy endpoint;
- at least one endpoint with the issue, if available;
- different Windows hardware models where relevant.

Review the Intune output before broadening the assignment.

## 5. Validate after remediation

Confirm that:

- the stale driver package was removed only where required;
- no unrelated printer queues were changed;
- the current printer driver is redeployed by the print-management platform;
- printing works as expected;
- users do not have pending jobs lost by the remediation.

## 6. Expand in stages

Only expand the assignment once the pilot is successful.

For a larger environment I would use staged groups rather than targeting the full estate immediately.

## 7. Monitor and review

After deployment:

- review detection/remediation status in Intune;
- investigate repeated `BLOCKED` or `REMEDIATION ERROR` results;
- update the configured minimum version when the organisation intentionally adopts a newer driver;
- keep a record of the change, pilot outcome and rollback considerations.

## Rollback

The remediation does not itself install a replacement driver. It assumes a separate print-management platform is responsible for redeploying the approved queue and driver.

Before production deployment, confirm that the platform can reliably restore the target queues. If it cannot, do not run the remediation.
