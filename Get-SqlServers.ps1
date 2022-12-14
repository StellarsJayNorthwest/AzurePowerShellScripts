#
# Pre-requisites:
# Azure PowerShell must be installed on the machine.
# Run Connect-AzAccount in the current PowerShell session.
#
# To specify one or more subscriptions by name or ID on the command line use:
# .\Get-SqlServers.ps1 -Subscriptions "69db6f5b-4fbe-42df-b96e-1ff93b45f90f"
# .\Get-SqlServers.ps1 -Subscriptions "Subscription name"
# .\Get-SqlServers.ps1 -Subscriptions ("Subscription name", "d58769f5-f832-4cd5-9dd6-49529bf2ba56")
#

[CmdletBinding()]
Param(
    [string[]]$Subscriptions,
    [string]$OutFile = ".\sqlservers.csv",
    [int]$CostDays = 0
)

Write-Host

# This function adds a line to the array of CSV entries. Having this code in a function eliminates the danger of 
# having different copies of this code create CSV entries differently. It also makes the foreach loops below easier
# to read. This function can take an AzVM object, or an AzSqlVM object, or an AzSqlServer object.
function Add-CsvEntryForServer() {
    param (
        $Subscription,          # The subscription object this server belongs to.
        $AzVm,                  # An AzVm object returned from Get-AzVm, if this server has one.
        $AzSqlVm,               # An AzSqlVm object returned from Get-AzSqlVm, if this server has one.
        $AzSqlServer,           # An AzSqlServer object returned from Get-AzSqlServer, if this server has one.
        [int]$CostDays          # The number of days to collect cost for or zero to skip cost. 
    )

    # Determine the management group name of the subscription that this server belongs to.
    $managementGroupName = "Unknown"
    if ($global:managementGroupHashTable.ContainsKey($Subscription.Id)) {
        $managementGroupName = $global:managementGroupHashTable[$Subscription.Id]
    }

    # Determine the value of the resource ID column.
    $resourceId = "Unknown"
    if ($AzSqlServer -and $AzSqlServer.ResourceId) {
        $resourceId = $AzSqlServer.ResourceId
    } elseif ($AzSqlVm -and $AzSqlVm.ResourceId) {
        $resourceId = $AzSqlVm.ResourceId
    } elseif ($AzVm -and $AzVm.Id) {
        $resourceId = $AzVm.Id
    }

    # Determine the value of the VmType column depending on which objects were passed in.
    $vmType = "Unknown"
    if ($AzSqlServer) {
        $vmType = "AzSqlServer"
    } elseif ($AzSqlVm) {
        $vmType = "AzSqlVm"
    } elseif ($AzVm) {
        $vmType = "AzVm"
    }

    # Determine the value of the name column.
    $name = "Unknown"
    if ($AzSqlServer -and $AzSqlServer.ServerName) {
        $name = $AzSqlServer.ServerName
    } elseif ($AzSqlVm -and $AzSqlVm.Name) {
        $name = $AzSqlVm.Name
    } elseif ($AzVm -and $AzVm.Name) {
        $name = $AzVm.Name
    }

    # Determine the value of the resource group column.
    $resourceGroup = "Unknown"
    if ($AzSqlServer) {
        $resourceGroup = $AzSqlServer.ResourceGroupName
    } elseif ($AzSqlVm) {
        $resourceGroup = $AzSqlVm.ResourceGroupName
    } elseif ($AzVm) {
        $resourceGroup = $AzVm.ResourceGroupName
    }

    # Output a line to the console so the user knows what's happening.
    Write-Host "Processing $vmType $name in $resourceGroup `'$($Subscription.Name)`'"

    # Determine the value of the location column.
    $location = "Unknown"
    if ($AzSqlServer) {
        $location = $AzSqlServer.Location
    } elseif ($AzSqlVm) {
        $location = $AzSqlVm.Location
    } elseif ($AzVm) {
        $location = $AzVm.Location
    }

    # Determine the value of the AzSqlServerVersion column. This is "na" unless the object is an AzSqlServer.
    $azSqlServerVersion = "na"
    if ($AzSqlServer) {
        $azSqlServerVersion = $AzSqlServer.ServerVersion
    }

    # Determine the value of the VmSize column. This is "Unknown" unless an AzVm was passed in.
    $vmSize = "na"
    if ($AzVm -and $AzVm.HardwareProfile.VmSize.ToString()) {
        $vmSize = $AzVm.HardwareProfile.VmSize.ToString()
    }

    # Determine the number of cores if an AzVm was passed in. This is done by looking up the VM size for the region and
    # finding the VM size entry (i.e. the instance type) matching the VmSize string of the VM.
    $numberOfCores = "0"
    if ($AzVm) {
        $azVmSize = Get-AzVMSize -Location $AzVm.Location | Where-Object { $_.Name -eq $AzVm.HardwareProfile.VmSize }
        $numberOfCores = $azVmSize.NumberOfCores
    }

    # Determine the value of the OsType column. This is "Unknown" unless the object is an AzVm.
    $osType = "Unknown"
    if ($AzVm -and $AzVm.StorageProfile.OsDisk.OsType.ToString()) {
        $osType = $AzVm.StorageProfile.OsDisk.OsType.ToString()
    }

    # Determine the value of the SKU column. Use Offer if this is an AzSqlVm else the SKU from the AzVm storage profile.
    $sku = "Unknown"
    if ($AzSqlVm -and $AzSqlVm.Offer) {
        $sku = $AzSqlVm.Offer
    }
    elseif ($AzVm -and $AzVm.StorageProfile.ImageReference.Sku) {
        $sku = $AzVm.StorageProfile.ImageReference.Sku
    }


    # Determine the value of the license type column. This is from either the AzSqlVm or the AzVm object, otherwise "na".
    $licenseType = "na"
    if ($AzSqlVm -and $AzSqlVm.LicenseType) {
        $licenseType = $AzSqlVm.LicenseType
    } elseif ($AzVm -and $AzVm.LicenseType) {
        $licenseType = $AzVm.LicenseType
    }

    # Compute cost for the AZ VM, if one was passed in. This is done by collecting the specified number of days of 
    # consumption usage details for the VM resource ID.
    [float]$cost = 0.0
    $currency = "na"
    $costUsageDetailCount = 0
    if ($AzVm -and ($CostDays -gt 0)) {
        $start = (Get-Date).AddDays(-$CostDays)
        $end = Get-Date
        $usageDetails = Get-AzConsumptionUsageDetail -InstanceId $AzVm.Id -StartDate $start -EndDate $end -IncludeMeterDetails -IncludeAdditionalProperties
        foreach ($usageDetail in $usageDetails) {
            $cost += $usageDetail.PretaxCost
            $currency = $usageDetail.Currency.ToString()
            ++$costUsageDetailCount
        }
    }

    # Create a new entry for the CSV with each of the desired properties.
    $newCsvEntry = [PSCustomObject] @{
        "ManagementGroup" = $managementGroupName;
        "Name" = $name;
        "VmType" = $vmType;
        "SubscriptionId" = $Subscription.SubscriptionId;
        "SubscriptionName" = $Subscription.Name;
        "ResourceGroup" = $resourceGroup;
        "Location" = $location;
        "AzSqlServerVersion" = $azSqlServerVersion;
        "VmSize" = $vmSize;
        "NumberOfCores" = $numberOfCores;
        "OsType" = $osType;
        "SKU" = $sku;
        "LicenseType" = $licenseType;
        "CostDays" = $CostDays;
        "CostDetailCount" = $costUsageDetailCount;
        "PretaxCost" = $cost;
        "Currency" = $currency;
        "ResourceId" = $resourceId;
    }

    # Add the new CSV entry to the end of the CSV entry array.
    $global:sqlServersCsv += $newCsvEntry;
}

