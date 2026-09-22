<powershell>
# Windows Server Bootstrap Script
Start-Transcript -Path "C:\bootstrap.log" -Append

Write-Output "Starting Windows Server automated provisioning..."

# Set Timezone
Set-TimeZone -Id "UTC"

# Configure WinRM for remote management
Write-Output "Configuring WinRM..."
winrm quickconfig -q
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="1024"}'

# Open Windows Firewall ports for WinRM and RDP
netsh advfirewall firewall add rule name="WinRM 5985" dir=in action=allow protocol=TCP localport=5985
netsh advfirewall firewall add rule name="WinRM 5986" dir=in action=allow protocol=TCP localport=5986
netsh advfirewall firewall add rule name="RDP 3389" dir=in action=allow protocol=TCP localport=3389

# ==============================================================================
# Automated Secondary EBS Disk Initialization & Formatting
# Because Terraform attaches extra EBS volumes asynchronously after instance launch,
# we create a dedicated disk initializer script and run it as an active watcher
# ==============================================================================

$DiskInitScript = @'
# Set SAN policy so new EBS disks come online automatically
Set-StorageSetting -NewDiskPolicy OnlineAll

# Process all non-OS disks
Get-Disk | Where-Object { $_.Number -ne 0 } | ForEach-Object {
    $num = $_.Number
    $driveLetter = [char](68 + $num) # Disk 1 -> E:, Disk 2 -> F:, etc.
    
    # 1. Bring online if offline
    if ($_.IsOffline) {
        Write-Output "Bringing Disk $num online..."
        Set-Disk -Number $num -IsOffline $false
    }
    
    # 2. Clear read-only attribute if set
    if ($_.IsReadOnly) {
        Write-Output "Clearing read-only on Disk $num..."
        Set-Disk -Number $num -IsReadOnly $false
    }
    
    # 3. Initialize with GPT if raw
    if ($_.PartitionStyle -eq 'Raw') {
        Write-Output "Initializing Disk $num as GPT..."
        Initialize-Disk -Number $num -PartitionStyle GPT
    }
    
    # 4. Partition and format if no partitions exist yet
    $partitions = Get-Partition -DiskNumber $num -ErrorAction SilentlyContinue | Where-Object { $_.Type -ne 'Reserved' }
    if (-not $partitions) {
        Write-Output "Creating NTFS partition on Disk $num with drive letter $driveLetter..."
        New-Partition -DiskNumber $num -DriveLetter $driveLetter -UseMaximumSize |
            Format-Volume -FileSystem NTFS -NewFileSystemLabel "DataDisk-$num" -Confirm:$false
        Write-Output "Disk $num successfully mounted as $driveLetter`:"
    }
}
'@

# Save disk initializer script to C:\disk_init.ps1
Set-Content -Path "C:\disk_init.ps1" -Value $DiskInitScript -Force

# Execute immediately for any disk already present
& C:\disk_init.ps1

# Register a Scheduled Task to auto-mount disks on any reboot
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File C:\disk_init.ps1"
$Trigger = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -TaskName "AutoInitEBSDisks" -Action $Action -Trigger $Trigger -User "SYSTEM" -RunLevel Highest -Force

# Start a background watcher loop to catch volumes attached by Terraform shortly after boot
# Watches every 5 seconds for up to 5 minutes
Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -Command `"for (`$i=0; `$i -lt 60; `$i++) { & C:\disk_init.ps1; Start-Sleep -Seconds 5 }`"" -WindowStyle Hidden

Write-Output "Windows Server provisioning completed successfully."
Stop-Transcript
</powershell>
