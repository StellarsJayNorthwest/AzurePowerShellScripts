[CmdletBinding()]
Param(
    [string]$OutFile = ".\databases.csv"
)

Write-Host

$databaseCsv = @()
$databasesFound = 0
$serversFound = 0
foreach ($sub in Get-AzSubscription) {
    foreach ($rg in Get-AzResourceGroup) {
        Write-Host "Searching resource group $($rg.ResourceGroupName) in subscription $($sub.SubscriptionId)"
        foreach ($s in (Get-AzSqlServer -ResourceGroup $rg.ResourceGroupName)) {
            Write-Host "Found SQL server $($s.ServerName) in resource group $($rg.ResourceGroupName)"
            ++$serversFound
            foreach ($d in (Get-AzSqlDatabase -ServerName $s.ServerName -ResourceGroupName $rg.ResourceGroupName)) {
                if ($d.DatabaseName -eq "master")
                {
                    Write-Host "Found SQL database $($d.DatabaseName) on server $($d.ServerName) in resource group $($d.ResourceGroupName) with SkuName '$($d.SkuName)' and LicenseType '$($d.LicenseType)'"

                    ++$databasesFound

                    $licenseType = $d.LicenseType
                    if (-not $licenseType) {
                        $licenseType = "(none)"
                    }

                    $newCsvLine = [PSCustomObject]@{
                        "SubscriptionId" = $sub.SubscriptionId;
                        "SubscriptionName" = $sub.Name;
                        "ResourceGroup" = $d.ResourceGroupName;
                        "Server" = $d.ServerName;
                        "Database" = $d.DatabaseName;
                        "SkuName" = $d.SkuName;
                        "LicenseType" = $licenseType;
                    }
                    $databaseCsv += $newCsvLine;
                }
            }
        }
    }
}

Write-Host
Write-Host "Found a total of $serversFound servers and $databasesFound databases"

$databaseCsv | Export-Csv $OutFile -Force
Write-Host "Exported databases to $OutFile"
