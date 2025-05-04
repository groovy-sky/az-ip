# Copy-AzSubnets

## Introduction

![](logo.png)

This script allows you to clone existing subnets within an Azure Virtual Network (VNet). It uses a new address space provided by the user, creates duplicates of subnets based on their size and name, and adds a customizable prefix (`n-` by default) to the new subnet names.

## Installation
```
Install-Script -Name Copy-AzSubnets -Force
```

### Features
- **Clone Subnets**: Duplicates existing subnets within a new address space.
- **Customizable Prefix**: Adds a prefix to new subnet names for easy identification.
- **Automated IP Allocation**: Divides CIDR blocks and allocates new subnets automatically.
- **Error Handling**: Logs and handles errors during the IP allocation and subnet creation process.

### Parameters
- **`vnet_id`**: The ID of the Azure Virtual Network.
- **`new_address_space`**: The new IP address space to be used for subnet creation.
- **`new_subnet_prefix`** (Optional): The prefix for new subnet names (default is `n-`).

### Workflow
1. Retrieves the existing VNet specified by `vnet_id`.
2. Adds the new address space to the VNet if it doesn’t already exist.
3. Identifies and processes existing subnets that don’t overlap with the new address space.
4. Generates new subnets within the new address space.
5. Adds the new subnets to the VNet and applies the changes.

### Example Usage
```powershell
Copy-AzSubnets.ps1 -vnet_id "/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Network/virtualNetworks/<vnet-name>" -new_address_space "10.1.0.0/16" -new_subnet_prefix "new-"
```
