<#
_author_ = Texas Roemer <Texas_Roemer@Dell.com>
_version_ = 3.0

Copyright (c) 2021, Dell, Inc.

This software is licensed to you under the GNU General Public License,
version 2 (GPLv2). There is NO WARRANTY for this software, express or
implied, including the implied warranties of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. You should have received a copy of GPLv2
along with this software; if not, see
http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt
#>

<#
.Synopsis
   iDRAC cmdlet using Redfish API to either get current BIOS boot mode/boot order, enable or disable boot order devices. 
.DESCRIPTION
   iDRAC cmdlet using Redfish API to either get current BIOS boot mode/boot order, enable or disable boot order devices. 
   - idrac_ip: Pass in the iDRAC IP address
   - idrac_username: Pass in the iDRAC user name
   - idrac_password: Pass in the iDRC user name password
   - x_auth_token: Pass in iDRAC X-Auth token session to execute cmdlet instead of username / password (recommended)
   - view_bios_boot_order_only: Get current BIOS boot mode and boot order.
   - enable_disable_boot_devices: Pass in this argument to enable or disable boot devices. Argument "filepath" is also required when enabling/disabling boot devices. Before running the cmdlet, make sure to modify the file you generated containing the boot order. To enable a boot order device, set "Enabled" as true. To disable a boot order device, set "Enabled" to false.  
   - filepath: Pass in the complete filepath including the name of the file containing the boot order. To generate this file, pass in this argument along with view_bios_boot_order_only argument. NOTE: This file is needed to enable/disable boot order devices and when generating the file, pass in any string value 
   - reboot_server: Reboot the server to execute BIOS config job. Pass in "y" to reboot the server now or "n" not to reboot the server. If you select to not reboot the server now, config job is still marked as scheduled and will execute on next server manual reboot
.EXAMPLE
   Invoke-EnableDisableBiosBootOrderDevicesREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -view_boot_order_boot_source_state_only  
   This example will return current BIOS boot mode and the boot order. 
.EXAMPLE
   Invoke-EnableDisableBiosBootOrderDevicesREDFISH -idrac_ip 192.168.0.120 -view_boot_order_boot_source_state_only -filepath C:\Users\administrator\Downloads\boot_order.txt
   This example will first prompt for iDRAC username and password using Get-Credentials, return current BIOS boot mode/boot order and then generate the boot order file needed for enabling/disabling boot order devices. 
.EXAMPLE
   Invoke-EnableDisableBiosBootOrderDevicesREDFISH -idrac_ip 192.168.0.120 -view_boot_order_boot_source_state_only -x_auth_token 7bd9bb9a8727ec366a9cef5bc83b2708
   This example will return current BIOS boot mode and the boot order using iDRAC X-auth token session. 
.EXAMPLE
   Invoke-EnableDisableBiosBootOrderDevicesREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -enable_disable_boot_devices -filepath C:\Users\Texas_Roemer\Downloads\boot_order.txt -reboot_server n
   This example will read file "C:\Users\Texas_Roemer\Downloads\boot_order.txt" to set boot order devices to enable or disable state depending on file settings for those boot order devices. Job ID will get scheduled but server will not auto reboot. 
.EXAMPLE
   Invoke-EnableDisableBiosBootOrderDevicesREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -enable_disable_boot_devices -filepath C:\Users\Texas_Roemer\Downloads\boot_order.txt -reboot_server y
   This example will read file "C:\Users\Texas_Roemer\Downloads\boot_order.txt" to set boot order devices to enable or disable state depending on file settings for those boot order devices. Job ID will get scheduled  and auto reboot now to apply the changes.
#>

