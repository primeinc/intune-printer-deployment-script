[CmdletBinding()]
param (
    [Parameter(
        Mandatory=$true,
        Position=0)
    ]
    [string]$DriverName,
    [Parameter(
        Mandatory=$true,
        Position=1)
    ]
    [string]$PrinterName,
    [Parameter(
        Mandatory=$true,
        Position=2)
    ]
    [string]$PrinterHostAddress,
    [Parameter(
        Mandatory=$false,
        ParameterSetName="Snmp")
    ]
    [switch]$SNMP
)


#Write to a log file on the system
function Write-Log {
    param (
        [parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('Verbose','Information','Warning','Error','Critical')]
        [string]$Severity = 'Information'
    )

    $LogFile = Join-Path -Path $LogFilePath -ChildPath $("$($PrinterName).log")

    Try {
        #Don't write verbose records to the log file
        if ($Severity -ne "Verbose"){
            
            [pscustomobject]@{
                Time = (Get-date -Format "yyyy-MM-dd HH:mm:ss")
                Severity = $Severity
                Message = $Message
            } | Export-Csv -Path $LogFile -Append -NoTypeInformation
        }

        # Add a trailing record to mark the script failure
        if ($Severity -eq "Critical"){
            
            [pscustomobject]@{
                Time = (Get-date -Format "yyyy-MM-dd HH:mm:ss")
                Severity = $Severity
                Message = "####### SCRIPT CRITICAL FAILURE #######"
            } | Export-Csv -Path $LogFile -Append -NoTypeInformation
        }

        switch ($Severity) {
            "Verbose" { Write-Verbose -Message $Message }
            "Warning" { Write-Warning -Message $Message }
            "Error" { Write-Error -Message $Message}
            "Critical" {
                Write-Host -ForegroundColor Red "CRITICAL: $Message"
                Write-Host -ForegroundColor Red "CRITICAL: Unable to continue installation script"
                Write-Host -ForegroundColor Red "####### SCRIPT CRITICAL FAILURE #######"
            }
            Default { Write-Information -MessageData $Message -InformationAction Continue }
        }

    }
    Catch [System.Exception] {
        Write-Warning -Message "Unable to add log entry to $LogFile file. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
    }
}


# Function to get absolute path of PrinterDriver folder based on the system architecture
# and the folder the script is run from
function Get-DriverPath {
    $ScriptPath = $PSScriptRoot
    $DriverPath = "PrinterDriver\64bit"

    $Arch = ([System.Runtime.InteropServices.RuntimeInformation,mscorlib]::OSArchitecture.ToString().ToLower())

    Write-Log "$Arch Architecture Detected"

    switch ($Arch)
    {
        "x64" {$DriverPath = "PrinterDriver\64bit"}
        "x86" {$DriverPath = "PrinterDriver\32bit"}
        "arm64" {$DriverPath = "PrinterDriver\arm64"}
        default{
            Write-Log "Unknown System Architecture: $Arch" -Severity Critical
            Exit 1
        }
    } 
    
    return (Join-Path -Path $ScriptPath -ChildPath $DriverPath)
}

# Function to install printer driver into the windows driver store using pnputil.exe
# The powershell command Add-PrinterDriver cannot add drivers that are not aleady in the store.
function Install-PrinterDriver {
    param (
        [Parameter(
            Mandatory=$true,
            Position=0)]
        [string]$DriverPath
    )

    Write-Log -Message "Installing printer driver from path: $DriverPath"

    if ( Test-Path -Path $DriverPath ){
        $infFile = Get-ChildItem -Path $DriverPath -Filter *.inf
    
        if ($null -eq $infFile) {
            Write-Log "No inf files exist in the driver folder" -Severity Critical
            Exit 1
        }else{
            Write-Log ("{0} inf files located in directory" -f $infFile.Count)
        }

        pnputil.exe /add-Driver "$DriverPath/*.inf" /install | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "Printer drivers installed successfully."
        }elseif ($LASTEXITCODE -eq 259) {
            Write-Log -Message "Printer drivers already installed."
        }elseif ($LASTEXITCODE -eq 3010) {
            Write-Log -Message "Printer drivers installed successfully. System restart required" -Severity Warning
        } else {
            throw [System.Exception]::New('pnputil.exe return code of $LASTEXITCODE was received while installing the driver')
        }
    }else{
        Write-Log "$DriverPath does not exist.`nDrivers for each architecture must be placed in a sub folder named x86, x64, arm64" -Severity Critical
        Exit 1
    }
}

