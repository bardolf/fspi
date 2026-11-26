# First logon of the VMware Windows 11 VM. Log: C:\Windows\Temp\vm-setup.log
Start-Transcript -Path C:\Windows\Temp\vm-setup.log -Append

# VMware Tools: the SVGA 3D driver (DirectX 11 for Fusion), shared folders, clipboard, resizing.
# The Windows ISO has a setup.exe at its root too, hence the ProductName check.
$tools = Get-PSDrive -PSProvider FileSystem |
  ForEach-Object { Join-Path $_.Root 'setup.exe' } |
  Where-Object { (Test-Path $_) -and ((Get-Item $_).VersionInfo.ProductName -like '*VMware Tools*') } |
  Select-Object -First 1
if ($tools) {
  Write-Output "Installing VMware Tools from $tools"
  Start-Process $tools -ArgumentList '/S /v "/qn REBOOT=R ADDLOCAL=ALL"' -Wait
} else {
  Write-Output 'VMware Tools ISO not found'
}

powercfg /change monitor-timeout-ac 0
powercfg /change standby-timeout-ac 0

# Autodesk Fusion through the same direct link the Fusion web page offers.
$fusion = 'C:\Users\Public\Downloads\FusionAdminInstall.exe'
curl.exe -L --retry 3 -o $fusion 'https://dl.appstreaming.autodesk.com/production/installers/Fusion%20Admin%20Install.exe'
if (Test-Path $fusion) {
  Write-Output 'Installing Autodesk Fusion'
  Start-Process $fusion -ArgumentList '--quiet' -Wait
}

Stop-Transcript
Restart-Computer -Force