function Invoke-EnableDisableBiosBootOrderDevicesREDFISH {

param(
    [Parameter(Mandatory=$True)]
    [string]$idrac_ip,
    [Parameter(Mandatory=$False)]
    [string]$idrac_username,
    [Parameter(Mandatory=$False)]
    [string]$idrac_password,
    [Parameter(Mandatory=$False)]
    [string]$x_auth_token,
    [Parameter(Mandatory=$False)]
    [switch]$view_bios_boot_order_only,
    [Parameter(Mandatory=$False)]
    [switch]$enable_disable_boot_devices,
    [Parameter(Mandatory=$False)]
    [string]$filepath,
    [ValidateSet("y", "n")]
    [Parameter(Mandatory=$False)]
    [string]$reboot_server
    )

# Function to ignore SSL certs

function Ignore-SSLCertificates
{
    $Provider = New-Object Microsoft.CSharp.CSharpCodeProvider
    $Compiler = $Provider.CreateCompiler()
    $Params = New-Object System.CodeDom.Compiler.CompilerParameters
    $Params.GenerateExecutable = $false
    $Params.GenerateInMemory = $true
    $Params.IncludeDebugInformation = $false
    $Params.ReferencedAssemblies.Add("System.DLL") > $null
    $TASource=@'
        namespace Local.ToolkitExtensions.Net.CertificatePolicy
        {
            public class TrustAll : System.Net.ICertificatePolicy
            {
                public bool CheckValidationResult(System.Net.ServicePoint sp,System.Security.Cryptography.X509Certificates.X509Certificate cert, System.Net.WebRequest req, int problem)
                {
                    return true;
                }
            }
        }
'@ 
    $TAResults=$Provider.CompileAssemblyFromSource($Params,$TASource)
    $TAAssembly=$TAResults.CompiledAssembly
    $TrustAll = $TAAssembly.CreateInstance("Local.ToolkitExtensions.Net.CertificatePolicy.TrustAll")
    [System.Net.ServicePointManager]::CertificatePolicy = $TrustAll
}

# Function to get Powershell version

function get_powershell_version 
{
$get_host_info = Get-Host
$major_number = $get_host_info.Version.Major
$global:get_powershell_version = $major_number
}

get_powershell_version

function setup_idrac_creds
{

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::TLS12

if ($x_auth_token)
{
$global:x_auth_token = $x_auth_token
}
elseif ($idrac_username -and $idrac_password)
{
$user = $idrac_username
$pass= $idrac_password
$secpasswd = ConvertTo-SecureString $pass -AsPlainText -Force
$global:credential = New-Object System.Management.Automation.PSCredential($user, $secpasswd)
}
else
{
$get_creds = Get-Credential
$global:credential = New-Object System.Management.Automation.PSCredential($get_creds.UserName, $get_creds.Password)
}
}

setup_idrac_creds

if ($view_bios_boot_order_only)
{

$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Bios"
if ($x_auth_token)
{
 try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
    }
    }
    catch
    {
    $RespErr
    return
    }
}

else
{
    try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    }
    catch
    {
    $RespErr
    return
    }
}

if ($result.StatusCode -eq 200)
{
    #[String]::Format("`n- PASS, statuscode {0} returned successfully get current boot mode",$result.StatusCode)
}
else
{
    [String]::Format("`n- FAIL, statuscode {0} returned",$result.StatusCode)
    return
}

$get_all_attributes=$result.Content | ConvertFrom-Json | Select Attributes
$get_boot_mode_attribute= $get_all_attributes.Attributes | Select BootMode
$current_boot_mode=$get_boot_mode_attribute.BootMode

$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Oem/Dell/DellBootSources"
if ($x_auth_token)
{
 try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
    }
    }
    catch
    {
    $RespErr
    return
    }
}

else
{
    try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    }
    catch
    {
    $RespErr
    return
    }
}

if ($result.StatusCode -eq 200)
{
    #[String]::Format("- PASS, statuscode {0} returned successfully to get boot order devices and boot source state",$result.StatusCode)
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result.StatusCode)
    return
}

