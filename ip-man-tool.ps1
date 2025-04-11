<# 
.DESCRIPTION
IP management tool
.EXAMPLES
# Calculate subnet details from CIDR
ip-man-tool -CIDR 192.168.0.0/24

# Calculate subnet details from an IP and Mask
ip-man-tool -IPAddress 192.168.0.0 -Mask 255.255.255.0

# Add an IP offset
(ip-man-tool -IPAddress 192.168.99.56/28).Add(1).IPAddress
#>

[CmdletBinding(DefaultParameterSetName = 'CIDR')]
param (
    [Parameter(Mandatory, ParameterSetName = 'CIDR', ValueFromPipelineByPropertyName, Position = 0)]
    [ValidateScript({
        $parts = ($_ -split '[|\/]')
        ($parts[0] -as [IPAddress]).AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and 
        $parts[1] -as [int] -in 0..32
    })]
    [Alias('DestinationPrefix')]
    [string]$CIDR,

    [Parameter(ParameterSetName = 'Mask', ValueFromPipelineByPropertyName)]
    [Parameter(ParameterSetName = 'PrefixLength')]
    [Parameter(ParameterSetName = 'WildCard')]
    [ValidateScript({ ($_ -as [IPAddress]).AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork })]
    [Alias('IP')]
    [IPAddress]$IPAddress,

    [Parameter(Mandatory, ParameterSetName = 'Mask')]
    [IPAddress]$Mask,

    [Parameter(Mandatory, ParameterSetName = 'PrefixLength', ValueFromPipelineByPropertyName)]
    [ValidateRange(0, 32)]
    [int]$PrefixLength,

    [Parameter(Mandatory, ParameterSetName = 'WildCard')]
    [IPAddress]$WildCard
)

# Convert CIDR input if provided
if ($CIDR) {
    Write-Verbose "Processing CIDR input: $CIDR"
    $IPAddress, $PrefixLength = $CIDR -split '[|\/]'
    $IPAddress = [IPAddress]$IPAddress
    $PrefixLength = [int]$PrefixLength
    Write-Debug "Extracted IPAddress: $IPAddress, PrefixLength: $PrefixLength"
}

# Calculate Mask if PrefixLength is provided without Mask
if ($PrefixLength -and -not $Mask) {
    Write-Verbose "Calculating Mask from PrefixLength: $PrefixLength"
    $Mask = [IPAddress]([string](4gb - [math]::Pow(2, 32 - $PrefixLength)))
    Write-Debug "Calculated Mask: $Mask"
}

# Calculate Mask if WildCard is provided
if ($WildCard) {
    Write-Verbose "Calculating Mask from WildCard: $WildCard"
    $Mask = [IPAddress](([byte[]]$WildCard.GetAddressBytes() | ForEach-Object { 255 - $_ }) -join '.')
    Write-Debug "Calculated Mask from WildCard: $Mask"
}

# Calculate PrefixLength if Mask is provided without PrefixLength
if (-not $PrefixLength -and $Mask) {
    Write-Verbose "Calculating PrefixLength from Mask: $Mask"
    $PrefixLength = 32 - ($Mask.GetAddressBytes() | ForEach-Object { [math]::Log(256 - $_, 2) }).Sum
    Write-Debug "Calculated PrefixLength: $PrefixLength"
}

# Input Validation for Mask
if (($Mask.GetAddressBytes() -join '') -match '0+1') {
    Write-Warning 'Invalid Mask detected. Consider using a WildCard for more flexibility.'
    return
}

# Ensure the bytes are in big-endian order
function ConvertToBigEndian {
    param ([byte[]]$bytes)
    return [array]::Reverse($bytes); # Reverses the array for big-endian order
}

# Calculate Subnet details
if ($IPAddress -and $PrefixLength) {
    Write-Verbose "Calculating subnet details for IPAddress: $IPAddress and PrefixLength: $PrefixLength"

    # Calculate the network address
    $networkAddressBytes = $IPAddress.GetAddressBytes()
    $maskBytes = $Mask.GetAddressBytes()
    # Perform bitwise AND operation element-wise
    $networkAddressBytes = for ($i = 0; $i -lt $networkAddressBytes.Length; $i++) {
        $networkAddressBytes[$i] -band $maskBytes[$i]
    }
    $NetworkAddress = [IPAddress]([System.Net.IPAddress]::new($networkAddressBytes))

    # Calculate the broadcast address
    $wildcardBytes = $maskBytes | ForEach-Object { 255 - $_ }
    # Perform bitwise OR operation element-wise
    $broadcastAddressBytes = for ($i = 0; $i -lt $networkAddressBytes.Length; $i++) {
        $networkAddressBytes[$i] -bor $wildcardBytes[$i]
    }
    $BroadcastAddress = [IPAddress]([System.Net.IPAddress]::new($broadcastAddressBytes))

    # Calculate the total number of usable hosts
    $usableHosts = [math]::Pow(2, 32 - $PrefixLength) - 2

    # Update the result object
    $Result.NetworkAddress = $NetworkAddress.IPAddressToString
    $Result.BroadcastAddress = $BroadcastAddress.IPAddressToString
    $Result.UsableHosts = $usableHosts
    Write-Debug "Calculated NetworkAddress: $NetworkAddress, BroadcastAddress: $BroadcastAddress, UsableHosts: $usableHosts"
} else {
    Write-Warning "Cannot calculate subnet details. Ensure IPAddress and PrefixLength are provided."
}

# Generate output object
$Result = [PSCustomObject]@{
    IPAddress  = $IPAddress.IPAddressToString
    Mask       = $Mask.IPAddressToString
    PrefixLength = $PrefixLength
}
Write-Verbose "Output Result: $Result"
