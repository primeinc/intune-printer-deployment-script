param(
    [string]$DriverName,
    [string]$PrinterName,
    [string]$PrinterHostAddress,
    [switch]$Remove
)

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp $Message"
    # Optionally log to file:
    # Add-Content -Path "C:\Temp\printer_install.log" -Value "$timestamp $Message"
}

Write-Log "=== Deploy-Printer.ps1 START ==="
Write-Log "Parameters: DriverName='$DriverName', PrinterName='$PrinterName', PrinterHostAddress='$PrinterHostAddress', Remove=$Remove"

# Handle printer removal
if ($Remove) {
    Write-Log "REMOVE MODE: Removing printer '$PrinterName'"
    
    # Get printer details before removing
    $printer = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
    $driverNameToRemove = $null
    
    if ($printer) {
        $driverNameToRemove = $printer.DriverName
        Write-Log "Printer uses driver: $driverNameToRemove"
        
        Write-Log "Removing printer: $PrinterName"
        try {
            Remove-Printer -Name $PrinterName -ErrorAction Stop
            Write-Log "SUCCESS: Printer removed successfully"
        } catch {
            Write-Log "ERROR: Failed to remove printer: $_"
            throw $_
        }
    } else {
        Write-Log "Printer not found: $PrinterName"
    }
    
    # Remove driver if specified or if we found it from the printer
    if ($DriverName) {
        $driverNameToRemove = $DriverName
    }
    
    if ($driverNameToRemove) {
        Write-Log "Checking if driver '$driverNameToRemove' is still in use..."
        
        # Check if any other printers are using this driver
        $printersUsingDriver = Get-Printer | Where-Object { $_.DriverName -eq $driverNameToRemove }
        
        if ($printersUsingDriver.Count -eq 0) {
            Write-Log "No other printers are using driver '$driverNameToRemove'. Removing driver..."
            
            try {
                Remove-PrinterDriver -Name $driverNameToRemove -ErrorAction Stop
                Write-Log "SUCCESS: Driver removed successfully"
                
                # Also try to remove from driver store using pnputil
                Write-Log "Attempting to remove driver from Windows driver store..."
                # Note: Removing from driver store is complex and may not always work
                # The driver might be in use by Windows or protected
                Write-Log "Driver store removal skipped - driver may be needed by Windows"
            } catch {
                Write-Log "WARNING: Failed to remove driver: $_"
                Write-Log "Driver may be protected or in use by Windows"
            }
        } else {
            Write-Log "Driver '$driverNameToRemove' is still in use by $($printersUsingDriver.Count) other printer(s):"
            foreach ($p in $printersUsingDriver) {
                Write-Log "  - $($p.Name)"
            }
            Write-Log "Driver will not be removed."
        }
    }
    
    Write-Log "=== Deploy-Printer.ps1 END (REMOVE) ==="
    exit 0
}

