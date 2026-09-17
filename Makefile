# NerdStats developer commands. See CONTRIBUTING.md for details.

APP := build/NerdStats.app

.PHONY: build debug run dump test dmg clean

## build: universal release .app bundle at build/NerdStats.app
build:
	scripts/build-app.sh release

## debug: universal debug .app bundle (faster to build)
debug:
	scripts/build-app.sh debug

## run: build, then (re)launch the menu bar app
run: build
	-pkill -x NerdStats
	open $(APP)

## dump: print one snapshot of every reading to the terminal
dump:
	swift run NerdStats --dump

## test: run unit tests (no special hardware needed)
test:
	swift test

## dmg: drag-to-install build/NerdStats-<version>.dmg (VERSION=x.y.z to override)
dmg:
	scripts/build-dmg.sh

clean:
	rm -rf .build build
