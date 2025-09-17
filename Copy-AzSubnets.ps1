<#PSScriptInfo

.VERSION 1.1.6

.GUID 0ce538a5-e9c7-44e6-acac-13f306290b38

.AUTHOR groovy-sky

.COMPANYNAME groovy-sky

.COPYRIGHT groovy-sky

.TAGS Azure Network VirtualNetwork Subnet

.LICENSEURI

.PROJECTURI https://github.com/groovy-sky/az-ip

.ICONURI https://raw.githubusercontent.com/groovy-sky/az-ip/refs/heads/main/logo.png

.EXTERNALMODULEDEPENDENCIES Az.Resources

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES
Version 1.1.6 - Fixed null reference error in findAvailableIPbyMask function
Version 1.1.5 - Initial release with subnet copying functionality

.PRIVATEDATA

#>

<#

.DESCRIPTION
This script allows to clone existing subnets for Azure Virtual Network. It requires a new address space using which it creates duplicates of subnets by size and name (with prefix 'n-').

#>

[CmdletBinding()]	
param (
    [Parameter(Mandatory = $true)][string]$vnet_id,  # Virtual Network ID
    [Parameter(Mandatory = $true)][string]$new_address_space,  # New Address Space
    [Parameter(Mandatory = $false)][string]$new_subnet_prefix
)

# [Rest of your script code continues here...]
