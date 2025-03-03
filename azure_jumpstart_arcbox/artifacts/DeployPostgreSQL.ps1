Start-Transcript -Path C:\ArcBox\deployPostgreSQL.log

# Deployment environment variables
$controllerName = "arcbox-dc"

# Deploying Azure Arc SQL Managed Instance
Write-Host "Deploying Azure Arc PostgreSQL Hyperscale"
Write-Host "`n"

$dataControllerId = $(az resource show --resource-group $env:resourceGroup --name $controllerName --resource-type "Microsoft.AzureArcData/dataControllers" --query id -o tsv)
$customLocationId = $(az customlocation show --name "arcbox-cl" --resource-group $env:resourceGroup --query id -o tsv)
$memoryRequest = "0.25Gi"
$StorageClassName = "managed-premium"
$dataStorageSize = "5Gi"
$logsStorageSize = "5Gi"
$backupsStorageSize = "5Gi"
$numWorkers = 1

$PSQLParams = "C:\ArcBox\postgreSQL.parameters.json"

(Get-Content -Path $PSQLParams) -replace 'resourceGroup-stage',$env:resourceGroup | Set-Content -Path $PSQLParams
(Get-Content -Path $PSQLParams) -replace 'dataControllerId-stage',$dataControllerId | Set-Content -Path $PSQLParams
(Get-Content -Path $PSQLParams) -replace 'customLocation-stage',$customLocationId | Set-Content -Path $PSQLParams
(Get-Content -Path $PSQLParams) -replace 'subscriptionId-stage',$env:subscriptionId | Set-Content -Path $PSQLParams
(Get-Content -Path $PSQLParams) -replace 'azdataPassword-stage',$env:AZDATA_PASSWORD | Set-Content -Path $PSQLParams
(Get-Content -Path $PSQLParams) -replace 'memoryRequest-stage',$memoryRequest | Set-Content -Path $PSQLParams
(Get-Content -Path $PSQLParams) -replace 'dataStorageClassName-stage',$StorageClassName | Set-Content -Path $PSQLParams
(Get-Content -Path $PSQLParams) -replace 'logsStorageClassName-stage',$StorageClassName | Set-Content -Path $PSQLParams
(Get-Content -Path $PSQLParams) -replace 'backupStorageClassName-stage',$StorageClassName | Set-Content -Path $PSQLParams
(Get-Content -Path $PSQLParams) -replace 'dataSize-stage',$dataStorageSize | Set-Content -Path $PSQLParams
(Get-Content -Path $PSQLParams) -replace 'logsSize-stage',$logsStorageSize | Set-Content -Path $PSQLParams
(Get-Content -Path $PSQLParams) -replace 'backupsSize-stage',$backupsStorageSize | Set-Content -Path $PSQLParams
(Get-Content -Path $PSQLParams) -replace 'numWorkersStage',$numWorkers | Set-Content -Path $PSQLParams

az deployment group create --resource-group $env:resourceGroup --template-file "C:\ArcBox\postgreSQL.json" --parameters "C:\ArcBox\postgreSQL.parameters.json"
Write-Host "`n"

Do {
    Write-Host "Waiting for PostgreSQL Hyperscale. Hold tight, this might take a few minutes..."
    Start-Sleep -Seconds 45
    $dcStatus = $(if(kubectl get postgresqls -n arc | Select-String "Ready" -Quiet){"Ready!"}Else{"Nope"})
    } while ($dcStatus -eq "Nope")
Write-Host "Azure Arc PostgreSQL Hyperscale is ready!"
Write-Host "`n"

# Downloading demo database and restoring onto Postgres
$podname = "arcboxpsc0-0"
Write-Host "Downloading AdventureWorks.sql template for Postgres... (1/3)"
kubectl exec $podname -n arc -c postgres -- /bin/bash -c "cd /tmp && curl -k -O https://raw.githubusercontent.com/microsoft/azure_arc/main/azure_jumpstart_arcbox/artifacts/AdventureWorks2019.sql" 2>&1 | Out-Null
Write-Host "Creating AdventureWorks database on Postgres... (2/3)"
kubectl exec $podname -n arc -c postgres -- sudo -u postgres psql -c 'CREATE DATABASE "adventureworks2019";' postgres 2>&1 | Out-Null
Write-Host "Restoring AdventureWorks database on Postgres. (3/3)"
kubectl exec $podname -n arc -c postgres -- sudo -u postgres psql -d adventureworks2019 -f /tmp/AdventureWorks2019.sql 2>&1 | Out-Null

# Creating Azure Data Studio settings for PostgreSQL connection
Write-Host "`n"
Write-Host "Creating Azure Data Studio settings for PostgreSQL connection"
$settingsTemplate = "C:\ArcBox\settingsTemplate.json"
kubectl describe svc arcboxps-external-svc -n arc | Select-String "LoadBalancer Ingress" | Tee-Object "C:\ArcBox\postgres_instance_endpoint.txt" | Out-Null
$pgsqlfile = "C:\ArcBox\postgres_instance_endpoint.txt"
$pgsqlstring = Get-Content $pgsqlfile
$pgsqlstring.split(" ") | Out-File "C:\ArcBox\postgres_instance_endpoint.txt" | Out-Null
(Get-Content $pgsqlfile | Select-Object -Skip 7) | Set-Content $pgsqlfile
(Get-Content $pgsqlfile | Where-Object {$_.trim() -ne "" }) | Set-Content $pgsqlfile
$pgsqlstring = Get-Content $pgsqlfile

(Get-Content -Path $settingsTemplate) -replace 'arc_postgres',$pgsqlstring | Set-Content -Path $settingsTemplate
(Get-Content -Path $settingsTemplate) -replace 'ps_password',$env:AZDATA_PASSWORD | Set-Content -Path $settingsTemplate

# Cleaning garbage
Remove-Item "C:\ArcBox\postgres_instance_endpoint.txt" -Force