#!/bin/bash

set -eux


# Acquire AWS account from Boskos
python3 hack/boskos.py --get


# Deploy the TCE Managed Cluster on AWS
make aws-management-and-workload-cluster-e2e-test
