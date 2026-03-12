SHELL := /usr/bin/env bash

CONFIG ?= .env

.PHONY: bootstrap prepare-dicom harden smoke lock-runtime help

help:
	@echo "Targets:"
	@echo "  make bootstrap [CONFIG=.env]"
	@echo "  make prepare-dicom [CONFIG=.env]"
	@echo "  make harden    [CONFIG=.env]"
	@echo "  make smoke     [CONFIG=.env]"
	@echo "  make lock-runtime [CONFIG=.env]"

bootstrap:
	./scripts/bootstrap_new_clinic_deployment.sh --config "$(CONFIG)"

prepare-dicom:
	./phase2-cloud-push/init_gcp_dicom_store.sh --config "$(CONFIG)"

harden:
	./phase3-cloud-deployment/harden_cloud_sql_network.sh --config "$(CONFIG)"

smoke:
	./phase3-cloud-deployment/smoke_test_deployment.sh --config "$(CONFIG)"

lock-runtime:
	./phase3-cloud-deployment/lock_openemr_runtime.sh --config "$(CONFIG)"
