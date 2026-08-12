terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

# AWS 설정 시작
provider "aws" {
  region = var.region
}
# AWS 설정 끝

# kubeadm 조인 토큰 (형식: [a-z0-9]{6}.[a-z0-9]{16})
resource "random_string" "k8s_token_a" {
  length  = 6
  lower   = true
  numeric = true
  upper   = false
  special = false
}

resource "random_string" "k8s_token_b" {
  length  = 16
  lower   = true
  numeric = true
  upper   = false
  special = false
}

locals {
  k8s_token = "${random_string.k8s_token_a.result}.${random_string.k8s_token_b.result}"
}

# VPC 설정 시작
resource "aws_vpc" "vpc_1" {
  cidr_block = "10.0.0.0/16"

  # 무조건 켜세요.
  enable_dns_support = true
  # 무조건 켜세요.
  enable_dns_hostnames = true

  tags = {
    Name = "${var.prefix}-vpc-1"
  }
}

resource "aws_subnet" "subnet_1" {
  vpc_id                  = aws_vpc.vpc_1.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.prefix}-subnet-1"
  }
}

resource "aws_subnet" "subnet_2" {
  vpc_id                  = aws_vpc.vpc_1.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.prefix}-subnet-2"
  }
}

resource "aws_subnet" "subnet_3" {
  vpc_id                  = aws_vpc.vpc_1.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "${var.region}c"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.prefix}-subnet-3"
  }
}

resource "aws_internet_gateway" "igw_1" {
  vpc_id = aws_vpc.vpc_1.id

  tags = {
    Name = "${var.prefix}-igw-1"
  }
}

resource "aws_route_table" "rt_1" {
  vpc_id = aws_vpc.vpc_1.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw_1.id
  }

  tags = {
    Name = "${var.prefix}-rt-1"
  }
}

resource "aws_route_table_association" "association_1" {
  subnet_id      = aws_subnet.subnet_1.id
  route_table_id = aws_route_table.rt_1.id
}

resource "aws_route_table_association" "association_2" {
  subnet_id      = aws_subnet.subnet_2.id
  route_table_id = aws_route_table.rt_1.id
}

resource "aws_route_table_association" "association_3" {
  subnet_id      = aws_subnet.subnet_3.id
  route_table_id = aws_route_table.rt_1.id
}

