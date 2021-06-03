info_ruler="********************************"
error_ruler="!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
arrow_up_ruler="^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
arrow_down_ruler="VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV"

catch() {
    local exit_code="$1"
    local error_line="$2"

    if [ "$1" != "0" ]; then
        printf "\n%s\nError %s occured at line %s\n%s\n" \
            "${error_ruler}" \
            "${error_code}" \
            "${error_line}" \
            "${error_ruler}"
    fi
}

start_sandbox() {
    local message="$1"

    printf "\n%s\n[%s]\n" \
        "${arrow_down_ruler}" \
        "${message}"
    
    set +e
}

end_sandbox() {
    set -e
    printf "\n%s\n" \
        "${arrow_up_ruler}"
}

start_progress() {
    local message="$1"

    printf "\n%s\n%s...\n" \
        "${info_ruler}" \
        "${message}"
}

end_progress() {
    printf "\n[Done]\n%s\n" \
        "${info_ruler}"
}

create_file() {
    local dir_path="$1"
    local file_name="$2"
    local file_ext="$3"
    local file_path="${dir_path}/${file_name}.${file_ext}"

    mkdir -p "${dir_path}"
    touch "${file_path}"
    printf "${file_path}"
}

format_epoch() {
    local timestamp_epoch="$1"
    printf $(TZ="UTC" date -d "@${1}" "+%Y_%m_%d-%H_%M_%S-UTC")
}

create_timestamped_file() {
    local dir_path="$1"
    local file_name="$2"
    local file_ext="$3"
    local timestamp_epoch=$(date "+%s")
    local timestamp=$(format_epoch "${timestamp_epoch}")

    printf $(create_file "${dir_path}" "${file_name}-${timestamp}" "${file_ext}")
}

unjsonify() {
    while read -r data; do
        printf "%s\n" "${data}" | sed 's/"//g' | sed 's/\\n/\n/g'
    done
}

