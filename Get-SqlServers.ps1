#
# Pre-requisites:
# Azure PowerShell must be installed on the machine.
# Run Connect-AzAccount in the current PowerShell session.
#
# To specify one or more subscriptions use:
# .\Get-SqlServers.ps1 -SubscriptionIds ("69db6f5b-4fbe-42df-b96e-1ff93b45f90f", "d58769f5-f832-4cd5-9dd6-49529bf2ba56")
#

[CmdletBinding()]
Param(
    [string[]]$SubscriptionIds,
    [string]$OutFile = ".\sqlservers.csv"
)

Write-Host

# Create an empty array to hold the CSV entries. As the script runs it will add elements to $sqlServersCsv for each
# SQL server found.
$sqlServersCsv = @()

# Determine the list of subscription IDs to search. If one or more subscription IDs was passed in the SubscriptionIds
# argument, use those subscriptions. If the SubscriptionIds argument was empty, search all available subscriptions.
$subscriptionsToSearch = @()
if ($SubscriptionIds) {
    # For each subscription ID in the input parameter, retrieve the subscription object and add it to the list.
    foreach ($id in $SubscriptionIds) {
        $sub = Get-AzSubscription -SubscriptionId $id
        $subscriptionsToSearch += $sub
    }
} else {
    $subscriptionsToSearch = Get-AzSubscription
}

# First, enumerate all of the available subscriptions. This could be changed to take a list of subscriptions on the
# command line, or take a list of subscriptions from a file. For now we'll just enumerate all subscriptions that the
# user has access to.
foreach ($subscription in $subscriptionsToSearch) {

    Write-Host "Searching subscription named `"$($subscription.Name)`" with ID $($subscription.SubscriptionId)..."

    # Select this subscription. This will cause Get-AzSqlServer will retrieve all of the SQL servers for this subscription.
    $subscription | Select-AzSubscription 

    # Using Get-AzSqlServer, iterate all of the available SQL servers in this Azure subscription.
    foreach ($sqlServer in Get-AzSqlServer) {

        Write-Host "Get-AzSqlServer returned SQL server `"$($sqlServer.ServerName)`" in resource group `"$($sqlServer.ResourceGroupName)`""

        # See if this is a standlone Azure VM by invoking Get-AzVM on the SQL server's name.
        # Determine values for VmType, VmSizeOrSku, OsType, LicenseType.
        $azureVm = Get-AzVM -Name $sqlServer.ServerName
        if ($azureVm) {
            Write-Host "Get-AzVM returned a standalone VM for `"$($sqlServer.ServerName)`" in resource group `"$($sqlServer.ResourceGroupName)`""
            $vmType = "Standalone"
            $vmSizeOrSku = $azureVm.HardwareProfile.VmSize
            $osType = $azureVm.StorageProfile.OsDisk.OsType
            $licenseType = $azureVm.LicenseType
        } else {
            $vmType = "AzSqlServer"
            $vmSizeOrSku = ""
            $osType = ""
            $licenseType = ""
        }

        # Create a new entry for the CSV with each of the desired properties.
        $newCsvEntry = [PSCustomObject] @{
            "Name" = $sqlServer.ServerName;
            "VmType" = $vmType;
            "SubscriptionId" = $subscription.SubscriptionId;
            "SubscriptionName" = $subscription.Name;
            "ResourceGroup" = $sqlServer.ResourceGroupName;
            "Location" = $sqlServer.Location;
            "ServerVersion" = $sqlServer.ServerVersion;
            "VmSizeOrSku" = $vmSizeOrSku;
            "OsType" = $osType;
            "LicenseType" = $licenseType;
            "ResourceId" = $sqlServer.ResourceId;
        }

        # Add this new CSV entry to the end of the CSV entry array.
        $sqlServersCsv += $newCsvEntry;
    }

    # Using Get-AzSqlVM, iterate all of the available SQL VMs in this Azure subscription.
    foreach ($sqlVm in Get-AzSqlVM) {

        Write-Host "Get-AzSqlVM returned SQL server VM `"$($sqlVm.Name)`" in resource group `"$($sqlVm.ResourceGroupName)`""

        # Determine values for VmType, VmSizeOrSku, OsType, LicenseType.
        # Note that the "Offer" field is reported as "OsType" since it seems to contain OS details.
        $vmType = "AzSqlVM"
        $vmSizeOrSku = $sqlVm.Sku
        $osType = $sqlVm.Offer
        $licenseType = $sqlVm.LicenseType

        # Create a new entry for the CSV with each of the desired properties.
        $newCsvEntry = [PSCustomObject] @{
            "Name" = $sqlVm.Name;
            "VmType" = $vmType;
            "SubscriptionId" = $subscription.SubscriptionId;
            "SubscriptionName" = $subscription.Name;
            "ResourceGroup" = $sqlVm.ResourceGroupName;
            "Location" = $sqlVm.Location;
            "ServerVersion" = "";
            "VmSizeOrSku" = $vmSizeOrSku;
            "OsType" = $osType;
            "LicenseType" = $licenseType;
            "ResourceId" = $sqlVm.ResourceId;
        }

        # Add this new CSV entry to the end of the CSV entry array.
        $sqlServersCsv += $newCsvEntry;
    }
}

# Export the array of CSV entries to the output file.
$sqlServersCsv | Export-Csv $OutFile -Force -NoTypeInformation
Write-Host "Exported $($sqlServersCsv.Count) entries to $OutFile"