resource "aws_security_group" "sg_1" {
  name = "${var.prefix}-sg-1"

  ingress {
    from_port = 0
    to_port   = 0

    # 모든 프로토콜을 의미하는 AWS 공식 값 (-1)
    protocol = "-1"

    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0

    # 모든 프로토콜을 의미하는 AWS 공식 값 (-1)
    protocol = "-1"

    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = aws_vpc.vpc_1.id

  tags = {
    Name = "${var.prefix}-sg-1"
  }
}

# VPC 설정 끝

# ROUTE 53 설정 시작
resource "aws_route53_zone" "vpc_1_zone" {
  vpc {
    vpc_id = aws_vpc.vpc_1.id
  }
  name = "vpc-1.com"
}
# ROUTE 53 설정 끝

# EC2 설정 시작

# EC2 역할 생성
resource "aws_iam_role" "ec2_role_1" {
  name = "${var.prefix}-ec2-role-1"

  # 이 역할에 대한 신뢰 정책 설정. EC2 서비스가 이 역할을 가정할 수 있도록 설정
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
}

# EC2 역할에 AmazonS3FullAccess 정책을 부착
resource "aws_iam_role_policy_attachment" "s3_full_access" {
  role       = aws_iam_role.ec2_role_1.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# EC2 역할에 최신 SSM 정책을 부착
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_role_1.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM 인스턴스 프로파일 생성
resource "aws_iam_instance_profile" "instance_profile_1" {
  name = "${var.prefix}-instance-profile-1"
  role = aws_iam_role.ec2_role_1.name
}

# 최신 Amazon Linux 2023 AMI 조회
data "aws_ssm_parameter" "amazon_linux_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  ec2_user_data_base = <<-END_OF_FILE
#!/bin/bash
set -euxo pipefail

timedatectl set-timezone Asia/Seoul

LOG_FILE="/var/log/bootstrap.log"
exec > >(tee -a $LOG_FILE) 2>&1

echo "BOOTSTRAP START"

dnf update -y
dnf install -y git docker

systemctl enable docker
systemctl start docker

# This overwrites any existing configuration in /etc/yum.repos.d/kubernetes.repo
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.36/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.36/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

# Set SELinux in permissive mode (effectively disabling it)
sudo setenforce 0 || true
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

# Disable swap (k8s 필수)
swapoff -a
sed -i '/swap/s/^/#/' /etc/fstab

# Enable IPv4 packet forwarding (k8s 공식 필수 sysctl)
# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system

# containerd setting
containerd config default > /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd

sudo dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
sudo systemctl enable --now kubelet

echo "BOOTSTRAP DONE"

END_OF_FILE

  # 마스터(ec2-1) 전용: 클러스터 생성 + Calico + NPM/PG/Redis 매니페스트 적용
  ec2_1_master_bootstrap = <<-END_OF_FILE
hostnamectl set-hostname ec2-1

echo "K8S MASTER BOOTSTRAP START"

# 공인 IP 조회 (IMDSv2) - 외부(GITHUB ACTIONS 등)에서 kubectl 접속할 수 있도록 인증서 SAN에 추가
MDT=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $MDT" http://169.254.169.254/latest/meta-data/public-ipv4)

# 클러스터 생성
# --token-ttl 0 : 토큰 만료 없음(강의용 편의). 운영에서는 만료시간을 두는 것이 안전
kubeadm init \
  --token ${local.k8s_token} \
  --token-ttl 0 \
  --pod-network-cidr=10.10.0.0/16 \
  --apiserver-cert-extra-sans=$PUBLIC_IP \
  -v=5

export KUBECONFIG=/etc/kubernetes/admin.conf
mkdir -p /root/.kube
cp -f /etc/kubernetes/admin.conf /root/.kube/config

# kubectl 자동완성
dnf install -y bash-completion
kubectl completion bash | tee /etc/bash_completion.d/kubectl > /dev/null
echo 'alias k=kubectl' >> /root/.bashrc
echo 'complete -o default -F __start_kubectl k' >> /root/.bashrc

# ========================================
# Calico v3.32.1 설치 (Pod CIDR: 10.10.0.0/16, VXLAN, BGP Disabled)
# ========================================
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.1/manifests/v1_crd_projectcalico_org.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.1/manifests/tigera-operator.yaml

mkdir -p /kube

cat <<'CALICO_EOF' > /kube/calico-resources.yaml
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    bgp: Disabled
    ipPools:
      - cidr: 10.10.0.0/16
        encapsulation: VXLAN

---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
CALICO_EOF

kubectl create -f /kube/calico-resources.yaml

# ========================================
# NPM(nginx-proxy-manager) - 서비스명 포워딩 준비작업 + 배포
# nginx 내장 리졸버는 search domain을 지원하지 않으므로
# dnsmasq 사이드카(--append-search-domains)를 resolver로 사용
# ========================================
mkdir -p /data/ec2-1/nginx-proxy-manager-1/data/nginx/custom
echo "resolver 127.0.0.1  valid=10s;" > /data/ec2-1/nginx-proxy-manager-1/data/nginx/custom/server_proxy.conf
echo "resolver 127.0.0.1  valid=10s;" > /data/ec2-1/nginx-proxy-manager-1/data/nginx/custom/server_stream.conf

mkdir -p /kube/nginx-proxy-manager-1

cat <<'NPM_EOF' > /kube/nginx-proxy-manager-1/nginx-proxy-manager-1.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-proxy-manager-1-deployment
spec:
  selector:
    matchLabels:
      app: nginx-proxy-manager-1
  template:
    metadata:
      labels:
        app: nginx-proxy-manager-1
    spec:
      nodeSelector:
        kubernetes.io/hostname: ec2-1
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      containers:
      - image: jc21/nginx-proxy-manager:latest
        name: nginx-proxy-manager-1
        ports:
        - containerPort: 443
          hostPort: 443
        - containerPort: 80
          hostPort: 80
        - containerPort: 81
          hostPort: 81
        - containerPort: 5432
          hostPort: 5432
        - containerPort: 6379
          hostPort: 6379
        env:
        - name: TZ
          value: "Asia/Seoul"
        volumeMounts:
        - name: vol
          mountPath: /data
          subPath: data
        - name: vol
          mountPath: /etc/letsencrypt
          subPath: etc/letsencrypt
      - image: "janeczku/go-dnsmasq:release-1.0.7"
        name: dnsmasq
        args:
          - --listen
          - "127.0.0.1:53"
          - --default-resolver
          - --append-search-domains
          - --hostsfile=/etc/hosts
          - --verbose
      volumes:
      - name: vol
        hostPath:
          path: /data/ec2-1/nginx-proxy-manager-1
          type: DirectoryOrCreate
NPM_EOF

kubectl apply -f /kube/nginx-proxy-manager-1/nginx-proxy-manager-1.yaml

# ========================================
# PG(jangka512/pgj) - ec2-2
# ========================================
mkdir -p /kube/pg-1

cat <<'PG_EOF' > /kube/pg-1/pg-1.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pg-1-deployment
spec:
  selector:
    matchLabels:
      app: pg-1
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: pg-1
    spec:
      nodeSelector:
        kubernetes.io/hostname: ec2-2
      containers:
      - image: jangka512/pgj:latest
        name: pg-1
        ports:
        - containerPort: 5432
          name: pg-1
        env:
        - name: TZ
          value: "Asia/Seoul"
        - name: POSTGRES_USER
          value: postgres
        - name: POSTGRES_DATABASE
          value: postgres
        - name: POSTGRES_DATABASES
          value: p_14190_1_prod
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: pg-1-secret
              key: password
        volumeMounts:
        - name: vol
          mountPath: /var/lib/postgresql
          subPath: var/lib/postgresql
      volumes:
      - name: vol
        hostPath:
          path: /data/ec2-2/pg-1
          type: DirectoryOrCreate

---

apiVersion: v1
kind: Service
metadata:
  name: pg-1-service
spec:
  ports:
  - port: 5432
  selector:
    app: pg-1

---

apiVersion: v1
kind: Secret
metadata:
  name: pg-1-secret
data:
  password: bGxkajEyMzQxNA== # echo -n 'lldj123414' | base64
PG_EOF

kubectl apply -f /kube/pg-1/pg-1.yaml

# ========================================
# Redis - ec2-3
# ========================================
mkdir -p /kube/redis-1

cat <<'REDIS_EOF' > /kube/redis-1/redis-1.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-1
spec:
  selector:
    matchLabels:
      app: redis-1
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: redis-1
    spec:
      nodeSelector:
        kubernetes.io/hostname: ec2-3
      containers:
      - image: redis
        name: redis-1
        args:
          - redis-server
          - --maxmemory
          - 200mb
          - --maxmemory-policy
          - allkeys-lru
          - --requirepass
          - lldj123414
        ports:
        - containerPort: 6379
          name: redis-1
        env:
        - name: TZ
          value: "Asia/Seoul"

---

apiVersion: v1
kind: Service
metadata:
  name: redis-1-service
spec:
  ports:
  - port: 6379
  selector:
    app: redis-1
REDIS_EOF

kubectl apply -f /kube/redis-1/redis-1.yaml

echo "K8S MASTER BOOTSTRAP DONE"
END_OF_FILE
}

resource "aws_instance" "ec2_1" {
  # 최신 Amazon Linux 2023 AMI 사용
  ami                         = data.aws_ssm_parameter.amazon_linux_ami.value
  instance_type               = "t3.large"
  subnet_id                   = aws_subnet.subnet_1.id
  vpc_security_group_ids      = [aws_security_group.sg_1.id]
  associate_public_ip_address = true

  # Assign IAM role to the instance
  iam_instance_profile = aws_iam_instance_profile.instance_profile_1.name

  tags = {
    Name = "${var.prefix}-ec2-1"
  }

  # 루트 볼륨 설정
  root_block_device {
    volume_type = "gp3"
    volume_size = 32 # 볼륨 크기를 32GB로 설정
  }

  # User data script for ec2_1 (master)
  user_data = <<-EOF
${local.ec2_user_data_base}
${local.ec2_1_master_bootstrap}
EOF
}

# ec2-1 에 private 도메인 연결
resource "aws_route53_record" "record_ec2-1_vpc-1_com" {
  zone_id = aws_route53_zone.vpc_1_zone.zone_id
  name    = "ec2-1.vpc-1.com"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.ec2_1.private_ip]
}

