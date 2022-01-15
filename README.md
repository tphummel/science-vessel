# OCI + Algo VPN

Deploy [Algo VPN](https://github.com/trailofbits/algo) on [OCI](https://www.oracle.com/cloud/)

## Setup

```
cp example.tfvars terraform.tfvars

# fill in the variables in terraform.tfvars

terraform init

terraform plan -out plan

terraform apply plan

# note the public ip address of the created compute instance

ssh ubuntu@<ip address>

ubuntu@algo:~$ export METHOD=local
ubuntu@algo:~$ export ONDEMAND_CELLULAR=true
ubuntu@algo:~$ export USERS=user1,user2,user3,user4,user5,user6,user7,user8,user9
ubuntu@algo:~$ export ENDPOINT=<ip address>
ubuntu@algo:~$ curl -s https://raw.githubusercontent.com/trailofbits/algo/master/install.sh | sudo -E bash -x

```

then remove ssh access from the security list rule. re-plan, re-apply.
