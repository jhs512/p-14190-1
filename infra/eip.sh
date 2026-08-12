#!/bin/bash
# 고정 EIP 할당 (한 번만 실행, 멱등)
# 테라폼 밖에서 관리하므로 terraform destroy 해도 EIP가 유지된다
# -> DNSZi A레코드, GITHUB KUBE_CONFIG 시크릿을 다시 만질 필요가 없다
TAG=p14190-eip-1
IP=$(aws ec2 describe-addresses --filters "Name=tag:Name,Values=$TAG" --query "Addresses[0].PublicIp" --output text 2>/dev/null)
if [ "$IP" = "None" ] || [ -z "$IP" ]; then
  IP=$(aws ec2 allocate-address --domain vpc \
    --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=$TAG}]" \
    --query "PublicIp" --output text)
  echo "EIP 새로 할당: $IP"
else
  echo "기존 EIP 사용: $IP"
fi
