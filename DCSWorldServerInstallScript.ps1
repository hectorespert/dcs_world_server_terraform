param($drive='C:')

Write-Host "Execution drive:" $drive

Write-Output "Downloading DCS World server installer"
Invoke-WebRequest https://www.digitalcombatsimulator.com/upload/iblock/937/DCS_World_OpenBeta_Server_web_5.exe -OutFile $drive\DCS_World_OpenBeta_Server.exe
