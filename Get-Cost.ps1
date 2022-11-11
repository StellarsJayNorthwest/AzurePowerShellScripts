[CmdletBinding()]
Param(
    [int] $MonthsToLookBack = 3,
    [string]$OutFile = ".\cost.csv"
)

Write-Host

$subscriptions = Get-AzSubscription

$csvArray = @()

$monthIndex = $MonthsToLookBack
while ($monthIndex -gt 0) {

    $today = Get-Date -Format "MM/dd/yyyy"
    $monthStart = Get-Date $today -Day 1
    $monthStart = $monthStart.AddMonths(-1 * $monthIndex)
    $monthEnd = $monthStart.AddMonths(1).AddSeconds(-1)

    foreach ($subscription in $subscriptions) {
        $subscription | Select-AzSubscription | Out-Null

        Write-Host "Gathering cost from $monthStart to $monthEnd for $($subscription.Name)"

        $consumptionDetails = Get-AzConsumptionUsageDetail -StartDate $monthStart -EndDate $monthEnd

        Write-Host "Retrieved $($consumptionDetails.Count) consumption usage entries"

        $cost = 0
        foreach ($c in $consumptionDetails) {
            $cost = $cost + $c.PretaxCost
            $currency = $c.Currency
        }

        Write-Host "Pre-tax cost from $monthStart to $monthEnd was $cost in $currency"

        $row = "" | Select SubscriptionName, SubscriptionId, Start, End, Cost, Currency
        $row.SubscriptionName = $subscription.Name
        $row.SubscriptionId = $subscription.Id
        $row.Start = Get-Date $monthStart -Format "MM/dd/yyyy"
        $row.End = Get-Date $monthEnd -Format "MM/dd/yyyy"
        $row.Cost = $cost
        $row.Currency = $currency
        $csvArray += $row

    }

    $monthIndex = $monthIndex - 1
}

$csvArray | Export-Csv $OutFile -Force -NoTypeInformation
Write-Host "Exported $($csvArray.Count) entries to $OutFile"
