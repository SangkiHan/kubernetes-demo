# 빠른 시작 가이드

이 가이드는 kubernetes-demo를 Azure AKS에 최대한 빠르게 배포하는 방법을 설명합니다.

## 사전 준비

1. **Azure CLI 설치 및 로그인**
```bash
# Azure CLI 설치 (Windows)
# https://aka.ms/installazurecliwindows 에서 다운로드

# 로그인
az login
```

2. **필수 도구 설치**
```bash
# Windows (PowerShell 관리자 권한)
choco install kubernetes-helm kubernetes-cli

# 또는 수동 설치
# kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/
# helm: https://helm.sh/docs/intro/install/
```

## 방법 1: 자동 설정 스크립트 사용 (권장)

### Windows (Git Bash 사용)
```bash
# 1. 스크립트 실행 권한 부여
chmod +x scripts/setup-azure.sh

# 2. Azure 리소스 자동 생성
./scripts/setup-azure.sh

# 3. 출력된 정보를 기록해두세요:
#    - ACR Login Server
#    - ACR Username
#    - ACR Password  
#    - Service Principal JSON (GitHub Secrets용)
```

### Linux/macOS
```bash
# 1. 스크립트 실행
bash scripts/setup-azure.sh

# 2. 출력된 정보를 기록해두세요
```

## 방법 2: 수동 설정

### 1단계: Azure 리소스 생성

```bash
# Resource Group 생성
az group create --name rg-kubernetes-demo --location koreacentral

# ACR 생성 (이름은 고유해야 함)
az acr create \
  --resource-group rg-kubernetes-demo \
  --name acrkubernetesdemo \
  --sku Standard \
  --location koreacentral

# AKS 생성 (약 5-10분 소요)
az aks create \
  --resource-group rg-kubernetes-demo \
  --name aks-kubernetes-demo \
  --node-count 3 \
  --node-vm-size Standard_B2s \
  --enable-managed-identity \
  --attach-acr acrkubernetesdemo \
  --enable-cluster-autoscaler \
  --min-count 2 \
  --max-count 5 \
  --network-plugin azure \
  --generate-ssh-keys

# AKS 자격 증명 가져오기
az aks get-credentials \
  --resource-group rg-kubernetes-demo \
  --name aks-kubernetes-demo \
  --overwrite-existing

# 연결 확인
kubectl get nodes
```

### 2단계: Ingress Controller 설치

```bash
# Helm 레포지토리 추가
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Ingress Controller 설치
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace

# External IP 확인 (1-2분 소요)
kubectl get svc -n ingress-nginx
```

### 3단계: GitHub 설정

#### Service Principal 생성
```bash
az ad sp create-for-rbac \
  --name "github-actions-kubernetes-demo" \
  --role contributor \
  --scopes /subscriptions/{subscription-id}/resourceGroups/rg-kubernetes-demo \
  --sdk-auth
```

출력된 JSON을 복사하세요.

#### GitHub Secrets 추가
1. GitHub Repository → Settings → Secrets and variables → Actions
2. New repository secret 클릭
3. 다음 Secrets 추가:

| Name | Value |
|------|-------|
| `AZURE_CREDENTIALS` | Service Principal JSON 전체 |
| `ACR_LOGIN_SERVER` | acrkubernetesdemo.azurecr.io |
| `ACR_USERNAME` | `az acr credential show --name acrkubernetesdemo --query username -o tsv` |
| `ACR_PASSWORD` | `az acr credential show --name acrkubernetesdemo --query "passwords[0].value" -o tsv` |

### 4단계: 설정 파일 수정

#### `helm/kubernetes-demo/values.yaml` 수정
```yaml
image:
  repository: acrkubernetesdemo.azurecr.io/kubernetes-demo  # ACR 이름 변경

ingress:
  hosts:
    - host: kubernetes-demo.yourdomain.com  # 실제 도메인으로 변경
```

#### `.github/workflows/deploy-aks.yml` 수정
```yaml
env:
  ACR_NAME: acrkubernetesdemo  # 실제 ACR 이름
```

### 5단계: 배포

```bash
# GitHub에 푸시
git add .
git commit -m "Setup Azure AKS deployment"
git push origin main

# GitHub Actions에서 배포 진행 확인
# Repository → Actions 탭
```

## 로컬에서 테스트 배포

자동 배포 스크립트 사용:

```bash
# Dev 환경 배포
chmod +x scripts/deploy-local.sh
./scripts/deploy-local.sh

# Prod 환경 배포
./scripts/deploy-local.sh prod
```

수동 배포:

```bash
# 1. 빌드
./gradlew clean build -x test

# 2. ACR 로그인
az acr login --name acrkubernetesdemo

# 3. Docker 이미지 빌드 및 푸시
docker build -t acrkubernetesdemo.azurecr.io/kubernetes-demo:latest .
docker push acrkubernetesdemo.azurecr.io/kubernetes-demo:latest

# 4. Helm 배포
helm upgrade --install kubernetes-demo-dev ./helm/kubernetes-demo \
  --namespace dev \
  --create-namespace \
  --values ./helm/kubernetes-demo/values-dev.yaml \
  --set image.repository=acrkubernetesdemo.azurecr.io/kubernetes-demo \
  --set image.tag=latest \
  --wait
```

## 배포 확인

```bash
# Pod 상태 확인
kubectl get pods -n dev

# 서비스 확인
kubectl get svc -n dev

# Ingress 확인
kubectl get ingress -n dev

# 로그 확인
kubectl logs -n dev -l app.kubernetes.io/instance=kubernetes-demo-dev --tail=100 -f

# 포트 포워딩으로 로컬 테스트
kubectl port-forward svc/kubernetes-demo-dev 8080:80 -n dev

# 브라우저나 curl로 확인
curl http://localhost:8080/api/hello
curl http://localhost:8080/actuator/health
```

## 유용한 명령어

```bash
# 전체 리소스 확인
kubectl get all -n dev

# Pod 재시작
kubectl rollout restart deployment/kubernetes-demo-dev -n dev

# 리소스 사용량 확인
kubectl top nodes
kubectl top pods -n dev

# Helm 릴리스 확인
helm list -A

# Helm 릴리스 삭제
helm uninstall kubernetes-demo-dev -n dev
```

## 문제 해결

### Pod가 시작되지 않는 경우
```bash
# Pod 상세 정보 확인
kubectl describe pod <pod-name> -n dev

# 로그 확인
kubectl logs <pod-name> -n dev

# 이벤트 확인
kubectl get events -n dev --sort-by='.lastTimestamp'
```

### 이미지 Pull 실패
```bash
# ACR 연결 확인
az aks check-acr \
  --resource-group rg-kubernetes-demo \
  --name aks-kubernetes-demo \
  --acr acrkubernetesdemo.azurecr.io
```

### Ingress 작동 안함
```bash
# Ingress Controller 상태 확인
kubectl get pods -n ingress-nginx

# Ingress 상세 정보
kubectl describe ingress kubernetes-demo-dev -n dev
```

## 리소스 정리

모든 Azure 리소스를 삭제하려면:

```bash
# 자동 정리 (권장)
chmod +x scripts/cleanup-azure.sh
./scripts/cleanup-azure.sh

# 수동 정리
az group delete --name rg-kubernetes-demo --yes --no-wait
```

## 다음 단계

1. ✅ 기본 배포 완료
2. 📊 [모니터링 설정](README-DEPLOY.md#모니터링-및-관리) - Prometheus, Grafana
3. 🔒 [HTTPS 설정](README-DEPLOY.md#cert-manager-설치) - Cert-Manager
4. 🗄️ [데이터베이스 연결](README-DEPLOY.md) - Azure Database for PostgreSQL
5. 🚀 [고급 배포 전략](README-DEPLOY.md) - Blue-Green, Canary

## 참고 문서

- [상세 배포 가이드](README-DEPLOY.md)
- [Azure AKS 문서](https://docs.microsoft.com/ko-kr/azure/aks/)
- [Helm 문서](https://helm.sh/docs/)

---

**예상 소요 시간**
- 자동 스크립트 사용: 15-20분
- 수동 설정: 30-40분

**예상 비용** (한국 중부 리전 기준)
- AKS: ~$100-150/월 (Standard_B2s × 3 노드)
- ACR: ~$5/월 (Standard)
- LoadBalancer: ~$25/월
- **총합: 약 $130-180/월**

💡 **Tip**: 개발/테스트 환경은 업무시간 외에 중지하여 비용 절감 가능
```bash
az aks stop --name aks-kubernetes-demo --resource-group rg-kubernetes-demo
az aks start --name aks-kubernetes-demo --resource-group rg-kubernetes-demo
```
