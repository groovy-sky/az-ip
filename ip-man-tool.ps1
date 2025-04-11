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
    $IPAddress, $PrefixLength = $CIDR -split '[|\/]'
    $IPAddress = [IPAddress]$IPAddress
    $PrefixLength = [int]$PrefixLength
}

# Calculate Mask if PrefixLength is provided without Mask
if ($PrefixLength -and -not $Mask) {
    $Mask = [IPAddress]([string](4gb - [math]::Pow(2, 32 - $PrefixLength)))
}

# Calculate Mask if WildCard is provided
if ($WildCard) {
    $Mask = [IPAddress](([byte[]]$WildCard.GetAddressBytes() | ForEach-Object { 255 - $_ }) -join '.')
}

# Calculate PrefixLength if Mask is provided without PrefixLength
if (-not $PrefixLength -and $Mask) {
    $PrefixLength = 32 - ($Mask.GetAddressBytes() | ForEach-Object { [math]::Log(256 - $_, 2) }).Sum
}

# Input Validation for Mask
if (($Mask.GetAddressBytes() -join '') -match '0+1') {
    Write-Warning 'Invalid Mask detected. Consider using a WildCard for more flexibility.'
    return
}

# Calculate Subnet details
$Subnet = $IPAddress.Address -band $Mask.Address
$Broadcast = [IPAddress](([byte[]]$Subnet.GetAddressBytes() | ForEach-Object { $_ }) + ([byte[]]$WildCard.GetAddressBytes() | ForEach-Object { $_ }))
$IPcount = [math]::Pow(2, 32 - $PrefixLength)

# Generate output object
$Result = [PSCustomObject]@{
    IPAddress  = $IPAddress.IPAddressToString
    Mask       = $Mask.IPAddressToString
    PrefixLength = $PrefixLength
}
