# =============================================================================
# OmniYield Protocol - Makefile
# 运行 `make` 即可自动安装依赖、编译、测试
# =============================================================================

# 默认目标
.PHONY: all install update build test clean deploy snapshot fmt

# =============================================================================
# 1. 自动安装 Foundry（如果不存在）
# =============================================================================
FOUNDRY_DIR = $(shell dirname $$(command -v forge || echo ""))
FOUNDRYUP = foundryup
FOUNDRY_BIN = $(HOME)/.foundry/bin

# 检查是否已安装 Foundry
check-foundry:
	@if ! command -v forge >/dev/null 2>&1; then \
		echo "Foundry not found. Installing via foundryup..."; \
		curl -L https://foundry.paradigm.xyz | bash; \
		. $(HOME)/.bashrc || . $(HOME)/.zshrc; \
		$(FOUNDRYUP); \
	else \
		echo "Foundry is already installed."; \
	fi

# =============================================================================
# 2. 安装项目依赖（lib）
# =============================================================================
install: check-foundry
	@echo "Installing dependencies with forge install..."
	@forge install OpenZeppelin/openzeppelin-contracts

# 更新依赖
update:
	@echo "Updating dependencies..."
	@forge update

# =============================================================================
# 3. 核心任务
# =============================================================================
all: install build test

build:
	@echo "Building contracts..."
	@forge build

test:
	@echo "Running tests..."
	@forge test

test-verbose:
	@echo "Running tests (verbose)..."
	@forge test -vvv

clean:
	@echo "Cleaning build artifacts..."
	@forge clean

fmt:
	@echo "Formatting code..."
	@forge fmt

snapshot:
	@echo "Generating gas snapshot..."
	@forge snapshot

gas:
	@echo "Generating gas report..."
	@forge test --gas-report

# =============================================================================
# 4. 部署脚本（需配置 .env）
# =============================================================================
deploy:
	@if [ ! -f .env ]; then \
		echo "Error: .env file not found! Create one with PRIVATE_KEY and RPC_URL."; \
		exit 1; \
	fi
	@echo "Deploying OmniYieldPortal..."
	@forge script script/DeployOmniYield.s.sol \
		--rpc-url $$RPC_URL \
		--private-key $$PRIVATE_KEY \
		--broadcast \
		--verify \
		--etherscan-api-key $$ETHERSCAN_API_KEY \
		-vvvv

# =============================================================================
# 5. 辅助目标
# =============================================================================
help:
	@echo "OmniYield Makefile Commands:"
	@echo "  make          → install deps + build + test"
	@echo "  make install  → install Foundry + forge install"
	@echo "  make build    → compile contracts"
	@echo "  make test     → run tests"
	@echo "  make deploy   → deploy to network (requires .env)"
	@echo "  make clean    → remove artifacts"
	@echo "  make fmt      → format code"
	@echo "  make snapshot → gas snapshot"