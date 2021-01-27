#!/bin/bash
#########################################################################################################################
# This script is written by Olaitan Adebowale April 9th 2020 During the great quarantine and lockdown of 2020
# Bash Script to install kubeadm and Helm 3 and Stable Repo from Helm Hub. You have to fulfill all prerequisites 
# 1, You have to disable selinux from /etc/sysconfig/selinux or it will be done by the script
# 2, Make sure you disable swap with command (swapoff -a)
# 3, Make sure you have enough resource on your master node. Recommendation is 4GB ram and 30 GB hard drive space + 4cpu
## if you can afford that
# 4 Make sure you edit your hostfile and add the appropriate keys and value pairs, hostname of the worker nodes
clear
mkdir script
cd script
echo -e "\nHi, This Script will install kubeadm  and Kubectl. You may Choose to install helm 3, K8 Dashboard and helm repo"
sleep 4

echo -e "\nThis script is interactive and you will need to supply some values to help configure the script"
sleep 3

echo -e "\nAre you ready to set your hostname? answer y or n"
sleep 5

read hostnameResponse
if [ $hostnameResponse == 'y' ]
then
  echo "Please enter your hostname.. Make sure it is fqdn"
  read hostname
  hostnamectl set-hostname "$hostname"
else
  echo "Alaye mi, hope say you set hostname?"
  sleep 10
fi

# Swap has to be off
swapoff -a
sed -i.bak '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

#Update System
yum update -y
#Disable SELINUX
setenforce 0
sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux

#Firewall Configuration
systemctl restart firewalld
sleep 2
firewall-cmd --permanent --add-port=6443/tcp
firewall-cmd --permanent --add-port=2379-2380/tcp
firewall-cmd --permanent --add-port=10250/tcp
firewall-cmd --permanent --add-port=10251/tcp
firewall-cmd --permanent --add-port=10252/tcp
firewall-cmd --permanent --add-port=10255/tcp
firewall-cmd --reload
modprobe br_netfilter
echo '1' > /proc/sys/net/bridge/bridge-nf-call-iptables

#Now, Lets Enable Kubernetes Repo
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

#Lets Install Kubeadm and Docker and enable it
yum install kubeadm docker -y
sleep 10
echo "DOCKER_STORAGE_OPTIONS="--storage-driver devicemapper "" > /etc/sysconfig/docker-storage
echo "STORAGE_DRIVER=devicemapper" > /etc/sysconfig/docker-storage-setup
systemctl restart docker && systemctl enable docker 
systemctl restart kubelet && systemctl enable kubelet
touch /root/kubeadm.txt
sleep 10
kubeadm init > /root/kubeadm.txt &
process_id=$!
mkdir -p $HOME/.kube &
wait $process_id
echo Job 1 exited with status $?
wait $!
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
export kubever=$(kubectl version | base64 | tr -d '\n')
echo "Your Kubeadm Files is stored at kubeadm.txt"
sleep 5
echo "Now, Lets Install Weave Network.."
sleep 2

##LETS Apply Weave Newtwork, To Make Our nodes Available##
kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$kubever"
sleep 60
kubectl get nodes
sleep 15

#We will be creating yml files for kubernetes dashboard role binding and service accounts
touch /root/script/cluster-role-binding.yml 
touch /root/script/admin-role-binding.yml
touch /root/script/admin-user.yml

cat <<EOF> /root/script/cluster-role-binding.yml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: default
  namespace: default
EOF

cat <<EOF> /root/script/admin-role-binding.yml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kube-system
EOF

cat <<EOF> /root/script/admin-user.yml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kube-system
EOF

#Those files above can help with the below script. A clean up will be asked at the end of the script
#Lets install kubernetes Dashboard

echo "Do you want to install kubernetes Dashboard? Answer y or n"
read dashBoardResponse
if [ $dashBoardResponse == 'y' ]
then 
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-beta8/aio/deploy/recommended.yaml
  echo "Let's wait for the pods to be ready.. Lets sleep for another 60 seconds"
  sleep 120
  echo "Creating Admin User Role Binding"
  echo "Creating Admin User Account"
  kubectl apply -f /root/script/admin-user.yml
  kubectl apply -f /root/script/cluster-role-binding.yml
  kubectl apply -f /root/script/admin-role-binding.yml
  touch /root/token.txt
  kubectl -n default  describe secret $(kubectl -n kube-system get secret | grep kube-system | awk '{print $1}') > /root/token.txt
else 
  echo "Ok Bye"
fi


echo -e "\nDo you want to install Helm 3? Pls Answer y or n"

read helmResponse

if [ $helmResponse == 'y' ]
then
  curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
  helm repo add stable https://kubernetes-charts.storage.googleapis.com
  helm repo update
  echo "Helm Repo Stable has been installed"
else
  echo "Ok Bye."
fi

echo "Do you want to Port-Forward to port 443 for you to see your Dashboard?  Answer "y" or "n" "
sleep 5

#The below command sets a variable that gets the exact kubernetes dashboard name for the port-forwarder
dashboardNamespace=`kubectl get pods -l k8s-app=kubernetes-dashboard -o custom-columns=:metadata.name -n kubernetes-dashboard`


read portForwardResponse
if [ $portForwardResponse == 'y' ]
then
  dashboardNamespace=`kubectl get pods -l k8s-app=kubernetes-dashboard -o custom-columns=:metadata.name -n kubernetes-dashboard`
  kubectl port-forward $dashboardNamespace -n kubernetes-dashboard --address 0.0.0.0 443:8443 &
  echo "Your dashboard token is stored at /root/token.txt"
  sleep 5
else
  echo "Your Dashboard has not been port forwarded. Except you have done it before, You may not see your dashboard"
  sleep 5
fi

#Lets Cleasn Up or tracks.

echo "Do you want me to clean up?"
sleep 2 
read cleanupResponse
if [ $cleanupResponse == 'y' ]
then 
  rm -rf /root/script
  echo "All Scripts Removed"
  sleep 2
else
  echo "Ok Thanks and Bye"
fi
#Dashboard confirmation

if [ $portForwardResponse == 'y' ]
then
  echo "IF YOUR DASHBOARD DOES NOT APPEAR, RUN THE FOLLOWING COMMANDS IN /root/dashboard-commands."
  echo -e "IF YOU SEE A CRASH LOOP AT THE COMMAND BELOW, PLS REBOOT YOUR MACHINE AND RUN THE DASHBOARD COMMANDS LOCATED IN /root/dashboard-commands AFTER REBOOT"
  sleep 5
  kubectl get pods --all-namespaces
  sleep 5
  echo -e """dashboardNamespace=`kubectl get pods -l k8s-app=kubernetes-dashboard -o custom-columns=:metadata.name -n kubernetes-dashboard`"""  > /root/dashboard-commands.txt
  echo -e "kubectl port-forward $dashboardNamespace -n kubernetes-dashboard --address 0.0.0.0 443:8443 &" >> /root/dashboard-commands.txt
  echo "Your token is saved in /root/token.txt"
  systemctl stop firewalld
  systemctl disable firewalld
  echo "Your Firewall has been Stopped and DISABLED DAWG"
  sleep 3
else
  echo "See you later"
fi
