KIND_VERSION = 0.11.1
KUBERNETES_VERSION = 1.21.1
KUSTOMIZE_VERSION = 4.2.0
HELM_VERSION = 3.8.0

TELEPORT_VERSION = 8.3.6
CERT_MANAGER_VERSION = 1.8.0

KIND := $(shell pwd)/bin/kind
KUBECTL := $(shell pwd)/bin/kubectl
KUSTOMIZE := $(shell pwd)/bin/kustomize
TSH := $(shell pwd)/bin/tsh
HELM := $(shell pwd)/bin/helm

CLUSTER_NAME = teleport-test

.PHONY: start
start: $(KIND)
	$(KIND) create cluster --name=${CLUSTER_NAME} --config cluster-config/cluster-config.yaml

.PHONY: setup
setup: $(KUSTOMIZE) $(KUBECTL) $(HELM) $(TSH)
	$(KUSTOMIZE) build cert-manager | $(KUBECTL) apply -f -
	$(KUBECTL) wait -n cert-manager deploy/cert-manager --for condition=available --timeout 3m
	$(KUBECTL) wait -n cert-manager deploy/cert-manager-cainjector --for condition=available --timeout 3m
	$(KUBECTL) wait -n cert-manager deploy/cert-manager-webhook --for condition=available --timeout 3m
	$(KUBECTL) create namespace teleport
	$(KUSTOMIZE) build teleport | $(KUBECTL) apply -f -
	$(KUBECTL) wait -n teleport deploy/teleport --for condition=available --timeout 3m

.PHONY: create-user
create-user: $(KUBECTL)
	$(eval POD := $(shell $(KUBECTL) get pod -n teleport -o jsonpath='{.items..metadata.name}'))
	echo ${POD}
	$(KUBECTL) exec -n teleport -it ${POD} -- tctl users add cybozu --logins=root --roles=access,editor

.PHONY: stop
stop: $(KIND)
	$(KIND) delete cluster --name=${CLUSTER_NAME}

.PHONY: clean
clean:
	rm -rf bin

.PHONY: update-cert-manager
update-cert-manager:
	curl -sSLf -o cert-manager/upstream/cert-manager.yaml https://github.com/cert-manager/cert-manager/releases/download/v${CERT_MANAGER_VERSION}/cert-manager.yaml

.PHONY: update-teleport
update-teleport: $(HELM)
	$(HELM) repo add teleport https://charts.releases.teleport.dev >/dev/null
	$(HELM) repo update >/dev/null
	$(HELM) template teleport teleport/teleport-cluster \
		--version ${TELEPORT_VERSION} \
		--namespace teleport \
		--values teleport/values.yaml > teleport/upstream/teleport.yaml

$(KIND):
	mkdir -p bin
	curl -sfL -o $@ https://github.com/kubernetes-sigs/kind/releases/download/v$(KIND_VERSION)/kind-linux-amd64
	chmod a+x $@

$(KUBECTL):
	mkdir -p bin
	curl -sfL -o $@ https://dl.k8s.io/release/v$(KUBERNETES_VERSION)/bin/linux/amd64/kubectl
	chmod a+x $@

$(KUSTOMIZE):
	mkdir -p bin
	wget -O bin/kustomize.tar.gz https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v$(KUSTOMIZE_VERSION)_linux_amd64.tar.gz
	tar zxf bin/kustomize.tar.gz -C bin
	rm bin/kustomize.tar.gz

$(TSH):
	mkdir -p bin
	wget -O bin/tsh.tar.gz https://get.gravitational.com/teleport-v${TELEPORT_VERSION}-linux-amd64-bin.tar.gz
	tar zxf bin/tsh.tar.gz -C bin --strip-components=1 teleport/tsh
	rm bin/tsh.tar.gz

$(HELM):
	mkdir -p bin
	curl -sSLf -o bin/helm.tar.gz https://get.helm.sh/helm-v$(HELM_VERSION)-linux-amd64.tar.gz
	tar --strip-components=1 -zxf bin/helm.tar.gz -C bin linux-amd64/helm
	rm -f bin/helm.tar.gz
