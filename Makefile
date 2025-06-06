MAKEFILE_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

# `kubernetes_version` is a build variable, but requires some introspection
# to dynamically determine build templates & variable defaults.
# initialize the kubernetes version from the provided packer file if missing.
ifeq ($(kubernetes_version),)
ifneq ($(PACKER_VARIABLE_FILE),)
	kubernetes_version ?= $(shell jq -r .kubernetes_version $(PACKER_VARIABLE_FILE))
endif
endif

K8S_VERSION_PARTS := $(subst ., ,$(kubernetes_version))
K8S_VERSION_MINOR := $(word 1,${K8S_VERSION_PARTS}).$(word 2,${K8S_VERSION_PARTS})

AMI_VARIANT ?= amazon-eks
AMI_VERSION ?= v$(shell date '+%Y%m%d')
os_distro ?= rhel
arch ?= x86_64
aws_region ?= us-west-2
binary_bucket_region ?= us-west-2
binary_bucket_name ?= amazon-eks

ifeq ($(os_distro), rhel)
	AMI_VARIANT := $(AMI_VARIANT)-rhel
endif
ifeq ($(arch), arm64)
	instance_type ?= m6g.large
	AMI_VARIANT := $(AMI_VARIANT)-arm64
else
	instance_type ?= t3.large
endif
ifeq ($(enable_fips), true)
	AMI_VARIANT := $(AMI_VARIANT)-fips
endif

ami_name ?= $(AMI_VARIANT)-node-$(K8S_VERSION_MINOR)-$(AMI_VERSION)

# ami owner overrides for cn/gov-cloud
ifeq ($(aws_region), cn-northwest-1)
	source_ami_owners ?= 141808717104
else ifneq ($(filter $(aws_region),us-gov-west-1 us-gov-east-1),)
	source_ami_owners ?= 219670896067
endif

# default to the latest supported Kubernetes version
k8s=1.28

.PHONY: build
build: ## Build EKS Optimized RHEL AMI
	$(MAKE) k8s $(shell hack/latest-binaries.sh $(k8s) $(aws_region) $(binary_bucket_region) $(binary_bucket_name))

.PHONY: fmt
fmt: ## Format the source files
	hack/shfmt --write

.PHONY: lint
lint: lint-docs ## Check the source files for syntax and format issues
	hack/shfmt --diff
	hack/shellcheck --format gcc --severity error $(shell find $(MAKEFILE_DIR) -type f -name '*.sh' -not -path '*/nodeadm/vendor/*')
	hack/lint-space-errors.sh

.PHONY: test
test: ## run the test-harness
	templates/test/test-harness.sh

PACKER_BINARY ?= packer
PACKER_TEMPLATE_DIR ?= templates/$(os_distro)
PACKER_TEMPLATE_FILE ?= $(PACKER_TEMPLATE_DIR)/template.json
PACKER_DEFAULT_VARIABLE_FILE ?= $(PACKER_TEMPLATE_DIR)/variables-default.json
PACKER_OPTIONAL_K8S_VARIABLE_FILE ?= $(PACKER_TEMPLATE_DIR)/variables-$(K8S_VERSION_MINOR).json
ifeq (,$(wildcard $(PACKER_OPTIONAL_K8S_VARIABLE_FILE)))
	# unset the variable, no k8s-specific variable file exists
	PACKER_OPTIONAL_K8S_VARIABLE_FILE=
endif

# extract Packer variables from the template file,
# then store variables that are defined in the Makefile's execution context
AVAILABLE_PACKER_VARIABLES := $(shell $(PACKER_BINARY) inspect -machine-readable $(PACKER_TEMPLATE_FILE) | grep 'template-variable' | awk -F ',' '{print $$4}')
PACKER_VARIABLES := $(foreach packerVar,$(AVAILABLE_PACKER_VARIABLES),$(if $($(packerVar)),$(packerVar)))
# read & construct Packer arguments in order from the following sources:
# 1. default variable files
# 2. (optional) user-specified variable file
# 3. variables specified in the Make context
PACKER_ARGS := -var-file $(PACKER_DEFAULT_VARIABLE_FILE) \
	$(if $(PACKER_OPTIONAL_K8S_VARIABLE_FILE),-var-file=$(PACKER_OPTIONAL_K8S_VARIABLE_FILE),) \
	$(if $(PACKER_VARIABLE_FILE),-var-file=$(PACKER_VARIABLE_FILE),) \
	$(foreach packerVar,$(PACKER_VARIABLES),-var $(packerVar)='$($(packerVar))')

