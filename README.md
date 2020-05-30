# devopsfest2020samples

Repository contains code, which was used for preparation to devopsfest 2020: 
* powershell modules with helper functions  
* dockerfile for running terraform and terragrunt (including powershell helpers) 
* terraform definition of abstract "backend" infrastructure in azure

## How to use
Clone project
```bash
git clone https://github.com/id27182/devopsfest2020samples.git
cd devopsfest2020samples
```
Build docker image
```bash
docker build -t infrastructure . 
```
Run container from image. Mount folder with repository as a volume to container
```
docker run -it --rm -v $(pwd):/home infrastructure
```
Login to Azure with azure cli and Powershell module for Azure. Set proper subscribtion with powershell if needed
```
az login 
... 
Connect-AzAccount
...
Set-AzContext -SubscribtionName <your subscribtion name> 
```
Deploy InstanceHub
```
cd /home/backend/InstanceHub
Set-Environment -environmentName dev -force -skipInit 
terragrunt apply-all 
```
Deploy Instance
```
cd /home/backend/Instance
Set-Environment -environmentName dev -force -skipInit 
terragrunt apply-all
```
Deploy InstanceLbRule
```
cd /home/backend/InstanceLbRule
Set-Environment -environmentName dev -force -skipInit 
terraform apply
```