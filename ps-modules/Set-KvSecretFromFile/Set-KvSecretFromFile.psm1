
function Set-KvSecretFromFile {
    param (
        [Parameter(Mandatory=$true)]
        [string]$secretname, 
        [Parameter(Mandatory=$false)]
        [string]$filePath
    )

    $rgName = "tfinfra"
    $vault = Get-AzKeyVault -ResourceGroupName $rgName 
    Write-Output "using backend vault: $($vault.VaultName)"

    $value = Get-Content $filePath -Raw | ConvertTo-SecureString -AsPlainText -Force
    Set-AzKeyVaultSecret -VaultName $vault.VaultName -Name $secretname -SecretValue $value
}

Export-ModuleMember -Function Set-KvSecretFromFile