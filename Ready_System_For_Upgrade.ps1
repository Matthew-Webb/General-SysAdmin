param(
  [Parameter(Mandatory=$true, HelpMessage="Specify the target environment. Train, UAT, Prod, or QA.")]
  [ValidateSet('Train', 'UAT', 'QA', 'Prod')]
  [string]$Environment,

  [Parameter(Mandatory=$true, HelpMessage="Specify the action to perform. Start(services), Stop(services), Create(snapshot), or Remove(snapshot).")]
  [ValidateSet('Start', 'Stop', 'Create', 'Remove')]
  [string]$Action,

  [Parameter(Mandatory=$false, HelpMessage="Credentials to connect to vCenter and domain.")]
  [System.Management.Automation.PSCredential]$Credential
)

$EnvironmentConfig = @{
  'UAT' = @{
    'SERVERROLE1' = @{ Servers = @("SERVERNAME","SERVERNAME") };
    'SERVERROLE2' = @{ Servers = @("SERVERNAME","SERVERNAME"); Services = @("SERVICENAME","SERVICENAME") };
    'SERVERROLE3' = @{ Servers = @("SERVERNAME"); Services = @("SERVICENAME","SERVICENAME","SERVICENAME") };
    'SERVERROLE4' = @{ Servers = @("SERVERNAME"); Services = @("SERVICENAME") };
    'SERVERROLE5' = @{ Servers= @("SERVERNAME","SERVERNAME")};
  };
  'Train' = @{
    'SERVERROLE1' = @{ Servers = @("D2DNAAPI01T") };
    'SERVERROLE2' = @{ Servers = @("D2DNACRM02I"); Services = @("SERVICENAME","SERVICENAME","SERVICENAME") };
    'SERVERROLE3' = @{ Servers= @("D2DNASAF01T")};
  };
  'QA' = @{
    'SERVERROLE1' = @{ Servers = @("SERVERNAME") };
    'SERVERROLE2' = @{ Servers = @("SERVERNAME","SERVERNAME"); Services = @("SERVICENAME","SERVICENAME") };
    'SERVERROLE3' = @{ Servers = @("SERVERNAME"); Services = @("SERVICENAME","SERVICENAME","SERVICENAME") };
    'SERVERROLE4' = @{ Servers= @("SERVERNAME")};
  };
  'Prod' = @{
    'SERVERROLE1' = @{ Servers = @("SERVERNAME","SERVERNAME") };
    'SERVERROLE2' = @{ Servers = @("SERVERNAME","SERVERNAME"); Services = @("SERVICENAME","SERVICENAME") };
    'SERVERROLE3' = @{ Servers = @("SERVERNAME"); Services = @("SERVICENAME","SERVICENAME","SERVICENAME") };
    'SERVERROLE4' = @{ Servers = @("SERVERNAME","SERVERNAME"); Services = @("SERVICENAME") };
    'SERVERROLE5' = @{ Servers= @("SERVERNAME","SERVERNAME","SERVERNAME")};
  };
}

function Start-Service {
  param(
    [string]$Server,
    [string]$Service
  )
  Write-Host "Starting $Service service on server $Server" -ForegroundColor Green
  try {
    Invoke-Command -ComputerName $Server -ScriptBlock {
      param($Service)
      $svc = Get-Service -Name $Service -ErrorAction Stop
      Start-Service -InputObject $svc # -whatif ## Uncomment the "-whatif" if testing is needed
    } -ArgumentList $Service
  }
  catch {
    Write-Warning "Failed to start service '$Service' on server '$Server'. Error: $($_.Exception.Message)"
  }
}

function Stop-Service {
  param(
    [string]$Server,
    [string]$Service
  )
  Write-Host "Stopping $Service service on server $Server" -ForegroundColor Yellow
  try {
    Invoke-Command -ComputerName $Server -ScriptBlock {
      param($Service)
      $svc = Get-Service -Name $Service -ErrorAction Stop
      Stop-Service -InputObject $svc # -whatif ## Uncomment the "-whatif" if testing is needed
    } -ArgumentList $Service
  }
  catch {
      Write-Warning "Failed to stop service '$Service' on server '$Server'. Error: $($_.Exception.Message)"
  }
}

