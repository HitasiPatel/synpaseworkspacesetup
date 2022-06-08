#Prepare your PowerShell environment: Install dependencies (run the Install and Import lines below. You just need to run it once.)
#Install below modules one by one and follow instructions.
    Install-Module -Name Az 
    Install-Module -Name Az.Accounts 
    Install-Module -Name Az.Storage 
    Install-Module -Name Az.Synapse 
    Import-Module  Az.Synapse

<#
    Uninstall-Module -Name Az -AllVersions -force
    Uninstall-Module -Name Az.Synapse -AllVersions -force
    Uninstall-Module -Name Az.Storage -AllVersions -force
    Uninstall-Module -Name Az.Accounts -AllVersions -force
#>

#Retrieve your Client's IP Address (2 options).
#Option 1)
    #Visit: https://whatismyipaddress.com/
    #Populate the $ClientIPAddress variable below with the IP address shown on the screen.

#Option 2)
    $MyIPAddress = (Invoke-WebRequest -uri "https://api.ipify.org/")
    $MyIPAddress = $MyIPAddress.Content

#Login via browser
    Connect-AzAccount

#Use this step to retrieve Subscription ID, and hit F8 in your keyboard. 
    
    Get-AzSubscription

#Copy the Subscription ID (i.e.: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" ) associated with the Subscription you want to deploy your resources to.
#Paste the Subsctription ID in the $SubscriptionID parameter below.    

#Variables/Input Parameters
#Please change the parameters below and make sure to match your subscription's configuration.
#Make sure to only change the values inside the double quotes ("").
#Input parameters:
    $Location               = "East US 2"                                                             #Set this value to match the desired Azure Region for your resources. For a full list, please visit: https://docs.microsoft.com/en-us/azure/availability-zones/cross-region-replication-azure#azure-cross-region-replication-pairings-for-all-geographies 
    $CompanyName            = "company".ToLower()                                                          #The name of your company, abbreviated and without containing any spaces or special characters. For example: Set the value to "MS" for Microsoft.
    $UserUniqueIdentifier   = "user".ToLower()                                                    #A unique identifier for yourself within your company. Can be your username or another text string you would like to use. No space and no special charactes. 
    $SubscriptionID         = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"                                  #Populate this variable with the Subscription ID retrieved above.
    $SqlUser                = "synwadmin"                                                             #Choose a value for the username
    $SqlPassword            = "ej7dhes#LXPF9m~bYr9D"                                                  #Choose a secure password. Feel free to use: https://passwordsgenerator.net/
    $ClientIPAddress        = $MyIPAddress                                                          #Populate this variable with the Client IP Address retrieved above or use the $MyIPAddress variable, populated by the result of an API call to: https://api.ipify.org/
   


    #Parameters (no change needed):
    $LocationShortened      = $Location.replace(' ', '').ToLower()                                    #Do not change this parameter/value.
    $ResourceBaseName       = $CompanyName + "-" + `
                              $LocationShortened + "-" + `
                              $UserUniqueIdentifier                                                   #Do not change this parameter/value.
    $ResourceBaseNameLowerCaseNoHyphen = $ResourceBaseName.replace('-', '').ToLower()                 #Do not change this parameter/value.
    $ResourceGroupName      = $ResourceBaseName + "-rg"                                               #Do not change this parameter/value.
    $ADLSAccountName        = $ResourceBaseNameLowerCaseNoHyphen + "adls"                             #Do not change this parameter/value.        
    $BlobStorageAccountName = $ResourceBaseNameLowerCaseNoHyphen + "blsa"                             #Do not change this parameter/value.        
    $SynapseWorkspaceName   = $ResourceBaseName + "-synw"                                             #Do not change this parameter/value.
    $SynapseResourceGroup   = $SynapseWorkspaceName + "-rg"                                           #Do not change this parameter/value.
    $SQLServerName          = $ResourceBaseNameLowerCaseNoHyphen + "sqlsrvr"
    $SQLDatabaseName        = $ResourceBaseNameLowerCaseNoHyphen + "sqldb"

#Create New Resource Group
#https://docs.microsoft.com/en-us/powershell/module/az.resources/new-azresourcegroup?view=azps-8.0.0
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location

#Create Storage Account (ADLS Gen 2)
#https://docs.microsoft.com/en-us/azure/storage/common/storage-account-create?tabs=azure-powershell#create-a-storage-account
#https://docs.microsoft.com/en-us/powershell/module/az.storage/new-azstorageaccount?view=azps-8.0.0
    $StorageAccount = New-AzStorageAccount `
        -ResourceGroupName $ResourceGroupName `
        -Name $ADLSAccountName `
        -Location $Location `
        -SkuName Standard_LRS `
        -Kind StorageV2 `
        -EnableHierarchicalNamespace $true

