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

# ── Release lane ──────────────────────────────────────────────────────────────
# The cut is split by concern, one script each, chained here in order:
#   preflight → publish → tag → distribute
# The pure ends (preflight, tag, distribute) re-derive their inputs from git +
# project.yml, so each runs standalone. The dirty middle (publish: version-bump
# prompts + auto-merging PR + CI-wait) is the one stateful script; state crosses
# to the later steps via the merged commit on main, not through Make.
#
# PLATFORM selects scope (default all); UPLOAD=0 stops after export (no ASC
# upload). The steps are a linear dependency chain so they stay ordered even
# under `make -j`. Run from a clean, up-to-date main.
PLATFORM ?= all
UPLOAD ?= 1
DIST_FLAGS := $(if $(filter 0,$(UPLOAD)),--no-upload,)

# The steps form a linear dependency chain — each requires the previous — so
# `make release` (an alias for the last step) runs them in order, and the order
# holds even under `make -j`. Running an intermediate target pulls in its
# predecessors; to repeat just one step (e.g. re-tag after a stalled merge),
# call its script directly (Scripts/release-tag.sh all) — the scripts re-derive
# their inputs from git + project.yml, so each stands alone.
.PHONY: release
release: release-distribute  ## Cut a release (PLATFORM=all|ios|macos, UPLOAD=0 to skip ASC)
	@echo "✓ release complete (PLATFORM=$(PLATFORM))."

.PHONY: release-build
release-build:  ## Like `release` but stop after export (no upload)
	@$(MAKE) release UPLOAD=0

.PHONY: release-preflight
release-preflight:  ## Release step 1: verify clean, up-to-date main
	@Scripts/release-preflight.sh

.PHONY: release-publish
release-publish: release-preflight  ## Release step 2: bump, open auto-merging PR, wait for CI
	@Scripts/release-publish.sh $(PLATFORM)

.PHONY: release-tag
release-tag: release-publish  ## Release step 3: tag the merge commit + publish GitHub releases
	@Scripts/release-tag.sh $(PLATFORM)

.PHONY: release-distribute
release-distribute: release-tag  ## Release step 4: archive/export (+ upload unless UPLOAD=0)
	@Scripts/release-distribute.sh $(PLATFORM) $(DIST_FLAGS)

# Distribute is the likeliest step to fail (archive/export/ASC upload) and is
# safe to repeat. This standalone retry has NO prereqs — it re-distributes an
# already-tagged release without touching git/PR/tags, after verifying the tag
# for the current version+build exists.
.PHONY: release-distribute-retry
release-distribute-retry:  ## Re-distribute an already-tagged release (no PR/tag steps)
	@Scripts/release-distribute.sh $(PLATFORM) $(DIST_FLAGS) --require-tag

.PHONY: clean
clean:  ## Remove the generated project + local build output
	@rm -rf Donpa.xcodeproj .build-xcode
	@echo "removed Donpa.xcodeproj and .build-xcode"