function New-vSphereSnapshot {
  param(
    [array]$ServerList
  )
  Connect-VIServer <VSPHERESERVER -Credential $credentials
  $VmInventory = @()
  foreach ($Server in $ServerList) {
    $VmInventory += Get-VM | where 'Name' -match $Server
  }
  foreach ($Vm in $VmInventory) {
      Write-Host "Creating snapshot for '$vm'..." -ForegroundColor Green
      New-Snapshot -VM $vm -Name 'Upgrade Snapshot' -Description 'This snapshot was taken automatically as system is being upgraded' -RunAsync
  }
}

function Remove-vSphereSnapshot {
  param(
    [array]$ServerList
  )
  Connect-VIServer <VSPHERESERVER> -Credential $credentials
  $VmInventory = @()
  foreach ($Server in $ServerList) {
    $VmInventory += Get-VM | where 'Name' -match $Server
  }
  foreach ($Vm in $VmInventory) {
      $snapshotRemove = Get-Snapshot $Vm | where 'Name' -match "Upgrade Snapshot"
      Write-Host "Deleting snapshot $snapshotRemove for '$vm'..." -ForegroundColor Yellow
      $snapshotRemove | Remove-Snapshot -Confirm:$false -RunAsync
  }
}  

##########################
#####  SCRIPT START  #####
##########################
if ( -not $(Get-Module -ListAvailable -Name "vmware.powercli")) {
    Write-Output "Required vSphere modules not installed`nDownloading and configuring`nPlease allow ~10min for download..." -ForegroundColor Yellow
    Install-Module VMware.PowerCLI
    Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -InvalidCertificateAction Ignore -Confirm:$false
}
if (-not $PSBoundParameters.ContainsKey('Credential')) {
  $credentials = Get-Credential -message "Enter your credentials ie..FirstLast@land*.com"
} else {
  $credentials = $Credential
}
#Extract creds from popup
$username = $credentials.username
$Password = $credentials.GetNetworkCredential().password

# Get current domain using logged-on user's credentials
$CurrentDomain = "LDAP://" + ([ADSI]"").distinguishedName
$domain = New-Object System.DirectoryServices.DirectoryEntry($CurrentDomain,$username,$Password)
$DomainName = $domain.Name
if (-not $DomainName) {
  write-host "Authentication failed - please verify your username and password and rerun the script." -ForegroundColor Yellow
  exit
}
else {
  write-host "Successfully authenticated with domain $DomainName" -ForegroundColor Green
  
  $Config = $EnvironmentConfig[$Environment]
  if (-not $Config) {
      Write-Error "Configuration for environment '$Environment' not found."
      exit
  }
  switch ($Action) {
    "Start" {
      $ServerRoles = $Config.Keys
      foreach ($Role in $ServerRoles) {
        $RoleConfig = $Config[$Role]
        foreach ($Server in $RoleConfig.Servers) {
          foreach ($Service in $RoleConfig.Services) {
            Start-Service -Server $Server -Service $Service
          }
        }
      }
    }
    "Stop" {
      $ServerRoles = $Config.Keys
      foreach ($Role in $ServerRoles) {
        $RoleConfig = $Config[$Role]
        foreach ($Server in $RoleConfig.Servers) {
          foreach ($Service in $RoleConfig.Services) {
            Stop-Service -Server $Server -Service $Service
          }
        }
      }
    }
    "Create" {
      $ServerList = @()
      $ServerRoles = $Config.Keys
      foreach ($Role in $ServerRoles) {
        $ServerList += $Config[$Role].Servers
      }
      New-vSphereSnapshot -ServerList $ServerList
    }
    "Remove" {
      $ServerList = @()
      $ServerRoles = $Config.Keys
      foreach ($Role in $ServerRoles) {
        $ServerList += $Config[$Role].Servers
      }
      Remove-vSphereSnapshot -ServerList $ServerList
    }
  }
}
if ($Action -eq 'stop') {
  #Next step popup 
  Write-Warning "Call vendor before proceeding!!!"
  Read-Host "Press Enter to close..."
  exit
}
else {
  Read-Host "Press Enter to close..."
  exit
}
