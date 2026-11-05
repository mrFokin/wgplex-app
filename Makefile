.PHONY: check build test dmg clean

check: build test

build:
	swift build

test:
	swift test

dmg:
	scripts/dmg.sh

clean:
	rm -rf .build dist
