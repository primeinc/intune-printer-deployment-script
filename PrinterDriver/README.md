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