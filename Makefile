# Tabs — build, test, and release tasks.
#
# Local testing needs nothing but Xcode. Archiving and uploading to TestFlight
# need a paid Apple Developer account and signing configured in Xcode. See
# RELEASING.md for the full runbook.

SCHEME    := Tabs
BUNDLE_ID := com.sahilramani.tabs
DERIVED   := build/DerivedData
APP_SIM   := $(DERIVED)/Build/Products/Debug-iphonesimulator/$(SCHEME).app

# A monotonic build number for TestFlight uploads (each upload must be unique).
BUILD ?= $(shell date +%Y%m%d%H%M)

# Apple Developer Team ID, used only for signed builds. Deliberately not stored
# in the project file — export ASC_TEAM_ID (see RELEASING.md) or pass TEAM=...
TEAM ?= $(ASC_TEAM_ID)

# Resolve a simulator at call time so the destination isn't pinned to one UDID.
SIM = $(shell ./scripts/sim-udid.sh)

.PHONY: test run device archive export upload beta clean help require-team

help: ## List targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*## /\t/' | sort

test: ## Run the unit test suite on a simulator
	xcodebuild test -scheme $(SCHEME) -destination "id=$(SIM)"

run: ## Build, install, and launch on a simulator (SEED=1 for demo data; SCREEN=import|review|detail to open a screen)
	xcodebuild build -scheme $(SCHEME) -destination "id=$(SIM)" -derivedDataPath $(DERIVED)
	-xcrun simctl boot $(SIM) 2>/dev/null
	open -a Simulator
	xcrun simctl install $(SIM) "$(APP_SIM)"
	xcrun simctl launch $(SIM) $(BUNDLE_ID) $(if $(SEED),--seed-demo,) $(if $(SCREEN),--seed-$(SCREEN),)

require-team:
	@test -n "$(TEAM)" || { \
		echo "error: no Team ID. export ASC_TEAM_ID=<your 10-char Team ID>"; \
		echo "       find it at https://developer.apple.com/account (Membership)"; \
		exit 1; }

device: require-team ## Build for a connected device (then Run from Xcode, or use devicectl)
	xcodebuild build -scheme $(SCHEME) -destination 'generic/platform=iOS' \
		-derivedDataPath $(DERIVED) -allowProvisioningUpdates \
		DEVELOPMENT_TEAM=$(TEAM)
	@echo "Built. Install with:"
	@echo "  xcrun devicectl device install app --device <UDID> \\"
	@echo "    '$(DERIVED)/Build/Products/Debug-iphoneos/$(SCHEME).app'"
	@echo "List devices: xcrun devicectl list devices"

archive: require-team ## Archive a signed Release build (stamps build number $(BUILD))
	xcodebuild archive -scheme $(SCHEME) -destination 'generic/platform=iOS' \
		-archivePath build/$(SCHEME).xcarchive -allowProvisioningUpdates \
		CURRENT_PROJECT_VERSION=$(BUILD) DEVELOPMENT_TEAM=$(TEAM)

export: require-team ## Export the archive to an App Store .ipa
	xcodebuild -exportArchive -archivePath build/$(SCHEME).xcarchive \
		-exportOptionsPlist ExportOptions.plist -exportPath build/export \
		-allowProvisioningUpdates DEVELOPMENT_TEAM=$(TEAM)

upload: ## Upload the .ipa to App Store Connect (needs ASC_KEY_ID, ASC_ISSUER_ID)
	xcrun altool --upload-app -f build/export/$(SCHEME).ipa -t ios \
		--apiKey "$(ASC_KEY_ID)" --apiIssuer "$(ASC_ISSUER_ID)"

beta: archive export upload ## Archive → export → upload to TestFlight in one step
	@echo "Uploaded build $(BUILD) to App Store Connect. It appears in TestFlight after processing."

clean: ## Remove build artifacts
	rm -rf build