.PHONY: validate
validate: ## Validate packer config
	@echo "PACKER_TEMPLATE_FILE: $(PACKER_TEMPLATE_FILE)"
	@echo "PACKER_ARGS: $(PACKER_ARGS)"
	# Check containerd and RHEL version compatibility
	@echo "Verifying containerd and RHEL version compatibility..."
	@containerd_version=$$(if echo "$(PACKER_ARGS)" | grep -q 'containerd_version='; then \
		echo "$(PACKER_ARGS)" | grep -o 'containerd_version=[^[:space:]]*' | cut -d'=' -f2; \
	else \
		jq -r '.containerd_version' $(PACKER_DEFAULT_VARIABLE_FILE); \
	fi) && \
	rhel_filter_name=$$(if echo "$(PACKER_ARGS)" | grep -q 'source_ami_filter_name='; then \
		echo "$(PACKER_ARGS)" | grep -o 'source_ami_filter_name=[^[:space:]]*' | cut -d'=' -f2; \
	else \
		jq -r '.source_ami_filter_name' $(PACKER_DEFAULT_VARIABLE_FILE); \
	fi) && \
	rhel_full_version=$$(echo "$$rhel_filter_name" | grep -oE 'RHEL-[0-9]+\.[0-9]+' | sed 's/RHEL-//') && \
	rhel_major_version=$$(echo "$$rhel_full_version" | cut -d '.' -f 1) && \
	if [ "$$containerd_version" = "*" ] && [ $$rhel_major_version -lt 9 ]; then \
		echo "Error: Wildcard value (*) for containerd_version is only allowed with RHEL version 9 or higher (current: $$rhel_full_version) due to GNU C Library (glibc) version requirement"; \
		exit 1; \
	elif [ "$$containerd_version" != "*" ]; then \
		containerd_major_version=$$(echo "$$containerd_version" | cut -d '.' -f 1 | grep -oE '[0-9]+') && \
		if [ $$containerd_major_version -ge 2 ] && [ $$rhel_major_version -lt 9 ]; then \
			echo "Error: When containerd_version is 2 or greater (current: $$containerd_version), RHEL version must be 9 or higher (current: $$rhel_full_version)  due to GNU C Library (glibc) version requirement"; \
			exit 1; \
		fi; \
	fi
	$(PACKER_BINARY) validate $(PACKER_ARGS) $(PACKER_TEMPLATE_FILE)

.PHONY: k8s
k8s: validate ## Build default K8s version of EKS Optimized AMI
	@echo "Building AMI [os_distro=$(os_distro) kubernetes_version=$(kubernetes_version) arch=$(arch)]"
	$(PACKER_BINARY) build -timestamp-ui -color=false $(PACKER_ARGS) $(PACKER_TEMPLATE_FILE)

# DEPRECATION NOTICE: `make` targets for each Kubernetes minor version will not be added after 1.28
# Use the `k8s` variable to specify a minor version instead

.PHONY: 1.23
1.23: ## Build EKS Optimized AMI - K8s 1.23 - DEPRECATED: use the `k8s` variable instead
	$(MAKE) k8s $(shell hack/latest-binaries.sh 1.23)

.PHONY: 1.24
1.24: ## Build EKS Optimized AMI - K8s 1.24 - DEPRECATED: use the `k8s` variable instead
	$(MAKE) k8s $(shell hack/latest-binaries.sh 1.24)

.PHONY: 1.25
1.25: ## Build EKS Optimized AMI - K8s 1.25 - DEPRECATED: use the `k8s` variable instead
	$(MAKE) k8s $(shell hack/latest-binaries.sh 1.25)

.PHONY: 1.26
1.26: ## Build EKS Optimized AMI - K8s 1.26 - DEPRECATED: use the `k8s` variable instead
	$(MAKE) k8s $(shell hack/latest-binaries.sh 1.26)

.PHONY: 1.27
1.27: ## Build EKS Optimized AMI - K8s 1.27 - DEPRECATED: use the `k8s` variable instead
	$(MAKE) k8s $(shell hack/latest-binaries.sh 1.27)

.PHONY: 1.28
1.28: ## Build EKS Optimized AMI - K8s 1.28 - DEPRECATED: use the `k8s` variable instead
	$(MAKE) k8s $(shell hack/latest-binaries.sh 1.28)

.PHONY: lint-docs
lint-docs: ## Lint the docs
	hack/lint-docs.sh

.PHONY: clean
clean:
	rm *-manifest.json
	rm *-version-info.json

.PHONY: help
help: ## Display help
	@awk 'BEGIN {FS = ":.*##"; printf "Usage:\n  make \033[36m<target>\033[0m\n"} /^[\.a-zA-Z_0-9\-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
