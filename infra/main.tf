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

# EIP (마스터 고정 IP) 시작
# EIP는 테라폼 밖에서 관리한다 (한 번만: bash eip.sh 로 할당)
# -> terraform destroy 를 해도 EIP가 유지되므로 DNSZi A레코드, KUBE_CONFIG가 안 바뀐다
data "aws_eip" "eip_1" {
  filter {
    name   = "tag:Name"
    values = ["${var.prefix}-eip-1"]
  }
}

resource "aws_eip_association" "eip_assoc_1" {
  instance_id   = aws_instance.ec2_1.id
  allocation_id = data.aws_eip.eip_1.id
}
# EIP 끝

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

# 환경변수 세팅(/etc/environment)
echo "PASSWORD_1=${var.password_1}" >> /etc/environment
echo "APP_1_DOMAIN=${var.app_1_domain}" >> /etc/environment

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

  # 마스터(ec2-1) 전용: 클러스터 생성 + Calico + NPMplus/PG/Redis 배포 + NPMplus 스트림/프록시 자동 세팅
  ec2_1_master_bootstrap = <<-END_OF_FILE
hostnamectl set-hostname ec2-1

echo "K8S MASTER BOOTSTRAP START"

# 클러스터 생성
# --token-ttl 0 : 토큰 만료 없음(강의용 편의). 운영에서는 만료시간을 두는 것이 안전
# --apiserver-cert-extra-sans : EIP + k8s.도메인 → 외부(KUBE_CONFIG, GITHUB ACTIONS)에서
#   https://k8s.(base_domain):6443 으로 kubectl 접속 가능 (인증서 SAN에 도메인 포함)
kubeadm init \
  --token ${local.k8s_token} \
  --token-ttl 0 \
  --pod-network-cidr=10.10.0.0/16 \
  --apiserver-cert-extra-sans=${data.aws_eip.eip_1.public_ip},k8s.${var.base_domain} \
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
# NPMplus (게이트웨이) - ec2-1
# - NPMplus(OpenResty)의 "resolver local=on"이 resolv.conf를 읽으므로,
#   pod의 resolv.conf가 dnsmasq(127.0.0.1)를 가리키게 하고(dnsConfig),
#   dnsmasq가 search domain을 붙여서 CoreDNS에 물어보게 한다.
#   -> 짧은 서비스명(pg-1-service 등)으로 프록시/스트림 포워딩 가능
# ========================================
DNS_IP=$(kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}')

# NPMplus는 시작 시 외부 DNS(certbot)를 사용하므로 CoreDNS가 준비된 후에 배포
kubectl -n kube-system rollout status deployment/coredns --timeout=600s

mkdir -p /kube/npmplus-1

cat <<NPM_EOF > /kube/npmplus-1/npmplus-1.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: npmplus-1-deployment
spec:
  selector:
    matchLabels:
      app: npmplus-1
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: npmplus-1
    spec:
      nodeSelector:
        kubernetes.io/hostname: ec2-1
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      dnsPolicy: "None"
      dnsConfig:
        nameservers:
        - 127.0.0.1
        searches:
        - default.svc.cluster.local
        - svc.cluster.local
        - cluster.local
        options:
        - name: ndots
          value: "5"
      containers:
      - image: zoeyvid/npmplus:latest
        name: npmplus-1
        ports:
        - containerPort: 80
          hostPort: 80
        - containerPort: 443
          hostPort: 443
        - containerPort: 443
          hostPort: 443
          protocol: UDP
        - containerPort: 81
          hostPort: 81
        - containerPort: 5432
          hostPort: 5432
        - containerPort: 6379
          hostPort: 6379
        env:
        - name: TZ
          value: "Asia/Seoul"
        - name: "INITIAL_ADMIN_EMAIL"
          value: "admin@npm.com"
        - name: "INITIAL_ADMIN_PASSWORD"
          value: "${var.password_1}"
        # 초기 기동 실패(클러스터 DNS 미준비 등) 시 자동 재시작되도록
        livenessProbe:
          tcpSocket:
            port: 81
          initialDelaySeconds: 60
          periodSeconds: 15
          failureThreshold: 5
        volumeMounts:
        - name: vol
          mountPath: /data
          subPath: data
      - image: "janeczku/go-dnsmasq:release-1.0.7"
        name: dnsmasq
        args:
          - --listen
          - "127.0.0.1:53"
          - --nameservers
          - "$DNS_IP:53"
          - --search-domains
          - "default.svc.cluster.local,svc.cluster.local,cluster.local"
          - --append-search-domains
      volumes:
      - name: vol
        hostPath:
          path: /data/ec2-1/npmplus-1
          type: DirectoryOrCreate
