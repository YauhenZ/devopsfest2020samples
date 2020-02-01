Demo terraform modules for rolling updates of multiregional deployments with deployment flow, which is controlled by depoy automation system instead of terraform.

Usage (Initial deployment): 
1. import wrapper module: 
    Import-Module  ..\scripting-time\tfwrapper.psm1
2. Deploy instancehub: 
    cd .\InstanceHub 
    Set-Environment -environment fakeprod -force
    terraform apply
3. Deploy first instance: 
    cd .\Instance
    Set-Environment -environment fakeprod1 -force
    terraform apply -var 'hub_environment_name=fakeprod' -var 'location=westeurope'
4. Add first instance to InstanceHub (LB) 
    cd .\InstanceLBRule
    Set-Environment -environment fakeprod1 -force
    terraform apply -var 'hub_environment_name=fakeprod'
5. To add more instances: repead steps 3-4 with different environment (for example replace fakeprod1 with fakeprod2) and location

Usage (rolling update): 
1. Import module (like for initial deployment) 
2. Disable traffic for first instance
    cd .\InstanceLBRule
    Set-Environment -environment fakeprod1 -force
    terraform destroy -var 'hub_environment_name=fakeprod'
3. Update instance
    cd .\Instance
    Set-Environment -environment fakeprod1 -force
    terraform apply -var 'hub_environment_name=fakeprod' -var 'location=westeurope'
4. Enable trafic for first instance
    cd .\InstanceLBRule
    Set-Environment -environment fakeprod1 -force
    terraform apply -var 'hub_environment_name=fakeprod'
5. Repeat steps 2-4 for all other instanecs