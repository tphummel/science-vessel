# Science Vessel

Reference to Starcraft Terran discovery & research unit. Provision a compute instance, put it on the internet, conduct security research.

- Deploy [Cowrie](https://github.com/cowrie/cowrie) on [OCI](https://www.oracle.com/cloud/)

## Setup

```bash
tpop
...
Plan: 6 to add, 0 to change, 0 to destroy.

terraform apply plan
...
Apply complete! Resources: 6 added, 0 changed, 0 destroyed.
```

not going to worry about locking myself out of ssh. i can reboot and it will wipe out the firewall settings. or use it as a chance to try oci compute run command

updated security group rules to allow tcp port 2222 in addition to 22

```bash
ssh opc@150.136.53.13
sudo -s
dnf update -y

dnf remove -y python3
dnf module enable -y python39
dnf install -y python39 git firewalld

systemctl enable --now firewalld.service
firewall-cmd --add-port 2222/tcp

useradd cowrie
su - cowrie
git clone https://github.com/cowrie/cowrie.git
cd cowrie

pip3 install -r requirements.txt

cp etc/cowrie.cfg.dist etc/cowrie.cfg
sed -i "s/svr04/securebastion104/g" etc/cowrie.cfg

bin/cowrie start
ss -lntp

exit

# as root again
sudo iptables -t nat -A PREROUTING -p tcp --dport 22 -j REDIRECT --to-port 2222
```

test from second terminal

```bash
ssh -p 2222 root@150.136.53.13
whoami
ls -l
ls -l /
```

verification from first terminal

```bash
tail -f /home/cowrie/cowrie/var/log/cowrie/cowrie.json
tail -f /home/cowrie/cowrie/var/log/cowrie/cowrie.log
```

verify port 22

```bash

ssh root@150.136.53.13

```

all good.

remove port 2222 security list. commented 2222 sg ingress. tpop. terraform apply plan. done
