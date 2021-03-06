export GO111MODULE=on

# By default, the target OS is the same as the host OS,
# but this can be overridden by setting TARGET_OS to "windows"/"darwin"/"linux".
GOOS:=$(shell go env GOOS)
TARGET_CMD?=Desktop-Bridge
TARGET_OS?=${GOOS}

## Build
.PHONY: build build-ie build-nogui build-ie-nogui check-has-go

# Keep version hardcoded so app build works also without Git repository.
BRIDGE_APP_VERSION?=1.4.5-git
IE_APP_VERSION?=1.2.0-git
APP_VERSION:=${BRIDGE_APP_VERSION}
SRC_ICO:=logo.ico
SRC_ICNS:=Bridge.icns
SRC_SVG:=logo.svg
TGT_ICNS:=Bridge.icns
ifeq "${TARGET_CMD}" "Import-Export"
    APP_VERSION:=${IE_APP_VERSION}
    SRC_ICO:=ie.ico
    SRC_ICNS:=ie.icns
    SRC_SVG:=ie.svg
    TGT_ICNS:=ImportExport.icns
endif
REVISION:=$(shell git rev-parse --short=10 HEAD)
BUILD_TIME:=$(shell date +%FT%T%z)

BUILD_TAGS?=pmapi_prod
BUILD_FLAGS:=-tags='${BUILD_TAGS}'
BUILD_FLAGS_NOGUI:=-tags='${BUILD_TAGS} nogui'
GO_LDFLAGS:=$(addprefix -X github.com/ProtonMail/proton-bridge/pkg/constants.,Version=${APP_VERSION} Revision=${REVISION} BuildTime=${BUILD_TIME})
ifneq "${BUILD_LDFLAGS}" ""
    GO_LDFLAGS+= ${BUILD_LDFLAGS}
endif
GO_LDFLAGS:=-ldflags '${GO_LDFLAGS}'
BUILD_FLAGS+= ${GO_LDFLAGS}
BUILD_FLAGS_NOGUI+= ${GO_LDFLAGS}

DEPLOY_DIR:=cmd/${TARGET_CMD}/deploy
ICO_FILES:=
EXE:=$(shell basename ${CURDIR})

ifeq "${TARGET_OS}" "windows"
    EXE:=${EXE}.exe
    ICO_FILES:=${SRC_ICO} icon.rc icon_windows.syso
endif
ifeq "${TARGET_OS}" "darwin"
    DARWINAPP_CONTENTS:=${DEPLOY_DIR}/darwin/${EXE}.app/Contents
    EXE:=${EXE}.app/Contents/MacOS/${EXE}
endif
EXE_TARGET:=${DEPLOY_DIR}/${TARGET_OS}/${EXE}

TGZ_TARGET:=bridge_${TARGET_OS}_${REVISION}.tgz
ifeq "${TARGET_CMD}" "Import-Export"
    TGZ_TARGET:=ie_${TARGET_OS}_${REVISION}.tgz
endif


build: ${TGZ_TARGET}
build-ie:
	TARGET_CMD=Import-Export $(MAKE) build

build-nogui:
	go build ${BUILD_FLAGS_NOGUI} -o ${TARGET_CMD} cmd/${TARGET_CMD}/main.go

build-ie-nogui:
	TARGET_CMD=Import-Export $(MAKE) build-nogui

${TGZ_TARGET}: ${DEPLOY_DIR}/${TARGET_OS}
	rm -f $@
	cd ${DEPLOY_DIR} && tar czf ../../../$@ ${TARGET_OS}

${DEPLOY_DIR}/linux: ${EXE_TARGET}
	cp -pf ./internal/frontend/share/icons/${SRC_SVG} ${DEPLOY_DIR}/linux/logo.svg
	cp -pf ./LICENSE ${DEPLOY_DIR}/linux/
	cp -pf ./Changelog.md ${DEPLOY_DIR}/linux/

${DEPLOY_DIR}/darwin: ${EXE_TARGET}
	cp ./internal/frontend/share/icons/${SRC_ICNS} ${DARWINAPP_CONTENTS}/Resources/${TGT_ICNS}
	cp LICENSE ${DARWINAPP_CONTENTS}/Resources/
	rm -rf "${DARWINAPP_CONTENTS}/Frameworks/QtWebEngine.framework"
	rm -rf "${DARWINAPP_CONTENTS}/Frameworks/QtWebView.framework"
	rm -rf "${DARWINAPP_CONTENTS}/Frameworks/QtWebEngineCore.framework"
	./utils/remove_non_relative_links_darwin.sh "${EXE_TARGET}"