Write-Host "`n- Current $current_boot_mode boot order -`n"
$get_output=$result.Content | ConvertFrom-Json
if ($current_boot_mode -eq "Uefi")
{
$boot_seq = $get_output.Attributes.UefiBootSeq
$create_json = @{"Attributes"=@{"UefiBootSeq"=@()}}
$create_json["Attributes"]["UefiBootSeq"] += $boot_seq 
$create_json = $create_json | ConvertTo-Json -Depth 20 -Compress
}
elseif ($current_boot_mode -eq "Bios")
{
$boot_seq = $get_output.Attributes.BootSeq
$create_json = @{"Attributes"=@{"BootSeq"=@()}}
$create_json["Attributes"]["BootSeq"] += $boot_seq 
$create_json = $create_json | ConvertTo-Json -Depth 20 -Compress
}

$boot_seq

if ($filepath)
{
if (Test-Path $filepath -PathType Leaf)
{
Remove-Item $filepath
}

$create_json | Out-String | Add-Content $filepath
}

return
}


if ($enable_disable_boot_devices)
{

$JsonBody = Get-Content $filepath

$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Oem/Dell/DellBootSources/Settings"
if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Method Patch -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -UseBasicParsing -Uri $uri -Method Patch -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    return
    } 
}


else
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Credential $credential -Method Patch -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -UseBasicParsing -Uri $uri -Credential $credential -Method Patch -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    return
    } 
}

if ($result.StatusCode -eq 200)
{
    [String]::Format("`n- PASS, statuscode {0} returned successfully to set pending value(s)",$result.StatusCode)
    
    
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result.StatusCode)
    return
}


$JsonBody = @{ "TargetSettingsURI" ="/redfish/v1/Systems/System.Embedded.1/Bios/Settings"
    } | ConvertTo-Json -Compress


$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/Jobs"
if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    Write-Host "`n- INFO, if no pending data present error returned, check to make sure you're not enabling/disabling devices which are already enabled/disabled."
    return
    } 
}


else
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Credential $credential -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Credential $credential -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    return
    } 
}
$raw_output = $result1.RawContent | ConvertTo-Json -Compress
$job_search = [regex]::Match($raw_output, "JID_.+?r").captures.groups[0].value
$job_id=$job_search.Replace("\r","")
Start-Sleep 3
if ($result1.StatusCode -eq 200)
{
    [String]::Format("- PASS, statuscode {0} returned to successfully create job: {1}",$result1.StatusCode,$job_id)
    Start-Sleep 10
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result1.StatusCode)
    return
}

$uri ="https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/Jobs/$job_id" 
if ($x_auth_token)
{
 try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
    }
    }
    catch
    {
    $RespErr
    return
    }
}

else
{
    try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    }
    catch
    {
    $RespErr
    return
    }
}
$overall_job_output=$result.Content | ConvertFrom-Json

if ($overall_job_output.JobState -eq "Scheduled")
{
[String]::Format("- PASS, {0} job ID marked as scheduled",$job_id)
}
else 
{
Write-Host
[String]::Format("- FAIL, {0} job ID not marked as scheduled",$job_id)
[String]::Format("- Extended error details: {0}",$overall_job_output)
return
}

if ($reboot_server.ToLower() -eq "n")
{
Write-Host "`n- INFO, user selected to not reboot the server now. Job ID is still scheduled and will execute on next server reboot."
return
}
elseif ($reboot_server.ToLower() -eq "y")
{
Write-Host "- INFO, rebooting the server now to apply the configuration changes"
}
else
{
Write-Host "`n- INFO, either reboot argument not passed in or incorrect argument value passed in. Job ID is still scheduled and will execute on next server reboot."
return
}

$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1"
if ($x_auth_token)
{
 try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
    }
    }
    catch
    {
    $RespErr
    return
    }
}

else
{
    try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    }
    catch
    {
    $RespErr
    return
    }
}
$get_content = $result.Content | ConvertFrom-Json
$host_power_state = $get_content.PowerState

if ($host_power_state -eq "On")
{
Write-Host "- WARNING, server power state ON, performing graceful shutdown"
$JsonBody = @{ "ResetType" = "GracefulShutdown" } | ConvertTo-Json -Compress


$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Actions/ComputerSystem.Reset"
    if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    return
    } 
}


else
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Credential $credential -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Credential $credential -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    return
    } 
}

