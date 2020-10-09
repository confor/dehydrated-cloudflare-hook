#!/usr/bin/env bash
# shellcheck disable=SC2155,SC2154

# references:
# https://api.cloudflare.com/#dns-records-for-a-zone-create-dns-record
# https://github.com/sineverba/cfhookbash
# https://github.com/dehydrated-io/dehydrated/blob/master/docs/examples/hook.sh

hook_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
config_file="${hook_dir}/config.sh"


deploy_challenge() {
    local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"
    local json_response="${hook_dir}/api_response_${TOKEN_FILENAME}.json"
    local record_name="_acme-challenge.${DOMAIN}"
    . "${config_file}"

    echo "Creating TXT record '${record_name}'"

    # need to store the record id to delete it later
    curl -X POST "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records" \
         -H "X-Auth-Email: ${email}" \
         -H "X-Auth-Key: ${global_api_key}" \
         -H "Content-Type: application/json" \
         --data '{"type":"TXT","name":"'"${record_name}"'","content":"'"${TOKEN_VALUE}"'","ttl":120,"priority":10,"proxied":false}' \
         --output "${json_response}" \
         --silent

    local output="$(jq -r '.success' < "$json_response")"

    if [[ "$output" == "true" ]]; then
        echo "Success creating TXT record"

    elif [[ "$output" == "false" ]]; then
        # just skip if the record already exists
        if grep -qF '"The record already exists."' "$json_response"; then
            echo "Warning: TXT record already exists. Ignoring."
        else
            echo "Error: couldn't create the TXT record:"
            jq '.errors' < "$json_response"
        fi
    else
        echo "Unknown error"
        exit 1
    fi
}

clean_challenge() {
    local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"
    local json_response="${hook_dir}/api_response_${TOKEN_FILENAME}.json"
    local record_name="_acme-challenge.${DOMAIN}"
    . "${config_file}"

    if grep -qF 'The record already exists.' "$json_response"; then
        echo "Warning: TXT record '${record_name}' not created by this script. Leaving as-is."
        return
    fi

    local record_id="$( jq -r '.result.id' < "$json_response" )"

    if [[ "$record_id" =~ "null" ]]; then
        echo "Warning: API response appears to be wrong, won't clean up TXT record '${record_name}'"
        return
    fi

    curl -X DELETE "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/${record_id}" \
         -H "X-Auth-Email: ${email}" \
         -H "X-Auth-Key: ${global_api_key}" \
         -H "Content-Type: application/json" \
         --output "$json_response" \
         --silent

    if [ $? -ne 0 ]; then
        echo "Unknown error (curl's fault?)"
        exit 1
    fi

    local output="$(jq -r '.success' < "$json_response")"

    if [[ "$output" == "true" ]]; then
        echo "Success cleaning up TXT record '${record_name}'"
    elif [[ "$output" == "false" ]]; then
        echo "Warning: couldn't delete TXT record '${record_name}'"
        jq '.errors' < "$json_response"
    else
        echo "Unknown error"
        exit 1
    fi

    if [[ -f "$json_response" ]]; then
        rm "$json_response"
    fi
}

sync_cert() {
    local KEYFILE="${1}" CERTFILE="${2}" FULLCHAINFILE="${3}" CHAINFILE="${4}" REQUESTFILE="${5}"

    # This hook is called after the certificates have been created but before
    # they are symlinked. This allows you to sync the files to disk to prevent
    # creating a symlink to empty files on unexpected system crashes.
    #
    # This hook is not intended to be used for further processing of certificate
    # files, see deploy_cert for that.
    #
    # Parameters:
    # - KEYFILE
    #   The path of the file containing the private key.
    # - CERTFILE
    #   The path of the file containing the signed certificate.
    # - FULLCHAINFILE
    #   The path of the file containing the full certificate chain.
    # - CHAINFILE
    #   The path of the file containing the intermediate certificate(s).
    # - REQUESTFILE
    #   The path of the file containing the certificate signing request.

    # Simple example: sync the files before symlinking them
    # sync "${KEYFILE}" "${CERTFILE}" "${FULLCHAINFILE}" "${CHAINFILE}" "${REQUESTFILE}"
}

deploy_cert() {
    local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}" TIMESTAMP="${6}"

    # This hook is called once for each certificate that has been
    # produced. Here you might, for instance, copy your new certificates
    # to service-specific locations and reload the service.
    #
    # Parameters:
    # - DOMAIN
    #   The primary domain name, i.e. the certificate common
    #   name (CN).
    # - KEYFILE
    #   The path of the file containing the private key.
    # - CERTFILE
    #   The path of the file containing the signed certificate.
    # - FULLCHAINFILE
    #   The path of the file containing the full certificate chain.
    # - CHAINFILE
    #   The path of the file containing the intermediate certificate(s).
    # - TIMESTAMP
    #   Timestamp when the specified certificate was created.

    # Simple example: Copy file to nginx config
    # cp "${KEYFILE}" "${FULLCHAINFILE}" /etc/nginx/ssl/; chown -R nginx: /etc/nginx/ssl
    # systemctl reload nginx
}

