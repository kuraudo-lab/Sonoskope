.PHONY: build test app run check
build:
	swift build
test:
	swift test
app:
	bash scripts/build-app.sh
run: app
	open dist/Sonoskope.app
check: test
	git diff --check
