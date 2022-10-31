#
# Pre-requisites:
# Azure PowerShell must be installed on the machine.
# Run Connect-AzAccount in the current PowerShell session.
#

[CmdletBinding()]
Param(
    [string]$OutFile = ".\sqlservers.csv"
)

Write-Host

# Create an empty array to hold the CSV entries. As the script runs it will add elements to $sqlServersCsv for each
# SQL server found.
$sqlServersCsv = @()

# First, enumerate all of the available subscriptions. This could be changed to take a list of subscriptions on the
# command line, or take a list of subscriptions from a file. For now we'll just enumerate all subscriptions that the
# user has access to.
foreach ($subscription in Get-AzSubscription) {

    Write-Host "Searching subscription $($subscription.Name) $($subscription.SubscriptionId) for SQL servers ..."

    # Iterate all of the available SQL servers in this Azure subscription.
    foreach ($sqlServer in (Get-AzSqlServer)) {

        Write-Host "Found SQL server `"$($sqlServer.ServerName)`" in subscription `"$($subscription.Name)`", resource group `"$($sqlServer.ResourceGroupName)`""

        # !!! NOTE: I'm not certain looking up the VM by name will work here but we can try it out. !!!
        #
        # Try to retrieve the name of the SQL server as an Azure VM. If this fails then there is no standalone Azure VM
        # with that name so this must be a managed SQL server.
        $azureVm = Get-AzVM -Name "my-test-vmn"
        if ($azureVm) {
            $managedVm = "Yes"
            $vmSize = $azureVm.HardwareProfile.VmSize
            $osType = $azureVm.StorageProfile.OsDisk.OsType
        } else {
            $managedVm = "No"
            $vmSize = "Unknown"
            $osType = "Unknown"
        }


        # Create a new entry for the CSV with each of the desired properties.
        $newCsvEntry = [PSCustomObject] @{
            "SubscriptionId" = $sub.SubscriptionId;
            "SubscriptionName" = $sub.Name;
            "ResourceGroup" = $sqlServer.ResourceGroupName;
            "Location" = $sqlServer.Location;
            "ServerName" = $sqlServer.ServerName;
            "ServerVersion" = $sqlServer.ServerVersion;
            "ManagedVm" = $managedVm;
            "VmSize" = $vmSize;
            "OsType" = $osType;
            "ResourceId" = $sqlServer.ResourceId;
        }

        # Add this new CSV entry to the end of the CSV entry array.
        $sqlServersCsv += $newCsvEntry;
    }
}

# Export the array of CSV entries to the output file.
$sqlServersCsv | Export-Csv $OutFile -Force
Write-Host "Exported $($sqlServersCsv.Count) SQL server entries to $OutFile"
