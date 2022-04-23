New-Item -ItemType Directory -Path tools
Invoke-WebRequest -UseBasicParsing -Uri https://cloudbase.it/downloads/qemu-img-win-x64-2_3_0.zip -OutFile tools\qemu-img-win-x64-2_3_0.zip
Expand-Archive -Path tools\qemu-img-win-x64-2_3_0.zip -DestinationPath tools\qemu-img-win-x64
Invoke-WebRequest -UseBasicParsing -Uri https://github.com/fdcastel/Hyper-V-Automation/raw/master/tools/oscdimg.exe -OutFile tools\oscdimg.exe