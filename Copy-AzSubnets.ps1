<#PSScriptInfo

.VERSION 1.1.8

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
Version 1.1.8 - Fixed array handling in findAvailableIPbyMask function to prevent InvalidRequestFormat errors
Version 1.1.7 - Updated IP allocation logic
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

# Divides provided IP CIDR
function DivideSubnet {  
    param (  
        [Parameter(Mandatory)]  
        [string]$CIDR  
    )  
    Write-Verbose "Dividing CIDR: $CIDR into two smaller subnets"  
  
    # Split CIDR into IP and PrefixLength  
    $IPAddress, $PrefixLength = $CIDR -split '[|\/]'  
    $IPAddress = [IPAddress]$IPAddress  
    $PrefixLength = [int]$PrefixLength  
  
    # New PrefixLength for next subnets  
    $NewPrefixLength = $PrefixLength + 1  
    if ($NewPrefixLength -gt 32) {  
        throw "Cannot divide the subnet further. New PrefixLength exceeds 32."  
    }  
  
    # Step size for each new subnet  
    $StepSize = [math]::Pow(2, 32 - $NewPrefixLength)  
  
    # Convert IP to integer  
    $IPAddressBytes = $IPAddress.GetAddressBytes()  
    [array]::Reverse($IPAddressBytes)  
    $IPAddressInt = [BitConverter]::ToUInt32($IPAddressBytes, 0)  
  
    # Generate the two subnets  
    $SubnetsList = @()  
    for ($i = 0; $i -lt 2; $i++) {  
        $SubnetStart = $IPAddressInt + ($i * $StepSize)  
        $SubnetBytes = [BitConverter]::GetBytes([uint32]$SubnetStart)  
        [array]::Reverse($SubnetBytes) # Convert back to big-endian  
        $SubnetIP = [IPAddress]::new($SubnetBytes)  
  
        $SubnetCIDR = "$SubnetIP/$NewPrefixLength"  
        $SubnetsList += $SubnetCIDR  
    }  
    return $SubnetsList  
}   

# Divides IP CIDR to specified IP mask
function DivideSubnetMultipleTimes {
    param (
        [Parameter(Mandatory)]
        [string]$CIDR,
        [Parameter(Mandatory)]
        [int]$DesiredMaskSize
    )
    Write-Verbose "Dividing CIDR: $CIDR to reach the desired mask size: $DesiredMaskSize"

    # Split CIDR into IP and PrefixLength
    $IPAddress, $PrefixLength = $CIDR -split '[|\/]'
    $IPAddress = [IPAddress]$IPAddress
    $PrefixLength = [int]$PrefixLength

    # Validate the desired mask size
    if ($DesiredMaskSize -le $PrefixLength) {
        throw "Desired mask size must be greater than the current prefix length."
    }

    if ($DesiredMaskSize -gt 32) {
        throw "Desired mask size exceeds 32."
    }

    # Initialize the current subnet list with the initial CIDR as a dynamic ArrayList
    $SubnetsList = [System.Collections.ArrayList]@($CIDR)

    # Iterate over the subnets and divide only when necessary
    $i = 0
    while ($i -lt $SubnetsList.Count) {
        $CurrentSubnet = $SubnetsList[$i]
        $SubnetIP, $SubnetPrefixLength = $CurrentSubnet -split '[|\/]'
        $SubnetPrefixLength = [int]$SubnetPrefixLength

        # If the current subnet's prefix length is smaller than the desired mask size, divide it
        if ($SubnetPrefixLength -lt $DesiredMaskSize) {
            $StepSize = [math]::Pow(2, 32 - ($SubnetPrefixLength + 1))

            # Convert the IP to an integer
            $SubnetBytes = ([IPAddress]$SubnetIP).GetAddressBytes()
            [array]::Reverse($SubnetBytes)
            $SubnetInt = [BitConverter]::ToUInt32($SubnetBytes, 0)

            # Generate two subnets
            $NewSubnets = @()
            for ($j = 0; $j -lt 2; $j++) {
                $NewSubnetStart = $SubnetInt + ($j * $StepSize)
                $NewSubnetBytes = [BitConverter]::GetBytes([uint32]$NewSubnetStart)
                [array]::Reverse($NewSubnetBytes) # Convert back to big-endian
                $NewSubnetIP = [IPAddress]::new($NewSubnetBytes)
                $NewSubnets += "$NewSubnetIP/$($SubnetPrefixLength + 1)"
            }

            # Replace the current subnet with the two new subnets
            $SubnetsList[$i] = $NewSubnets[0]
            $SubnetsList.Insert($i + 1, $NewSubnets[1])
        }
        # Move to the next subnet
        $i++
    }
    # Return the final list of subnets
    return $SubnetsList
} 

