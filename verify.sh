#!/usr/bin/env bash

set -e

source ./vars.sh
source ./helpers.sh

trap 'catch $? $LINENO' EXIT

verify_chain() {
    while read -r leaf_cert_file_path; do
        start_progress "verifying ${leaf_cert_file_path}"
        openssl verify \
            -CAfile "cert/${cert_type_root}.pem" \
            -untrusted "cert/${cert_type_int}.pem" \
            "${leaf_cert_file_path}"
        end_progress
    done

}

find "${certs_dir}/leaf" -name "cert.pem" -size +0c | verify_chain
