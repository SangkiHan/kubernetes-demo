#!/bin/bash

# 로컬에서 AKS에 수동 배포하는 스크립트

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 변수 설정
ACR_NAME="sangkihanKubernetes"
IMAGE_NAME="kubernetes-demo"
RESOURCE_GROUP="test-kubernete"
AKS_NAME="test-kubernete"
NAMESPACE="dev"
RELEASE_NAME="kubernetes-demo-dev"

# 인자 확인
if [ "$1" == "prod" ]; then
    NAMESPACE="prod"
    RELEASE_NAME="kubernetes-demo"
    echo -e "${YELLOW}프로덕션 환경으로 배포합니다.${NC}"
else
    echo -e "${YELLOW}개발 환경으로 배포합니다.${NC}"
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}로컬 배포 시작${NC}"
echo -e "${GREEN}========================================${NC}"

# 1. Gradle 빌드
echo -e "\n${YELLOW}1. Gradle 빌드 중...${NC}"
./gradlew clean build -x test
echo -e "${GREEN}✓ 빌드 완료${NC}"

# 2. ACR 로그인
echo -e "\n${YELLOW}2. ACR 로그인 중...${NC}"
az acr login --name $ACR_NAME
echo -e "${GREEN}✓ ACR 로그인 완료${NC}"

# 3. Docker 이미지 빌드
echo -e "\n${YELLOW}3. Docker 이미지 빌드 중...${NC}"
IMAGE_TAG=$(git rev-parse --short HEAD)
FULL_IMAGE_NAME="$ACR_NAME.azurecr.io/$IMAGE_NAME:$IMAGE_TAG"

docker build -t $FULL_IMAGE_NAME .
docker tag $FULL_IMAGE_NAME "$ACR_NAME.azurecr.io/$IMAGE_NAME:latest"
echo -e "${GREEN}✓ Docker 이미지 빌드 완료${NC}"

# 4. Docker 이미지 푸시
echo -e "\n${YELLOW}4. Docker 이미지 ACR에 푸시 중...${NC}"
docker push $FULL_IMAGE_NAME
docker push "$ACR_NAME.azurecr.io/$IMAGE_NAME:latest"
echo -e "${GREEN}✓ 이미지 푸시 완료${NC}"

# 5. AKS 자격 증명 가져오기
echo -e "\n${YELLOW}5. AKS 자격 증명 확인 중...${NC}"
az aks get-credentials \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_NAME \
    --overwrite-existing
echo -e "${GREEN}✓ AKS 연결 완료${NC}"

# 6. 네임스페이스 생성
echo -e "\n${YELLOW}6. 네임스페이스 확인 중...${NC}"
if kubectl get namespace $NAMESPACE &> /dev/null; then
    echo -e "${YELLOW}네임스페이스 '$NAMESPACE'가 이미 존재합니다.${NC}"
else
    kubectl create namespace $NAMESPACE
    echo -e "${GREEN}✓ 네임스페이스 '$NAMESPACE' 생성 완료${NC}"
fi

# 7. Helm 배포
echo -e "\n${YELLOW}7. Helm으로 배포 중...${NC}"
if [ "$NAMESPACE" == "prod" ]; then
    helm upgrade --install $RELEASE_NAME ./helm/kubernetes-demo \
        --namespace $NAMESPACE \
        --set image.repository=$ACR_NAME.azurecr.io/$IMAGE_NAME \
        --set image.tag=$IMAGE_TAG \
        --wait \
        --timeout 5m
else
    helm upgrade --install $RELEASE_NAME ./helm/kubernetes-demo \
        --namespace $NAMESPACE \
        --values ./helm/kubernetes-demo/values-dev.yaml \
        --set image.repository=$ACR_NAME.azurecr.io/$IMAGE_NAME \
        --set image.tag=$IMAGE_TAG \
        --wait \
        --timeout 5m
fi
echo -e "${GREEN}✓ Helm 배포 완료${NC}"

# 8. 배포 확인
echo -e "\n${YELLOW}8. 배포 상태 확인 중...${NC}"
kubectl rollout status deployment/$RELEASE_NAME -n $NAMESPACE
echo -e "${GREEN}✓ 배포 성공${NC}"

# 9. Pod 상태 확인
echo -e "\n${YELLOW}9. Pod 상태:${NC}"
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME

# 10. 서비스 확인
echo -e "\n${YELLOW}10. 서비스 상태:${NC}"
kubectl get svc -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME

# 11. Ingress 확인
echo -e "\n${YELLOW}11. Ingress 상태:${NC}"
kubectl get ingress -n $NAMESPACE

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}배포 완료!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Image:${NC} $FULL_IMAGE_NAME"
echo -e "${GREEN}Namespace:${NC} $NAMESPACE"
echo -e "${GREEN}Release:${NC} $RELEASE_NAME"

echo -e "\n${YELLOW}유용한 명령어:${NC}"
echo -e "  로그 확인: kubectl logs -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME --tail=100 -f"
echo -e "  Pod 상태: kubectl get pods -n $NAMESPACE"
echo -e "  포트 포워딩: kubectl port-forward svc/$RELEASE_NAME 8080:80 -n $NAMESPACE"
echo -e "  삭제: helm uninstall $RELEASE_NAME -n $NAMESPACE"

echo -e "\n${GREEN}배포가 완료되었습니다! 🚀${NC}\n"