# Find available IP by specified IP mask  
function findAvailableIPbyMask {  
    param (  
        [Parameter(Mandatory)]  
        [array]$IPs, # List of available CIDRs  
        [Parameter(Mandatory)]  
        [int]$Mask   # Required mask size  
    )  
    # Initialize variables  
    $resultCIDR = $null  
    $updatedIPs = @()  
  
    # Iterate through the IPs to find a suitable CIDR  
    foreach ($cidr in $IPs) {  
        # Extract the prefix length from the CIDR  
        $prefixLength = [int]($cidr -split '/')[1]  
          
        # If the prefix length matches the required mask, return the CIDR  
        if ($prefixLength -eq $Mask) {  
            $resultCIDR = $cidr  
            $updatedIPs = @($IPs | Where-Object {$_ -ne $cidr})  
            return @($resultCIDR, $updatedIPs)  
        }  
          
        # If the prefix length is smaller (larger block), split the CIDR further  
        if ($prefixLength -lt $Mask) {  
            $dividedSubnets = DivideSubnetMultipleTimes -CIDR $cidr -DesiredMaskSize $Mask  
            # Take the first subnet and update the IPs list  
            $resultCIDR = $dividedSubnets[-1]  
            $dividedSubnets = @($dividedSubnets | Where-Object {$_ -ne $resultCIDR})  
            
            # Fixed: Create a new array with all IPs except the current one, then add divided subnets
            $updatedIPs = @($IPs | Where-Object {$_ -ne $cidr})
            if ($dividedSubnets.Count -gt 0) {
                $updatedIPs += $dividedSubnets  
            }
            
            return @($resultCIDR, $updatedIPs)  
        }  
    }  
    # If no suitable CIDR found, return null for resultCIDR but preserve the IPs list
    return @($null, $IPs)  
}  

# Check if one IP is a part of another
function Test-IPAddressInRange {  
    [CmdletBinding()]  
    param (  
        [Parameter(Mandatory)]  
        [string]$CIDR1,  
        [Parameter(Mandatory)]  
        [string]$CIDR2  
    )  
  
    Write-Verbose "Testing if CIDR $CIDR1 overlaps with CIDR $CIDR2"  
  
    # Helper function to convert IP address to uint32  
    function ConvertTo-UInt32 {  
        param (  
            [IPAddress]$IPAddress  
        )  
  
        $bytes = $IPAddress.GetAddressBytes()  
        [array]::Reverse($bytes) # Convert to little-endian  
        return [BitConverter]::ToUInt32($bytes, 0)  
    }  
  
    # Parse CIDRs  
    $ip1, $prefix1 = $CIDR1 -split '/'  
    $ip2, $prefix2 = $CIDR2 -split '/'  
  
    $ip1 = [IPAddress]$ip1  
    $ip2 = [IPAddress]$ip2  
  
    $prefix1 = [int]$prefix1  
    $prefix2 = [int]$prefix2  
  
    # Convert IPs to UInt32  
    $ip1UInt32 = ConvertTo-UInt32 -IPAddress $ip1  
    $ip2UInt32 = ConvertTo-UInt32 -IPAddress $ip2  
  
    # Calculate the range for each CIDR  
    $totalHosts1 = [math]::Pow(2, 32 - $prefix1) - 1  
    $lastIP1UInt32 = $ip1UInt32 + [uint32]$totalHosts1  
  
    $totalHosts2 = [math]::Pow(2, 32 - $prefix2) - 1  
    $lastIP2UInt32 = $ip2UInt32 + [uint32]$totalHosts2  
  
    # Check if ranges overlap  
    if (($ip1UInt32 -le $lastIP2UInt32 -and $ip1UInt32 -ge $ip2UInt32) -or  
        ($ip2UInt32 -le $lastIP1UInt32 -and $ip2UInt32 -ge $ip1UInt32)) {  
        return "overlap"
    } else {
        return "differ"
    }  
}  

# Function to add new subnets to the virtual network properties  
function AddNewSubnetsToVNetProperties {  
    param (  
        [Parameter(Mandatory)]  
        [hashtable]$new_subnets,  
        [Parameter(Mandatory)]  
        [object]$vnet  
    )  
      
    # Initialize a list to store new subnet objects  
    $new_subnet_objects = @()  
  
    # Iterate over each entry in the new subnets  
    foreach ($subnet in $new_subnets.GetEnumerator()) {  
        $subnet_name = $subnet.Key  
        $subnet_prefix = $subnet.Value  
          
        # Create a new subnet object  
        $new_subnet = [PSCustomObject]@{  
            name       = $subnet_name  
            id         = "$($vnet.id)/subnets/$subnet_name"  
            etag       = "" # ETag can be generated or left empty if not relevant  
            properties = [PSCustomObject]@{  
                provisioningState                  = "Succeeded"  
                addressPrefix                      = $subnet_prefix  
                serviceEndpoints                   = @() # Add specific service endpoints if required  
                delegations                        = @() # Add specific delegations if needed  
                privateEndpointNetworkPolicies     = "Disabled"  
                privateLinkServiceNetworkPolicies  = "Enabled"  
            }  
            type       = "Microsoft.Network/virtualNetworks/subnets"  
        }  
  
        # Add the new subnet object to the list  
        $new_subnet_objects += $new_subnet  
    }  
  
    # Append the new subnet objects to the existing subnets  
    $vnet.Properties.subnets += $new_subnet_objects  
  
    return $vnet  
}

