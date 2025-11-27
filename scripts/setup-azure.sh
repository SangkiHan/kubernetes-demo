#!/bin/bash

# Azure AKS 환경 자동 설정 스크립트
# 이 스크립트는 Azure 리소스를 생성하고 AKS 클러스터를 설정합니다.

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 변수 설정
RESOURCE_GROUP="rg-kubernetes-demo"
LOCATION="koreacentral"
ACR_NAME="acrkubernetesdemo"
AKS_NAME="aks-kubernetes-demo"
NODE_COUNT=3
NODE_VM_SIZE="Standard_B2s"
MIN_COUNT=2
MAX_COUNT=5

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Azure AKS 환경 설정 시작${NC}"
echo -e "${GREEN}========================================${NC}"

# Azure 로그인 확인
echo -e "\n${YELLOW}1. Azure 로그인 확인 중...${NC}"
if ! az account show &> /dev/null; then
    echo -e "${RED}Azure에 로그인되어 있지 않습니다. 로그인을 진행합니다.${NC}"
    az login
else
    echo -e "${GREEN}✓ Azure 로그인 확인됨${NC}"
fi

# 구독 정보 표시
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
echo -e "${GREEN}현재 구독: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})${NC}"

# Resource Group 생성
echo -e "\n${YELLOW}2. Resource Group 생성 중...${NC}"
if az group show --name $RESOURCE_GROUP &> /dev/null; then
    echo -e "${YELLOW}Resource Group이 이미 존재합니다. 건너뜁니다.${NC}"
else
    az group create \
        --name $RESOURCE_GROUP \
        --location $LOCATION
    echo -e "${GREEN}✓ Resource Group 생성 완료${NC}"
fi

# ACR 생성
echo -e "\n${YELLOW}3. Azure Container Registry 생성 중...${NC}"
if az acr show --name $ACR_NAME &> /dev/null; then
    echo -e "${YELLOW}ACR이 이미 존재합니다. 건너뜁니다.${NC}"
else
    az acr create \
        --resource-group $RESOURCE_GROUP \
        --name $ACR_NAME \
        --sku Standard \
        --location $LOCATION
    echo -e "${GREEN}✓ ACR 생성 완료${NC}"
fi

# ACR 로그인
echo -e "\n${YELLOW}4. ACR 로그인 중...${NC}"
az acr login --name $ACR_NAME
echo -e "${GREEN}✓ ACR 로그인 완료${NC}"

# AKS 생성
echo -e "\n${YELLOW}5. AKS 클러스터 생성 중... (약 5-10분 소요)${NC}"
if az aks show --name $AKS_NAME --resource-group $RESOURCE_GROUP &> /dev/null; then
    echo -e "${YELLOW}AKS 클러스터가 이미 존재합니다. 건너뜁니다.${NC}"
else
    az aks create \
        --resource-group $RESOURCE_GROUP \
        --name $AKS_NAME \
        --node-count $NODE_COUNT \
        --node-vm-size $NODE_VM_SIZE \
        --enable-managed-identity \
        --attach-acr $ACR_NAME \
        --enable-cluster-autoscaler \
        --min-count $MIN_COUNT \
        --max-count $MAX_COUNT \
        --network-plugin azure \
        --load-balancer-sku standard \
        --location $LOCATION \
        --generate-ssh-keys
    echo -e "${GREEN}✓ AKS 클러스터 생성 완료${NC}"
fi

# AKS 자격 증명 가져오기
echo -e "\n${YELLOW}6. AKS 자격 증명 가져오기...${NC}"
az aks get-credentials \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_NAME \
    --overwrite-existing
echo -e "${GREEN}✓ AKS 자격 증명 설정 완료${NC}"

# 클러스터 연결 확인
echo -e "\n${YELLOW}7. 클러스터 연결 확인 중...${NC}"
kubectl get nodes
echo -e "${GREEN}✓ 클러스터 연결 성공${NC}"

