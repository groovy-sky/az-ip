<#PSScriptInfo

.VERSION 1.2.4

.GUID 0ce538a5-e9c7-44e6-acac-13f306290b38

.AUTHOR groovy-sky

.COMPANYNAME groovy-sky

.COPYRIGHT groovy-sky

.TAGS Azure Network VirtualNetwork Subnet

.LICENSEURI

.PROJECTURI https://github.com/groovy-sky/az-ip

.ICONURI https://raw.githubusercontent.com/groovy-sky/az-ip/refs/heads/main/logo.png

.EXTERNALMODULEDEPENDENCIES Az.Network

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES
Version 1.2.4 - Added proper subscription context handling before accessing resources
Version 1.2.3 - Fixed resource group name parsing from VNet ID
Version 1.2.2 - Fixed syntax errors and switched to Az.Network module
Version 1.2.1 - Fixed subnet object structure to match Azure Network API schema
Version 1.2.0 - Fixed subnet object structure and error handling

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
    [Parameter(Mandatory = $false)][string]$new_subnet_prefix = "n-"
)

# Import required module
Import-Module Az.Network -ErrorAction Stop

# Divides provided IP CIDR
function DivideSubnet {  
    param (  
        [Parameter(Mandatory)]  
        [string]$CIDR  
    )  
    Write-Verbose "Dividing CIDR: $CIDR into two smaller subnets"  
  
    # Split CIDR into IP and PrefixLength  
    $parts = $CIDR -split '/'
    $IPAddress = [IPAddress]$parts[0]
    $PrefixLength = [int]$parts[1]
  
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
    $parts = $CIDR -split '/'
    $IPAddress = [IPAddress]$parts[0]
    $PrefixLength = [int]$parts[1]

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
        $subnetParts = $CurrentSubnet -split '/'
        $SubnetIP = $subnetParts[0]
        $SubnetPrefixLength = [int]$subnetParts[1]

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
        $prefixLength = [int](($cidr -split '/')[1])
          
        # If the prefix length matches the required mask, return the CIDR  
        if ($prefixLength -eq $Mask) {  
            $resultCIDR = $cidr  
            $updatedIPs = @($IPs | Where-Object {$_ -ne $cidr})  
            return @($resultCIDR, $updatedIPs)  
        }  
          
        # If the prefix length is smaller (larger block), split the CIDR further  
        if ($prefixLength -lt $Mask) {  
            $dividedSubnets = DivideSubnetMultipleTimes -CIDR $cidr -DesiredMaskSize $Mask  
            # Take the last subnet and update the IPs list  
            $resultCIDR = $dividedSubnets[-1]  
            
            # Remove the selected subnet from the divided subnets
            $remainingDividedSubnets = @($dividedSubnets | Where-Object {$_ -ne $resultCIDR})  
            
            # Create updated IPs list: all IPs except the current one, plus the remaining divided subnets
            $updatedIPs = @($IPs | Where-Object {$_ -ne $cidr})
            if ($remainingDividedSubnets.Count -gt 0) {
                $updatedIPs += $remainingDividedSubnets  
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
    $cidr1Parts = $CIDR1 -split '/'
    $cidr2Parts = $CIDR2 -split '/'
    
    $ip1 = [IPAddress]$cidr1Parts[0]
    $ip2 = [IPAddress]$cidr2Parts[0]
  
    $prefix1 = [int]$cidr1Parts[1]
    $prefix2 = [int]$cidr2Parts[1]
  
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
    [array]::Reverse($sortedRanges)

    return $sortedRanges
}

# Main script logic
$available_ips = @($new_address_space)  

# Parse the VNet ID to get resource group and VNet name
# Format: /subscriptions/{subscription-id}/resourceGroups/{resource-group}/providers/Microsoft.Network/virtualNetworks/{vnet-name}
Write-Output "[INFO]: Parsing VNet ID: $vnet_id"

if ($vnet_id -match '^/subscriptions/([^/]+)/resourceGroups/([^/]+)/providers/Microsoft.Network/virtualNetworks/([^/]+)$') {
    $subscriptionId = $Matches[1]
    $resourceGroupName = $Matches[2]
    $vnetName = $Matches[3]
    Write-Output "[INFO]: Extracted - Subscription: $subscriptionId, Resource Group: $resourceGroupName, VNet: $vnetName"
} else {
    Write-Error "Invalid VNet ID format. Expected format: /subscriptions/{subscription-id}/resourceGroups/{resource-group}/providers/Microsoft.Network/virtualNetworks/{vnet-name}"
    exit 1
}

# Check Azure connection and set correct subscription
Write-Output "[INFO]: Checking Azure connection..."
try {
    $currentContext = Get-AzContext -ErrorAction Stop
    if ($null -eq $currentContext) {
        Write-Error "No Azure context found. Please run Connect-AzAccount first."
        exit 1
    }
    
    Write-Output "[INFO]: Currently connected to Azure account: $($currentContext.Account.Id)"
    Write-Output "[INFO]: Current subscription: $($currentContext.Subscription.Name) ($($currentContext.Subscription.Id))"
    
    # Switch to the target subscription if different
    if ($currentContext.Subscription.Id -ne $subscriptionId) {
        Write-Output "[INFO]: Switching to target subscription $subscriptionId..."
        try {
            $null = Set-AzContext -SubscriptionId $subscriptionId -ErrorAction Stop
            $newContext = Get-AzContext
            Write-Output "[INFO]: Successfully switched to subscription: $($newContext.Subscription.Name) ($($newContext.Subscription.Id))"
        } catch {
            Write-Error "Failed to switch to subscription $subscriptionId. Error: $_"
            Write-Error "Please ensure you have access to this subscription."
            exit 1
        }
    } else {
        Write-Output "[INFO]: Already in the correct subscription context"
    }
} catch {
    Write-Error "Failed to get Azure context: $_"
    Write-Error "Please run Connect-AzAccount to authenticate to Azure."
    exit 1
}

# Retrieve the existing virtual network using Az cmdlet
Write-Output "[INFO]: Retrieving existing virtual network '$vnetName' in resource group '$resourceGroupName'"
try {
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $resourceGroupName -Name $vnetName -ErrorAction Stop
    Write-Output "[INFO]: Successfully retrieved VNet with $($vnet.Subnets.Count) existing subnets"
    Write-Output "[INFO]: Current address spaces: $($vnet.AddressSpace.AddressPrefixes -join ', ')"
} catch {
    Write-Error "Failed to retrieve virtual network: $_"
    Write-Error "Please verify that:"
    Write-Error "  - You are in the correct subscription: $subscriptionId"
    Write-Error "  - Resource Group '$resourceGroupName' exists"
    Write-Error "  - VNet '$vnetName' exists in the resource group"
    Write-Error "  - You have appropriate permissions to read the VNet"
    
    # Try to list resource groups to help diagnose
    try {
        $rgs = Get-AzResourceGroup -ErrorAction Stop | Select-Object -ExpandProperty ResourceGroupName
        if ($rgs -contains $resourceGroupName) {
            Write-Output "[DEBUG]: Resource group '$resourceGroupName' exists in the subscription"
            # Try to list VNets in the resource group
            $vnets = Get-AzVirtualNetwork -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
            if ($vnets) {
                Write-Output "[DEBUG]: VNets in resource group: $($vnets -join ', ')"
            } else {
                Write-Output "[DEBUG]: No VNets found in resource group '$resourceGroupName'"
            }
        } else {
            Write-Output "[DEBUG]: Resource group '$resourceGroupName' not found. Available resource groups:"
            $rgs | ForEach-Object { Write-Output "  - $_" }
        }
    } catch {
        Write-Verbose "Could not list resource groups for debugging"
    }
    
    exit 1
}

# Add the new address space to the virtual network if needed
$current_prefixes = $vnet.AddressSpace.AddressPrefixes
$new_prefixes = $current_prefixes + $new_address_space | Sort-Object | Get-Unique

if ($current_prefixes.Count -ne $new_prefixes.Count) {
    Write-Output "[INFO]: Adding new address space to the virtual network: $new_address_space"
    Write-Output "[INFO]: Current address spaces: $($current_prefixes -join ', ')"
    $vnet.AddressSpace.AddressPrefixes = $new_prefixes
    
    try {
        Write-Output "[INFO]: Updating VNet with new address space..."
        $null = Set-AzVirtualNetwork -VirtualNetwork $vnet -ErrorAction Stop
        # Re-retrieve the vnet to get the updated state
        $vnet = Get-AzVirtualNetwork -ResourceGroupName $resourceGroupName -Name $vnetName -ErrorAction Stop
        Write-Output "[INFO]: Successfully added new address space. New address spaces: $($vnet.AddressSpace.AddressPrefixes -join ', ')"
    } catch {
        Write-Error "Failed to add new address space: $_"
        exit 1
    }
} else {
    Write-Output "[INFO]: Address space $new_address_space already exists in the VNet"
}

# Process subnets
Write-Output "[INFO]: Processing subnets for the new address space"
$existing_subnets = @{}
$skipped_subnets = @()

foreach ($subnet in $vnet.Subnets) {
    $subnet_name = $subnet.Name
    $subnet_prefix = $null
    
    # Handle both AddressPrefix and AddressPrefixes
    if ($subnet.AddressPrefixes -and $subnet.AddressPrefixes.Count -gt 0) {  
        $subnet_prefix = $subnet.AddressPrefixes[0]  
    } elseif ($subnet.AddressPrefix) {  
        $subnet_prefix = $subnet.AddressPrefix  
    }
    
    if ([string]::IsNullOrEmpty($subnet_prefix)) {
        Write-Warning "Subnet $subnet_name has no address prefix, skipping"
        continue
    }
    
    Write-Output "[INFO]: Checking if $subnet_prefix is part of $new_address_space"

    if ((Test-IPAddressInRange -CIDR1 $new_address_space -CIDR2 $subnet_prefix) -eq "differ") {
        $existing_subnets[$subnet_name] = $subnet_prefix
        Write-Output "[INFO]: Subnet $subnet_name ($subnet_prefix) will be cloned to new address space"
    } else {
        # Store subnet to $skipped_subnets to check if a new IP have not been already allocated
        if ($subnet_name.StartsWith($new_subnet_prefix)) {
            $skipped_subnets += $subnet_name.Substring($new_subnet_prefix.Length)
        } else {
            $skipped_subnets += $subnet_name
        }
        Write-Output "[INFO]: Subnet $subnet_name ($subnet_prefix) already in new address space, skipping"
    }  
}

if ($existing_subnets.Count -eq 0) {
    Write-Output "[INFO]: No subnets to clone from existing address space"
    exit 0
}

# Generate new subnets
Write-Output "[INFO]: Generating new subnets for $($existing_subnets.Count) existing subnets"
$new_subnets = @{}

# Sort the existing_subnets hashtable by prefix length (smaller subnets first)
$sorted_existing_subnets = $existing_subnets.GetEnumerator() | Sort-Object {
    $prefixLength = ($_.Value -split '/')[1]
    [int]$prefixLength
}

# Process the sorted subnets
foreach ($entry in $sorted_existing_subnets) {
    $subnet_name = $entry.Key
    $subnet_prefix = $entry.Value

    if (-not ($skipped_subnets -contains $subnet_name)) {
        try {
            $mask = [int](($subnet_prefix -split '/')[1])
            Write-Verbose "Allocating subnet for $subnet_name with mask /$mask"
            
            $result = findAvailableIPbyMask -IPs $available_ips -Mask $mask
            $allocated_subnet = $result[0]
            $available_ips = $result[1]
            
            # Check if we successfully allocated a subnet
            if ($null -eq $allocated_subnet) {
                Write-Warning "Unable to allocate IP space for subnet $subnet_name with mask /$mask - insufficient space in new address range"
                continue
            }
            
            $new_subnet_name = $new_subnet_prefix + $subnet_name
            $new_subnets[$new_subnet_name] = $allocated_subnet
            Write-Output "[INFO]: Allocated $allocated_subnet for new subnet $new_subnet_name"
            
        } catch {
            Write-Error "Failed to allocate new IP for subnet $subnet_name. Exception: $_"
            continue
        }
    } else {
        Write-Output "[INFO]: Skipping subnet $subnet_name as it already exists in the new address space"
    }
}

if ($new_subnets.Count -eq 0) {
    Write-Output "[INFO]: No new subnets to add"
    exit 0
}

# Add new subnets to the virtual network
Write-Output "[INFO]: Adding $($new_subnets.Count) new subnets to the virtual network"

# Create subnet configurations and add them to VNet
$addedCount = 0
foreach ($subnet in $new_subnets.GetEnumerator()) {
    try {
        Write-Output "[INFO]: Creating subnet configuration for $($subnet.Key) with prefix $($subnet.Value)"
        $subnetConfig = New-AzVirtualNetworkSubnetConfig `
            -Name $subnet.Key `
            -AddressPrefix $subnet.Value `
            -ErrorAction Stop
        
        $vnet.Subnets.Add($subnetConfig)
        $addedCount++
    } catch {
        Write-Error "Failed to create subnet configuration for $($subnet.Key): $_"
    }
}

if ($addedCount -eq 0) {
    Write-Error "No subnets were successfully configured"
    exit 1
}

# Apply changes
Write-Output "[INFO]: Applying changes to the virtual network (adding $addedCount subnets)"
try {
    $null = Set-AzVirtualNetwork -VirtualNetwork $vnet -ErrorAction Stop
    Write-Output "[SUCCESS]: Virtual network updated successfully with $addedCount new subnets"
    
    # List the newly created subnets
    Write-Output "`n[SUCCESS]: The following subnets were created:"
    foreach ($subnet in $new_subnets.GetEnumerator()) {
        Write-Output "  - $($subnet.Key): $($subnet.Value)"
    }
} catch {
    Write-Error "Failed to update virtual network: $_"
    if ($_.Exception.Message) {
        Write-Error "Error details: $($_.Exception.Message)"
    }
    exit 1
}