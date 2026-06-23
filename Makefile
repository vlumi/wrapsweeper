# Donpa — command-line build/run/test, so you never have to open Xcode.
#
# The Scripts/*.sh do the actual work (one job each); this Makefile wires up the
# dependencies (e.g. the Xcode project is regenerated only when project.yml or
# an Info.plist changes) and gives short targets. Run `make` (or `make help`)
# to list them.

.DEFAULT_GOAL := help

.PHONY: help
help:  ## List the available commands
	@echo "Donpa — available make targets:"
	@echo
	@grep -hE '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) \
		| sort \
		| awk 'BEGIN {FS = ":.*## "} {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

# Inputs xcodegen reads — regenerate the project when any of these change.
PROJECT_INPUTS := project.yml \
	$(wildcard Sources/*/Info.plist) \
	$(wildcard Sources/*/*.xcstrings)

# File target: the generated project depends on its inputs, so `make` skips the
# regen when nothing changed (and reruns it when project.yml etc. are edited).
Donpa.xcodeproj: $(PROJECT_INPUTS)
	@Scripts/generate.sh

.PHONY: generate
generate: Donpa.xcodeproj  ## Regenerate Donpa.xcodeproj from project.yml (if stale)

.PHONY: run-mac
run-mac: Donpa.xcodeproj  ## Build + launch the macOS app
	@Scripts/run.sh

.PHONY: run-ios
run-ios: Donpa.xcodeproj  ## Build + launch in an iOS simulator
	@Scripts/run-ios.sh

.PHONY: build-mac
build-mac: Donpa.xcodeproj  ## Build the macOS app
	@Scripts/build.sh macos

.PHONY: build-ios
build-ios: Donpa.xcodeproj  ## Build the iOS app (simulator)
	@Scripts/build.sh ios

# Logic tests run straight from the Swift package — no Xcode project involved.
.PHONY: test
test:  ## Run the package logic tests (no Xcode project needed)
	@Scripts/test.sh

# UI tests are local-only (CI never runs `xcodebuild test`); they drive the
# built iOS app in a simulator.
.PHONY: uitest
uitest: Donpa.xcodeproj  ## Run the local-only iOS UI tests (simulator)
	@Scripts/uitest.sh

.PHONY: clean
clean:  ## Remove the generated project + local build output
	@rm -rf Donpa.xcodeproj .build-xcode
	@echo "removed Donpa.xcodeproj and .build-xcode"