# Detect architecture
$arch = if ([System.Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
Write-Log "Detected architecture: $arch"

# Set paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DriverPath = Join-Path $ScriptDir "64bit"
Write-Log "Driver path: $DriverPath"

# Find INF files
$infFiles = Get-ChildItem -Path $DriverPath -Filter *.inf
Write-Log "$($infFiles.Count) INF files found: $(($infFiles | ForEach-Object { $_.Name }) -join ', ')"
if ($infFiles.Count -eq 0) {
    Write-Log "ERROR: No INF files found."
    throw "No INF files in $DriverPath"
}

# Install driver using pnputil
foreach ($infFile in $infFiles) {
    $infFullPath = $infFile.FullName
    Write-Log "Installing driver from: $infFullPath"
    $pnputilOutput = & pnputil.exe /add-driver "$infFullPath" /install 2>&1
    $exitCode = $LASTEXITCODE
    Write-Log "pnputil.exe output: $pnputilOutput"
    Write-Log "pnputil.exe exit code: $exitCode"
    
    # Common pnputil exit codes:
    # 0 = Success - driver newly installed
    # 5 = Driver already exists (common with HP drivers)
    # 259 = ERROR_NO_MORE_ITEMS - driver already exists and is up-to-date
    # 3010 = ERROR_SUCCESS_REBOOT_REQUIRED - success but reboot required
    
    switch ($exitCode) {
        0 {
            Write-Log "Driver newly installed: $($infFile.Name)"
        }
        5 {
            Write-Log "Driver already exists in system: $($infFile.Name)"
        }
        259 {
            Write-Log "Driver already exists and is up-to-date: $($infFile.Name)"
        }
        3010 {
            Write-Log "Driver installed successfully but REBOOT REQUIRED: $($infFile.Name)"
            Write-Log "WARNING: System reboot is required to complete driver installation"
        }
        default {
            Write-Log "ERROR: pnputil failed for $($infFile.Name) with code $exitCode"
            throw [System.Exception]::new("pnputil.exe failed: code $exitCode, output: $pnputilOutput")
        }
    }
}

# Add printer driver from the installed INF
Write-Log "Adding printer driver: $DriverName"
$driverAdded = $false

# First check if driver already exists
$existingDriver = Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue
if ($existingDriver) {
    Write-Log "Printer driver already exists: $DriverName"
    $driverAdded = $true
} else {
    # Since pnputil already installed the driver to the store, we just need to add it
    # without specifying an INF path
    try {
        Add-PrinterDriver -Name $DriverName -ErrorAction Stop
        Write-Log "SUCCESS: Printer driver added: $DriverName"
        $driverAdded = $true
    } catch {
        Write-Log "ERROR: Failed to add printer driver using Add-PrinterDriver: $_"
        Write-Log "Attempting alternative installation method using rundll32..."
        
        # Try using rundll32 to install the driver
        $installCmd = "rundll32 printui.dll,PrintUIEntry /ia /m `"$DriverName`" /f `"$DriverPath\su2emenu.inf`""
        Write-Log "Running: $installCmd"
        $result = & cmd /c $installCmd 2>&1
        $exitCode = $LASTEXITCODE
        
        if ($exitCode -eq 0) {
            Write-Log "SUCCESS: Driver installed via rundll32"
            $driverAdded = $true
        } else {
            Write-Log "ERROR: rundll32 failed with exit code $exitCode. Output: $result"
        }
    }
}

# Parse the INF file to see what drivers it contains
Write-Log "Checking what drivers the INF file contains..."
$infContent = Get-Content "$DriverPath\su2emenu.inf" -ErrorAction SilentlyContinue
$modelLines = $infContent | Where-Object { $_ -match '^Model\d+=' }
Write-Log "INF file contains $($modelLines.Count) driver models"

# List available drivers after installation
Write-Log "Checking for installed printer drivers..."
$existingDriver = Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue
if ($existingDriver) {
    Write-Log "Driver verified in system: $($existingDriver.Name)"
} else {
    Write-Log "Driver '$DriverName' not found in system. Available drivers:"
    $allDrivers = Get-PrinterDriver
    Write-Log "Total drivers in system: $($allDrivers.Count)"
    # Show first 10 drivers as reference
    $allDrivers | Select-Object -First 10 | ForEach-Object { Write-Log "  - $($_.Name)" }
}

# Verify the driver exists before proceeding
$actualDriver = Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue
if (-not $actualDriver) {
    Write-Log "WARNING: Driver '$DriverName' not found in Windows driver store"
    Write-Log "Proceeding anyway - Add-Printer may still work if driver was installed differently"
}

# Add printer port if not exists
$portName = "IP_$PrinterHostAddress"
$portExists = Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue
if (-not $portExists) {
    Write-Log "Creating printer port: $portName"
    Add-PrinterPort -Name $portName -PrinterHostAddress $PrinterHostAddress
    Write-Log "Printer port created."
} else {
    Write-Log "Printer port already exists: $portName"
}

# Add printer
$printerExists = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
if (-not $printerExists) {
    Write-Log "Adding printer: $PrinterName with driver '$DriverName'"
    try {
        Add-Printer -Name $PrinterName -PortName $portName -DriverName $DriverName -ErrorAction Stop
        Write-Log "SUCCESS: Printer added successfully!"
    } catch {
        Write-Log "ERROR: Failed to add printer: $_"
        
        # Check if driver really exists
        $verifyDriver = Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue
        if (-not $verifyDriver) {
            Write-Log "ERROR: Driver '$DriverName' does not exist in Windows driver store"
            Write-Log "Available drivers:"
            Get-PrinterDriver | ForEach-Object { Write-Log "  - $($_.Name)" }
        }
        
        Write-Log "FAILED: Printer installation failed!"
        throw $_
    }
} else {
    Write-Log "Printer already exists: $PrinterName"
}

Write-Log "=== Deploy-Printer.ps1 END ==="