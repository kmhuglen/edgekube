# Download Tools
If (Test-Path -Path ".\tools") {
    # Tools folder exist
} else {
    New-Item -ItemType Directory -Path tools
}
If (Test-Path -Path ".\tools\qemu-img-win-x64") {
    # qemu-img-win-x64 folder exist
} else {
    Invoke-WebRequest -UseBasicParsing -Uri https://cloudbase.it/downloads/qemu-img-win-x64-2_3_0.zip -OutFile tools\qemu-img-win-x64-2_3_0.zip
    Expand-Archive -Path tools\qemu-img-win-x64-2_3_0.zip -DestinationPath tools\qemu-img-win-x64
}
if (Test-Path -Path ".\tools\oscdimg.exe") {
    # oscdimg.exe exist
} else {
    Invoke-WebRequest -UseBasicParsing -Uri https://github.com/fdcastel/Hyper-V-Automation/raw/master/tools/oscdimg.exe -OutFile tools\oscdimg.exe
}
