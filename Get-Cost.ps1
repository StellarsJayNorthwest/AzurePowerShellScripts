[CmdletBinding()]
Param(
    [int] $MonthsBackToStart = 2,
    [int] $MonthsToCollect = 2,
    [string] $OutFile = ".\cost.csv",
    [switch] $Append
)

Write-Host

$startTime = Get-Date

if ((Test-Path $OutFile) -and $Append) {
    Write-Host
    Write-Host "Output lines will be appended to $Outfile"
}

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

                # Save the currency string. We assume all details use the same currency.
                $currency = $c.Currency

                # Use a regular expression to parse the resource group name out of the InstanceId.
                if ($c.InstanceId -match "resourceGroups/(.*?)/") {

                    # The name of the resource group has been saved in the Matches variable by PowerShell.
                    $resourceGroupName = $Matches[1]

                    # For uniformity, convert all resource group names to lower case. This could be commented out.
                    $resourceGroupName = $resourceGroupName.ToLower()

                    # Write-Host "Cost detail: $resourceGroupName cost $($c.PretaxCost)"

                    # If the key exists, add this cost. Otherwise create a new key with this cost.
                    if ($costHashTable.ContainsKey($resourceGroupName)) {
                        $costHashTable[$resourceGroupName] = $costHashTable[$resourceGroupName] + $c.PretaxCost
                    } else {
                        $costHashTable[$resourceGroupName] = $c.PretaxCost
                    }

                } else {

                    Write-Host "Failed to get resource group name from InstanceId `'$($c.InstanceId)`'"
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

                $row = "" | Select ManagementGroup, SubscriptionName, SubscriptionId, ResourceGroup, Location, Start, End, PretaxCost, Currency
                $row.ManagementGroup = $managementGroupName
                $row.SubscriptionName = $subscription.Name
                $row.SubscriptionId = $subscription.Id
                $row.ResourceGroup = $resourceGroupName
                $row.Location = $location
                $row.Start = Get-Date $monthStart -Format "MM/dd/yyyy"
                $row.End = Get-Date $monthEnd -Format "MM/dd/yyyy"
                $row.PretaxCost = $costHashTable[$resourceGroupName]
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

$csvArray | Export-Csv $OutFile -NoTypeInformation -Append:$Append
Write-Host "Exported with Append:$Append $($csvArray.Count) entries to $OutFile"
Write-Host "Script started at $startTime and finished at $(Get-Date)"
Write-Host "Script run time: $((Get-Date) - $startTime)"
