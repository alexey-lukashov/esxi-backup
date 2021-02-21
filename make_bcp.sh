#!/bin/sh

# amount of time to wait after attempt to start up a VM
vm_startup_wait=10s

# amount of time to wait after first attempt to shutdown a VM
vm_shutdown_wait_first=20s

# amount of time to wait after second and subsequent attempts to shutdown a VM
vm_shutdown_wait_after=30s

# amount of attempts to shutdown a VM gracefully
vm_shutdown_attempts=10

# current execution depth used for better logging visualisation
execution_depth=0

depth() {
  depth=$(awk "BEGIN {while (c++<$1) printf \"    \"}")
}

# params:
#  $1: method name
#  $2.. : parameters
# result:
#  reports about method execution respecting execution stack depth
executed() {
  name=$1
  shift;
  params=$@

  depth $execution_depth
  echo "[$(date)] [EXEC] $depth $name ( $params ) {"
  execution_depth=$(( execution_depth+1 ))
}

# params:
#  $1: method name
#  $2.. : results
# result:
#  reports about method completion respecting execution stack depth
completed() {
  name=$1
  shift;
  result=$@
  depth $execution_depth
  echo "[$(date)] [ RET] $depth return \"$result\""
  execution_depth=$(( execution_depth-1 ))
  depth $execution_depth
  echo "[$(date)] [    ] $depth }"
}

# params:
#  $1: method name
#  $2.. : messages
# result:
#  prints operation message respecting execution stack depth
operation() {
  name=$1
  shift;
  message=$@
  depth $execution_depth
  echo "[$(date)] [ MSG] $depth // $message"
}

# params:
#  $1: method name
#  $2.. : messages
# result:
#  prints operation error message respecting execution stack depth
error() {
  name=$1
  message=$2
  shift; shift;
  cause=$@
  echo "[$(date)] [ ERR] \"$message\" : $cause"
}

# params:
#  $1: method name
#  $2.. : messages
# result:
#  prints operation info message respecting execution stack depth
info() {
  name=$1
  message=$2
  shift; shift;
  extra=$@
  echo "[$(date)] [INFO] \"$message\" : $extra"
}

# params:
#   $1: string vm name
# result:
#   integer vm identifier
#   'Error'
vmId() {
  executed vmId $@
  vm=$( ( vim-cmd vmsvc/getallvms | grep $1 ) 2>&1 )
 
  vmName=$(echo $vm | awk '{print $2}')
  if [ "$vmName" = "$1" ]; then
    operation vmId "Virtual machine $1 was succesfully found"
    
    vmDatastore=$(echo $vm | awk 'match($3,/\[.*\]/) {print substr($3,RSTART+1,RLENGTH-2)}' )
    vmVmx=$(echo $vm | awk '{print $4}')
    vmOs=$(echo $vm | awk '{print $5}')
    vmVmxId=$(echo $vm | awk '{print $6}')
    vmVmxPath="/vmfs/volumes/${vmDatastore}/${vmVmx}"
    vmPath=$( echo $vmVmxPath | awk 'match($0,/.*\//) {print substr($0,RSTART,RLENGTH)}' )
    operation vmId "$1 datastore : $vmDatastore"
    operation vmId "$1 vmx : $vmVmx"
    operation vmId "$1 os : $vmOs"
    operation vmId "$1 vmxId : $vmVmxId"          
    operation vmVmxPath "$1 vmx path : $vmVmxPath"
    operation vmPath "$1 vm path : $vmPath"


	vmId=$(echo $vm | awk '{print $1}')
    operation vmId "Virtual machine $1 identifier is $vmId"
  else
    error vmId "Can not find virtual machine by name $1" $vm
	vmId="Error"
  fi
  
  completed vmId $vmId
}

# params:
#   $1: integer vm identifier
# result:
#   'Powered on'
#   'Powered off'
#   'Error'
vmState() {
  executed vmState $@
  vmState=$( ( vim-cmd vmsvc/power.getstate $1 | grep 'Powered' ) 2>&1 )
  if [ "$vmState" = "Powered on" ]; then
    operation vmState "Virtual machine $1 is on"
  elif [ "$vmState" = "Powered off" ]; then
    operation vmState "Virtual machine $1 is off"
  else
    error vmState "Can not detect state of virtual machine $1" $vmState 
    vmState="Error"
  fi
  completed vmState $vmState
}

