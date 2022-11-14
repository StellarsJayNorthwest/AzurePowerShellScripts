[CmdletBinding()]
Param(
    [int] $MonthsBackToStart = 12,
    [int] $MonthsToCollect = 12,
    [string]$OutFile = ".\cost.csv"
)

Write-Host

$startTime = Get-Date

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

$today = Get-Date -Format "MM/dd/yyyy"

$csvArray = @()

$monthIndex = 0
while ($monthIndex -lt $MonthsToCollect) {

    $monthStart = (Get-Date $today -Day 1).AddMonths(-1 * $MonthsBackToStart + $monthIndex)
    $monthEnd = $monthStart.AddMonths(1).AddSeconds(-1)

    foreach ($subscription in $subscriptions) {
        $subscription | Select-AzSubscription | Out-Null

        # Determine the management group name of this subscription.
        $managementGroupName = "Unknown"
        if ($managementGroupHashTable.ContainsKey($Subscription.Id)) {
            $managementGroupName = $managementGroupHashTable[$Subscription.Id]
        }

        Write-Host
        Write-Host "Gathering cost from $monthStart to $monthEnd for $managementGroupName $($subscription.Name) at $(Get-Date)"

        $consumptionDetails = Get-AzConsumptionUsageDetail -StartDate $monthStart -EndDate $monthEnd

        # Don't output an entry in the CSV if there were no cost details
        if ($consumptionDetails.Count -ne 0) {

            Write-Host "Retrieved $($consumptionDetails.Count) consumption usage entries for $($subscription.Name) at $(Get-Date)"

            # We must now process all of the consumption detail objects. Each detail object contains the name of the
            # resource group embedded in the very long "InstanceId" string. Create a hash table where the key is the
            # resource group name and the value is the sum of the costs. 
            $costHashTable = @{}
            $currency = ""
            foreach ($c in $consumptionDetails) {

                # Save the currency string. We assume all details for this subscription use the same currency.
                $currency = $c.Currency

                if ($c.InstanceId -match "resourceGroups/(.*?)/") {

                    $key = $Matches[1]

                    # For uniformity, convert all resource group names to lower case. This could be commented out.
                    $key = $key.ToLower()

                    # Write-Host "Cost detail: $key cost $($c.PretaxCost)"

                    # If the key exists, add this cost. Otherwise create a new key with this cost.
                    if ($costHashTable.ContainsKey($key)) {
                        $costHashTable[$key] = $costHashTable[$key] + $c.PretaxCost
                    } else {
                        $costHashTable[$key] = $c.PretaxCost
                    }

                } else {

                    Write-Host "Failed to get resource group from InstanceId `'$($c.InstanceId)`'"
                }
            }

            # Now we have the cost by resource group in $costHashTable. Output one CSV line for each entry $costHashTable.
            foreach ($resourceGroupName in $costHashTable.Keys) { 

                # Determine the location of this resource group by getting it from Az-GetResourceGroup. If the resource
                # group no longer exists, then use "Unknown" as the location.
                $location = "Unknown"
                $rg = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
                if ($rg) {
                    $location = $rg.Location
                }

                # Write-Host "Pre-tax cost from $monthStart to $monthEnd for $resourceGroupName in $location was $($costHashTable[$resourceGroupName]) $currency"

                $row = "" | Select ManagementGroup, SubscriptionName, SubscriptionId, ResourceGroup, Location, Start, End, Cost, Currency
                $row.ManagementGroup = $managementGroupName
                $row.SubscriptionName = $subscription.Name
                $row.SubscriptionId = $subscription.Id
                $row.ResourceGroup = $resourceGroupName
                $row.Location = $location
                $row.Start = Get-Date $monthStart -Format "MM/dd/yyyy"
                $row.End = Get-Date $monthEnd -Format "MM/dd/yyyy"
                $row.Cost = $costHashTable[$resourceGroupName]
                $row.Currency = $currency
                $csvArray += $row
            }
        } else {
            Write-Host "Unable to get consumption usage entries for $($subscription.Name) at $(Get-Date)"
        }

        Write-Host
        Write-Host "------------------------------------------------------------"
    }

    $monthIndex = $monthIndex + 1
}

$csvArray | Export-Csv $OutFile -Force -NoTypeInformation
Write-Host "Exported $($csvArray.Count) entries to $OutFile"
Write-Host "Script started at $startTime and finished at $(Get-Date)"
Write-Host "Script run time: $((Get-Date) - $startTime)"
