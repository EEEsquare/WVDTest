$RGPrefix = "rg-JustComma-"
$RGSuffixes = @("basics","hostpool-1","hostpool-2","hostpool-3")
$RGLocation = ""

#select your deployment region
do {
    $regions = @("")
    Get-AzLocation | foreach -Begin { $i = 0 } -Process {
        $i++
        $regions += "{0}. {1}" -f $i, $_.Location
    } -outvariable menu
    $regions | Format-Wide { $_ } -Column 4 -Force
    $r = Read-Host "Select a region to deploy to by number"
    $RGLocation = $regions[$r].Split()[1]
    if ($RGLocation -eq $null) { Write-Host "You must make a valid selection" -ForegroundColor Red }
    else {
        Write-Host "Selecting region $($regions[$r])" -ForegroundColor Green
    }
}
until ($RGLocation -ne $null)

foreach ($RGSuffix in $RGSuffixes)
{
   New-AzResourceGroup -Name "$($RGPrefix)$($RGSuffix)" -Location $RGLocation
}  
#remember your region :-)  