# params:
#   $1: vm name
#   $2: integer vm identifier
# result:
#   'Powered on'
#   'Powered off'
vmShutdown() {
  executed vmShutdown $@
  vmName=$1
  vmId=$2

  vmState $vmId
  nShutdownAttempt=1
  while [ "$vmState" = "Powered on" ] && [ $nShutdownAttempt -le $vm_shutdown_attempts ]
  do
    operation vmShutdown "Attempt #$nShutdownAttempt to shutdown virtual machine $vmName"

    shutdown=$( ( vim-cmd vmsvc/power.shutdown $vmId ) 2>&1 )
	info vmShutdown "Virtual machine $vmName was attempted to shutdown" $shutdown 
	
    if [ $nShutdownAttempt -eq 1 ]; then
	  operation vmShutdown "Wait $vm_shutdown_wait_first for $vmName shuts down"
      sleep $vm_shutdown_wait_first
    else
	  operation vmShutdown "Wait $vm_shutdown_wait_after for $vmName shuts down"
      sleep $vm_shutdown_wait_after
    fi
    vmState $vmId
    nShutdownAttempt=$(( nShutdownAttempt+1 ))
  done
  
  if [ "$vmState" = "Powered off" ]; then
    operation vmShutdown "Virtual machine $vmName is off" 
  else
    operation vmShutdown "Virtual machine shutdown failed" 
  fi
  
  vmShutdown=$vmState
  completed vmShutdown $vmShutdown
}

# params:
#   $1: vm name
#   $2: integer vm identifier
# result:
#   'Powered on'
#   'Powered off'
vmStartup() {
  executed vmStartup $@
  vmName=$1
  vmId=$2
    
  vmState $vmId
  
  if [ "$vmState" = "Powered off" ]; then
    operation vmStartup "Virtual machine $vmName is off"

    startup=$( ( vim-cmd vmsvc/power.on $vmId ) 2>&1 )

    info vmStartup "Virtual machine $vmName was attempted to startup" $startup

    operation vmStartup "Wait $vm_startup_wait for $vmName starts up"

    sleep $vm_startup_wait

    vmState $vmId
  fi

  if [ "$vmState" = "Powered on" ]; then
    operation vmShutdown "Virtual machine $vmName is on" 
  else
    operation vmShutdown "Virtual machine startup failed" 
  fi
  
  vmStartup=$vmState  
  completed vmStartup $vmStartup
}

# params:
#   $1: vm name
#   $2: integer vm identifier
#   $3: absolute bcp path
#   $4: backup datastore name
#   $5: backup date in format compartible with folder name "+%Y-%m-%d_%H-%M-%S"
# result:
#   'ok'
#   'Error'
disksBackup() {
  executed disksBackup $@
  vmName=$1
  vmId=$2
  bcpPath=$3
  bcpDatastore=$4
  bcpDate=$5

  vmState $vmId

  disksBackup="Error"

  bcpPath=$( echo $bcpPath | sed -e "s/{bcpDatastore}/$bcpDatastore/g" )
  bcpPath=$( echo $bcpPath | sed -e "s/{vmName}/$vmName/g" )
  bcpPath=$( echo $bcpPath | sed -e "s/{bcpDate}/$bcpDate/g" )
  bcpPath=$( echo $bcpPath | sed -e "s/{vmPath}/$vmPath/g" )

  if [ "$vmState" = "Powered off" ]; then
    operation disksBackup "Virtual machine $vmName is off, ready for backup" 
  
    cd $vmPath
    cat $vmVmxPath | grep fileName | grep .vmdk | awk 'match($3,/".*?"/) {print substr($3,RSTART+1,RLENGTH-2)}' | while IFS= read -r disk ; do {

      diskBcpPath=$bcpPath

      operation disksBackup "Check disk $disk"
      diskName=$( echo $disk | awk 'match($0,/.*\//) {print substr($0,RLENGTH+1); exit;} {print $0;}' | awk 'match($0,/-[0-9]+\.vmdk/) {print substr($0,0,RSTART-1); exit; } match($0,/\.vmdk/) {print substr($0,0,RSTART-1); exit; } {print $0;}' )  
      operation disksBackup "Resolved disk name $diskName"  

      operation disksBackup "Check $disk of virtual machine $vmName" 
      checkDisk=$( ( vmkfstools -x check "$disk" ) 2>&1 )

      operation disksBackup "Check consistency of $disk of virtual machine $vmName" 
      consistDisk=$( ( vmkfstools -e "$disk" ) 2>&1 )

      disk_errors=0

      if [ "$checkDisk" = "Disk is error free" ]; then
        info disksBackup "Disk $disk of virtual machine $vmName check OK" $checkDisk
      else
        error disksBackup "Disk $disk of virtual machine $vmName check FAILED" $checkDisk
        disk_errors=$(( disk_errors+1 ))
      fi

      if [ "$consistDisk" = "Disk chain is consistent." ]; then
        info disksBackup "Disk $disk of virtual machine $vmName consistency check OK" $consistDisk
      else
        error disksBackup "Disk $disk of virtual machine $vmName consistency check FAILED" $consistDisk
        disk_errors=$(( disk_errors+1 ))
      fi

      if [ "$disk_errors" = "0" ]; then
        info disksBackup "Disk $disk of virtual machine $vmName has no errors, ready for backup"

        mkdir -p "$diskBcpPath"
        operation disksBackup "Starting backup of $disk of virtual machine $vmName to ${$diskBcpPath}/${diskName}.vmdk"

#        diskClone=$( ( vmkfstools -i "$disk" "${$diskBcpPath}/${diskName}.vmdk" -d thin ) 2>&1 )

        info disksBackup "Disk $disk of virtual machine $vmName clone finished" $diskClone
      fi  
    }
    done

    disksBackup="ok"
  fi
  
  completed disksBackup $disksBackup
}