${DEPLOY_DIR}/windows: ${EXE_TARGET}
	cp ./internal/frontend/share/icons/${SRC_ICO} ${DEPLOY_DIR}/windows/logo.ico
	cp LICENSE ${DEPLOY_DIR}/windows/

QT_BUILD_TARGET:=build desktop
ifneq "${GOOS}" "${TARGET_OS}"
  ifeq "${TARGET_OS}" "windows"
    QT_BUILD_TARGET:=-docker build windows_64_shared
  endif
endif

${EXE_TARGET}: check-has-go gofiles ${ICO_FILES} update-vendor
	rm -rf deploy ${TARGET_OS} ${DEPLOY_DIR}
	cp cmd/${TARGET_CMD}/main.go .
	qtdeploy ${BUILD_FLAGS} ${QT_BUILD_TARGET}
	mv deploy cmd/${TARGET_CMD}
	rm -rf ${TARGET_OS} main.go

logo.ico ie.ico: ./internal/frontend/share/icons/${SRC_ICO}
	cp $^ $@
icon.rc: ./internal/frontend/share/icon.rc
	cp $^ .
icon_windows.syso: icon.rc logo.ico
	windres --target=pe-x86-64 -o $@ $<


## Rules for therecipe/qt
.PHONY: prepare-vendor update-vendor
THERECIPE_ENV:=github.com/therecipe/env_${TARGET_OS}_amd64_513

# vendor folder will be deleted by gomod hence we cache the big repo
# therecipe/env in order to download it only once
vendor-cache/${THERECIPE_ENV}:
	git clone https://${THERECIPE_ENV}.git vendor-cache/${THERECIPE_ENV}

# The command used to make symlinks is different on windows.
# So if the GOOS is windows and we aren't crossbuilding (in which case the host os would still be *nix)
# we need to change the LINKCMD to something windowsy.
LINKCMD:=ln -sf ${CURDIR}/vendor-cache/${THERECIPE_ENV} vendor/${THERECIPE_ENV}
ifeq "${GOOS}" "windows"
  WINDIR:=$(subst /c/,c:\\,${CURDIR})/vendor-cache/${THERECIPE_ENV}
  LINKCMD:=cmd //c 'mklink $(subst /,\,vendor\${THERECIPE_ENV} ${WINDIR})'
endif

prepare-vendor:
	go install -v -tags=no_env github.com/therecipe/qt/cmd/...
	go mod vendor

# update-vendor is PHONY because we need to make sure that we always have updated vendor
update-vendor: vendor-cache/${THERECIPE_ENV} prepare-vendor
	${LINKCMD}


## Dev dependencies
.PHONY: install-devel-tools install-linter install-go-mod-outdated
LINTVER:="v1.29.0"
LINTSRC:="https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh"

install-dev-dependencies: install-devel-tools install-linter install-go-mod-outdated

install-devel-tools: check-has-go
	go get -v github.com/golang/mock/gomock
	go get -v github.com/golang/mock/mockgen
	go get -v github.com/go-delve/delve

install-linter: check-has-go
	curl -sfL $(LINTSRC) | sh -s -- -b $(shell go env GOPATH)/bin $(LINTVER)

install-go-mod-outdated:
	which go-mod-outdated || go get -u github.com/psampaz/go-mod-outdated


## Checks, mocks and docs
.PHONY: check-has-go add-license change-copyright-year test bench coverage mocks lint-license lint-golang lint updates doc
check-has-go:
	@which go || (echo "Install Go-lang!" && exit 1)

add-license:
	./utils/missing_license.sh add

change-copyright-year:
	./utils/missing_license.sh change-year

test: gofiles
	@# Listing packages manually to not run Qt folder (which needs to run qtsetup first) and integration tests.
	go test -coverprofile=/tmp/coverage.out -run=${TESTRUN} \
		./internal/api/... \
		./internal/bridge/... \
		./internal/events/... \
		./internal/frontend/autoconfig/... \
		./internal/frontend/cli/... \
		./internal/imap/... \
		./internal/metrics/... \
		./internal/importexport/... \
		./internal/preferences/... \
		./internal/smtp/... \
		./internal/store/... \
		./internal/transfer/... \
		./internal/updates/... \
		./internal/users/... \
		./pkg/...

bench:
	go test -run '^$$' -bench=. -memprofile bench_mem.pprof -cpuprofile bench_cpu.pprof ./internal/store
	go tool pprof -png -output bench_mem.png bench_mem.pprof
	go tool pprof -png -output bench_cpu.png bench_cpu.pprof

coverage: test
	go tool cover -html=/tmp/coverage.out -o=coverage.html

