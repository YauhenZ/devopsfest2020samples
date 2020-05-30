# https://social.msdn.microsoft.com/Forums/en-US/c90782a8-e1a6-4d45-bfe1-9a50c5a6210a/unable-to-upload-pfx-file-to-azure-key-vault?forum=AzureKeyVault
function Set-KVCertificate {
    param (
        [Parameter(Mandatory=$true)]
        [string]$secretname, 
        [Parameter(Mandatory=$true)]
        [string]$pfxFilePath,
        [Parameter(Mandatory=$true)]
        [string]$pwd
    )

    $rgName = "tfinfra"
    $vault = Get-AzKeyVault -ResourceGroupName $rgName 
    Write-Output "using backend vault: $($vault.VaultName)"

    $flag = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
    $collection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
    $collection.Import($pfxFilePath, $pwd, $flag)
    $pkcs12ContentType = [System.Security.Cryptography.X509Certificates.X509ContentType]::Pkcs12
    $clearBytes = $collection.Export($pkcs12ContentType)
    $fileContentEncoded = [System.Convert]::ToBase64String($clearBytes)
    $secret = ConvertTo-SecureString -String $fileContentEncoded -AsPlainText -Force
    $secretContentType = 'application/x-pkcs12'
    
    Set-AzKeyVaultSecret -VaultName $vault.VaultName -Name $secretname -SecretValue $Secret -ContentType $secretContentType
}

Export-ModuleMember -Function Set-KVCertificate