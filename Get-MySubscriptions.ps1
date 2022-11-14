$array = @()

foreach ($subscription in Get-AzSubscription) {
    $row = "" | Select Name, Id
    $row.Name = $subscription.Name
    $row.Id = $subscription.Id
    $array += $row
}

$array