# params:
#   $1: vm name
#   $2: backup datastore name
#   $3: backup path with placholders {bcpDatastore} {vmName} {bcpDate}
#   $4: backup date in format compartible with folder name "+%Y-%m-%d_%H-%M-%S"
#   $5: amount of backups for this vm to keep
# result:
#   'ok'
#   'Error'
vmBackup() {
  executed vmBackup $@

  vmName=$1
  bcpDatastore=$2
  bcpPath=$3
  bcpDate=$4

  vmBackup='Error'

  vmId $vmName
 
  vmShutdown $vmName $vmId

  disksBackup $vmName $vmId $bcpPath $bcpDatastore $bcpDate

  vmStartup $vmName $vmId

  if [ "$vmShutdown" = "Powered off" ]; then
    if [ "$disksBackup" = "ok" ]; then
      #if [ "$vmStartup" = "Powered on" ]; then
      vmBackup='ok'
      #fi
    fi
  fi

  completed vmBackup $vmBackup
 
}

# params:
#   $1: vm name
#   $2: backup datastore name
#   $3: backup path with placeholders {bcpDatastore} {vmName} {bcpDate}
#   $4: backup date in format compartible with folder name "+%Y-%m-%d_%H-%M-%S"
#   $5: backup path for control of amount of backups, supports placeholders {bcpDatastore} {vmName} {bcpDate}
#   $6: amount of backups for this vm to keep
# result:
#   'ok'
#   'Error'
vmBackupControlPopulation() {
  executed vmBackupControlPopulation $@

  vmName=$1
  bcpDatastore=$2
  bcpPath=$3
  bcpDate=$4
  bcpControlPath=$5
  keepBackupsN=$6

  vmBackup $vmName $bcpDatastore $bcpPath $bcpDate

  vmBackupControlPopulation='Error'
  if [ "$vmBackup" = "ok" ]; then
      operation vmBackupControlPopulation "Backup flow for $vmName successfully completed, removing backups"
      ls -dt /vmfs/volumes/data/backups/$vmName/* | tail -n +$(( keepBackupsN+1 )) | xargs rm -rf
      vmBackupControlPopulation='ok'
  fi

  completed vmBackupControlPopulation $vmBackupControlPopulation
}

# params:
#   $1: vm name
#   $2: backup datastore name
#   $3: backup path with placeholders {bcpDatastore} {vmName} {bcpDate}
#   $4: backup date in format compartible with folder name "+%Y-%m-%d_%H-%M-%S"
#   $5: backup path for control of amount of backups, supports placeholders {bcpDatastore} {vmName} {bcpDate}
#   $6: amount of backups for this vm to keep

#nohup /vmfs/volumes/data/backups/make_bcp.sh "eusap-ts" "data" "/vmfs/volumes/{bcpDatastore}/backups/{vmName}/{bcpDate}" "$(date +%Y-%m-%d_%H-%M-%S)" "/vmfs/volumes/{bcpDatastore}/backups/$vmName/*" 2 > "./eusap-ts-$(date +%Y-%m-%d_%H-%M-%S).txt" &
#nohup /vmfs/volumes/data/backups/make_bcp.sh "fincom.server" "data" "/vmfs/volumes/{bcpDatastore}/backups/{vmName}/{bcpDate}" "$(date +%Y-%m-%d_%H-%M-%S)" "/vmfs/volumes/{bcpDatastore}/backups/$vmName/*" 2 > "./fincom-server-$(date +%Y-%m-%d_%H-%M-%S).txt" &
vmBackupControlPopulation"$1" "$2" "$3" "$4" "$5" "$6"

