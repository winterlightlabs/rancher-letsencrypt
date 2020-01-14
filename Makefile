# These env vars have to be set in the CI
# GITHUB_TOKEN
# DOCKER_HUB_TOKEN

.PHONY: build deps test release clean push image ci-compile build-dir ci-dist dist-dir ci-release version help

PROJECT := rancher-letsencrypt
PLATFORMS := linux
ARCH := amd64
DOCKER_IMAGE := winterlightlabs/$(PROJECT)

VERSION := $(shell cat VERSION)
SHA := $(shell git rev-parse --short HEAD)

all: help

help:
	@echo "make build - build binary in the current environment"
	@echo "make deps - install build dependencies"
	@echo "make vet - run vet & gofmt checks"
	@echo "make test - run tests"
	@echo "make clean - Duh!"
	@echo "make release - tag with version and trigger CI release build"
	@echo "make image - build Docker image"
	@echo "make dockerhub - build and push dev image to Docker Hub"
	@echo "make version - show app version"

build: build-dir
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags "-X main.Version=$(VERSION) -X main.Git=$(SHA)" -o build/$(PROJECT)-linux-amd64

deps:
	go get github.com/c4milo/github-release

vet:
	scripts/vet

test:
	go test -v ./...

docker:
	docker build -t timw/rancher-letsencrypt -f Dockerfile.local .

release:
	git tag -f `cat VERSION`
	git push -f origin master --tags

clean:
	go clean
	rm -fr ./build
	rm -fr ./dist

dockerhub: image
	@echo "Pushing $(DOCKER_IMAGE):dev-$(SHA)"
	docker push $(DOCKER_IMAGE):dev-$(SHA)

image:
	docker build -t $(DOCKER_IMAGE):dev-$(SHA) -f Dockerfile.dev .

version:
	@echo $(VERSION) $(SHA)

ci-compile: build-dir $(PLATFORMS)

build-dir:
	@rm -rf build && mkdir build

dist-dir:
	@rm -rf dist && mkdir dist

$(PLATFORMS):
	CGO_ENABLED=0 GOOS=$@ GOARCH=$(ARCH) go build -ldflags "-X main.Version=$(VERSION) -X main.Git=$(SHA) -w -s" -a -o build/$(PROJECT)-$@-$(ARCH)/$(PROJECT)

ci-dist: ci-compile dist-dir
	$(eval FILES := $(shell ls build))
	@for f in $(FILES); do \
		(cd $(shell pwd)/build/$$f && tar -cvzf ../../dist/$$f.tar.gz *); \
		(cd $(shell pwd)/dist && shasum -a 256 $$f.tar.gz > $$f.tar.gz.sha256); \
		(cd $(shell pwd)/dist && md5sum $$f.tar.gz > $$f.tar.gz.md5); \
		echo $$f; \
	done
	@cp -r $(shell pwd)/dist/* $(CIRCLE_ARTIFACTS)
	ls $(CIRCLE_ARTIFACTS)

ci-release:
	@previous_tag=$$(git describe --abbrev=0 --tags $(VERSION)^); \
	comparison="$$previous_tag..HEAD"; \
	if [ -z "$$previous_tag" ]; then comparison=""; fi; \
	changelog=$$(git log $$comparison --oneline --no-merges --reverse); \
	github-release $(CIRCLE_PROJECT_USERNAME)/$(CIRCLE_PROJECT_REPONAME) $(VERSION) master "**Changelog**<br/>$$changelog" 'dist/*'
