
# Initialize variables  
$maximum_mask_size = 32  
$available_ips = @($new_address_space)  

function DivideCIDR {  
    param (  
        [Parameter(Mandatory)]  
        [string]$CIDR,  
        [Parameter(Mandatory)]  
        [int]$TargetPrefixLength  
    )  
  
    # Split CIDR into IP and PrefixLength  
    $IPAddress, $PrefixLength = $CIDR -split '/'  
    $IPAddress = [IPAddress]$IPAddress  
    $PrefixLength = [int]$PrefixLength  
  
    # Check if division is needed  
    if ($PrefixLength -ge $TargetPrefixLength) {  
        return @($CIDR)  
    }  
  
    # Prepare for division  
    $SubnetsList = @($CIDR)  
    while ($PrefixLength -lt $TargetPrefixLength) {  
        $NewSubnetsList = @()  
        foreach ($subnetCIDR in $SubnetsList) {  
            $SubnetParts = DivideSubnet -CIDR $subnetCIDR  
            $NewSubnetsList += $SubnetParts  
        }  
        $SubnetsList = $NewSubnetsList  
        $PrefixLength += 1  
    }  
  
    return $SubnetsList  
}  
  
function SplitAvailableIPs {  
    param (  
        [array]$available_ips,  
        [int]$maximum_mask_size  
    )  
  
    # List to store the new divided subnets  
    $divided_subnets = @()  
  
    foreach ($cidr in $available_ips) {  
        # Divide the CIDR into smaller subnets with the maximum_mask_size  
        $divided_subnets += DivideCIDR -CIDR $cidr -TargetPrefixLength $maximum_mask_size  
    }  
  
    return $divided_subnets  
}   
  
# Retrieve the existing virtual network  
$vnet = Get-AzResource -ResourceId $vnet_id -ApiVersion $api_ver  
  
# Step 1: Gather information about existing subnets  
$existing_subnets = @{}  
foreach ($subnet in $vnet.Properties.subnets) {  
    $subnet_name = $subnet.name  
    $subnet_prefix = $subnet.properties.addressPrefix  
      
    # Check if this subnet is part of the new address space  
    if (-not ($subnet_prefix -like "$new_address_space*")) {  
        $existing_subnets[$subnet_name] = $subnet_prefix  
  
        # Update maximum_mask_size  
        $prefix_length = [int]($subnet_prefix -split '/')[1]  
        if ($prefix_length -lt $maximum_mask_size) {  
            $maximum_mask_size = $prefix_length  
        }  
    }  
}  
  
# Step 2: Sort existing subnets by size (largest first)  
$sorted_subnets = $existing_subnets.GetEnumerator() | Sort-Object -Property Value
  
$available_ips = SplitAvailableIPs -available_ips $available_ips -maximum_mask_size $maximum_mask_size    
  
# Step 3: Divide available IPs based on maximum_mask_size  
$new_subnets = @{}  
foreach ($subnet in $sorted_subnets) {  
    $subnet_name = "n-" + $subnet.Key  
    $subnet_prefix = $subnet.Value  
  
    # Divide the available IPs  
    $next_subnet = $available_ips | Select-Object -First 1  
    $available_ips = $available_ips | Where-Object { $_ -ne $next_subnet }  
  
    # Store new subnet's IP and name  
    $new_subnets[$subnet_name] = $next_subnet  

    # Divide the subnet further if necessary  
    $divided_subnets = DivideSubnet -CIDR $next_subnet  
    $available_ips += $divided_subnets  
}  
  
# Step 4: Apply new subnets to the VNet  
foreach ($new_subnet in $new_subnets.GetEnumerator()) {  
    $subnet_name = $new_subnet.Key  
    $subnet_prefix = $new_subnet.Value  
  
    # Create a new subnet configuration  
    $subnet_config = @{  
        name = $subnet_name  
        properties = @{  
            addressPrefix = $subnet_prefix  
        }  
    }  
  
    # Add the new subnet to the existing subnets  
    $vnet.Properties.subnets += $subnet_config  
}  
  
# Update the virtual network with the new subnets  
Set-AzResource -ResourceId $vnet_id -ApiVersion $api_ver -Properties $vnet.Properties -Force  
