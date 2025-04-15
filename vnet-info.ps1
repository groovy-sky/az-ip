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

  
# Retrieve the existing virtual network  
$vnet = Get-AzResource -ResourceId $vnet_id -ApiVersion $api_ver 
  
$new_addr = $vnet.Properties.addressSpace.addressPrefixes + $new_address_space
$new_addr = $new_addr | Sort-Object | Get-Unique  

# Add the new address space to the virtual network if needed
if ($vnet.Properties.addressSpace.addressPrefixes.Length -ne $new_addr.Length)
{
$vnet.Properties.addressSpace.addressPrefixes += $new_address_space
Set-AzResource -ResourceId $vnet_id -ApiVersion $api_ver -Properties $vnet.Properties -Force
}

# Iteratively divide the address space until reaching the desired prefix length  
$current_subnets = @($new_address_space)  
while ($true) {  
    $next_subnets = @()  
    foreach ($subnet in $current_subnets) {  
        $divided = DivideSubnet -CIDR $subnet  
        $next_subnets += $divided  
    }  
    $current_subnets = $next_subnets  
    if ($current_subnets[0] -match "\/$desired_subnet_prefix$") {  
        break  
    }  
}  
  
# Select one of the divided subnets for the new subnet  
$new_subnet_prefix = $current_subnets[0] + "" # Choose the first available /24 subnet  
  
# Create a new subnet configuration using the determined subnet prefix  
$new_subnet = @{  
    name = $new_subnet_name
    properties = @{  
        addressPrefix = $new_subnet_prefix  
    }  
}  
  
# Add the new subnet to the existing subnets  
$vnet.Properties.subnets += $new_subnet  

Set-AzResource -ResourceId $vnet_id -ApiVersion $api_ver -Properties $vnet.Properties -Force
