
function pscp {
  param( $sshHost, $credentials, $localFile, $remoteFile )
  $app = $(get-location).Path+"\pscp.exe"
  $options = " -pw $($credentials.GetNetworkCredential().Password) " + $localFile
  $output = $app + $options + " " + $credentials.UserName + "@" + $sshHost + ":" + $remoteFile
  Invoke-Expression -command $output
}

function plink {
  param( $sshHost, $credentials, $cmd, $esxiFingerPrint )
  $userName = $credentials.UserName
  $app = $(get-location).Path+"\plink.exe"
  $options = " -v -batch -pw $($credentials.GetNetworkCredential().Password)"
  Start-Process -FilePath $app -ArgumentList "-hostkey `"${esxiFingerPrint}`" $options ${userName}@${sshHost} `"$cmd`"" -Wait
}                                                                                          

function Credentials {
  param( $description, $user )
  Write-Host "Take credentials for $description"
  return (Get-Credential -Message "Credentials for $description" -UserName $user)
}

function ConnectEsxi {
  param( $esxiHost, $esxiPort, $esxiCredentials )
  Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -InvalidCertificateAction ignore -Confirm:$false
  Set-PowerCLIConfiguration -Scope Session -InvalidCertificateAction ignore -Confirm:$false

  Write-Host "Connect ESXI"
  return Connect-VIServer -Credential $esxiCredentials -Server $esxiHost -Port $esxiPort
}

function esxiInfo {
  $ds = Get-Datastore
  $vms = Get-VM
  Write-Host " *** Datastores ***"
  foreach ($d in $ds) {
    Write-Host "[$($d.Name)] $([math]::Round($d.FreeSpaceGB,0))/$([math]::Round($d.CapacityGB,0)) GB"
  }
  Write-Host " *** Virtual Machines ***"
  foreach ($vm in $vms) {
    Write-Host "$($vm.Name)"
    $vmdks = $vm | Get-HardDisk
    foreach ($vmdk in $vmdks) {
      Write-Host "  $($vmdk.Filename)"
    }
  }
}

Import-Module VMware.VimAutomation.Core

### INPUT ####
#
# argument 1 : virtiual machine na,e
# argumen=t 2 : esxi host address

$vmName=$Args[0]
$esxiHost=$Args[1]
$esxiFingerPrint=$Args[2]

$backupsPath="data/backups"
$backupVmPath="{vmName}/{bcpDate}"
#############################################################

$bcpDatastore=$backupsPath.Substring(0, $backupsPath.IndexOf("/"))

$nVmBackups=2

$vmPathDate=(Get-Date).tostring("yyyy-MM-dd_hh-mm-ss")

$credentials = Credentials -user "root" -description "ESXI"
$esxi = ConnectEsxi -esxiHost $esxiHost -esxiPort "443" -esxiCredentials $credentials

esxiInfo

# enable ssh
Get-VMHostService  | Where-Object {$_.Key -eq "TSM-SSH"}  | Start-VMHostService -Confirm:$false

#pscp $esxiHost $credentials "./esxi-backup.sh" "{backups}/esxi-backup-{date}.sh"
$plinkCmd = "cd /vmfs/volumes/$backupsPath; nohup /vmfs/volumes/$backupsPath/make_bcp.sh '$vmName' '$bcpDatastore' '/vmfs/volumes/$backupsPath/$backupVmPath' '$vmPathDate' $nVmBackups > '/vmfs/volumes/$backupsPath/$vmName-$vmPathDate.txt' &"
plink $esxiHost $credentials $plinkCmd $esxiFingerPrint

# disable ssh
Get-VMHostService  | Where-Object {$_.Key -eq "TSM-SSH"}  | Stop-VMHostService -Confirm:$false

Disconnect-VIServer -Confirm:$false