if ($result1.StatusCode -eq 204)
{
    [String]::Format("- PASS, statuscode {0} returned to gracefully shutdown the server",$result1.StatusCode)
    Start-Sleep 15
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result1.StatusCode)
    return
}

Start-Sleep 10
$count = 1
while ($true)
{

if ($count -eq 5)
{
Write-Host "- FAIL, retry count to validate graceful shutdown has been hit. Server will now perform a force off."
$JsonBody = @{ "ResetType" = "ForceOff" } | ConvertTo-Json -Compress


$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Actions/ComputerSystem.Reset"
   if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    return
    } 
}


else
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Credential $credential -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Credential $credential -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    return
    } 
}

if ($result1.StatusCode -eq 204)
{
    [String]::Format("- PASS, statuscode {0} returned to force off the server",$result1.StatusCode)
    Start-Sleep 15
    break
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned to force off the server",$result1.StatusCode)
    return
}
}

$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1"
if ($x_auth_token)
{
 try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
    }
    }
    catch
    {
    $RespErr
    return
    }
}

else
{
    try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    }
    catch
    {
    $RespErr
    return
    }
}
$get_content = $result.Content | ConvertFrom-Json
$host_power_state = $get_content.PowerState

if ($host_power_state -eq "Off")
{
Write-Host "- PASS, verified server is in OFF state"
$host_power_state = ""
break
}
else
{
Write-Host "- INFO, server still in ON state waiting for graceful shutdown to complete, polling power status again"
Start-Sleep 15
$count++
}

}

$JsonBody = @{ "ResetType" = "On" } | ConvertTo-Json -Compress


$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Actions/ComputerSystem.Reset"
   if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    return
    } 
}


else
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Credential $credential -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Credential $credential -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    return
    } 
}

if ($result1.StatusCode -eq 204)
{
    [String]::Format("- PASS, statuscode {0} returned successfully to power ON the server",$result1.StatusCode)
    Write-Host
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result1.StatusCode)
    return
}
}

if ($host_power_state -eq "Off")
{
Write-Host "- INFO, server power state OFF, performing power ON operation"
$JsonBody = @{ "ResetType" = "On" } | ConvertTo-Json -Compress


$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Actions/ComputerSystem.Reset"
   if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    return
    } 
}


else
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Credential $credential -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Credential $credential -Method Post -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    return
    } 
}

if ($result1.StatusCode -eq 204)
{
    [String]::Format("- PASS, statuscode {0} returned successfully to power ON the server",$result1.StatusCode)
    Start-Sleep 10
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result1.StatusCode)
    return
}

Start-Sleep 10
}
Write-Host
Write-Host "- INFO, cmdlet will now poll job ID every 15 seconds until marked completed"
Write-Host


$t=Get-Date -DisplayHint Time
$start_time = Get-Date
$end_time = $start_time.AddMinutes(30)

while ($overall_job_output.JobState -ne "Completed")
{
$loop_time = Get-Date
$uri ="https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/Jobs/$job_id"
if ($x_auth_token)
{
 try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
    }
    }
    catch
    {
    $RespErr
    return
    }
}

else
{
    try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    }
    catch
    {
    $RespErr
    return
    }
}
$overall_job_output=$result.Content | ConvertFrom-Json
if ($overall_job_output.JobState -eq "Failed")
{
Write-Host
[String]::Format("- FAIL, job not marked as scheduled, detailed error info: {0}",$overall_job_output)
return
}
elseif ($loop_time -gt $end_time)
{
Write-Host "- FAIL, timeout of 30 minutes has been reached before marking the job completed"
return
}
else
{
[String]::Format("- INFO, job not marked completed, current message: {0}",$overall_job_output.Message)
Start-Sleep 15
}
}
Write-Host
[String]::Format("- PASS, {0} job ID marked as completed!",$job_id)
$tt=Get-Date -DisplayHint Time
$ttt=$tt-$t
$final_completion_time=$ttt | select Minutes,Seconds 
Write-Host "  Job completed in $final_completion_time"

}

}


