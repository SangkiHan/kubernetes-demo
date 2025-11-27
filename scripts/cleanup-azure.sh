#!/bin/bash

# Azure 리소스 정리 스크립트
# 주의: 이 스크립트는 모든 Azure 리소스를 삭제합니다!

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 변수 설정
RESOURCE_GROUP="rg-kubernetes-demo"

echo -e "${RED}========================================${NC}"
echo -e "${RED}⚠️  Azure 리소스 정리${NC}"
echo -e "${RED}========================================${NC}"
echo -e "${YELLOW}다음 리소스 그룹의 모든 리소스가 삭제됩니다:${NC}"
echo -e "${RED}Resource Group: $RESOURCE_GROUP${NC}"
echo -e ""
echo -e "${YELLOW}포함된 리소스:${NC}"
az resource list --resource-group $RESOURCE_GROUP --query "[].{Name:name, Type:type}" -o table

echo -e "\n${RED}이 작업은 되돌릴 수 없습니다!${NC}"
read -p "정말로 삭제하시겠습니까? (yes/no): " -r
echo

if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    echo -e "${GREEN}취소되었습니다.${NC}"
    exit 0
fi

echo -e "\n${YELLOW}리소스 그룹 삭제 중... (약 5-10분 소요)${NC}"
az group delete --name $RESOURCE_GROUP --yes --no-wait

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}삭제 요청이 제출되었습니다.${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}삭제 상태 확인:${NC}"
echo -e "  az group show --name $RESOURCE_GROUP"
echo -e ""
echo -e "${YELLOW}백그라운드에서 삭제가 진행됩니다.${NC}"
echo -e "${YELLOW}완료까지 약 5-10분이 소요될 수 있습니다.${NC}\n"
