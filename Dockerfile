FROM mcr.microsoft.com/azure-powershell:latest

# install common pre-requirements & tools 
RUN apt-get update && apt-get install -y wget unzip git

# install az cli 
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# install terraform 
RUN wget  https://releases.hashicorp.com/terraform/0.12.24/terraform_0.12.24_linux_amd64.zip && unzip ./terraform_0.12.24_linux_amd64.zip -d /usr/local/bin/

# install terragrunt
RUN wget https://github.com/gruntwork-io/terragrunt/releases/download/v0.23.7/terragrunt_linux_amd64 -O /usr/local/bin/terragrunt && chmod +x /usr/local/bin/terragrunt