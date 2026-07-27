.PHONY: test test-static test-entrypoint test-image build push kustomize

IMAGE ?= registry.sion2k.ru/home/cups-hplip:0.1.0

test: test-static test-entrypoint

test-static:
	bash tests/run_tests.sh

test-entrypoint:
	bash tests/test_entrypoint.sh

test-image: build
	IMAGE=registry.sion2k.ru/home/cups-hplip:ci bash tests/test_image_smoke.sh

build:
	docker build -t $(IMAGE) image/

push:
	docker push $(IMAGE)

kustomize:
	kubectl kustomize deploy/base
