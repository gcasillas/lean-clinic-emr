SHELL := /usr/bin/env bash

CONFIG ?= .env
PROFILE ?= holistic-herbal

.PHONY: bootstrap harden smoke help

help:
	@echo "Targets:"
	@echo "  make bootstrap [PROFILE=holistic-herbal] [CONFIG=.env]"
	@echo "  make harden    [PROFILE=holistic-herbal] [CONFIG=.env]"
	@echo "  make smoke     [PROFILE=holistic-herbal] [CONFIG=.env]"

bootstrap:
	./scripts/bootstrap_new_clinic_deployment.sh --config "$(CONFIG)" --profile "$(PROFILE)"

harden:
	./phase3-cloud-deployment/harden_cloud_sql_network.sh --config "$(CONFIG)" --profile "$(PROFILE)"

smoke:
	./phase3-cloud-deployment/smoke_test_deployment.sh --config "$(CONFIG)" --profile "$(PROFILE)"
