#!/usr/bin/env bash

set -e

source ./vars.sh
source ./helpers.sh

trap 'catch $? $LINENO' EXIT

decode_cert() {
    local cert_file_path="$1"
        openssl x509 \
        -in "${cert_file_path}" \
        -text \
        -noout
}

set_pki_engine() {
    local pki_engine_name="$1"
    local max_ttl="$2"

    start_progress "Setting up \"${pki_engine_name}\" PKI engine"
   
    vault secrets \
        enable \
        -path "${pki_engine_name}" \
        "pki"
    
    vault secrets \
        tune \
        -max-lease-ttl="${max_ttl}" \
        "${pki_engine_name}"

    vault write \
        "${pki_engine_name}/config/urls" \
        issuing_certificates="${VAULT_ADDR}v1/${pki_engine_name}/ca" \
        crl_distribution_points="${VAULT_ADDR}v1/${pki_engine_name}/crl"

    end_progress
}

print_pki_engine_config() {
    local pki_engine_name="$1"
    
    vault read "${pki_engine_name}"/config/urls
}

set_role() {
    local role_name="$1" 
    local allowed_domains="$2" 

    start_progress "Setting up \"${role_name}\" role"
    
    vault write \
        "${pki_engine_int}/roles/${role_name}" \
        allow_bare_domains="true" \
        allow_subdomains="true" \
        allowed_domains="${allowed_domains}" \
        key_bits="${key_length}" \
        max_ttl="${cert_ttl_leaf}" \
        require_cn="true"

    end_progress
}

gen_root_cert() {
    local common_name="$1"
    local pki_engine_name="${pki_engine_root}"
    local cert_file_format="pem"
    local cert_file_path=$(create_file "${certs_dir}" "${cert_type_root}" "${cert_file_format}")
        
    start_progress "Generating a root certificate"

    vault write \
        -field "certificate" \
        "${pki_engine_name}/root/generate/internal" \
        common_name="${common_name}" \
        format="pem" \
        key_bits="${key_length}" \
        ttl=${cert_ttl_root} >> "${cert_file_path}"

    decode_cert "${cert_file_path}"

    end_progress
}

gen_int_cert() {
    local common_name="$1"
    local csr_file_path=$(create_file "${csrs_dir}" "${cert_type_int}" "csr")
    local cert_file_format="pem"
    local cert_file_name="${cert_type_int}.${cert_file_format}"
    local cert_file_path=$(create_file "${certs_dir}" "${cert_type_int}" "${cert_file_format}")

    start_progress "Generating an intermediate certificate CSR"

    vault write \
        -field "csr" \
        "${pki_engine_int}/intermediate/generate/internal" \
        common_name="${common_name}" \
        ttl="${cert_ttl_int}" \
        key_bits="${key_length}" >> "${csr_file_path}"
        
    end_progress
    
    start_progress "Signing the intermediate certificate"

    vault write \
        -field "certificate" \
        "${pki_engine_root}/root/sign-intermediate" \
        csr="@${csr_file_path}" \
        format="${cert_file_format}" \
        ttl="${cert_ttl_int}" >> "${cert_file_path}"

    end_progress

    vault write \
        "${pki_engine_int}/intermediate/set-signed" \
        certificate="@${cert_file_path}"

    decode_cert "${cert_file_path}"
}

issue_cert() {
    local role_name="$1" 
    local common_name="$2"
    local cert_file_format="pem"
    local tmp_dir_path="${certs_dir}/leaf/${role_name}/${common_name}"
    local tmp_file_path=$(create_file "${tmp_dir_path}" "tmp" "yml")
    
    start_progress "Issuing a certificate for \"${common_name}\""
   
    vault write \
        -format "json" \
        "${pki_engine_int}/issue/${role_name}" \
        common_name="${common_name}" \
        exclude_cn_from_sans=true \
        format="${cert_file_format}" \
        ttl="${cert_ttl_leaf}" >> "${tmp_file_path}"

    local issuing_epoch=$(date "+%s")
    local expiration_epoch=$(cat "${tmp_file_path}" | jq '.data.expiration')
    local issuing_utc=$(format_epoch "${issuing_epoch}")
    local expiration_utc=$(format_epoch "${expiration_epoch}")
    local cert_dir_path="${tmp_dir_path}/from-${issuing_utc}-to-${expiration_utc}"
    local cert_file_path=$(create_file "${cert_dir_path}" "cert" "${cert_file_format}")
    local priv_key_file_path=$(create_file "${cert_dir_path}" "id-rsa-priv" "${cert_file_format}")
    
    cat "${tmp_file_path}" | jq '.data.private_key' | unjsonify >> "${priv_key_file_path}"
    cat "${tmp_file_path}" | jq '.data.certificate' | unjsonify >> "${cert_file_path}"

    decode_cert "${cert_file_path}"

    rm -f "${tmp_file_path}"

    end_progress
}

run_docker_container() {
    start_progress "Building docker image"

    docker build -t "${image_name}" .

    end_progress

    start_progress "Starting docker container"

    docker rm -f $(docker ps -aq) || true

    docker run \
        --cap-add="IPC_LOCK" \
        --detach \
        --name "dev-vault" \
        --publish "${host_port}:${container_port}" \
        --env "VAULT_DEV_ROOT_TOKEN_ID=${root_token_id}" \
        "${image_name}"

    end_progress

    start_progress "Waiting for Vault to start"
    
    sleep 5

    end_progress
}

authenticate() {
    start_progress "Authentifying"

    vault login - <<<"${root_token_id}"

    end_progress
}

clean_up() {
    rm -rf "${certs_dir}" "${csrs_dir}" 
}

clean_up

run_docker_container

authenticate

set_pki_engine \
    "${pki_engine_root}" \
    "${ttl_year}"

set_pki_engine \
    "${pki_engine_int}" \
    "${ttl_month}"

gen_root_cert \
    "${cn_org} (Root)" 

gen_int_cert \
    "${cn_org} (Intermediate)" 

set_role \
    "${role_team_1}" \
    "${cn_service_1},${cn_service_2}"

set_role \
    "${role_team_2}" \
    "${cn_service_3}"

issue_cert \
    "${role_team_1}" \
    "${cn_service_1}"

issue_cert \
    "${role_team_1}" \
    "${cn_service_2}"

issue_cert \
    "${role_team_2}" \
    "${cn_service_3}"

sleep 5

issue_cert \
    "${role_team_2}" \
    "${cn_service_3}"

start_sandbox "This is meant to fail"

issue_cert \
    "${role_team_2}" \
    "${cn_service_1}"

end_sandbox

./verify.sh

print_pki_engine_config "${pki_engine_root}"
print_pki_engine_config "${pki_engine_int}"

printf "\nexport VAULT_ADDR=%s\n" \
    "${VAULT_ADDR}"

