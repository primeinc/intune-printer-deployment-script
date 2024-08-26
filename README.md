# Creating a Printer Deployment Package
The script [Create-PrinterDeployment.ps1](Create-PrinterDeployment.ps1) is a helper script that helps package the windows printer drivers and install scripts into a single InTune Win32 Package. The script will download the [InTune Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool), create the install, removal and detection commands, then package them all together and create a new intunewin file with the name of the new printer to be created.

1. The first step is to download a copy of the printer driver for the printer to be deployed. Extract the printer driver and place it in the appropriate subfolder under Package. See [Package Folder](#package-folder) for information on the required structure of the Package folder.
2. Using powershell, run the [Create-PrinterDeployment.ps1](Create-PrinterDeployment.ps1) script. See [Script Parameters](#script-parameters) for details on what parameters you need to be provided, or answer the prompts at run time.
3. Create a new Windows App in InTune.
    1. App type = Windows App (Win32)
    2. Select the *.intunewin file that the [Create-PrinterDeployment.ps1](Create-PrinterDeployment.ps1) script created
    3. Adjust the Name and Description to match the printer details
    4. Set the Publisher to the brand of printer
    5. Click Next
    6. Set the "Install Command" to install.cmd
    7. Set the "Uninstall Command" to remove.cmd
    8. Set "Allow available uninstall" to No
    9. Set "Install Behaviour" to System
    10. Click Next
    11. Set the Operating system requirements to match driver requirements.
    12. Click Next
    13. Set "Rules Format" to "Use Custom detection Script"
    14. Click the browse button and find the Detect-Printer.ps1 script that was generated.
    15. Click Next until the "Assignment" tab.
    16. Assign the App to the desired group or all devices.
    17. Click Next
    18. Click Create
4. The application package will be uploaded to InTune and pushed out to the devices it was assigned too.
5. To uninstall the printer, modify the app and remove the assigned and assign "Uninstall" to the required group of computers.



## Script Parameters
| Parameter | Description |
| --------- | ----------- |
| DriverName | This needs to be set to the exact printer [driver name that was found](#obtaining-the-printer-driver-name) in the inf file for the printer driver. |
| PrinterName | This is the name of the printer queue that will be created in windows. This is the printer name that users will know the printer as. |
| PrinterHostAddress | This is the IP address of FQDN of the printer. A TCP/IP printer port will be created that connects to this address |

## Package Folder
The Package folder contains the installation script and a subfolder for each of the supported architectures. For example, if the driver supported 32Bit, 64Bit and Arm64 then you would need to create a folder for each of these.

<pre>
├──Package
    ├── Deploy-Printer.ps1
    ├── 32bit
    ├── 64bit
    ├── arm64
</pre>

If the drive does not support a platform then simply not include the folder. If a system then tries to install the driver for that platform the script will fail.

## inf Files
The supplied printer driver needs to be in the form of a simply windows driver with an inf file and the required driver files. An executable or msi installer is not supported by this script.

## Obtaining the Printer Driver Name
The parameter DriverName for the [Create-PrinterDeployment.ps1](Create-PrinterDeployment.ps1) script can be obtained by opening the .inf file for the driver. Scrolling down throught the inf file to the "Model Sections" and look for the printer mode you need. You can simply copy the name from left hand side of the = sign. This is the name that the printer driver is referred to by windows.