NPM_EOF

kubectl apply -f /kube/npmplus-1/npmplus-1.yaml

# ========================================
# PG(jangka512/pgj) - ec2-2
# ========================================
mkdir -p /kube/pg-1

cat <<PG_EOF > /kube/pg-1/pg-1.yaml
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
  password: ${base64encode(var.password_1)}
PG_EOF

kubectl apply -f /kube/pg-1/pg-1.yaml

# ========================================
# Redis - ec2-3
# ========================================
mkdir -p /kube/redis-1

cat <<REDIS_EOF > /kube/redis-1/redis-1.yaml
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
          - ${var.password_1}
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

# ========================================
# 앱(스프링부트) 배포 - 시크릿이 제공된 경우에만
# ========================================
if [ -n "${var.github_access_token_1}" ]; then
  kubectl create secret docker-registry github-registry-secret \
    --docker-server=ghcr.io \
    --docker-username=${var.github_access_token_1_owner} \
    --docker-password=${var.github_access_token_1} \
    --docker-email=${var.github_access_token_1_owner}@users.noreply.github.com

  echo "${base64encode(var.app_1_env)}" | base64 -d > /root/app.env
  kubectl create secret generic p-14190-1-secret --from-env-file=/root/app.env

  mkdir -p /kube/p-14190-1

  cat <<'APP_EOF' > /kube/p-14190-1/p-14190-1.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: p-14190-1
spec:
  replicas: 2
  selector:
    matchLabels:
      app: p-14190-1
  template:
    metadata:
      labels:
        app: p-14190-1
    spec:
      imagePullSecrets:
      - name: github-registry-secret
      containers:
      - name: p-14190-1-1
        image: ghcr.io/${var.github_access_token_1_owner}/p-14190-1:latest
        envFrom:
        - secretRef:
            name: p-14190-1-secret
        env:
        - name: TZ
          value: "Asia/Seoul"
        ports:
        - containerPort: 8080
        readinessProbe:
          httpGet:
            path: /actuator/health/readiness
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 20
        livenessProbe:
          httpGet:
            path: /actuator/health/liveness
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 20
        # 파드 종료 시작과 endpoint 제거는 동시에 일어난다.
        # preStop으로 잠깐 버텨 주면 그 사이 endpoint에서 빠지므로
        # 게이트웨이가 죽는 파드로 새 요청을 보내지 않는다 (502 방지)
        lifecycle:
          preStop:
            exec:
              command: ["sh", "-c", "sleep 10"]
      # preStop(10s) + graceful shutdown 여유
      terminationGracePeriodSeconds: 45

---

apiVersion: v1
kind: Service
metadata:
  name: p-14190-1-service
spec:
  selector:
    app: p-14190-1
  ports:
  - port: 8080
    targetPort: 8080
APP_EOF

  kubectl apply -f /kube/p-14190-1/p-14190-1.yaml
fi

