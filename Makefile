APP_DIR := apps/kiwi_inventory
FLUTTER ?= flutter
DART ?= dart
NPM ?= npm
DEVICE ?= chrome
PDF_PYTHON ?= python3

.PHONY: setup doctor app-run format format-check analyze test golden-test golden-update build-web codegen check stage1-acceptance stage3-acceptance db-start db-stop db-status db-reset db-test pdf-label-prototype pdf-label-verify

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
	cd $(APP_DIR) && $(FLUTTER) test --exclude-tags golden

golden-test:
	cd $(APP_DIR) && $(FLUTTER) test test/home_golden_test.dart

golden-update:
	cd $(APP_DIR) && $(FLUTTER) test --update-goldens test/home_golden_test.dart

build-web:
	cd $(APP_DIR) && $(FLUTTER) build web --release

codegen:
	@cd $(APP_DIR) && if grep -Eq '^[[:space:]]+build_runner:' pubspec.yaml; then $(DART) run build_runner build --delete-conflicting-outputs; else echo "No code generators are configured."; fi

check: doctor format-check analyze test

stage1-acceptance:
	FLUTTER_CMD="$(FLUTTER)" DART_CMD="$(DART)" NPM_CMD="$(NPM)" PDF_PYTHON="$(PDF_PYTHON)" bash scripts/run_stage1_acceptance.sh

stage3-acceptance:
	FLUTTER_CMD="$(FLUTTER)" DART_CMD="$(DART)" NPM_CMD="$(NPM)" bash scripts/run_stage3_acceptance.sh

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
