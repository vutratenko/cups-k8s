.PHONY: test test-static test-entrypoint test-image test-scanner-image build push build-scanner push-scanner kustomize

IMAGE ?= registry.sion2k.ru/home/cups-hplip:0.1.0
SCANNER_IMAGE ?= registry.sion2k.ru/home/scanservjs-hplip:0.1.15

test: test-static test-entrypoint

test-static:
	bash tests/run_tests.sh

test-entrypoint:
	bash tests/test_entrypoint.sh

test-image: build
	IMAGE=registry.sion2k.ru/home/cups-hplip:ci bash tests/test_image_smoke.sh

test-scanner-image: build-scanner
	SCANNER_IMAGE=registry.sion2k.ru/home/scanservjs-hplip:ci bash tests/test_scanner_image_smoke.sh

build:
	docker build -t $(IMAGE) image/

push:
	docker push $(IMAGE)

build-scanner:
	docker build -t $(SCANNER_IMAGE) image-scanner/

push-scanner:
	docker push $(SCANNER_IMAGE)

kustomize:
	kubectl kustomize deploy/base