#Create founr (4) ADLS File Systems. The first section authenticates, second section creates the File System/Container.
#https://docs.microsoft.com/en-us/azure/storage/blobs/data-lake-storage-directory-file-acl-powershell#create-a-container
    Select-AzSubscription -SubscriptionId $SubscriptionID
    $Context = $StorageAccount.Context

    $FileSystemName = $SynapseWorkspaceName
    New-AzStorageContainer -Context $Context -Name $FileSystemName

    $FileSystemName = "bronze"
    New-AzStorageContainer -Context $Context -Name $FileSystemName

    $FileSystemName = "silver"
    New-AzStorageContainer -Context $Context -Name $FileSystemName

    $FileSystemName = "gold"
    New-AzStorageContainer -Context $Context -Name $FileSystemName

#Create an Azure Synapse Workspace
#https://docs.microsoft.com/en-us/azure/synapse-analytics/quickstart-create-workspace-powershell
    $Credentials = New-Object -TypeName System.Management.Automation.PSCredential ($SqlUser, (ConvertTo-SecureString $SqlPassword -AsPlainText -Force))

    $WorkspaceParams = @{
        Name = $SynapseWorkspaceName
        ResourceGroupName = $ResourceGroupName
        ManagedResourceGroupName = $SynapseResourceGroup
        DefaultDataLakeStorageAccountName = $ADLSAccountName #$StorageAccountName
        DefaultDataLakeStorageFilesystem = $SynapseWorkspaceName
        SqlAdministratorLoginCredential = $Credentials
        Location = $Location
    }
    New-AzSynapseWorkspace @WorkspaceParams

#Add current Client IP Address to Azure Synapse Firewall Rule
    New-AzSynapseFirewallRule `
        -WorkspaceName $SynapseWorkspaceName `
        -Name "ClientIPAddress" `
        -StartIpAddress $ClientIPAddress `
        -EndIpAddress $ClientIPAddress 

#Create two Apache Spark Pools
#https://docs.microsoft.com/en-us/powershell/module/az.synapse/remove-azsynapsesparkpool?view=azps-8.0.0
    New-AzSynapseSparkPool `
        -WorkspaceName $SynapseWorkspaceName `
        -Name "SparkPool01" `
        -NodeCount 3 `
        -SparkVersion 3.1 `
        -NodeSize Small

#Create a Dedicated SQL Pool
#https://docs.microsoft.com/en-us/powershell/module/az.synapse/new-azsynapsesqlpool?view=azps-8.0.0
    New-AzSynapseSqlPool `
        -WorkspaceName $SynapseWorkspaceName `
        -Name "SQLPool" `
        -PerformanceLevel DW100c

#Create an Azure SQL Server with a system wide unique server name
    $SQLServer = New-AzSqlServer `
        -ResourceGroupName $ResourceGroupName `
        -ServerName $SQLServerName `
        -Location $Location `
        -SqlAdministratorCredentials $Credentials

#Create an Azure SQL Server firewall rule that to allow access from the client IP address.
    $SQLServerFirewallRule = New-AzSqlServerFirewallRule `
        -ResourceGroupName $ResourceGroupName `
        -ServerName $SQLServerName `
        -FirewallRuleName "ClientIPAddress" -StartIpAddress $ClientIPAddress -EndIpAddress $ClientIPAddress

# Create a sample database with an S2 performance level
    $SQLDatabase = New-AzSqlDatabase  -ResourceGroupName $resourceGroupName `
        -ServerName $SQLServerName `
        -DatabaseName "SalesDB" `
        -RequestedServiceObjectiveName "S2" `
        -SampleName "AdventureWorksLT"
# Assign Blob Contributor Role to Synapse workspase 
    $resourceIdWithManagedIdentityparm = "/subscriptions/" + $SubscriptionID + "/resourceGroups/" + $ResourceGroupName + `
    "/providers/Microsoft.Synapse/workspaces/" +  $SynapseWorkspaceName
    $resourceIdWithManagedIdentity = $resourceIdWithManagedIdentityparm 
    $Object = (Get-AzResource -ResourceId $resourceIdWithManagedIdentity).Identity.PrincipalId
    $scopeparm = "/subscriptions/" + $SubscriptionID + "/resourceGroups/" + $ResourceGroupName + "/Microsoft.Storage/storageAccounts/" + $StorageAccount
    New-AzRoleAssignment -ObjectID $Object `
    -RoleDefinitionName "Storage Blob Data Contributor" `
    -Scope  $scopeparm 
#Retrieve the Azure Synapse Workspace Endpoints, for you to access it: 
    $WorkspaceWeb = (Get-AzSynapseWorkspace -Name $SynapseWorkspaceName -ResourceGroupName $ResourceGroupName).ConnectivityEndpoints.web
    $WorkspaceDev = (Get-AzSynapseWorkspace -Name $SynapseWorkspaceName -ResourceGroupName $ResourceGroupName).ConnectivityEndpoints.dev

    

#This step will  display the Azure Synapse Endpoints, and automatically open a browser session to the Azure Synapse Workspace created during this deployment. 
#Display Endpoints. Feel free to comment out the next two lines below. 
    $WorkspaceWeb
    $WorkspaceDev

#Start browser session
    Start-Process $WorkspaceWeb

#Cleanup resources
#Remove Resource Group created during this exercise. This will remove/drop all resources created within the Resource Group.
#Select the code within the <##> comment block below, and hit F8.
<#
    Remove-AzResourceGroup -Name $ResourceGroupName -Force
#>
