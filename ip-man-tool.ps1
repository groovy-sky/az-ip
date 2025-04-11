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

# Calculate Subnet details - Alternative Method
if ($IPAddress -and $Mask) {
    Write-Verbose "Calculating Subnet and Broadcast using alternative method for IPAddress: $IPAddress and Mask: $Mask"
    
    # Convert IP and Mask to BigInteger for precise bitwise operations
    $ipBytes = [System.Net.IPAddress]::Parse($IPAddress.IPAddressToString).GetAddressBytes()
    $maskBytes = [System.Net.IPAddress]::Parse($Mask.IPAddressToString).GetAddressBytes()
    $ipBigInt = [System.Numerics.BigInteger]::new($ipBytes -join '')
    $maskBigInt = [System.Numerics.BigInteger]::new($maskBytes -join '')

    # Calculate Subnet
    $subnetBigInt = $ipBigInt -band $maskBigInt
    $Subnet = [System.Net.IPAddress]::new($subnetBigInt.ToByteArray())
    Write-Debug "Calculated Subnet: $Subnet"

    # Calculate Broadcast
    $wildcardBigInt = -bnot $maskBigInt -bor $subnetBigInt
    $Broadcast = [System.Net.IPAddress]::new($wildcardBigInt.ToByteArray())
    Write-Debug "Calculated Broadcast: $Broadcast"
} else {
    Write-Error "Error: IPAddress or Mask is null. Cannot calculate Subnet or Broadcast."
    return
}

$IPcount = [math]::Pow(2, 32 - $PrefixLength)
Write-Debug "Calculated number of IP addresses in Subnet: $IPcount"

# Generate output object
$Result = [PSCustomObject]@{
    IPAddress  = $IPAddress.IPAddressToString
    Mask       = $Mask.IPAddressToString
    PrefixLength = $PrefixLength
}
Write-Verbose "Output Result: $Result"
