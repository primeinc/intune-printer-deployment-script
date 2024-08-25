# PrinterDriver Folder
The PrinterDriver folder must contain a folder for each of the supported architectures. For example, if the driver supported 32Bit, 64Bit and Arm64 then you would need to create a folder for each of these.

<pre>
├──PrinterDriver
    ├── 32bit
    ├── 64bit
    ├── arm64
</pre>

If the drive does not support a platform then simply not include the folder.

## inf File
The supplied printer driver needs to be in the form of a simply windows driver with an inf file and the required driver files. An executable or msi installer is not supported by this script.

## Obtaining the Printer Driver Name
The parameter DriverName for the [Install-Printer.ps1](Install-Printer.ps1) script can be obtained by opening the .inf file, scrolling down to the "Model Sections" and looking for the printer mode you need. You can simply copy the name from left hand side of the = sign. This is the name that the printer driver is referred to by windows.
