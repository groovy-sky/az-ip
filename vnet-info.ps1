  
function DivideCIDR {  
    param (  
        [Parameter(Mandatory)]  
        [string]$CIDR,  
        [Parameter(Mandatory)]  
        [int]$TargetPrefixLength  
    )  
  
    Write-Output "[INF]: Starting division of CIDR $CIDR into subnets with target prefix length $TargetPrefixLength"  
  
    # Split CIDR into IP and PrefixLength  
    $IPAddress, $PrefixLength = $CIDR -split '/'  
    Write-Output "[DBG]: Initial IP Address: $IPAddress, Initial Prefix Length: $PrefixLength"  
    $IPAddress = [IPAddress]$IPAddress  
    $PrefixLength = [int]$PrefixLength  
  
    # Check if division is needed  
    if ($PrefixLength -ge $TargetPrefixLength) {  
        Write-Output "[INF]: No division needed, returning original CIDR: $CIDR"  
        return @($CIDR)  
    }  
  
    # Prepare for division  
    $SubnetsList = @($CIDR)  
    Write-Output "[DBG]: Initial Subnets List: $SubnetsList"  
  
    while ($PrefixLength -lt $TargetPrefixLength) {  
        $NewSubnetsList = @()  
        Write-Output "[DBG]: Current Prefix Length: $PrefixLength, Target Prefix Length: $TargetPrefixLength"  
  
        foreach ($subnetCIDR in $SubnetsList) {  
            Write-Output "[INF]: Dividing subnet $subnetCIDR further"  
              
            # Assuming DivideCIDR is called recursively here which might be incorrect based on context.  
            # Ensure the recursive call reflects the intended logic for dividing subnets.  
            $SubnetParts = DivideCIDR -CIDR $subnetCIDR -TargetPrefixLength ($PrefixLength + 1)  
  
            Write-Output "[DBG]: Subnet Parts after division: $SubnetParts"  
            $NewSubnetsList += $SubnetParts  
        }  
          
        $SubnetsList = $NewSubnetsList  
        Write-Output "[DBG]: New Subnets List: $SubnetsList"  
        $PrefixLength += 1  
    }  
  
    Write-Output "[INF]: Final Subnets List: $SubnetsList"  
    return $SubnetsList  
}  


function findAvailableIPbyMask {
    param (
        [Parameter(Mandatory)]
        [array]$IPs, # List of available CIDRs
        [Parameter(Mandatory)]
        [int]$Mask   # Required mask size
    )
  
    Write-Output "[INF]: Searching for an available IP CIDR with mask size /$Mask"

    # Initialize variables
    $resultCIDR = $null
    $updatedIPs = $IPs

    # Iterate through the IPs to find a suitable CIDR
    foreach ($cidr in $IPs) {
        Write-Output "[INF]: Checking CIDR $cidr"

        # Extract the prefix length from the CIDR
        $prefixLength = [int]($cidr -split '/')[1]

        # If the prefix length matches the required mask, return the CIDR
        if ($prefixLength -eq $Mask) {
            Write-Output "[INF]: Found a perfect match: $cidr"
            $resultCIDR = $cidr
            $updatedIPs = $IPs -ne $cidr
            return @($resultCIDR, $updatedIPs)
        }

        # If the prefix length is smaller (larger block), split the CIDR further
        if ($prefixLength -lt $Mask) {
            Write-Output "[INF]: Dividing CIDR $cidr to achieve mask size /$Mask"
            $dividedSubnets = DivideCIDR -CIDR $cidr -TargetPrefixLength $Mask

            # Take the first subnet and update the IPs list
            $resultCIDR = $dividedSubnets[0]
            $updatedIPs = ($IPs -ne $cidr) + $dividedSubnets[1..($dividedSubnets.Count - 1)]
            return @($resultCIDR, $updatedIPs)
        }
    }

    Write-Output "[ERR]: No available IP CIDR found with the required mask size /$Mask"
    return @($null, $updatedIPs)
}
  
