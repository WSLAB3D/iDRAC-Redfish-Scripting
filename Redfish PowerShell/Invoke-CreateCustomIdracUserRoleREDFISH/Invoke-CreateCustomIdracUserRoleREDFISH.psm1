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
   iDRAC cmdlet using Redfish API to create custom iDRAC user role.
.DESCRIPTION
   iDRAC cmdlet using Redfish API to create custom iDRAC user role. Note this cmdlet is only supported on iDRAC10 or newer versions.
   PARAMETERS 
   - idrac_ip: Pass in iDRAC IP address
   - idrac_username: Pass in iDRAC username
   - idrac_password: Pass in iDRAC username password
   - x_auth_token: Pass in iDRAC X-Auth token session to execute cmdlet instead of username / password (recommended)
   - get_custom_roles: Get current custom iDRAC user roles
   - create: Create new custom iDRAC user role pass in an unique string name. Note no whitespace is allowed in name and onlu dash, underscore special characters are allowed. Note when you create a custom user role you can either set dmtf privileges, oem privileges or both. 
   - dmtf_privilege_types: Pass in DMTF privilege type(s) you want to assign to the custom user role being created, supported case sensitive values are: Login, ConfigureComponents, ConfigureManager, ConfigureSelf, ConfigureUsers, AccessVirtualConsole, AccessVirtualMedia, ClearLogs, ExecuteDebugCommands, TestAlerts. Note if passing in multiple values using a comma separator and surround the value with double quotes.
   - oem_privilege_types: Pass in OEM privilege type(s) you want to assign to the custom user role being created, supported case sensitive values are: AccessVirtualConsole, AccessVirtualMedia, ClearLogs, ExecuteDebugCommands, TestAlerts. Note if passing in multiple values using a comma separator and surround the value with double quotes.
   - delete: Delete custom role pass in custom role absolute URI path, example: /redfish/v1/AccountService/Roles/custom-role
.EXAMPLE
   Invoke-CreateCustomIdracUserRoleREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -get_custom_roles
   This example will return custom iDRAC user roles detected.
.EXAMPLE
   Invoke-CreateCustomIdracUserRoleREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -create "test_custom_role" -dmtf_privilege_types "Login,ConfigureComponents,ConfigureManager" -oem_privilege_types "AccessVirtualConsole,AccessVirtualMedia"
   This example shows creating a custom role with both dmtf and oem privileges.
.EXAMPLE
   Invoke-CreateCustomIdracUserRoleREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -create "test_custom_role" -dmtf_privilege_types "Login,ConfigureManager"
   This example shows creating a custom role using only dmtf privileges. 
.EXAMPLE
   Invoke-CreateCustomIdracUserRoleREDFISH.ps1 -idrac_ip 100.65.214.120 -idrac_username root -idrac_password calvin -delete /redfish/v1/AccountService/Roles/test_custom_role
   This example shows deleting custom iDRAC user role. 
#>

function Invoke-CreateCustomIdracUserRoleREDFISH {

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
    [switch]$get_custom_roles,
    [Parameter(Mandatory=$False)]
    [string]$create,
    [Parameter(Mandatory=$False)]
    [string]$dmtf_privilege_types,
    [Parameter(Mandatory=$False)]
    [string]$oem_privilege_types,
    [Parameter(Mandatory=$False)]
    [string]$delete
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

$global:get_powershell_version = $null

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
$get_creds = Get-Credential -Message "Enter iDRAC username and password to run cmdlet"
$global:credential = New-Object System.Management.Automation.PSCredential($get_creds.UserName, $get_creds.Password)
}
}

setup_idrac_creds

function get_iDRAC_version
{

$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1?`$select=Model"


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
    $result = Invoke-WebRequest -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"; "X-Auth-Token" = $x_auth_token}
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
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result.StatusCode)
    return
}
$get_content = $result.Content | ConvertFrom-Json
if ($get_content.Model.Contains("12G") -or $get_content.Model.Contains("13G") -or $get_content.Model.Contains("14G") -or $get_content.Model.Contains("15G") -or $get_content.Model.Contains("16G"))
{
$global:iDRAC_version = "old"
}
else
{
$global:iDRAC_version = "new"
}
}
get_iDRAC_version


function get_custom_roles
{

$uri = "https://$idrac_ip/redfish/v1/AccountService/Roles"

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

$custom_role_uris = @()

foreach ($item in $get_content.Members)
{
$odata_string = "@odata.id"
    if ($item.$odata_string.Contains("Administrator") -or $item.$odata_string.Contains("Operator") -or $item.$odata_string.Contains("ReadOnly"))
    {
    } 
    else
    {
    $custom_role_uris += $item.$odata_string
    }  
}

if ($custom_role_uris.Count -eq 0)
{
Write-Host "`n- INFO, no custom iDRAC user roles detected`n"
return
}

Write-Host "`n- INFO, getting custom roles`n"
foreach ($item in $custom_role_uris)
{
$uri = "https://$idrac_ip$item"

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
$get_content   
}

return
}


function create_custom_role
{
Write-Host "`n- INFO creating custom user role '$create'`n"
$uri = "https://$idrac_ip/redfish/v1/AccountService/Roles"
$create_payload = @{"RoleId"=$create; "AssignedPrivileges"=@(); "OemPrivileges"=@()}
if ($dmtf_privilege_types)
{
    if ($dmtf_privilege_types.Contains(","))
    {
    $create_payload["AssignedPrivileges"] = $dmtf_privilege_types.Split(",")
    }
    else
    {
    $create_payload["AssignedPrivileges"] += $dmtf_privilege_types
    }
}
if ($oem_privilege_types)
{
    if ($oem_privilege_types.Contains(","))
    {
    $create_payload["OemPrivileges"] = $oem_privilege_types.Split(",")
    }
    else
    {
    $create_payload["OemPrivileges"] += $oem_privilege_types
    }
}

$JsonBody = $create_payload | ConvertTo-Json -Compress

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


if ($result1.StatusCode -eq 201)
{
    [String]::Format("`n- PASS, statuscode {0} returned successfully for POST command to create custom iDRAC user role",$result1.StatusCode)
}
else
{
    [String]::Format("- FAIL, POST command failed to create custom iDRAC user role, statuscode {0} returned",$result1.StatusCode)
    $result1
    return
}

}


function delete_custom_role
{
Write-Host "`n- INFO, deleting iDRAC custom role $delete"
$uri = "https://$idrac_ip$delete"

if ($x_auth_token)
{
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Method Delete -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Method Delete -ContentType 'application/json' -Headers @{"Accept" = "application/json"; "X-Auth-Token" = $x_auth_token} -ErrorVariable RespErr
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
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Credential $credential -Method Delete -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Credential $credential -Method Delete -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
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
    [String]::Format("`n- PASS, statuscode {0} returned successfully to delete iDRAC custom user role",$result1.StatusCode)
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result1.StatusCode)
    $result1
    return
}
}

# Run cmdlet 

if ($global:iDRAC_version -eq "old")
{
Write-Host "`n- WARNING, iDRAC version detected does not support this cmdlet"
return
}

if ($get_custom_roles)
{
get_custom_roles
}

elseif ($delete)
{
delete_custom_role
}

elseif ($create -and $dmtf_privilege_types -or $oem_privilege_types)
{
create_custom_role
}

else
{
Write-Host "- FAIL, either incorrect parameter(s) used or missing required parameters(s), please see help or examples for more information."
}

}