resource "aws_instance" "ec2_2" {
  # 최신 Amazon Linux 2023 AMI 사용
  ami                         = data.aws_ssm_parameter.amazon_linux_ami.value
  instance_type               = "t3.large"
  subnet_id                   = aws_subnet.subnet_3.id
  vpc_security_group_ids      = [aws_security_group.sg_1.id]
  associate_public_ip_address = true

  # Assign IAM role to the instance
  iam_instance_profile = aws_iam_instance_profile.instance_profile_1.name

  tags = {
    Name = "${var.prefix}-ec2-2"
  }

  # 루트 볼륨 설정
  root_block_device {
    volume_type = "gp3"
    volume_size = 32 # 볼륨 크기를 32GB로 설정
  }

  # User data script for ec2_2 (worker)
  # 마스터가 준비될 때까지 조인을 재시도 (최대 15분)
  user_data = <<-EOF
${local.ec2_user_data_base}
hostnamectl set-hostname ec2-2

for i in $(seq 1 60); do
  kubeadm join ${aws_instance.ec2_1.private_ip}:6443 \
    --token ${local.k8s_token} \
    --discovery-token-unsafe-skip-ca-verification && break
  kubeadm reset -f || true
  sleep 15
done
EOF
}

# ec2-2 에 private 도메인 연결
resource "aws_route53_record" "record_ec2-2_vpc-1_com" {
  zone_id = aws_route53_zone.vpc_1_zone.zone_id
  name    = "ec2-2.vpc-1.com"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.ec2_2.private_ip]
}

