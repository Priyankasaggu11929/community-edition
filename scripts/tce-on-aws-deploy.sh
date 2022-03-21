#!/bin/bash

set -o nounset
set -o pipefail

JANITOR_ENABLED=1

ARTIFACTS="${ARTIFACTS:-${PWD}/_artifacts}"
mkdir -p "$ARTIFACTS/logs/"

# our exit handler (trap)
cleanup() {
  # stop boskos heartbeat
  [[ -z ${HEART_BEAT_PID:-} ]] || kill -9 "${HEART_BEAT_PID}"
}
trap cleanup EXIT

sudo apt-get update && sudo apt-get install -y python3-pip

#Install requests module explicitly for HTTP calls
python3 -m pip install requests

# If BOSKOS_HOST is set then acquire an AWS account from Boskos.
if [ -n "${BOSKOS_HOST:-}" ]; then
  # Check out the account from Boskos and store the produced environment
  # variables in a temporary file.
  account_env_var_file="$(mktemp)"
  python3 hack/boskos.py --get 1>"${account_env_var_file}"
  checkout_account_status="${?}"

  # If the checkout process was a success then load the account's
  # environment variables into this process.
  # shellcheck disable=SC1090
  [ "${checkout_account_status}" = "0" ] && . "${account_env_var_file}"

  # Always remove the account environment variable file. It contains
  # sensitive information.
  rm -f "${account_env_var_file}"

  if [ ! "${checkout_account_status}" = "0" ]; then
    echo "error getting account from boskos" 1>&2
    exit "${checkout_account_status}"
  fi

  # run the heart beat process to tell boskos that we are still
  # using the checked out account periodically
  python3 -u hack/boskos.py --heartbeat >>$ARTIFACTS/logs/boskos.log 2>&1 &
  HEART_BEAT_PID=$(echo $!)
fi


# Deploy the TCE Managed Cluster on AWS
# chmod +x test/fetch-tce.sh && ./test/fetch-tce.sh $(curl https://api.github.com/repos/vmware-tanzu/community-edition/releases -s | jq  -r '.[0].tag_name')
make aws-management-and-workload-cluster-e2e-test

test_status="${?}"

# If Boskos is being used then release the AWS account back to Boskos.
[ -z "${BOSKOS_HOST:-}" ] || python3 -u hack/boskos.py --release

# The janitor is typically not run as part of the e2e process, but rather
# in a parallel process via a service on the same cluster that runs Prow and
# Boskos.
#
# However, setting JANITOR_ENABLED=1 tells this program to run the janitor
# after the e2e test is executed.
if [ "${JANITOR_ENABLED:-0}" = "1" ]; then
  if ! command -v aws-janitor >/dev/null 2>&1; then
    echo "skipping janitor; aws-janitor not found" 1>&2
  else
    aws-janitor -all -v 2
  fi
else
  echo "skipping janitor; JANITOR_ENABLED=${JANITOR_ENABLED:-0}" 1>&2
fi

exit "${test_status}"
