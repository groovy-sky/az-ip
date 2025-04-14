
$vnet=$(Get-AzResource -ResourceId /subscriptions/f406059a-f933-45e0-aefe-e37e0382d5de/resourceGroups/spoke-vnet/providers/Microsoft.Network/virtualNetworks/spoke-vnet-02 -ApiVersion 2024-05-01)
$res.Properties.subnets | % {$_.properties.addressPrefixes}
