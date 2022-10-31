[CmdletBinding()]
Param(
    [DateTime] $Start = ((Get-Date).AddMonths(-1)),
    [DateTime] $End = (Get-Date),
    [string]$ResourceGroup)

Write-Host

$sub = Get-AzSubscription
if ($ResourceGroup) {
    Write-Host "Retrieving consumption usage details for subscription $($sub.SubscriptionId) from $Start to $End for resource group $ResourceGroup"
    $consumptionDetails = Get-AzConsumptionUsageDetail -StartDate $Start -EndDate $End -ResourceGroup $ResourceGroup
}
else {
    Write-Host "Retrieving consumption usage details for subscription $($sub.SubscriptionId) from $Start to $End"
    $consumptionDetails = Get-AzConsumptionUsageDetail -StartDate $Start -EndDate $End
}

Write-Host "Retrieved $($consumptionDetails.Count) consumption usage entries"

$cost = 0
foreach ($c in $consumptionDetails.PretaxCost) {
    $cost += $c
}
Write-Host ("Pre-tax cost from $Start to $End was `${0:n2}" -f $cost)