# Attempts connecting to the printer on the required IP address
# Will return a success if connection is established, false otherwise
function Test-PrinterAvailable {
    param (
        [string]$PrinterHostAddress
    )

    try{
        $TcpClient = [System.Net.Sockets.TcpClient]::new()
        #Attempt a TCP connection to the standard printer port.
        $TcpClient.Connect($PrinterHostAddress, 9100)

        #If the connection fails to connect then it raises an error, Because 
        #there is nothing that needs to be done with the connection, close it.
        $TcpClient.Close()

        Write-Log -Message "Succesfully connected to printer at $PrinterHostAddress on port 9100 using TCP/IP"
        return $true

    }catch{
        Write-Log -Message "Unable to connect to printer at $PrinterHostAddress on port 9100" -Severity Warning
        return $false
    }
}

# Function to install a local printer
function Install-LocalPrinter {
    param (
        [string]$DriverName,
        [string]$PrinterName,
        [string]$PrinterHostAddress,
        [bool]$SNMP
    )

    # Creating a Standard TCP/IP Port
    $PortName = "IP_$PrinterHostAddress"
    $PrinterPortExists = $true

    try{
        Get-PrinterPort -Name $PortName -ErrorAction Stop | Out-Null
    }catch{
        #An error means that the command didn't find the port
        $PrinterPortExists = $false
        Write-Log "No existing TCP/IP Port $PortName was found on system"
    }

    #If there is no printer port already present then create one
    if (! $PrinterPortExists){
        try{
            Test-PrinterAvailable -PrinterHostAddress $PrinterHostAddress | Out-Null

            Write-Log -Message "Creating a Standard TCP/IP Port for $PrinterHostAddress"
            
            Add-PrinterPort -Name $PortName -PrinterHostAddress $PrinterHostAddress -PortNumber 9100 -ErrorAction Stop
        }
        catch{
            throw $_.Exception
        }
    }else{
        Write-Log -Message "Using existing TCP/IP Port $PortName" -Severity Warning
    }
    

    #Check to see if the printer is already setup on the system
    $ExistingPrinter = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
    if ($null -eq $ExistingPrinter){
        #Printer doesn't exist so create it
        Write-Log "Installing the printer using driver: $DriverName"

        try{
            Write-Log "Adding Printer driver $DriverName to print spooler"
            Add-PrinterDriver -Name $DriverName -ErrorAction Stop
        }
        catch{
            throw $_.Exception
        }

        try{
            Write-Log "Adding Printer Queue $PrinterName on port $PortName using driver $DriverName"
            Add-Printer -Name $PrinterName -PortName $PortName -DriverName $DriverName -ErrorAction Stop      
        }
        catch{
            throw $_.Exception
        }
        
        
        Write-Log "$PrinterName was installed successfully."

    }else{
        #Printer already exists
        Write-Log "$PrinterName already exists on the system." -Severity Warning
    }
}


###########################################################
# Script entry point
###########################################################

#Create the temp folder to store log files in
$LogFilePath = (Join-Path -Path $env:SystemRoot -ChildPath $("temp\install-printer"))
[System.IO.Directory]::CreateDirectory($LogFilePath) | Out-Null


Write-Log -Message "####### Staring Printer Installation Script #######"


try{
    $DriverPath = Get-DriverPath
    Install-PrinterDriver -DriverPath $DriverPath -ErrorAction stop
    Install-LocalPrinter -DriverName $DriverName -PrinterName $PrinterName -PrinterHostAddress $PrinterHostAddress
}
catch{
    $Fields =[PSCustomObject]@{
        Message = $_.Exception.Message
        ScriptName = $_.InvocationInfo.ScriptName
        LineNumber = $_.InvocationInfo.ScriptLineNumber
        PositionMessage = $_.InvocationInfo.PositionMessage
        Exception = $_.Exception
    }

    Write-Log -Message ($Fields | Format-List -Force | Out-String) -Severity Error

    exit 1
}