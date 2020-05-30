## terraform/terragrunt related helpers 
function Set-Environment {
    param (
        [Parameter(Mandatory=$true)]
        [string]$environment,
        [Switch]$force, 
        [Switch]$skipInit
    )
    
    if ($force) { 
        Get-ChildItem -Recurse -Filter 'terraform.tfstate' -Force | Remove-Item -Force
    }

    # make sure that az is using same subscribtion 
    $context = (Get-AzContext) 
    $subscribtionName = $context.Subscription.Name 
    az account set --subscription "$subscribtionName"

    # const 
    $rgName = "tfinfra"
    $saPrefix = "infrasa" 
    $vaultPrefix = "infravault"

    $containerName = $environment
    if ($environment.Length -le 3) { 
        $containerName = $environment + $environment
    }

    Add-Environment -containerName $containerName -rgName $rgName -saPrefix $saPrefix -vaultPrefix $vaultPrefix    

    # get sa
    $sa = Get-AzStorageAccount -ResourceGroupName $rgName 
    Write-Output "using backend sa: $($sa.StorageAccountName)"

    # get vault 
    $vault = Get-AzKeyVault -ResourceGroupName $rgName 
    Write-Output "using backend vault: $($vault.VaultName)"

    # export envs 
    $env:TF_VAR_backend_storage_account_name=$sa.StorageAccountName
    $env:TF_VAR_environment_name=$environment
    $env:TF_VAR_backend_storage_account_rg=$rgName 
    $env:TF_VAR_infra_vault_rid=$vault.ResourceId

    # run terraform init       
    if (!$skipInit) { 
        $command = "terraform init --backend-config 'storage_account_name=$env:TF_VAR_backend_storage_account_name' --backend-config 'container_name=$containerName' --backend-config 'resource_group_name=$env:TF_VAR_backend_storage_account_rg'"
        Write-Host $command
        Invoke-Expression "& $command"
    }
}


Function Get-RandomAlphanumericString {
	[CmdletBinding()]
	Param (
        [int] $length = 10
	)
    $res = ( -join ((0x30..0x39) + ( 0x41..0x5A) + ( 0x61..0x7A) | Get-Random -Count $length  | % {[char]$_}) )	
    return $res.ToLower()
}

function Add-Environment {
    param (
        [string]$locatoin = "westeurope", 
        [string]$containerName, 
        [string]$rgName, 
        [string]$saPrefix, 
        [string]$vaultPrefix
    )    
    
    $context = Get-AzContext 
    Write-Output "initializing environment. Subscribtion: $($context.Subscription.Name). Infra resource group name: $rgName"

    # 1. make sure rg is created 
    $rg = Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue 
    if (!$rg) { 
        Write-Warning "creating resource group: $rgName"
        $rg = New-AzResourceGroup -Name $rgName -Location $locatoin
    }

    # 2. make sure storage account for tf backend is created 
    $sa = Get-AzStorageAccount -ResourceGroupName $rg.ResourceGroupName -ErrorAction SilentlyContinue
    if (!$sa) { 
        $saName =  $saPrefix + (Get-RandomAlphanumericString)
        Write-Warning "creating storage account: $saName"
        $sa = New-AzStorageAccount -Name $saName -Location $locatoin -ResourceGroupName $rg.ResourceGroupName -Kind "StorageV2" -SkuName Standard_RAGRS 
    }

    # 3. make sure containers for environment are created in backend sa
    $envContainer = Get-AzStorageContainer -Name $containerName -Context $sa.Context -ErrorAction SilentlyContinue 
    if (!$envContainer) { 
        Write-Warning "creating storage account blob container: $containerName"
        $envContainer = New-AzStorageContainer -Name $containerName -Context $sa.Context
    }

    # 4. make sure key vault for configuration is created
    $vault = Get-AzKeyVault -ResourceGroupName $rg.ResourceGroupName -ErrorAction SilentlyContinue 
    if (!$vault) { 
        $vaultName = $vaultPrefix + (Get-RandomAlphanumericString) 
        Write-Warning "creating a key vault: $vaultName"
        $vault = New-AzKeyVault -Name $vaultName -ResourceGroupName $rg.ResourceGroupName -Location $locatoin -Sku 'Standard'
    }
}

Export-ModuleMember -Function Set-Environment