# ========================================
# NPMplus 준비 대기 후 스트림/프록시 호스트 자동 세팅 (API)
# ========================================
for i in $(seq 1 120); do
  code=$(curl -sk -o /dev/null -w '%%{http_code}' https://127.0.0.1:81/api 2>/dev/null || true)
  [ "$code" = "200" ] && break
  sleep 5
done

JAR=/tmp/.npmjar
curl -sk -c $JAR -X POST https://127.0.0.1:81/api/tokens -H "Content-Type: application/json" \
  -d '{"identity":"admin@npm.com","secret":"${var.password_1}"}'

# 스트림: 5432 -> pg-1-service (DBeaver 등 외부 DB 접속용)
curl -sk -b $JAR -X POST https://127.0.0.1:81/api/nginx/streams -H "Content-Type: application/json" \
  -d '{"incoming_port":5432,"forwarding_host":"pg-1-service","forwarding_port":5432,"tcp_forwarding":true,"udp_forwarding":false}'

# 스트림: 6379 -> redis-1-service (Another Redis Desktop Manager 등 외부 접속용)
curl -sk -b $JAR -X POST https://127.0.0.1:81/api/nginx/streams -H "Content-Type: application/json" \
  -d '{"incoming_port":6379,"forwarding_host":"redis-1-service","forwarding_port":6379,"tcp_forwarding":true,"udp_forwarding":false}'

# 프록시 호스트: 앱 도메인 -> p-14190-1-service:8080
PROXY_RES=$(curl -sk -b $JAR -X POST https://127.0.0.1:81/api/nginx/proxy-hosts -H "Content-Type: application/json" \
  -d '{"domain_names":["${var.app_1_domain}"],"forward_scheme":"http","forward_host":"p-14190-1-service","forward_port":8080}')
PROXY_ID=$(echo "$PROXY_RES" | python3 -c "import sys,json;print(json.load(sys.stdin).get('id',''))" 2>/dev/null || true)

# 도메인이 이미 EIP를 가리키고 있으면(DNSZi 세팅 가정) Let's Encrypt 인증서 발급 + SSL 강제까지 자동
# (아직 DNS가 안 되어 있으면 이 블록은 조용히 건너뜀 - 나중에 NPMplus 관리자에서 발급)
DOMAIN_IP=$(getent hosts ${var.app_1_domain} | awk '{print $1}' | head -1 || true)
if [ "$DOMAIN_IP" = "${data.aws_eip.eip_1.public_ip}" ] && [ -n "$PROXY_ID" ]; then
  # NPMplus 인증서 발급 (HTTP-01). 계정 이메일은 INITIAL_ADMIN_EMAIL 사용, meta는 dns_challenge만
  CERT_RES=$(curl -sk -b $JAR -X POST https://127.0.0.1:81/api/nginx/certificates -H "Content-Type: application/json" \
    -d '{"provider":"letsencrypt","nice_name":"${var.app_1_domain}","domain_names":["${var.app_1_domain}"],"meta":{"dns_challenge":false}}' || true)
  CERT_ID=$(echo "$CERT_RES" | python3 -c "import sys,json;print(json.load(sys.stdin).get('id',''))" 2>/dev/null || true)
  if [ -n "$CERT_ID" ]; then
    curl -sk -b $JAR -X PUT https://127.0.0.1:81/api/nginx/proxy-hosts/$PROXY_ID -H "Content-Type: application/json" \
      -d "{\"certificate_id\":$CERT_ID,\"ssl_forced\":true}" || true
  fi
fi

# apex(${var.base_domain}) -> https://www.${var.base_domain} 301 리다이렉트 호스트
# (프론트는 Vercel(www)이고, 맨 도메인으로 들어오면 www로 보냄)
curl -sk -b $JAR -X POST https://127.0.0.1:81/api/nginx/redirection-hosts -H "Content-Type: application/json" \
  -d '{"domain_names":["${var.base_domain}"],"forward_scheme":"https","forward_domain_name":"www.${var.base_domain}","forward_http_code":301,"preserve_path":true,"block_exploits":true,"certificate_id":0,"ssl_forced":false,"hsts_enabled":false,"hsts_subdomains":false,"meta":{}}' || true

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
output "master_eip" {
  description = "마스터(ec2-1) 고정 공인 IP - 도메인 A레코드/KUBE_CONFIG는 이 IP로"
  value       = data.aws_eip.eip_1.public_ip
}

output "ec2_2_public_ip" {
  description = "워커(ec2-2, PG) 공인 IP"
  value       = aws_instance.ec2_2.public_ip
}

output "ec2_3_public_ip" {
  description = "워커(ec2-3, Redis) 공인 IP"
  value       = aws_instance.ec2_3.public_ip
}

output "npmplus_admin_url" {
  description = "NPMplus 관리자 (부팅 후 약 6~8분 뒤 접속 가능, admin@npm.com / password_1)"
  value       = "https://${data.aws_eip.eip_1.public_ip}:81"
}
