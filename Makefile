APP_DIR := apps/kiwi_inventory
FLUTTER ?= flutter
DART ?= dart
NPM ?= npm
DEVICE ?= chrome
PDF_PYTHON ?= python3

.PHONY: setup doctor app-run format format-check analyze test build-web codegen check db-start db-stop db-status db-reset db-test pdf-label-prototype pdf-label-verify

setup:
	$(NPM) ci
	cd $(APP_DIR) && $(FLUTTER) pub get

doctor:
	FLUTTER_CMD="$(FLUTTER)" DART_CMD="$(DART)" NPM_CMD="$(NPM)" bash scripts/check_tool_versions.sh

app-run:
	cd $(APP_DIR) && $(FLUTTER) run -d $(DEVICE)

format:
	cd $(APP_DIR) && $(DART) format lib test

format-check:
	cd $(APP_DIR) && $(DART) format --output=none --set-exit-if-changed lib test

analyze:
	cd $(APP_DIR) && $(FLUTTER) analyze

test:
	cd $(APP_DIR) && $(FLUTTER) test

build-web:
	cd $(APP_DIR) && $(FLUTTER) build web --release

codegen:
	@cd $(APP_DIR) && if grep -Eq '^[[:space:]]+build_runner:' pubspec.yaml; then $(DART) run build_runner build --delete-conflicting-outputs; else echo "No code generators are configured."; fi

check: doctor format-check analyze test

db-start:
	$(NPM) run db:start

db-stop:
	$(NPM) run db:stop

db-status:
	$(NPM) run db:status

db-reset:
	$(NPM) run db:reset

db-test:
	$(NPM) run db:test

pdf-label-prototype:
	$(PDF_PYTHON) experiments/fnd-07/generate_a5_label.py

pdf-label-verify:
	$(PDF_PYTHON) experiments/fnd-07/verify_a5_label.py
