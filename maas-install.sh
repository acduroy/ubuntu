#!/bin/bash

echo "* Setting NAT"
echo -n "Enter external interface (e.g. ens3): "; read EXTIF
echo -n "Enter internal interface (e.g. ens8): "; read INTIF
#sudo sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
sudo sed -i -e 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
# To enable the changes made in sysctl.conf you will need to run the command
sudo sysctl -p /etc/sysctl.conf
sudo iptables -t nat -A POSTROUTING -o $EXTIF -j MASQUERADE
sudo iptables -A FORWARD -i $EXTIF -o $INTIF -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i $INTIF -o $EXTIF -j ACCEPT
# Set NaT permanent
sudo apt-get install -y iptables-persistent
sudo cp /etc/iptables/rules.v4 /etc/iptables/rules.v4.prev
sudo iptables-save | sudo tee /etc/iptables/rules.v4

echo "* Installing MAAS"

sudo apt-cache search maas
sudo sudo apt-add-repository -yu ppa:maas/stable

sudo apt install -y maas

#sudo apt install -y maas-cli
echo "* Creating admin account"
echo -n "Enter admin user name (e.g. maas): "; read PROFILE
echo "Creating admin maas"
PROFILE="maas"
default_passwd='Super123'
sudo maas createadmin --username $PROFILE --password $default_passwd --email $PROFILE@test.lab

echo "* Creating maas login script"
login_script='maas_login.sh'
logout_script='maas_logout.sh'
api_key_file='.maas_apikey'
cat <<LOGIN_SCRIPT > $login_script
#!/bin/sh

sudo maas-region apikey --username=$PROFILE > $api_key_file
API_KEY_FILE=$api_key_file
API_SERVER='localhost'

MAAS_URL=http://$API_SERVER/MAAS/api/2.0

maas login $PROFILE $MAAS_URL - < $API_KEY_FILE

LOGIN_SCRIPT
chmod +x $login_script

cat <<LOGOUT_SCRIPT > $logout_script
maas logout $PROFILE
LOGOUT_SCRIPT
chmod +x $logout_script

echo "* Log in to maas command session"
./$login_script

SSH_KEY='~/.ssh/id_rsa.pub'

echo "* Register ssh key"
if [ ! -f .ssh/id_rsa.pub ]; then
  ssh-keygen
fi

if [ -f .ssh/id_rsa.pub ]; then
  ssh_key=$(cat .ssh/id_rsa.pub | grep ssh)
  maas $PROFILE sshkeys create "key=$ssh_key"
fi

echo "* Set a DNS forwarder"
MY_UPSTREAM_DNS=$(dig | grep SERVER | cut -d'(' -f2 | cut -d')' -f1)
maas $PROFILE maas set-config name=upstream_dns value=$MY_UPSTREAM_DNS

#echo "* Creating VLAN"
#echo -n "Enter vlan"
#echo "* Creating subnet"
#echo -n "Enter maas subnet (CIDR): "; read CIDR
#echo -n "Enter maas subnet gateway IP (e.g. MAAS IP): " read GW_IP
#echo -n "Enter maas subnet dns IP (e.g. MAAS IP and comma delim): "; read DNS_IPS
#maas $PROFILE subnets create cidr=$CIDR gateway_ip=$GW_IP dns_servers=$DNS_IPS

echo "* Install KVM"
sudo apt install -y libvirt-bin
echo "* Copy ssh key to KVM host"
sudo chsh -s /bin/bash maas
sudo su - maas -c "[ ! -f ~/.ssh/id_rsa ] && ssh-keygen -f ~/.ssh/id_rsa -N ''"
echo -n "Enter KVM Host User (e.g. acd): "; read USER
echo -n "Enter KVM Host IP (e.g. 10.100.204.2): "; read HOST
#USER=acd
#HOST=10.100.204.2
USER_HOME=$(sudo su - $USER -c 'echo ~/')
USER_AUTHKEYS_FILE_PATH=$USER_HOME.ssh/authorized_keys
USER_PUBKEY=$(sudo su - maas -c 'cat .ssh/id_rsa.pub')
MY_USER=$(whoami)
MY_HOST=$(hostname)
sudo ssh -t $USER@$HOST /bin/bash -c "'
pwd
echo "$USER_HOME"
cp $USER_AUTHKEYS_FILE_PATH $USER_AUTHKEYS_FILE_PATH.backup
sed -i "/\${MY_USER}@\${MY_HOST}$/d" $USER_AUTHKEYS_FILE_PATH
echo $USER_PUBKEY | tee $USER_AUTHKEYS_FILE_PATH
'"


# Testing connection between MAAS and KVM-Host:
#sudo su - maas
#virsh -c qemu+ssh://$USER@$HOST/system list --all

#TODO
#Adding Pod by script
