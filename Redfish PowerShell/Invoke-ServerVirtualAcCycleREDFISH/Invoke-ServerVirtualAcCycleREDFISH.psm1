<#
_author_ = Texas Roemer <Texas_Roemer@Dell.com>
_version_ = 1.0

Copyright (c) 2024, Dell, Inc.

This software is licensed to you under the GNU General Public License,
version 2 (GPLv2). There is NO WARRANTY for this software, express or
implied, including the implied warranties of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. You should have received a copy of GPLv2
along with this software; if not, see
http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt
#>

<#
.Synopsis
   Cmdlet using iDRAC with Redfish API to perform server virtual a/c power cycle. 
.DESCRIPTION
   Cmdlet using iDRAC with Redfish API to perform server virtual a/c power cycle. DMTF action will only a/c cycle the server and not drain flea power. OEM action will a/c cycle the server and also drain flea power (same behavior as pulling a/c power cables). Note to run OEM action the server must be powered off first.   
   Supported parameters:
   - idrac_ip: Pass in the iDRAC IP
   - idrac_username: Pass in the iDRAC user name
   - idrac_password: Pass in the iDRAC user name password
   - x_auth_token: Pass in iDRAC X-Auth token session to execute cmdlet instead of username / password (recommended)
   - get_current_power_state: Get current server power state
   - dmtf_virtual_ac_cycle: Perform virtual server a/c power cycle the server using DMTF method. Note this method will not completely drain flea power. Note if using iDRAC10 server must be in off state first.
   - oem_virtual_ac_cycle: Perform virtual server a/c cycle the server using OEM method. Note: This method will completely drain flea power which is equivalent to the action of disconnecting power cables. Note server must be powered off first before running this OEM action.
   - power_off: Power off the server first before running OEM action to perform server virtual a/c power cycle
   - final_power_state: Final server power state after performing OEM server virtual a/c cycle. Note this optional argument is only supported for OEM virtual a/c power cycle. Note if this argument is not passed in server will stay in Off state after a/c cycle. Supported values: On and Off
.EXAMPLE
   Invoke-ServerVirtualAcCycleREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_ password calvin -get_current_power_state 
   This example will get current server power state
.EXAMPLE
   Invoke-ServerVirtualAcCycleREDFISH -idrac_ip 192.168.0.120 -get_current_power_state
   This example will first prompt to enter iDRAC username and password using Get-Credentials, then get current server power state.
.EXAMPLE
   Invoke-ServerVirtualAcCycleREDFISH -idrac_ip 192.168.0.120 get_current_power_state -x_auth_token 7bd9bb9a8727ec366a9cef5bc83b2708
   This example will get current server power state using iDRAC X-auth token session.
.EXAMPLE
   Invoke-ServerVirtualAcCycleREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -dmtf_virtual_ac_cycle
   This example will perform DMTF action to virtual a/c power cycle the server.
.EXAMPLE
   Invoke-ServerVirtualAcCycleREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -oem_virtual_ac_cycle -power_off
   This example will first power off the server, then perform OEM action to virtual a/c power cycle the server. After a/c cycle is complete server will still be in Off state.
.EXAMPLE
   Invoke-ServerVirtualAcCycleREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -oem_virtual_ac_cycle -power_off -final_power_state On
   This example will first power off the server, then perform OEM action to virtual a/c power cycle the server. After a/c cycle is complete server will automatically power on.
#>

function Invoke-ServerVirtualAcCycleREDFISH {

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
    [switch]$get_current_power_state,
    [Parameter(Mandatory=$False)]
    [switch]$dmtf_virtual_ac_cycle,
    [Parameter(Mandatory=$False)]
    [switch]$oem_virtual_ac_cycle,
    [Parameter(Mandatory=$False)]
    [switch]$power_off,
    [ValidateSet("Off", "On")]
    [Parameter(Mandatory=$False)]
    [string]$final_power_state
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

# Function to setup iDRAC creds

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

# Get current server power state

function get_current_server_power_state
{

$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/"
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
    #[String]::Format("- PASS, statuscode {0} returned successfully to get current power state",$result.StatusCode)
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result.StatusCode)
    return
}

$get_content = $result.Content | ConvertFrom-json
$power_state = $get_content.PowerState

Write-Host "`n- INFO, current server power state: $power_state`n"
}


# DMTF action to perform server virtual a/c power cycle

function dmtf_server_virtual_ac_cycle
{

$JsonBody = @{ "ResetType" = "PowerCycle"
    } | ConvertTo-Json -Compress


$uri = "https://$idrac_ip/redfish/v1/Chassis/System.Embedded.1/Actions/Chassis.Reset"
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
    Write-Host
    [String]::Format("- PASS, statuscode {0} returned to perform DMTF server virtual a/c power cycle",$result1.StatusCode)
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result1.StatusCode)
    $result1
    return
}
}

# OEM action to perform server virtual a/c power cycle

function oem_server_virtual_ac_cycle
{

if ($power_off)
{
$JsonBody = @{ "ResetType" = "ForceOff"} | ConvertTo-Json -Compress

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
    Write-Host
    [String]::Format("- PASS, statuscode {0} returned to power off the server",$result1.StatusCode)
    Start-Sleep 10
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result1.StatusCode)
    $result1
    return
}
}

$JsonBody = @{ "ResetType" = "PowerCycle"}

if ($final_power_state)
{
$JsonBody["FinalPowerState"] = $final_power_state
}

$JsonBody = $JsonBody | ConvertTo-Json -Compress

$uri = "https://$idrac_ip/redfish/v1/Chassis/System.Embedded.1/Actions/Oem/DellOemChassis.ExtendedReset"
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
    Write-Host
    [String]::Format("- PASS, statuscode {0} returned to perform OEM server virtual a/c power cycle",$result1.StatusCode)
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result1.StatusCode)
    $result1
    return
}
}

############
# Run code #
############

get_powershell_version 
setup_idrac_creds

# Code to check for supported iDRAC version installed

$uri = "https://$idrac_ip/redfish/v1/Chassis/System.Embedded.1"
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
	    if ($result.StatusCode -eq 200 -or $result.StatusCode -eq 202)
	    {
	    }
	    else
	    {
        Write-Host "`n- WARNING, iDRAC version detected does not support this feature using Redfish API"
        $result
	    return
	    }



if ($get_current_power_state)
{
get_current_server_power_state
}
elseif ($dmtf_virtual_ac_cycle)
{
dmtf_server_virtual_ac_cycle
}
elseif ($oem_virtual_ac_cycle)
{
oem_server_virtual_ac_cycle
}
else
{
Write-Host "`n- FAIL, either invalid parameter value passed in or missing required parameter"
return
}

}