# Ingress NGINX 설치
echo -e "\n${YELLOW}8. Ingress NGINX 설치 중...${NC}"
if helm list -n ingress-nginx | grep -q ingress-nginx; then
    echo -e "${YELLOW}Ingress NGINX가 이미 설치되어 있습니다. 건너뜁니다.${NC}"
else
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update
    
    helm install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --create-namespace \
        --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz
    
    echo -e "${GREEN}✓ Ingress NGINX 설치 완료${NC}"
    echo -e "${YELLOW}External IP 할당을 기다리는 중...${NC}"
    sleep 30
fi

# External IP 확인
echo -e "\n${YELLOW}9. Ingress External IP 확인...${NC}"
kubectl get svc -n ingress-nginx

# Service Principal 생성 (GitHub Actions용)
echo -e "\n${YELLOW}10. Service Principal 생성 (GitHub Actions용)...${NC}"
SP_NAME="github-actions-kubernetes-demo"

# 기존 Service Principal 확인
if az ad sp list --display-name $SP_NAME --query "[].appId" -o tsv | grep -q .; then
    echo -e "${YELLOW}Service Principal이 이미 존재합니다.${NC}"
    SP_APP_ID=$(az ad sp list --display-name $SP_NAME --query "[0].appId" -o tsv)
    echo -e "${GREEN}기존 Service Principal App ID: ${SP_APP_ID}${NC}"
else
    # Service Principal 생성
    SP_OUTPUT=$(az ad sp create-for-rbac \
        --name $SP_NAME \
        --role contributor \
        --scopes /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP \
        --sdk-auth)
    
    echo -e "${GREEN}✓ Service Principal 생성 완료${NC}"
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}GitHub Secrets 설정${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${YELLOW}다음 값을 GitHub Repository Secrets에 추가하세요:${NC}\n"
    echo -e "${GREEN}Secret Name: AZURE_CREDENTIALS${NC}"
    echo -e "${YELLOW}Secret Value:${NC}"
    echo "$SP_OUTPUT"
fi

# ACR 자격 증명 출력
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}ACR 자격 증명${NC}"
echo -e "${GREEN}========================================${NC}"
ACR_LOGIN_SERVER=$(az acr show --name $ACR_NAME --query loginServer -o tsv)
ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query username -o tsv)
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query "passwords[0].value" -o tsv)

echo -e "${GREEN}ACR Login Server:${NC} $ACR_LOGIN_SERVER"
echo -e "${GREEN}ACR Username:${NC} $ACR_USERNAME"
echo -e "${GREEN}ACR Password:${NC} $ACR_PASSWORD"

# 요약 정보 출력
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}설정 완료 요약${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Resource Group:${NC} $RESOURCE_GROUP"
echo -e "${GREEN}Location:${NC} $LOCATION"
echo -e "${GREEN}ACR Name:${NC} $ACR_NAME"
echo -e "${GREEN}ACR Login Server:${NC} $ACR_LOGIN_SERVER"
echo -e "${GREEN}AKS Cluster:${NC} $AKS_NAME"
echo -e "${GREEN}Subscription ID:${NC} $SUBSCRIPTION_ID"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}다음 단계${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "1. GitHub Repository Secrets 설정"
echo -e "   - AZURE_CREDENTIALS: 위에 출력된 Service Principal JSON"
echo -e "   - ACR_LOGIN_SERVER: $ACR_LOGIN_SERVER"
echo -e "   - ACR_USERNAME: $ACR_USERNAME"
echo -e "   - ACR_PASSWORD: $ACR_PASSWORD"
echo -e ""
echo -e "2. values.yaml 파일 수정"
echo -e "   - image.repository를 $ACR_LOGIN_SERVER/kubernetes-demo 로 변경"
echo -e "   - ingress.hosts를 실제 도메인으로 변경"
echo -e ""
echo -e "3. 코드를 GitHub에 push하여 자동 배포 시작"
echo -e "   git add ."
echo -e "   git commit -m 'Setup AKS deployment'"
echo -e "   git push origin main"

echo -e "\n${GREEN}모든 설정이 완료되었습니다! 🎉${NC}\n"
