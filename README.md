# How to roll your own k8s

In this workshop we will take a closer look on how to setup your own Kubernetes cluster from scratch, on your own virtual machines. The goal is to get a deeper understanding of what it actually takes to manage your own cluster without the plug-n-play solutions offered by cloud providers.

The workshop assumes that you have the following prerequisites:

- Basic knowledge of Terraform and the command line.
- An AWS account

We will be go through:

- How to install the Kubernetes runtime on a set of Ubuntu virtual machines
- How to install networking in Kubernetes, so that our applications can reach each other and communicate
- How to deploy an application with `YAML` configuration files
- How to deploy an application with `Helm` charts
- How to upgrade Kubernetes clusters to newer versions

# Prerequisites

## jq

For running the script for ssh-ing into machines, JQ is required. Install through brew.

<details>
<summary>Installing on macOS</summary>

If you do not have homebrew installed, follow the instructions here: [https://brew.sh/](https://brew.sh/)

```
brew install jq
```

</details>

<details>
<summary>Installing on Linux/Windows (WSL) (Not tested)</summary>

```
sudo apt-get update
sudo apt-get install jq
```

</details>

## AWS CLI

To manage your AWS account, you need the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

<details>
<summary>Installing on macOS</summary>

If you do not have homebrew installed, follow the instructions here: [https://brew.sh/](https://brew.sh/)

```
brew install awscli
```

</details>

<details>
<summary>Installing on Linux/Windows (WSL) (Not tested)</summary>

```
sudo snap install aws-cli --classic
```

</details>

## AWS Account

Our infrastructure will be hosted in AWS, and thus you require an AWS user.

If you don't have an AWS Account, [sign up here](https://signin.aws.amazon.com/signup?request_type=register).

When creating an account in AWS, you will by default create a single root user, that has admin access to absolutely everything inside your account. This is a major security risk, and you should always create and use an IAM User with less permissions.

### Setup IAM User

1. Log in to your AWS account
1. Go to the IAM Service
1. Select "Access ,anagement -> Users" from the left-hand menu.
1. Press the orange "Create User" button
1. Provide a username and password. Make sure to tick the box "Provide user access to the AWS Management Console"
1. On the "Set Permissions" page, click the "Attach policies directly" box and attach "AdministratorAccess". Note: This is sually a pretty bad idea, and you should probably delete this user once your are done with the workshop.
1. Once your user has been created, log out and log back in again with your new user
1. You now need an Access Key. Click your username in the upper right corner and select "Security credentials"
1. Scroll down to the "Access keys" section and click "Create access key"
1. Select use case "Command Line Interface (CLI)". Tick the box where it says you understand what you are doing and click "Next"
1. Copy the Access Key and Secret Access Key to somewhere secure. You will not be able to view the secret again.

1. (Optional) Add profile to aws-vault, see below

## Verify access

Run `aws sts get-caller-identity` in order to assure you have the correct env setup locally.

## aws-vault (Optional but highly recommended)

In order to easily manage what account you have activated in your cli environment, we highly recommend using aws-vault.
Having aws-vault installed, you can simply enter the access keys from the AWS IAM User and get temporary sessions in a subshell by simple commands.
Read more about aws vault here and how to install it here:
https://github.com/99designs/aws-vault

Pros:

- does not store secrets in plaintext
- gives access to correct environment by simple profile commands
- supports aws-cli out of the box
- has features for running ec2 security meta servers

Cons:

- Most people are probably used to the --profile. But just try it. You will love it!

### How to use it?

1. Activate a shell by `aws-vault exec <profile>`
1. Login in a browser with `aws-vault login <profile>`
1. Thank me later

## Terraform

In order to do this workshop, you need to have `terraform` installed. We recommend installing it through [`tfenv`](https://github.com/tfutils/tfenv).

<details>
<summary>Installing on macOS</summary>

Detailed instruction can be found in the [official docs](https://github.com/tfutils/tfenv?tab=readme-ov-file#automatic).

Install `tfenv`, the Terraform Version Manager through homebrew:

```bash
brew install tfenv
```

If you do not have homebrew installed, follow the instructions here: [https://brew.sh/](https://brew.sh/)

Then `cd` into the `infra` folder in this repository and run `terraform init`, which will automatically install the correct Terraform version used in this workshop.

Verify your installation with the following command:

```
terraform --version
```

It should print your currently active version.

</details>

<details>
<summary>Installing on Linux/Windows (WSL) (Not tested)</summary>

Detailed instruction can be found in the [official docs](https://github.com/tfutils/tfenv?tab=readme-ov-file#manual).

Check out `tfenv` into any path (here is `${HOME}/.tfenv`)

```bash
git clone --depth=1 https://github.com/tfutils/tfenv.git ~/.tfenv
```

Add `~/.tfenv/bin` to your $PATH any way you like

bash:

```bash
echo 'export PATH="$HOME/.tfenv/bin:$PATH"' >> ~/.bash_profile
```

zsh:

```zsh
echo 'export PATH="$HOME/.tfenv/bin:$PATH"' >> ~/.zprofile
```

You might need to open a new shell in order to use the new `PATH`.

Then `cd` into the `infra` folder in this repository and run `terraform init`, which will automatically install the correct Terraform version used in this workshop.

Verify your installation with the following command:

```
terraform --version
```

It should print your currently active version.

</details>

# Architectural Overview

- We will use self-hosted virtual machines (EC2 instances) in AWS as nodes in our cluster
- In total we will use three nodes, one for the Kubernetes control plane (more on this later) and two for our worker nodes, where our applications (pods) will be running.

<details>
<summary>Vocabulary</summary>

[Node](https://kubernetes.io/docs/concepts/architecture/nodes/)

- (Virtual) machines that are part of our Kubernetes cluster. In this workshop we will use 3 nodes that are EC2 instances hosted in AWS.

[Control plane](https://kubernetes.io/docs/reference/glossary/?fundamental=true#term-control-plane)

- The container orchestration layer that exposes the API and interfaces to define, deploy, and manage the lifecycle of containers.
  The control plane usually runs on separate nodes from the worker nodes.
  In larger clusters, the control plane is usually distributed across multiple nodes for fault tolerance.

[Worker Nodes](https://kubernetes.io/docs/reference/glossary/?fundamental=true#term-data-plane)

- The nodes that run your applications (pods) and provide the networking and storage resources needed by those applications.
  There are usually multiple worker nodes in a cluster.

</details>

![Architectural overview of our Kubernetes cluster](./assets/architectural-overview-1.png "Architectural overview of our Kubernetes cluster")

## What are Control Plane components?

The Kubernetes `Control plane` encompasses the components and software you need in order to manage your Kubernetes cluster.
Like regular applications/deployments running in a cluster, these components are made up of Kubernetes resources like pods,
deployments and stateful sets. There are other ways to run these services "natively" on a node in the cluster, usually as
`systemd` services or similar, but that will not be covered in this workshop.

There are multiple ways to deploy the control plane, where we will use `kubeadm` to set it up
for us. For more details on deployment options, check out the [official architecture variation documentation](https://kubernetes.io/docs/concepts/architecture/#architecture-variations).

The components that make up the control plane are the following services:

[kube-controller-manager](https://kubernetes.io/docs/concepts/architecture/#kube-controller-manager) `c-m`

- Runs a control loop, checking that nodes, replicas, services, tokens, endpoints++ are working and are in the desired state

[cloud-controller-manager](https://kubernetes.io/docs/concepts/architecture/cloud-controller/) `c-cm`

- Responsible for cloud-specific control login. This is a separate component that is used in managed Kubernetes solutions like [EKS](https://aws.amazon.com/eks/), [GKE](https://cloud.google.com/kubernetes-engine) and [AKS](https://azure.microsoft.com/en-us/products/kubernetes-service). Not relevant for us.

[kube-apiserver](https://kubernetes.io/docs/concepts/architecture/#kube-apiserver) `api`

- The front-facing REST API service that you interact with through `kubectl`

[etcd](https://etcd.io/) `etcd`

- Highly available key-value store. All configuration for your cluster is stored here.

[kube-scheduler](https://kubernetes.io/docs/concepts/architecture/#kube-scheduler) `sched`

- Watches for newly created pods and schedules them to one or more nodes that are part of the worker nodes

![Control Plane overview](./assets/control-plane-overview-1.png)

## What are Worker Node components?

In order for the Control Plane to be able to manage and schedule workloads, it needs to manage worker nodes to execute that workload.
In this workshop we will refer to these nodes as Worker Nodes or simply Workers.
The term Node is also used in Kubernetes documentation and literature, but for clarity in this course we will use the term Worker.

All worker nodes run a set of services which together constitutes the Kubernetes runtime environment. These components are:

[kubelet](https://kubernetes.io/docs/concepts/architecture/#kubelet) `kubelet`

- Responsible for running and monitoring the health of containers on the node, making sure the containers specified as part of a Pod (more on this later) are working as expected.

[kube-proxy (optional)](https://kubernetes.io/docs/concepts/architecture/#kube-proxy) `k-proxy`

- Network proxy responsible for maintaining the network rules on nodes.

[container runtime](https://kubernetes.io/docs/concepts/architecture/#container-runtime)

- The container runtime used by `kubelet` to run containers. There are multiple choices available here, including [containerd](https://containerd.io/docs/), [CRI-O](https://cri-o.io/#what-is-cri-o) and [Docker Engine](https://docs.docker.com/). In thruth, any implementation that adheres to the Kubernetes [Container Runtime Interface (CRI)](https://github.com/kubernetes/community/blob/master/contributors/devel/sig-node/container-runtime-interface.md) can be used. In this workshop, we will use Docker to run the ontainers on our nodes.

![Data Plane overview](./assets/worker-node-overview-1.png)

## Installing Kubernetes

Guide: [Creating a single control-plane cluster with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)

**TODO: Update this step-by-step guide to 2024-standard. ALSO: Specify an older Kubernetes version (not too old!) so that we can update our cluster later.**


1. Prepare networking for k8s:
```bash
sudo apt-get update -y

sudo cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo sysctl --system
sudo sysctl -w net.ipv4.ip_forward=1

sudo modprobe overlay
sudo modprobe br_netfilter

swapoff -a
(crontab -l 2>/dev/null; echo "@reboot /sbin/swapoff -a") | crontab - || true

```

1. Install containerd, our container runtime 
```bash


# INSTALL CONTAINERD
wget https://github.com/containerd/containerd/releases/download/v1.6.8/containerd-1.6.8-linux-amd64.tar.gz

sudo tar Cxzvf /usr/local containerd-1.6.8-linux-amd64.tar.gz

wget https://github.com/opencontainers/runc/releases/download/v1.1.3/runc.amd64

sudo install -m 755 runc.amd64 /usr/local/sbin/runc

wget https://github.com/containernetworking/plugins/releases/download/v1.1.1/cni-plugins-linux-amd64-v1.1.1.tgz

sudo mkdir -p /opt/cni/bin

sudo tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.1.1.tgz

sudo mkdir /etc/containerd

containerd config default | sudo tee /etc/containerd/config.toml

sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml

sudo curl -L https://raw.githubusercontent.com/containerd/containerd/main/containerd.service -o /etc/systemd/system/containerd.service

sudo systemctl daemon-reload

sudo systemctl enable --now containerd

sudo systemctl status containerd
# END CONTAINERD
```

1. Install k8s
```bash
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update -y
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

sudo apt install jq -y
export local_ip="$(ip --json addr show ens5 | jq -r '.[0].addr_info[] | select(.family == "inet") | .local')"
export IPADDR="$local_ip"
echo "KUBELET_EXTRA_ARGS=--node-ip=$local_ip" | sudo tee /etc/default/kubelet > /dev/null
```

1. Export required cluster config variables
```bash
export NODENAME=$(hostname -s)
export POD_CIDR="10.244.0.0/16"

```

1. Create K8s cluster
```bash
sudo kubeadm init --apiserver-advertise-address=$IPADDR  --apiserver-cert-extra-sans=$IPADDR  --pod-network-cidr=$POD_CIDR --node-name $NODENAME --ignore-preflight-errors Swap
```

1. Make k8s available to current user 
```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```
1. Copy the kubeadm join command from output. 
```bash
sudo kubeadm join [YOURMASTERNODEIP]:6443 - token [thetokendisplayed] \
 - discovery-token-ca-cert-hash sha256:[thetokendisplayed]
```

1. Verify the Nodes are registered:

```bash
kubectl get nodes
```
Note: All notes should have status NotReady as they are missing internet
You can also see the pods running:
```bash
kubectl get pods  --all-namespaces
```

# Flannel networking
```
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

# Nginx Ingress
```
git clone https://github.com/nginxinc/kubernetes-ingress.git --branch v3.7.1
cd kubernetes-ingress/
kubectl apply -f deployments/common/ns-and-sa.yaml
kubectl apply -f deployments/rbac/rbac.yaml
kubectl apply -f deployments/common/nginx-config.yaml
kubectl apply -f deployments/common/ingress-class.yaml
kubectl apply -f deployments/deployment/nginx-ingress.yaml
kubectl create -f deployments/service/nodeport.yaml
```



## NOTE TO SELF:
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml


# Cilium Networking

1. First, lets install helm, which will intall cilium for us:

```bash
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
sudo apt-get install apt-transport-https --yes
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list

sudo apt-get update

sudo apt-get install helm -y
```

Now install cilium:
```bash
helm repo add cilium https://helm.cilium.io/

helm repo update
```

## Starting cilium network

```bash
export API_SERVER_IP="$IPADDR"
export API_SERVER_PORT=6443
helm install cilium cilium/cilium --version 1.15.6 \
--namespace kube-system \
--set k8sServiceHost=${API_SERVER_IP} \
--set k8sServicePort=${API_SERVER_PORT} \
--set kubeProxyReplacement=true \
--set l2announcements.enabled=true \
--set encryption.enabled=true \
--set encryption.type=wireguard \
--set ingressController.enabled=true \
--set ingressController.loadbalancerMode=dedicated \
--set hubble.relay.enabled=true \
--set hubble.ui.enabled=true 
```

### Install Cilium Cli for status:

```bash
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
```

### Wait for cilium to be ready 
```bash
cilium status --wait

```

### Run a test suite in your cluster to verify that Cilium is working as expected 
```bash
cilium connectivity test
```

## Install Hubble?

```
https://docs.cilium.io/en/stable/observability/hubble/setup/#hubble-setup
```

### Create Cilium Load balancer 
One of the key features of cilium is the load balancer. Lets create a load balancer with 

```bash
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: "pool-01"
spec:
  cidrs:
  - cidr: "192.168.65.32/27"
```

### Use cilium 
```bash
kubectl apply -f ip-addr-pool-01.yaml
```





TL;DR:

1.  Install Docker on your host machine. Docker will be detected automatically by Kubernetes on initialization as our container runtime
    1. <details>
        <summary>Solution</summary>
        <pre>
       sudo apt install docker.io
       </pre>
        </details>
2.  (Jakob jobber med denne. Mer spesifikt. Leser om flanell og pr;ver [ finne ut hvordan installere) Decide on a Pod network add-on. This is required to get network between your pods. We will use [Flannel](https://github.com/coreos/flannel).
3.  Install kubeadm, kubelet and kubectl on all the machines. Kubectl is only needed on the control node, but why not install on all the nodes? You simply do copy paste either way:)

    1. `sudo apt update`
    2. `sudo apt-get install -y apt-transport-https ca-certificates curl gpg`
    3. `curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg`
    4. `echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list`
    5. ```bash
       sudo apt-get update
       sudo apt-get install -y kubelet kubeadm kubectl
       sudo apt-mark hold kubelet kubeadm kubectl
       ```
    6. Sjekk at kubectl ble installert `kubectl version --client`. Client Version: v1.31.2
       Kustomize Version: v5.4.2 er riktig.

4.  (Jakob jobber med denne) Initialize Kubernetes on your host with the following command:
    `kubeadm init --pod-network-cidr=10.244.0.0/16`
    Note: `--pod-network-cidr=10.244.0.0/16` is required to use Flannel as networking
5.                                      Install Flannel:
    `kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/2140ac876ef134e0ed5af15c65e414cf26827915/Documentation/kube-flannel.yml`

<details>
<summary>Vocabulary</summary>

Control-plane

- The container orchestration layer that exposes the API and interfaces to define, deploy, and manage the lifecycle of containers

Node

- (Virtual) machines that are part of our cluster. Runs containerized applications.
  Controlled by the control plane

Addon

- Extra features that uses Kubernetes resources (DaemonSet, Deployment, etc) as implementation. They are really just sets of Kubernetes objects.
- Common addons: CoreDNS, Dashboard, Networking (Flannel++), Logging, Monitoring

</details>

## What is a Pod network addon?

Kubernetes does not enable communication between pods by default.

The networking contract in Kubernetes says that all pods must have a unique IP address inside the cluster, in order to route between Kubernetes objects, avoiding port collisions.

Kubernetes comes with the CoreDNS addon by default, but it does not start before a [network is installed](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/#pod-network). Pods are given an IP address on creation, but DNS lookups between pods are not available before we have a network.

Multiple pod networks are available: [Calico](https://docs.projectcalico.org/introduction/), [Weave Net](https://www.weave.works/oss/net/), [kube-router](https://github.com/cloudnativelabs/kube-router), [Flannel](https://github.com/coreos/flannel)++

## Flannel - the network fabric

We chose to use Flannel for our cluster networking. Why? Because a friend on Discord used it on his Raspberry Pi Kubernetes cluster

Each network addon uses their own default IP range.

- Flannel uses `10.244.0.0/16` by default, hence the `--pod-network-cidr=10.244.0.0/16` argument to kubeadm when creating the cluster.
  - `10.244.0.0/16` is known as CIDR notation, hence the argument name

Once Flannel is installed, CoreDNS should be running

- Can be checked with: `kutectl get pods --all-namespaces`

## Where are we now?

We have a cluster!

We have networking between pods!

But we don’t have any applications :(

## Deploying our first application

**TODO: Here we can be a bit more creative. How about a a backend and a NextJS-app that performs server-side rendering? Then we can check that out networking is functional**

We want to deploy a container that responds with “Hello world!” when receiving a request

- This little beauty: https://github.com/paulbouwer/hello-kubernetes

## Containers, pods, replicas, deployments, services

A unit we want to deploy is called a pod.

A pod can consist of multiple containers that makes up the application. We only have one container per pod in our example.

We want multiple copies of our pod to run simultaneously, these are called replicas.

Together, this configuration constitutes a deployment.

Each pod is an independent Kubernetes object. We can hide this detail behind a service, that can load balance (and more) between the pods

## Deploying with YAML configuration

Kubernetes configuration files are written in YAML.

Configuration for our hello-kubernetes deployment →

Deploy with the following command:

- `kubectl apply -f hello-kubernetes-deployment.yml`

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-kubernetes
spec:
  replicas: 3
  selector:
    matchLabels:
      app: hello-kubernetes
  template:
    metadata:
      labels:
        app: hello-kubernetes
    spec:
      containers:
      - name: hello-kubernetes
        image: paulbouwer/hello-kubernetes:1.8
        ports:
        - containerPort: 8080
```

Create a service to abstract away the pods →
Deploy with the following command:

- `kubectl apply -f hello-kubernetes-service.yml`

```
apiVersion: v1
kind: Service
metadata:
  name: hello-kubernetes
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: hello-kubernetes
```

## Where are we now?

We have a cluster!

We have networking between pods!

We have a deployment!

But we don’t have any users :(

## We need to expose our service to the world!

We need an Ingress to route traffic into our cluster

Install an ingress-controller. We will use [nginx-ingress](https://docs.nginx.com/nginx-ingress-controller/installation/installation-with-manifests/).

Make sure to deploy with a DaemonSet configuration, it makes life easier

Deploy an ingress that routes traffic to our service:

- `kubectl apply -f hello-kubernetes-ingress.yml`

```
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
Metadata:
  name: hello-kubernetes-ingress
spec:
  Rules:
    - host: kubernetes.santi.no
      http:
        paths:
        - path: /
          backend:
            serviceName: hello-kubernetes
            servicePort: 80
```

## Where are we now?

We have a cluster!

We have networking between pods!

We have a deployment!

We have users!

## Next steps

- Setup SSL/TLS termination in our Ingress
- Add another node to the cluster
- [Upgrade your Kubernetes cluster version without downtime](https://github.com/stakater/til/blob/master/kubernetes/upgrading-clusters-with-zero-downtime.md)
- Setup logging and monitoring (Prometheus and Grafana). Use Helm charts for this.