mocks:
	mockgen --package mocks github.com/ProtonMail/proton-bridge/internal/users Configer,PanicHandler,ClientManager,CredentialsStorer,StoreMaker > internal/users/mocks/mocks.go
	mockgen --package mocks github.com/ProtonMail/proton-bridge/internal/transfer PanicHandler,ClientManager > internal/transfer/mocks/mocks.go
	mockgen --package mocks github.com/ProtonMail/proton-bridge/internal/store PanicHandler,ClientManager,BridgeUser > internal/store/mocks/mocks.go
	mockgen --package mocks github.com/ProtonMail/proton-bridge/pkg/listener Listener > internal/store/mocks/utils_mocks.go
	mockgen --package mocks github.com/ProtonMail/proton-bridge/pkg/pmapi Client > pkg/pmapi/mocks/mocks.go

lint: lint-golang lint-license

lint-license:
	./utils/missing_license.sh check

lint-golang:
	which golangci-lint || $(MAKE) install-linter
	golangci-lint run ./...

updates: install-go-mod-outdated
	# Uncomment the "-ci" to fail the job if something can be updated.
	go list -u -m -json all | go-mod-outdated -update -direct #-ci

doc:
	godoc -http=:6060

.PHONY: gofiles
# Following files are for the whole app so it makes sense to have them in bridge package.
# (Options like cmd or internal were considered and bridge package is the best place for them.)
gofiles: ./internal/bridge/credits.go ./internal/bridge/release_notes.go ./internal/importexport/credits.go ./internal/importexport/release_notes.go
./internal/bridge/credits.go: ./utils/credits.sh go.mod
	cd ./utils/ && ./credits.sh bridge
./internal/bridge/release_notes.go: ./utils/release-notes.sh ./release-notes/notes-bridge.txt ./release-notes/bugs-bridge.txt
	cd ./utils/ && ./release-notes.sh bridge
./internal/importexport/credits.go: ./utils/credits.sh go.mod
	cd ./utils/ && ./credits.sh importexport
./internal/importexport/release_notes.go: ./utils/release-notes.sh ./release-notes/notes-importexport.txt ./release-notes/bugs-importexport.txt
	cd ./utils/ && ./release-notes.sh importexport


## Run and debug
.PHONY: run run-qt run-qt-cli run-nogui run-nogui-cli run-debug run-qml-preview run-ie-qml-preview run-ie run-ie-qt run-ie-qt-cli run-ie-nogui run-ie-nogui-cli clean-vendor clean-frontend-qt clean-frontend-qt-ie clean-frontend-qt-common clean

VERBOSITY?=debug-client
RUN_FLAGS:=-m -l=${VERBOSITY}

run: run-nogui-cli

run-qt: ${EXE_TARGET}
	PROTONMAIL_ENV=dev ./$< ${RUN_FLAGS} | tee last.log
run-qt-cli: ${EXE_TARGET}
	PROTONMAIL_ENV=dev ./$< ${RUN_FLAGS} -c

run-nogui: clean-vendor gofiles
	PROTONMAIL_ENV=dev go run ${BUILD_FLAGS_NOGUI} cmd/${TARGET_CMD}/main.go ${RUN_FLAGS} | tee last.log
run-nogui-cli: clean-vendor gofiles
	PROTONMAIL_ENV=dev go run ${BUILD_FLAGS_NOGUI} cmd/${TARGET_CMD}/main.go ${RUN_FLAGS} -c

run-debug:
	PROTONMAIL_ENV=dev dlv debug --build-flags "${BUILD_FLAGS_NOGUI}" cmd/${TARGET_CMD}/main.go -- ${RUN_FLAGS}

run-qml-preview:
	$(MAKE) -C internal/frontend/qt -f Makefile.local qmlpreview
run-ie-qml-preview:
	$(MAKE) -C internal/frontend/qt-ie -f Makefile.local qmlpreview

run-ie:
	TARGET_CMD=Import-Export $(MAKE) run
run-ie-qt:
	TARGET_CMD=Import-Export $(MAKE) run-qt
run-ie-nogui:
	TARGET_CMD=Import-Export $(MAKE) run-nogui


clean-frontend-qt:
	$(MAKE) -C internal/frontend/qt -f Makefile.local clean
clean-frontend-qt-ie:
	$(MAKE) -C internal/frontend/qt-ie -f Makefile.local clean
clean-frontend-qt-common:
	$(MAKE) -C internal/frontend/qt-common -f Makefile.local clean

clean-vendor: clean-frontend-qt clean-frontend-qt-ie clean-frontend-qt-common
	rm -rf ./vendor

clean: clean-vendor
	rm -rf vendor-cache
	rm -rf cmd/Desktop-Bridge/deploy
	rm -rf cmd/Import-Export/deploy
	rm -f build last.log mem.pprof main.go
	rm -rf logo.ico icon.rc icon_windows.syso internal/frontend/qt/icon_windows.syso
