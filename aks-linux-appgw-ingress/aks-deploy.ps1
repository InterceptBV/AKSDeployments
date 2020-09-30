<#
30-9-2020
Wesley Haakman - Intercept 

This script will deploy the following resources and configurations:
    - AKS Cluster
    - Linux Node Pool with 2 Nodes
    - Application Gateway
    - Application Gateway Ingress configuration
    - Azure Monitor plugins + log analytics
    - 3 Resource Groups
        - RG for AKS Cluster manager
        - RG for Nodes + App Gateway
        - RG for Monitoring
    - SQL Server + Elastic pools
    - Test container to test ingress functionality

    Functions can be called independently
    Run the following on the subscription before deploying!
        az feature register --name AKS-IngressApplicationGatewayAddon --namespace Microsoft.ContainerService
        az feature list -o table --query "[?contains(name, 'Microsoft.ContainerService/AKS-IngressApplicationGatewayAddon')].{Name:name,State:properties.state}"
        az provider register --namespace Microsoft.ContainerService
        az extension add --name aks-preview
#>

# Variables to change
$subscriptionID = <CHANGE THIS>

# Login
az login
az account set --subscription $subscriptionID


# Change these variables to suit customer environment

$location = <CHANGE THIS>
$resourceGroupNameAKS = <CHANGE THIS>
$resourceGroupNameDBs = <CHANGE THIS>
$nodeResourceGroup = <CHANGE THIS>
$monitoringResourceGroup = <CHANGE THIS>
$templateFileMonitoring = ".\loganalyticsworkspace.json"
$monitoringWorkspaceName = <CHANGE THIS>

# Azure SQL Configuration
$sqlServerName = <CHANGE THIS>
$elasticPoolName = <CHANGE THIS>
$sqlServerLogin= <CHANGE THIS>
$sqlServerPassword= <CHANGE THIS>

# Kubernetes Configuration
$kubernetesClusterName = <CHANGE THIS>
$vmNodeSize = "Standard_D4_v2"
$linuxNodePoolName = "nplinux01"

$elasticPoolSku = "Standard" 
$elasticPoolDtu = "100" 
$elasticPoolDatabaseDtuMin = "0" 
$elasticPoolDatabaseDtuMax = "100" 

$appgwName=<CHANGE THIS>
                    

az group create --name $resourceGroupNameAKS --location $location
az group create --name $resourceGroupNameDBs --location $location
az group create --name $monitoringResourceGroup --location $location
function DeployLoganalytics
    {
        Write-Host "Deploy Loganalytics"
        az group deployment create `
            --resource-group $monitoringResourceGroup `
            --name deployMonitoring `
            --template-file $templateFileMonitoring `
            --parameters workspaceName=$monitoringWorkspaceName
    }
function CreateKubernetesCluster
    {
        Write-Host "Test if cluster $kubernetesClustername already exists"
        $azAKSExists = az aks show --name $kubernetesClusterName --resource-group $resourceGroupNameAKS
        if ($azAKSExists -notlike "*was not found*")
            {
                Write-Host "Cluster $kubernetesClustername already exists"
                break
            }

        if ($kubernetesWindowsNodePoolName.length -gt 6)
            {
                Write-Host "kubernetesWindowsNodePoolName cannot be greater than 6"
                break
            }
       
        Write-Host "Create aks cluster $kubernetesClusterName"
           az aks create `
            --resource-group $resourceGroupNameAKS `
            --name $kubernetesClusterName `
            --node-count 2 `
            --nodepool-name $linuxNodePoolName `
            --node-vm-size $vmNodeSize `
            --node-resource-group $nodeResourceGroup `
            --generate-ssh-keys `
            --network-plugin azure `
            --enable-managed-identity `
            -a ingress-appgw `
            --appgw-name $appgwName `
            --appgw-subnet-prefix "10.2.0.0/16"

        
        $resourceIdMonitoring = az resource list --name $monitoringWorkspaceName --query [].id --output tsv
        az aks enable-addons `
            --addons monitoring `
            --name $kubernetesClusterName `
            --resource-group $resourceGroupNameAKS `
            --workspace-resource-id $resourceIdMonitoring
            

        az aks get-credentials `
            --resource-group $resourceGroupNameAKS `
            --name $kubernetesClusterName

        #Verify nodes
        Write-Host "Installed nodes:"
        kubectl get nodes

        # Deploy test container
        kubectl apply -f "https://raw.githubusercontent.com/Azure/application-gateway-kubernetes-ingress/master/docs/examples/aspnetapp.yaml"
    }

function CreateElasticPool
    {
        $sqlServerExists = az sql server list --resource-group $resourceGroupNameDBs
        if ($sqlServerExists -like "*$sqlServerName*")
            {    
                Write-Host "SQL Server $sqlServerName already exists"
                break
            }
        
        Write-Host "Create sql server $sqlServerName"
        az sql server create `
            --name $sqlServerName `
            --resource-group $resourceGroupNameDBs `
            --location "$location" `
            --admin-user $sqlServerLogin `
            --admin-password $sqlServerPassword
  

        Write-Host "Configure firewall $sqlServerName"

        #Allow azure services to access database
        az sql server firewall-rule create `
            --resource-group $resourceGroupNameDBs `
            --server $sqlServerName `
            -n AllowAzureServices `
            --start-ip-address 0.0.0.0 `
            --end-ip-address 0.0.0.0

        Write-Host "Create elastic pool $elasticPoolName"
        az sql elastic-pool create  `
            --resource-group $resourceGroupNameDBs `
            --server $sqlServerName `
            --name $elasticPoolName `
            --edition $elasticPoolSku `
            --capacity $elasticPoolDtu `
            --db-dtu-min $elasticPoolDatabaseDtuMin `
            --db-dtu-max $elasticPoolDatabaseDtuMax
    }
function LoginKubernetes
    {
      
        Write-Host "Connect kubectl to $kubernetesClusterName in resourcegroup $resourceGroupName"
        az aks get-credentials --resource-group $resourceGroupName --name $kubernetesClusterName
    }


DeployLoganalytics
CreateKubernetesCluster
CreateElasticPool