# Determine the list of subscription IDs to search. If one or more subscriptions were passed in the Subscriptions
# argument, use those subscriptions. If the Subscriptions argument was empty, search all available subscriptions.
$subscriptionsToSearch = @()
if ($Subscriptions) {
    # For each subscription in the input parameter, try to retrieve the subscription first by ID and then by name.
    foreach ($subscription in $Subscriptions) {
        $sub = Get-AzSubscription -SubscriptionId $subscription -ErrorAction SilentlyContinue
        if (-not $sub) {
            $sub = Get-AzSubscription -SubscriptionName $subscription
        }

        if (-not $sub) {
            throw "Error: Could not retrieve subscription by name or ID: `"$subscription`""
        }

        $subscriptionsToSearch += $sub
    }
} else {
    $subscriptionsToSearch = Get-AzSubscription
}

# Before we start iterating VMs, retrieve the management groups. Create a hash table associating each subscription with
# the name of a management group. We'll use this hash table to determine which management group each VM belongs to.
$global:managementGroupHashTable = @{}
foreach ($global:managementGroup in Get-AzManagementGroup)
{
    $expandedGroup = Get-AzManagementGroup -GroupId $managementGroup.Name -Expand
    foreach ($child in $expandedGroup.Children) {

        # It is a bit confusing but the "Name" property of each child in the management group is actually
        # the subscription ID. The "Name" property of the management group is DEV/PROD or whatever.
        $global:managementGroupHashTable[$child.Name] = $managementGroup.Name
    }
}

Write-Host "`nComplete list of subscriptions IDs and their management groups:"
$global:managementGroupHashTable | Format-Table -AutoSize
Write-Host

# Create an empty array to hold the CSV entries. As the script runs it will add elements to $sqlServersCsv for each
# SQL server found.
$global:sqlServersCsv = @()

# First, enumerate all of the available subscriptions. This could be changed to take a list of subscriptions on the
# command line, or take a list of subscriptions from a file. For now we'll just enumerate all subscriptions that the
# user has access to.
foreach ($subscription in $subscriptionsToSearch) {

    Write-Host "Searching subscription named `"$($subscription.Name)`" with ID $($subscription.SubscriptionId)..."

    # Select this subscription so that subsequent Get operations pull from this subscription.
    $subscription | Select-AzSubscription | Out-Null
    Write-Host

    # Using Get-AzSqlServer, iterate all of the available SQL servers in this Azure subscription.
    foreach ($sqlServer in Get-AzSqlServer) {

        # Try to get an AzVm object for the SQL server's name.
        $azureVm = Get-AzVM -Name $sqlServer.ServerName

        Add-CsvEntryForServer -Subscription $subscription -AzSqlServer $sqlServer -AzVm $azureVm -CostDays $CostDays
    }

    # Using Get-AzSqlVM, iterate all of the available SQL VMs in this Azure subscription.
    foreach ($sqlVm in Get-AzSqlVM) {

        # Try to get an AzVm object for the SQL VM's name.s
        $azureVm = Get-AzVM -Name $sqlVm.Name

        Add-CsvEntryForServer -Subscription $subscription -AzSqlVm $sqlVm -AzVm $azureVm -CostDays $CostDays
    }

    # Using Get-AzVM, iterate all of the available Azure VMs in this Azure subscription. Some of these VMs are also
    # AzSqlVms so skip those ones to avoid duplication.
    foreach ($azVm in Get-AzVM) {
        
        # Only include this VM if it is not an AzSqlVm
        if (Get-AzSqlVm -ResourceGroupName $azVm.ResourceGroupName -Name $azVm.Name -ErrorAction SilentlyContinue) {
            Write-Host "Skipping AzVm that is also an AzSqlVm: $($azVm.Name) in $($azVm.ResourceGroupName) `'$($subscription.Name)`'"
        } else {
            Add-CsvEntryForServer -Subscription $subscription -AzVm $azVm -CostDays $CostDays
        }
    }
}

# Export the array of CSV entries to the output file.
$global:sqlServersCsv | Export-Csv $OutFile -Force -NoTypeInformation
Write-Host "Exported $($global:sqlServersCsv.Count) entries to $OutFile"