deploy_ocsp() {
    local DOMAIN="${1}" OCSPFILE="${2}" TIMESTAMP="${3}"

    # This hook is called once for each updated ocsp stapling file that has
    # been produced. Here you might, for instance, copy your new ocsp stapling
    # files to service-specific locations and reload the service.
    #
    # Parameters:
    # - DOMAIN
    #   The primary domain name, i.e. the certificate common
    #   name (CN).
    # - OCSPFILE
    #   The path of the ocsp stapling file
    # - TIMESTAMP
    #   Timestamp when the specified ocsp stapling file was created.

    # Simple example: Copy file to nginx config
    # cp "${OCSPFILE}" /etc/nginx/ssl/; chown -R nginx: /etc/nginx/ssl
    # systemctl reload nginx
}


unchanged_cert() {
    local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}"

    # This hook is called once for each certificate that is still
    # valid and therefore wasn't reissued.
    #
    # Parameters:
    # - DOMAIN
    #   The primary domain name, i.e. the certificate common
    #   name (CN).
    # - KEYFILE
    #   The path of the file containing the private key.
    # - CERTFILE
    #   The path of the file containing the signed certificate.
    # - FULLCHAINFILE
    #   The path of the file containing the full certificate chain.
    # - CHAINFILE
    #   The path of the file containing the intermediate certificate(s).
}

invalid_challenge() {
    local DOMAIN="${1}" RESPONSE="${2}"

    # This hook is called if the challenge response has failed, so domain
    # owners can be aware and act accordingly.
    #
    # Parameters:
    # - DOMAIN
    #   The primary domain name, i.e. the certificate common
    #   name (CN).
    # - RESPONSE
    #   The response that the verification server returned

    # Simple example: Send mail to root
    # printf "Subject: Validation of ${DOMAIN} failed!\n\nOh noez!" | sendmail root
}

request_failure() {
    local STATUSCODE="${1}" REASON="${2}" REQTYPE="${3}" HEADERS="${4}"

    # This hook is called when an HTTP request fails (e.g., when the ACME
    # server is busy, returns an error, etc). It will be called upon any
    # response code that does not start with '2'. Useful to alert admins
    # about problems with requests.
    #
    # Parameters:
    # - STATUSCODE
    #   The HTML status code that originated the error.
    # - REASON
    #   The specified reason for the error.
    # - REQTYPE
    #   The kind of request that was made (GET, POST...)
    # - HEADERS
    #   HTTP headers returned by the CA

    # Simple example: Send mail to root
    # printf "Subject: HTTP request failed failed!\n\nA http request failed with status ${STATUSCODE}!" | sendmail root
}

generate_csr() {
    local DOMAIN="${1}" CERTDIR="${2}" ALTNAMES="${3}"

    # This hook is called before any certificate signing operation takes place.
    # It can be used to generate or fetch a certificate signing request with external
    # tools.
    # The output should be just the certificate signing request formatted as PEM.
    #
    # Parameters:
    # - DOMAIN
    #   The primary domain as specified in domains.txt. This does not need to
    #   match with the domains in the CSR, it's basically just the directory name.
    # - CERTDIR
    #   Certificate output directory for this particular certificate. Can be used
    #   for storing additional files.
    # - ALTNAMES
    #   All domain names for the current certificate as specified in domains.txt.
    #   Again, this doesn't need to match with the CSR, it's just there for convenience.

    # Simple example: Look for pre-generated CSRs
    # if [ -e "${CERTDIR}/pre-generated.csr" ]; then
    #   cat "${CERTDIR}/pre-generated.csr"
    # fi
}

startup_hook() {
    # This hook is called before the cron command to do some initial tasks
    # (e.g. starting a webserver).

    :

    if ! command -v jq > /dev/null; then
        echo "Error: command 'jq' could not be found"
        exit 1
    fi
}

exit_hook() {
  local ERROR="${1:-}"

  # This hook is called at the end of the cron command and can be used to
  # do some final (cleanup or other) tasks.
  #
  # Parameters:
  # - ERROR
  #   Contains error message if dehydrated exits with error
}

HANDLER="$1"; shift
if [[ "${HANDLER}" =~ ^(deploy_challenge|clean_challenge|sync_cert|deploy_cert|deploy_ocsp|unchanged_cert|invalid_challenge|request_failure|generate_csr|startup_hook|exit_hook)$ ]]; then
  "$HANDLER" "$@"
fi
