# Kubernetes Demo - Azure AKS 배포 가이드

이 문서는 kubernetes-demo 프로젝트를 Azure Kubernetes Service(AKS)에 Helm과 GitHub Actions를 사용하여 배포하는 전체 과정을 설명합니다.

## 목차
1. [사전 준비사항](#사전-준비사항)
2. [Azure 리소스 생성](#azure-리소스-생성)
3. [GitHub Secrets 설정](#github-secrets-설정)
4. [로컬에서 테스트](#로컬에서-테스트)
5. [배포 실행](#배포-실행)
6. [모니터링 및 관리](#모니터링-및-관리)
7. [트러블슈팅](#트러블슈팅)

---

## 사전 준비사항

### 필수 도구 설치
```bash
# Azure CLI 설치
# Windows: https://aka.ms/installazurecliwindows
# macOS: brew install azure-cli
# Linux: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Helm 설치
# Windows: choco install kubernetes-helm
# macOS: brew install helm
# Linux: curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kubectl 설치
# Windows: choco install kubernetes-cli
# macOS: brew install kubectl
# Linux: az aks install-cli
```

### Azure 로그인
```bash
az login
az account set --subscription "your-subscription-id"
```

---

## Azure 리소스 생성

### 1. Resource Group 생성
```bash
# Resource Group 생성
az group create \
  --name rg-kubernetes-demo \
  --location koreacentral

# 생성 확인
az group show --name rg-kubernetes-demo
```

### 2. Azure Container Registry (ACR) 생성
```bash
# ACR 생성 (이름은 전역적으로 고유해야 함)
az acr create \
  --resource-group rg-kubernetes-demo \
  --name acrkubernetesdemo \
  --sku Standard \
  --location koreacentral

# ACR 로그인
az acr login --name acrkubernetesdemo

# ACR 정보 확인
az acr show --name acrkubernetesdemo --query loginServer
```

### 3. Azure Kubernetes Service (AKS) 생성
```bash
# AKS 클러스터 생성 (약 5-10분 소요)
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
  --load-balancer-sku standard \
  --location koreacentral

# AKS 자격 증명 가져오기
az aks get-credentials \
  --resource-group rg-kubernetes-demo \
  --name aks-kubernetes-demo \
  --overwrite-existing

# 연결 확인
kubectl get nodes
```

### 4. Ingress Controller 설치 (NGINX)
```bash
# Ingress NGINX Helm 레포지토리 추가
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Ingress Controller 설치
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz

# 설치 확인
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

### 5. Cert-Manager 설치 (선택사항 - HTTPS용)
```bash
# Cert-Manager 설치
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

# 설치 확인
kubectl get pods -n cert-manager

# ClusterIssuer 생성 (Let's Encrypt)
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

---

## GitHub Secrets 설정

### 1. Service Principal 생성
```bash
# Service Principal 생성 및 권한 부여
az ad sp create-for-rbac \
  --name "github-actions-kubernetes-demo" \
  --role contributor \
  --scopes /subscriptions/{subscription-id}/resourceGroups/rg-kubernetes-demo \
  --sdk-auth

# 출력된 JSON을 복사하세요 (GitHub Secrets에 사용)
```

### 2. GitHub Repository Secrets 추가
GitHub Repository → Settings → Secrets and variables → Actions → New repository secret

필요한 Secrets:
- `AZURE_CREDENTIALS`: 위에서 생성한 Service Principal JSON 전체
- `ACR_LOGIN_SERVER`: acrkubernetesdemo.azurecr.io
- `ACR_USERNAME`: acrkubernetesdemo
- `ACR_PASSWORD`: ACR 접근 키 (az acr credential show --name acrkubernetesdemo)

```bash
# ACR 자격 증명 확인
az acr credential show --name acrkubernetesdemo
```

---

## 로컬에서 테스트

### 1. Dockerfile 빌드 테스트
```bash
# Docker 이미지 빌드
docker build -t kubernetes-demo:local .

# 이미지 실행 테스트
docker run -p 8080:8080 kubernetes-demo:local

# 헬스체크
curl http://localhost:8080/actuator/health
```

### 2. Helm Chart 검증
```bash
# Helm Chart 문법 검증
helm lint helm/kubernetes-demo

# Dry-run으로 생성될 매니페스트 확인
helm install kubernetes-demo helm/kubernetes-demo \
  --dry-run \
  --debug \
  --set image.repository=acrkubernetesdemo.azurecr.io/kubernetes-demo \
  --set image.tag=test

# Template 렌더링 확인
helm template kubernetes-demo helm/kubernetes-demo \
  --set image.repository=acrkubernetesdemo.azurecr.io/kubernetes-demo \
  --set image.tag=test
```

### 3. 로컬에서 AKS에 수동 배포 테스트
```bash
# 네임스페이스 생성
kubectl create namespace dev

# Helm 배포
helm upgrade --install kubernetes-demo-dev helm/kubernetes-demo \
  --namespace dev \
  --values helm/kubernetes-demo/values-dev.yaml \
  --set image.repository=acrkubernetesdemo.azurecr.io/kubernetes-demo \
  --set image.tag=latest \
  --wait

# 배포 확인
kubectl get pods -n dev
kubectl get svc -n dev
kubectl get ingress -n dev

# 로그 확인
kubectl logs -n dev -l app.kubernetes.io/instance=kubernetes-demo-dev --tail=100 -f
```

---

## 배포 실행

### 자동 배포 (GitHub Actions)
1. 코드를 GitHub에 push
```bash
git add .
git commit -m "Initial AKS deployment setup"
git push origin develop  # Dev 환경에 배포
git push origin main     # Prod 환경에 배포
```

2. GitHub Actions 진행상황 확인
   - GitHub Repository → Actions 탭에서 워크플로우 확인

### 수동 배포
```bash
# Dev 환경
helm upgrade --install kubernetes-demo-dev helm/kubernetes-demo \
  --namespace dev \
  --create-namespace \
  --values helm/kubernetes-demo/values-dev.yaml \
  --set image.repository=acrkubernetesdemo.azurecr.io/kubernetes-demo \
  --set image.tag=$(git rev-parse --short HEAD) \
  --wait

# Prod 환경
helm upgrade --install kubernetes-demo helm/kubernetes-demo \
  --namespace prod \
  --create-namespace \
  --set image.repository=acrkubernetesdemo.azurecr.io/kubernetes-demo \
  --set image.tag=$(git rev-parse --short HEAD) \
  --wait
```

---

## 모니터링 및 관리

### Pod 상태 확인
```bash
# Pod 목록 확인
kubectl get pods -n prod

# 특정 Pod 상세 정보
kubectl describe pod <pod-name> -n prod

# 로그 확인
kubectl logs -n prod -l app.kubernetes.io/instance=kubernetes-demo --tail=100 -f
```

### 서비스 및 Ingress 확인
```bash
# 서비스 확인
kubectl get svc -n prod

# Ingress 확인 및 External IP 확인
kubectl get ingress -n prod
```

### HPA (Horizontal Pod Autoscaler) 확인
```bash
# HPA 상태 확인
kubectl get hpa -n prod

# HPA 상세 정보
kubectl describe hpa kubernetes-demo -n prod
```

### 배포 롤백
```bash
# Helm 릴리스 히스토리 확인
helm history kubernetes-demo -n prod

# 이전 버전으로 롤백
helm rollback kubernetes-demo <revision-number> -n prod
```

### 스케일링
```bash
# 수동 스케일링 (HPA 비활성화 시)
kubectl scale deployment kubernetes-demo -n prod --replicas=5

# HPA 설정 변경
helm upgrade kubernetes-demo helm/kubernetes-demo \
  --namespace prod \
  --reuse-values \
  --set autoscaling.minReplicas=3 \
  --set autoscaling.maxReplicas=10
```

---

## 트러블슈팅

### 1. Pod가 시작되지 않는 경우
```bash
# Pod 상태 확인
kubectl get pods -n prod

# Pod 이벤트 확인
kubectl describe pod <pod-name> -n prod

# 로그 확인
kubectl logs <pod-name> -n prod
```

### 2. 이미지를 Pull할 수 없는 경우
```bash
# ACR 인증 확인
az acr check-health --name acrkubernetesdemo --yes

# AKS와 ACR 연결 확인
az aks check-acr \
  --resource-group rg-kubernetes-demo \
  --name aks-kubernetes-demo \
  --acr acrkubernetesdemo.azurecr.io
```

### 3. Ingress가 작동하지 않는 경우
```bash
# Ingress Controller 확인
kubectl get pods -n ingress-nginx

# Ingress 리소스 확인
kubectl describe ingress kubernetes-demo -n prod

# External IP 확인
kubectl get svc -n ingress-nginx
```

### 4. Health Check 실패
```bash
# Readiness/Liveness Probe 확인
kubectl describe pod <pod-name> -n prod

# Actuator 엔드포인트 직접 확인
kubectl port-forward <pod-name> 8080:8080 -n prod
curl http://localhost:8080/actuator/health
```

### 5. GitHub Actions 실패
- GitHub Repository → Actions → 실패한 워크플로우 클릭
- 각 Step의 로그 확인
- Secrets가 올바르게 설정되었는지 확인

---

## values.yaml 커스터마이징

### 도메인 변경
`helm/kubernetes-demo/values.yaml` 파일에서:
```yaml
ingress:
  hosts:
    - host: your-custom-domain.com  # 여기를 변경
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: kubernetes-demo-tls
      hosts:
        - your-custom-domain.com  # 여기를 변경
```

### ACR 이름 변경
`helm/kubernetes-demo/values.yaml` 파일에서:
```yaml
image:
  repository: your-acr-name.azurecr.io/kubernetes-demo  # 여기를 변경
```

### 리소스 요구사항 조정
```yaml
resources:
  limits:
    cpu: 2000m      # CPU 제한
    memory: 2Gi     # 메모리 제한
  requests:
    cpu: 1000m      # CPU 요청
    memory: 1Gi     # 메모리 요청
```

---

## 유용한 명령어 모음

```bash
# 전체 리소스 확인
kubectl get all -n prod

# 네임스페이스별 리소스 사용량
kubectl top nodes
kubectl top pods -n prod

# ConfigMap 확인
kubectl get configmap -n prod
kubectl describe configmap kubernetes-demo -n prod

# Secret 확인
kubectl get secrets -n prod

# Helm 릴리스 목록
helm list -A

# 특정 Pod에 접속
kubectl exec -it <pod-name> -n prod -- /bin/sh

# Port Forward로 로컬 테스트
kubectl port-forward svc/kubernetes-demo 8080:80 -n prod
```

---

## 비용 최적화 팁

1. **개발 환경 자동 중지**: Dev 환경은 업무시간 외에는 중지
2. **Node Pool 최적화**: 필요한 만큼만 노드 유지
3. **Spot Instances 사용**: 비용 절감을 위해 Spot VM 사용 고려
4. **리소스 제한 설정**: Pod의 리소스 요청/제한을 적절히 설정

```bash
# AKS 클러스터 중지 (개발 환경)
az aks stop --name aks-kubernetes-demo --resource-group rg-kubernetes-demo

# AKS 클러스터 시작
az aks start --name aks-kubernetes-demo --resource-group rg-kubernetes-demo
```

---

## 다음 단계

1. **모니터링 설정**: Azure Monitor, Prometheus, Grafana 통합
2. **로깅 설정**: Azure Log Analytics, ELK Stack 구성
3. **보안 강화**: Azure Key Vault 연동, RBAC 설정
4. **백업 전략**: Velero를 사용한 클러스터 백업
5. **CI/CD 고도화**: 카나리 배포, Blue-Green 배포 전략 적용

---

## 참고 자료

- [Azure AKS 공식 문서](https://docs.microsoft.com/ko-kr/azure/aks/)
- [Helm 공식 문서](https://helm.sh/docs/)
- [Kubernetes 공식 문서](https://kubernetes.io/ko/docs/home/)
- [GitHub Actions 문서](https://docs.github.com/ko/actions)
