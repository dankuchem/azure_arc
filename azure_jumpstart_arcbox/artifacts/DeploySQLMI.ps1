Start-Transcript -Path C:\ArcBox\deploySQL.log

# Deployment environment variables
$controllerName = "arcbox-dc"

# Deploying Azure Arc SQL Managed Instance
Write-Host "Deploying Azure Arc SQL Managed Instance"
Write-Host "`n"

$dataControllerId = $(az resource show --resource-group $env:resourceGroup --name $controllerName --resource-type "Microsoft.AzureArcData/dataControllers" --query id -o tsv)
$customLocationId = $(az customlocation show --name "arcbox-cl" --resource-group $env:resourceGroup --query id -o tsv)
$vCoresMax = 4
$memoryMax = "8"
$StorageClassName = "managed-premium"
$dataStorageSize = "5"
$logsStorageSize = "5"
$dataLogsStorageSize = "5"
$backupsStorageSize = "5"
$replicas = 1 # Value can be either 1 or 3

$SQLParams = "C:\ArcBox\SQLMI.parameters.json"

(Get-Content -Path $SQLParams) -replace 'resourceGroup-stage',$env:resourceGroup | Set-Content -Path $SQLParams
(Get-Content -Path $SQLParams) -replace 'dataControllerId-stage',$dataControllerId | Set-Content -Path $SQLParams
(Get-Content -Path $SQLParams) -replace 'customLocation-stage',$customLocationId | Set-Content -Path $SQLParams
(Get-Content -Path $SQLParams) -replace 'subscriptionId-stage',$env:subscriptionId | Set-Content -Path $SQLParams
(Get-Content -Path $SQLParams) -replace 'azdataUsername-stage',$env:AZDATA_USERNAME | Set-Content -Path $SQLParams
(Get-Content -Path $SQLParams) -replace 'azdataPassword-stage',$env:AZDATA_PASSWORD | Set-Content -Path $SQLParams
(Get-Content -Path $SQLParams) -replace 'vCoresMaxStage',$vCoresMax | Set-Content -Path $SQLParams
(Get-Content -Path $SQLParams) -replace 'memoryMax-stage',$memoryMax | Set-Content -Path $SQLParams
(Get-Content -Path $SQLParams) -replace 'dataStorageClassName-stage',$StorageClassName | Set-Content -Path $SQLParams
(Get-Content -Path $SQLParams) -replace 'dataSize-stage',$dataStorageSize | Set-Content -Path $SQLParams
(Get-Content -Path $SQLParams) -replace 'logsSize-stage',$logsStorageSize | Set-Content -Path $SQLParams
(Get-Content -Path $SQLParams) -replace 'dataLogseSize-stage',$dataLogsStorageSize | Set-Content -Path $SQLParams
(Get-Content -Path $SQLParams) -replace 'backupsSize-stage',$backupsStorageSize | Set-Content -Path $SQLParams
(Get-Content -Path $SQLParams) -replace 'replicasStage' ,$replicas | Set-Content -Path $SQLParams

az deployment group create --resource-group $env:resourceGroup --template-file "C:\ArcBox\SQLMI.json" --parameters "C:\ArcBox\SQLMI.parameters.json"
Write-Host "`n"

Do {
    Write-Host "Waiting for SQL Managed Instance. Hold tight, this might take a few minutes..."
    Start-Sleep -Seconds 45
    $dcStatus = $(if(kubectl get sqlmanagedinstances -n arc | Select-String "Ready" -Quiet){"Ready!"}Else{"Nope"})
    } while ($dcStatus -eq "Nope")
Write-Host "Azure Arc SQL Managed Instance is ready!"
Write-Host "`n"

# Downloading demo database and restoring onto SQL MI
$podname = "arcbox-sql-0"
Write-Host "Downloading AdventureWorks database for MS SQL... (1/2)"
kubectl exec $podname -n arc -c arc-sqlmi -- wget https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2019.bak -O /var/opt/mssql/data/AdventureWorks2019.bak 2>&1 | Out-Null
Write-Host "Restoring AdventureWorks database for MS SQL. (2/2)"
kubectl exec $podname -n arc -c arc-sqlmi -- /opt/mssql-tools/bin/sqlcmd -S localhost -U $env:AZDATA_USERNAME -P $env:AZDATA_PASSWORD -Q "RESTORE DATABASE AdventureWorks2019 FROM  DISK = N'/var/opt/mssql/data/AdventureWorks2019.bak' WITH MOVE 'AdventureWorks2017' TO '/var/opt/mssql/data/AdventureWorks2019.mdf', MOVE 'AdventureWorks2017_Log' TO '/var/opt/mssql/data/AdventureWorks2019_Log.ldf'" 2>&1 $null

# Creating Azure Data Studio settings for SQL Managed Instance connection
Write-Host "`n"
Write-Host "Creating Azure Data Studio settings for SQL Managed Instance connection"
$settingsTemplate = "C:\ArcBox\settingsTemplate.json"
kubectl describe svc arcbox-sql-external-svc -n arc | Select-String "LoadBalancer Ingress" | Tee-Object "C:\ArcBox\sql_instance_list.txt" | Out-Null
$sqlfile = "C:\ArcBox\sql_instance_list.txt"
$sqlstring = Get-Content $sqlfile
$sqlstring.split(" ") | Tee-Object "C:\ArcBox\sql_instance_list.txt" | Out-Null
(Get-Content $sqlfile | Select-Object -Skip 7) | Set-Content $sqlfile
$sqlstring = Get-Content $sqlfile

(Get-Content -Path $settingsTemplate) -replace 'arc_sql_mi',$sqlstring | Set-Content -Path $settingsTemplate
(Get-Content -Path $settingsTemplate) -replace 'sa_username',$env:AZDATA_USERNAME | Set-Content -Path $settingsTemplate
(Get-Content -Path $settingsTemplate) -replace 'sa_password',$env:AZDATA_PASSWORD | Set-Content -Path $settingsTemplate
(Get-Content -Path $settingsTemplate) -replace 'false','true' | Set-Content -Path $settingsTemplate

# Cleaning garbage
Remove-Item "C:\ArcBox\sql_instance_list.txt" -Force