function SplitAvailableIPs {  
    param (  
        [array]$available_ips,  
        [int]$maximum_mask_size  
    )  
  
    Write-Output "[INF]: Splitting available IPs into subnets with maximum mask size $maximum_mask_size"  
  
    # List to store the new divided subnets  
    $divided_subnets = @()  
  
    foreach ($cidr in $available_ips) {  
        Write-Output "[INF]: Splitting CIDR $cidr"  
        # Divide the CIDR into smaller subnets with the maximum_mask_size  
        $divided_subnets += DivideCIDR -CIDR $cidr -TargetPrefixLength $maximum_mask_size  
    }  
  
    return $divided_subnets  
}  
  
function Test-IPAddressInRange {  
    [CmdletBinding()]  
    param (  
        [Parameter(Mandatory)]  
        [string]$CIDR1,  
        [Parameter(Mandatory)]  
        [string]$CIDR2  
    )  
  
    Write-Output "[INF]: Testing if CIDR $CIDR1 overlaps with CIDR $CIDR2"  
  
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

  
# Retrieve the existing virtual network  
Write-Output "[INF]: Retrieving existing virtual network with ID $vnet_id"  
$vnet = Get-AzResource -ResourceId $vnet_id -ApiVersion $api_ver  

# Add new Address Space if needed
$new_addr = $vnet.Properties.addressSpace.addressPrefixes + $new_address_space
$new_addr = $new_addr | Sort-Object | Get-Unique  

# Add the new address space to the virtual network if needed
if ($vnet.Properties.addressSpace.addressPrefixes.Length -ne $new_addr.Length)
{
$vnet.Properties.addressSpace.addressPrefixes += $new_address_space
Set-AzResource -ResourceId $vnet_id -ApiVersion $api_ver -Properties $vnet.Properties -Force
}

# Store subnets info  
$existing_subnets = @{}  
foreach ($subnet in $vnet.Properties.subnets) {  
    $subnet_name = $subnet.name  
    $subnet_prefix = $subnet.properties.addressPrefix

    Write-Output "[INF]: Checking if $subnet_prefix is a part of $new_address_space"  

    # Check if this subnet is part of the new address space  
    if ((Test-IPAddressInRange -CIDR1 $new_address_space -CIDR2 $subnet_prefix) -eq "differ") {  
    	Write-Output "     Matched for $subnet_prefix"
        $existing_subnets[$subnet_name] = $subnet_prefix  
  
        # Update maximum_mask_size  
        $prefix_length = [int]($subnet_prefix -split '/')[1]  
        if ($prefix_length -lt $maximum_mask_size) {  
            $maximum_mask_size = $prefix_length  
        }  
    }  
}  
  
# Exclude any subnet from $existing_subnets, which IP in CIDR format belongs to $available_ips  
$new_subnets = @{}
$existing_subnets.GetEnumerator() | ForEach-Object {
    $subnet_name = $_.Key
    $subnet_prefix = $_.Value

    Write-Output "[INF]: Evaluating overlap for subnet $subnet_name with prefix $subnet_prefix"

    # Debugging outputs
    Write-Output "[DEBUG]: \$subnet_prefix = $subnet_prefix"
    Write-Output "[DEBUG]: \$available_ips = $($available_ips -join ', ')"

    # Validate CIDR split
    $mask = [int]($subnet_prefix -split '/')[1]
    Write-Output "[DEBUG]: Mask part = $mask"

    try {
        $subnet_prefix, $available_ips = findAvailableIPbyMask -IPs $available_ips -Mask $mask
        Write-Output "[DEBUG]: \$subnet_prefix = $subnet_prefix"
        Write-Output "[DEBUG]: \$available_ips = $($available_ips -join ', ')"
    } catch {
        Write-Output "[ERROR]: Failed during findAvailableIPbyMask execution. Exception: $_"
        throw
    }

    $subnet_name = $new_subnet_prefix + $subnet_name
    $new_subnets[$subnet_name] = $subnet_prefix
} 

# Add new subnets to VNet 
$vnet = AddNewSubnetsToVNetProperties -new_subnets $new_subnets -vnet $vnet  

# Apply changes
Set-AzResource -ResourceId $vnet_id -ApiVersion $api_ver -Properties $vnet.Properties -Force
