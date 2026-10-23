.PHONY: build test app demo probe install icon clean

build:
	swift build

test:
	swift test

# build/Sixty.app, ad-hoc signed
app:
	scripts/build-app.sh

# Short cycle: 20 s work, 5 s warning, 10 s break. Runs in the terminal, no login agent.
demo: app
	SIXTY_DEMO=1 build/Sixty.app/Contents/MacOS/Sixty

# What Sixty sees right now: apps on the microphone / speaker, camera, call or not
probe: app
	build/Sixty.app/Contents/MacOS/Sixty --probe

# Copies to /Applications and registers the login agent for this build. An ad-hoc signature changes with every
# build and launchd then refuses the agent, so sign with a real identity: SIGN_IDENTITY="Developer ID Application: …" make install
install: app
	rm -rf /Applications/Sixty.app
	cp -R build/Sixty.app /Applications/
	open -n /Applications/Sixty.app --args --reregister

icon:
	swift scripts/make-icon.swift

clean:
	rm -rf .build build
