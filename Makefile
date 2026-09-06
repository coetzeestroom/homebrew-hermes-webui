TAP = coetzeestroom/hermes-webui
FORMULA = hermes-webui

.PHONY: audit style syntax test install lint

audit:
	brew audit --except=installed --tap=$(TAP)

style:
	brew style $(TAP)/$(FORMULA)

syntax:
	brew test-bot --only-tap-syntax

test:
	brew tests --only $(FORMULA)

install:
	brew install $(TAP)/$(FORMULA)

lint: audit style syntax