function Sort-IPRanges {
    param (
        [Parameter(Mandatory)]
        [array]$IPs # Array of CIDRs (e.g., "10.0.0.0/24", "10.0.0.0/16")
    )

    # Sort the IPs by prefix length in ascending order (smaller prefix = larger range)
    $sortedRanges = $IPs | Sort-Object {
        # Extract the prefix length from the CIDR
        $cidrPrefix = ($_ -split '/')[1]
        [int]$cidrPrefix
    }

    # Reverse the order to prioritize the largest ranges first
    $sortedRanges = $sortedRanges[-1..0]

    return $sortedRanges
}

$api_ver="2024-07-01"
$available_ips = @($new_address_space)  
if ($new_subnet_prefix.Length -eq 0) {
    $new_subnet_prefix = "n-"
}
# Retrieve the existing virtual network
Write-Output "[INFO]: Retrieving existing virtual network with ID $vnet_id"
$vnet = Get-AzResource -ResourceId $vnet_id -ApiVersion $api_ver

# Add the new address space to the virtual network if needed
$current_prefixes = $vnet.Properties.addressSpace.addressPrefixes
$new_prefixes = $current_prefixes + $new_address_space | Sort-Object | Get-Unique

if ($current_prefixes.Length -ne $new_prefixes.Length) {
    $vnet.Properties.addressSpace.addressPrefixes += $new_address_space
    Write-Output ("[INFO]: Adding new address space to the virtual network " + $vnet.Properties.addressSpace.addressPrefixes)
    Set-AzResource -ResourceId $vnet_id -ApiVersion $api_ver -Properties $vnet.Properties -Force
}

# Process subnets
Write-Output "[INFO]: Processing subnets for the new address space"
$existing_subnets = @{}
$skipped_subnets = @()
$maximum_mask_size = 32  # Initialize to the maximum possible mask size

foreach ($subnet in $vnet.Properties.subnets) {
    $subnet_name = $subnet.name
    if ($subnet.properties.addressPrefixes) {  
        $subnet_prefix = $subnet.properties.addressPrefixes[0]  
    } elseif ($subnet.properties.addressPrefix) {  
        $subnet_prefix = $subnet.properties.addressPrefix  
    }
    Write-Output "[INFO]: Checking if $subnet_prefix is part of $new_address_space"

    if ((Test-IPAddressInRange -CIDR1 $new_address_space -CIDR2 $subnet_prefix) -eq "differ") {
        $existing_subnets[$subnet_name] = $subnet_prefix
        $prefix_length = [int]($subnet_prefix -split '/')[1]
        if ($prefix_length -lt $maximum_mask_size) {
            $maximum_mask_size = $prefix_length
        }
    } else {
        # Store subnet to $skipped_subnets to check if a new IP have not been already allocated
        if ($subnet_name.Length -gt $new_subnet_prefix.Length) {
            $skipped_subnets += $subnet_name.Substring($new_subnet_prefix.Length)
        } else {
            $skipped_subnets += $subnet_name
        }
    }  
}

# Generate new subnets
Write-Output "[INFO]: Generating new subnets"
$new_subnets = @{}
# Sort the existing_subnets hashtable by prefix length
$sorted_existing_subnets = $existing_subnets.GetEnumerator() | Sort-Object {
    # Extract and sort by the prefix length from the subnet prefix
    $prefixLength = ($_.Value -split '/')[1]
    [int]$prefixLength
}

# Process the sorted subnets
foreach ($entry in $sorted_existing_subnets) {
    $subnet_name = $entry.Key
    $subnet_prefix = $entry.Value

    if (-not ($skipped_subnets -contains $subnet_name)) {
        try {
            $result = findAvailableIPbyMask -IPs $available_ips -Mask ([int]($subnet_prefix -split '/')[1])
            $subnet_prefix = $result[0]
            $available_ips = $result[1]
            
            # Check if we successfully allocated a subnet
            if ($null -eq $subnet_prefix) {
                Write-Output "[ERROR]: Unable to allocate IP space for subnet $subnet_name with mask /$(($entry.Value -split '/')[1]). No available space in the provided address range."
                throw "Insufficient address space to allocate all subnets."
            }
            
            $new_subnets[$new_subnet_prefix + $subnet_name] = $subnet_prefix
        } catch {
            Write-Output "[ERROR]: Failed to allocate new IP for subnet $subnet_name. Exception: $_"
            throw
        }
    }
}

# Add new subnets to the virtual network
Write-Output "[INFO]: Adding new subnets to the virtual network"
$vnet = AddNewSubnetsToVNetProperties -new_subnets $new_subnets -vnet $vnet

# Apply changes
Write-Output "[INFO]: Applying changes to the virtual network"
Set-AzResource -ResourceId $vnet_id -ApiVersion $api_ver -Properties $vnet.Properties -Force
