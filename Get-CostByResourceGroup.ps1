[CmdletBinding()]
Param(
    [int] $MonthsBackToStart = 6,
    [int] $MonthsToCollect = 2,
    [string]$OutFile = ".\cost.csv"
)

Write-Host

# Before we start iterating VMs, retrieve the management groups. Create a hash table associating each subscription with
# the name of a management group. We'll use this hash table to determine which management group each VM belongs to.
$managementGroupHashTable = @{}
foreach ($managementGroup in Get-AzManagementGroup)
{
    $expandedGroup = Get-AzManagementGroup -GroupId $managementGroup.Name -Expand
    foreach ($child in $expandedGroup.Children) {

        # It is a bit confusing but the "Name" property of each child in the management group is actually
        # the subscription ID. The "Name" property of the management group is DEV/PROD or whatever.
        $managementGroupHashTable[$child.Name] = $managementGroup.Name
    }
}

Write-Host "`nComplete list of subscriptions IDs and their management groups:"
$managementGroupHashTable | Format-Table -AutoSize
Write-Host

# Get the list of subscriptions
$subscriptions = Get-AzSubscription

$csvArray = @()

$monthIndex = 0
while ($monthIndex -lt $MonthsToCollect) {

    $today = Get-Date -Format "MM/dd/yyyy"
    $monthStart = (Get-Date $today -Day 1).AddMonths(-1 * $MonthsBackToStart)
    $monthStart = $monthStart.AddMonths($monthIndex)
    $monthEnd = $monthStart.AddMonths(1).AddSeconds(-1)

    foreach ($subscription in $subscriptions) {
        $subscription | Select-AzSubscription | Out-Null

        Write-Host
        Write-Host "Gathering cost from $monthStart to $monthEnd for $($subscription.Name)"

        foreach($resourceGroup in Get-AzResourceGroup) {

            Write-Host
            Write-Host "Gathering cost from $monthStart to $monthEnd for $($resourceGroup.ResourceGroupName) in $($subscription.Name)"

            $consumptionDetails = Get-AzConsumptionUsageDetail -StartDate $monthStart -EndDate $monthEnd -ResourceGroup $resourceGroup.ResourceGroupName

            # Don't output an entry in the CSV if there were no cost details
            if ($consumptionDetails.Count -ne 0) {

                Write-Host "Retrieved $($consumptionDetails.Count) consumption usage entries for $($resourceGroup.ResourceGroupName) in $($subscription.Name)"

                # Determine the management group name of the subscription.
                $managementGroupName = "Unknown"
                if ($managementGroupHashTable.ContainsKey($Subscription.Id)) {
                    $managementGroupName = $managementGroupHashTable[$Subscription.Id]
                }

                $cost = 0
                $currency = ""
                foreach ($c in $consumptionDetails) {
                    $cost = $cost + $c.PretaxCost
                    $currency = $c.Currency
                }

                Write-Host "Pre-tax cost from $monthStart to $monthEnd was $cost in $currency"

                $row = "" | Select ManagementGroup, SubscriptionName, SubscriptionId, ResourceGroup, Location, Start, End, Cost, Currency
                $row.ManagementGroup = $managementGroupName
                $row.SubscriptionName = $subscription.Name
                $row.SubscriptionId = $subscription.Id
                $row.ResourceGroup = $resourceGroup.ResourceGroupName
                $row.Location = $resourceGroup.Location
                $row.Start = Get-Date $monthStart -Format "MM/dd/yyyy"
                $row.End = Get-Date $monthEnd -Format "MM/dd/yyyy"
                $row.Cost = $cost
                $row.Currency = $currency
                $csvArray += $row
            } else {
                Write-Host "Unable to get consumption usage entries for $($resourceGroup.ResourceGroupName) in $($subscription.Name)"
            }

            Write-Host
            Write-Host "------------------------------------------------------------"
        }
    }

    $monthIndex = $monthIndex + 1
}

$csvArray | Export-Csv $OutFile -Force -NoTypeInformation
Write-Host "Exported $($csvArray.Count) entries to $OutFile"
