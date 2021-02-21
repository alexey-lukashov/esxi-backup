Write-Host $Args.length

$vmName,$esxiHost = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath).split('_')

& ./remote-launch-esxi-backup.ps1 "$vmName" "$esxiHost"