resource "aws_instance" "ec2_3" {
  # 최신 Amazon Linux 2023 AMI 사용
  ami                         = data.aws_ssm_parameter.amazon_linux_ami.value
  instance_type               = "t3.large"
  subnet_id                   = aws_subnet.subnet_3.id
  vpc_security_group_ids      = [aws_security_group.sg_1.id]
  associate_public_ip_address = true

  # Assign IAM role to the instance
  iam_instance_profile = aws_iam_instance_profile.instance_profile_1.name

  tags = {
    Name = "${var.prefix}-ec2-3"
  }

  # 루트 볼륨 설정
  root_block_device {
    volume_type = "gp3"
    volume_size = 32 # 볼륨 크기를 32GB로 설정
  }

  # User data script for ec2_3 (worker)
  # 마스터가 준비될 때까지 조인을 재시도 (최대 15분)
  user_data = <<-EOF
${local.ec2_user_data_base}
hostnamectl set-hostname ec2-3

for i in $(seq 1 60); do
  kubeadm join ${aws_instance.ec2_1.private_ip}:6443 \
    --token ${local.k8s_token} \
    --discovery-token-unsafe-skip-ca-verification && break
  kubeadm reset -f || true
  sleep 15
done
EOF
}

# ec2-3 에 private 도메인 연결
resource "aws_route53_record" "record_ec2-3_vpc-1_com" {
  zone_id = aws_route53_zone.vpc_1_zone.zone_id
  name    = "ec2-3.vpc-1.com"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.ec2_3.private_ip]
}
# EC2 설정 끝

# 출력
output "ec2_1_public_ip" {
  description = "마스터(ec2-1, NPM 게이트웨이) 공인 IP"
  value       = aws_instance.ec2_1.public_ip
}

output "ec2_2_public_ip" {
  description = "워커(ec2-2, PG) 공인 IP"
  value       = aws_instance.ec2_2.public_ip
}

output "ec2_3_public_ip" {
  description = "워커(ec2-3, Redis) 공인 IP"
  value       = aws_instance.ec2_3.public_ip
}

output "npm_admin_url" {
  description = "NPM 관리자 (부팅 후 약 10분 뒤 접속 가능)"
  value       = "http://${aws_instance.ec2_1.public_ip}:81"
}
