.PHONY: check build test clean

check: build test

build:
	swift build

test:
	swift test

clean:
	rm -rf .build
