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

# Create a new subnet configuration using the new address space  
$new_subnet = @{  
    name = $new_subnet_name  
    properties = @{  
        addressPrefix = $new_subnet_prefix  
    }  
}  
  
# Add the new subnet to the existing subnets  
$vnet.Properties.subnets += $new_subnet
  
# Update the virtual network
Set-AzResource -ResourceId $vnet_id -ApiVersion $api_ver -Properties $vnet.Properties -Force
