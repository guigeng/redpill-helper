#!/usr/bin/env bash
set -eu

function checkPreconditon(){
    missing_tools=""
    for tool in jq curl docker realpath sha256sum; do
        if [ ! $(which ${tool} ) ];then
            missing_tools+=" ${tool}"
        fi
    done
    if [ ${#missing_tools} -gt 0 ]; then
        echo "required tool(s) missing:$missing_tools. Please install them and run the command again!"
        exit 1
    fi
}
checkPreconditon

function readConfig() {
    if [ ! -e custom_config.json ]; then
        cat global_config.json
    else
        jq -s '.[0].docker=(.[0].docker * .[1].docker) |.[0].build_configs=(.[1].build_configs + .[0].build_configs | unique_by(.id)) | .[0]' global_config.json custom_config.json
    fi
}

function getValueByJsonPath(){
    local JSONPATH=${1}
    local CONFIG=${2}
    jq -c -r "${JSONPATH}" <<<${CONFIG}
}

function buildImage(){
    local KERNEL_SRC_FILENAME=$( [ "${COMPILE_WITH}" == "kernel" ] && echo "${KERNEL_FILENAME}" || echo "${TOOLKIT_DEV_FILENAME}")
    local KERNEL_SRC_FILENAME_SHA256=$( [ "${COMPILE_WITH}" == "kernel" ] && echo "${KERNEL_DOWNLOAD_SHA256}" || echo "${TOOLKIT_DEV_DOWNLOAD_SHA256}")
    checkFileSHA256Checksum "${DOWNLOAD_FOLDER}/${KERNEL_SRC_FILENAME}" "${KERNEL_SRC_FILENAME_SHA256}"

    [ "${USE_BUILDKIT}" == "true" ] && export DOCKER_BUILDKIT=1
    docker build --file docker/Dockerfile --force-rm  --pull \
        $( [ "${USE_BUILD_CACHE}" == "false" ] && echo "--no-cache" ) \
        --build-arg DOCKER_BASE_IMAGE="${DOCKER_BASE_IMAGE}" \
        --build-arg COMPILE_WITH="${COMPILE_WITH}" \
        --build-arg EXTRACTED_KSRC="${EXTRACTED_KSRC}" \
        --build-arg KERNEL_SRC_FILENAME="${KERNEL_SRC_FILENAME}" \
        --build-arg REDPILL_LKM_REPO="${REDPILL_LKM_REPO}" \
        --build-arg REDPILL_LKM_BRANCH="${REDPILL_LKM_BRANCH}" \
        --build-arg REDPILL_LOAD_REPO="${REDPILL_LOAD_REPO}" \
        --build-arg REDPILL_LOAD_BRANCH="${REDPILL_LOAD_BRANCH}" \
        --build-arg TARGET_PLATFORM="${TARGET_PLATFORM}" \
        --build-arg TARGET_VERSION="${TARGET_VERSION}" \
        --build-arg DSM_VERSION="${DSM_VERSION}" \
        --build-arg TARGET_REVISION="${TARGET_REVISION}" \
        --build-arg REDPILL_LKM_MAKE_TARGET=${REDPILL_LKM_MAKE_TARGET} \
        --tag ${DOCKER_IMAGE_NAME}:${TARGET_PLATFORM}-${TARGET_VERSION}-${TARGET_REVISION} ./docker
}

function clean(){
    if [ "${AUTO_CLEAN}" != "true" ]; then
        echo "---------- before clean --------------------------------------"
        docker system df
        echo "---------- before clean --------------------------------------"
    fi
    if [ "${ID}" == "all" ];then
        OLD_IMAGES=$(docker image ls --filter label=redpill-tool-chain --quiet $( [ "${CLEAN_IMAGES}" == "orphaned" ] && echo "--filter dangling=true"))
        docker builder prune --all --filter label=redpill-tool-chain --force
    else
        OLD_IMAGES=$(docker image ls --filter label=redpill-tool-chain=${TARGET_PLATFORM}-${TARGET_VERSION}-${TARGET_REVISION} --quiet --filter dangling=true)
        docker builder prune --filter label=redpill-tool-chain=${TARGET_PLATFORM}-${TARGET_VERSION}-${TARGET_REVISION} --force
    fi
    if [ ! -z "${OLD_IMAGES}" ]; then
        docker image rm ${OLD_IMAGES}
    fi
    if [ "${AUTO_CLEAN}" != "true" ]; then
        echo "---------- after clean ---------------------------------------"
        docker system df
        echo "---------- after clean ---------------------------------------"
    fi
}

function runContainer(){
    local CMD=${1}
    local SCRIPTNAME=${2:-""}
    local PLATFORM_VERSION=${3:-""}
    # only shift args for ext.
    [ $# -gt 3 ] && shift 3
    local CMD_ARGS=${@:-""}
    if [ ! -e $(realpath "${USER_CONFIG_JSON}") ]; then
        echo "User config does not exist: ${USER_CONFIG_JSON}"
        exit 1
    fi
    if [[ "${LOCAL_RP_LKM_USE}" == "true" && ! -e $(realpath "${LOCAL_RP_LKM_PATH}") ]]; then
        echo "Local redpill-lkm path does not exist: ${LOCAL_RP_LKM_PATH}"
        exit 1
    fi
    if [[ "${LOCAL_RP_LOAD_USE}" == "true" && ! -e $(realpath "${LOCAL_RP_LOAD_PATH}") ]]; then
        echo "Local redpill-load path does not exist: ${LOCAL_RP_LOAD_PATH}"
        exit 1
    fi
    if [[ "${USE_CUSTOM_BIND_MOUNTS}" == "true" ]]; then
        NUMBER_OF_MOUNTS=$(getValueByJsonPath ". | length" "${CUSTOM_BIND_MOUNTS}")
        for (( i=0; i<${NUMBER_OF_MOUNTS}; i++ ));do
            HOST_PATH=$(getValueByJsonPath ".[${i}].host_path" "${CUSTOM_BIND_MOUNTS}")
            CONTAINER_PATH=$(getValueByJsonPath ".[${i}].container_path" "${CUSTOM_BIND_MOUNTS}")
            if [ ! -e $(realpath "${HOST_PATH}") ]; then
                echo "Host path does not exist: ${HOST_PATH}"
                exit 1
            fi
            BINDS+="--volume $(realpath "${HOST_PATH}"):${CONTAINER_PATH} "
        done
    fi
    docker run --privileged --rm  $( [ "${CMD}" == "run" ] || [ "${CMD}" == "ext" ] && echo " --interactive") --tty \
        --name rp-helper \
        --hostname rp-helper \
        --volume /dev:/dev \
        $( [ "${USE_CUSTOM_BIND_MOUNTS}" == "true" ] && echo "${BINDS}") \
        $( [ "${LOCAL_RP_LOAD_USE}" == "true" ] && echo "--volume $(realpath "${LOCAL_RP_LOAD_PATH}"):/opt/redpill-load") \
        $( [ "${LOCAL_RP_LKM_USE}" == "true" ] && echo "--volume $(realpath "${LOCAL_RP_LKM_PATH}"):/opt/redpill-lkm") \
        $( [ -e "${USER_CONFIG_JSON}" ] && echo "--volume $(realpath "${USER_CONFIG_JSON}"):/opt/redpill-load/user_config.json") \
        --volume ${REDPILL_LOAD_CACHE}:/opt/redpill-load/cache \
        --volume ${REDPILL_LOAD_IMAGES}:/opt/redpill-load/images \
        --volume ${REDPILL_LOAD_CUSTOM}:/opt/redpill-load/custom \
        --env REDPILL_LKM_MAKE_TARGET=${REDPILL_LKM_MAKE_TARGET} \
        --env TARGET_PLATFORM="${TARGET_PLATFORM}" \
        --env TARGET_VERSION="${TARGET_VERSION}" \
        --env DSM_VERSION="${DSM_VERSION}" \
        --env REVISION="${TARGET_REVISION}" \
        --env LOCAL_RP_LKM_USE="${LOCAL_RP_LKM_USE}" \
        --env LOCAL_RP_LOAD_USE="${LOCAL_RP_LOAD_USE}" \
        ${DOCKER_IMAGE_NAME}:${TARGET_PLATFORM}-${TARGET_VERSION}-${TARGET_REVISION} "${CMD}" "${SCRIPTNAME}" "${PLATFORM_VERSION}" "${CMD_ARGS}"
}

function downloadFromUrlIfNotExists(){
    local DOWNLOAD_URL="${1}"
    local OUT_FILE="${2}"
    local MSG="${3}"
    if [ ! -e ${OUT_FILE} ]; then
        echo "Downloading ${MSG}"
        curl --progress-bar --location ${DOWNLOAD_URL} --output ${OUT_FILE}
    fi
}

function checkFileSHA256Checksum(){
    local FILE="${1}"
    local EXPECTED_SHA256="${2}"
    local SHA256_RESULT=$(sha256sum ${FILE})
    if [ "${SHA256_RESULT%% *}" != "${EXPECTED_SHA256}" ];then
        echo "The ${FILE} is corrupted, expected sha256 checksum ${EXPECTED_SHA256}, got ${SHA256_RESULT%% *}"
        #rm -f "${FILE}"
        #echo "Deleted corrupted file ${FILE}. Please re-run your action!"
        echo "Please delete the file ${FILE} manualy and re-run your command!"
        exit 1
    fi
}

function showHelp(){
cat << EOF
$(basename ${0}) v${RP_HELPER_VERS}

Usage: ${0} <action> <build_config_id> [extension manager arguments]

Actions: build, ext, auto, run, clean

- build:    Build the redpill-helper image for the specified build config id

- ext:      Manage extensions within the specified build config id container.
            The modifications will apply to all build configs!

- auto:     Starts the redpill-helper container using the previously built 
            redpill-helper image for the specified buid config id. Updates 
            redpill sources and builds the bootloader image automaticaly and
            end the container once done

- run:      Starts the redpill-helper container using the previously built 
            redpill-helper image for the specified build config id with
            an interactive bash terminal

- clean:    Removes old/dangling images and the build cache for a given 
            build config id. Use "all" as build config id to remove images and
            build caches for all build configs.
            NB "docker.clean_images": "all" only affects "clean all"

Available build config ids:
---------------------
${AVAILABLE_IDS}

NB. by default, only build config ids supported by TTG are listed. Others can 
be added in the "custom_config.json".
EOF
}


RP_HELPER_VERS="0.12"

# mount-bind host folder with absolute path into redpill-load cache folder
# will not work with relativfe path! If single name is used, a docker volume will be created!
REDPILL_LOAD_CACHE=${PWD}/cache

# mount bind hots folder with absolute path into redpill load images folder
REDPILL_LOAD_IMAGES=${PWD}/images

# mount bind hots folder with absolute path into redpill load images folder
REDPILL_LOAD_CUSTOM=${PWD}/custom



####################################################
# Do not touch anything below, unless you know what you are doing...
####################################################

# parse paramters from config
CONFIG=$(readConfig)
AVAILABLE_IDS=$(getValueByJsonPath ".build_configs[].id" "${CONFIG}")
AUTO_CLEAN=$(getValueByJsonPath ".docker.auto_clean" "${CONFIG}")
USE_BUILD_CACHE=$(getValueByJsonPath ".docker.use_build_cache" "${CONFIG}")
CLEAN_IMAGES=$(getValueByJsonPath ".docker.clean_images" "${CONFIG}")
USE_CUSTOM_BIND_MOUNTS=$(getValueByJsonPath ".docker.use_custom_bind_mounts" "${CONFIG}")
CUSTOM_BIND_MOUNTS=$(getValueByJsonPath ".docker.custom_bind_mounts" "${CONFIG}")

if [ $# -lt 2 ]; then
    showHelp
    exit 1
fi

ACTION=${1}
ID=${2}

if [ "${ID}" != "all"  ]; then
    BUILD_CONFIG=$(getValueByJsonPath ".build_configs[] | select(.id==\"${ID}\")" "${CONFIG}")
    if [ -z "${BUILD_CONFIG}" ];then
        echo "Error: build config id ${ID} does not exist in global_config.json (or custom_config.json)"
        echo
        showHelp
        exit 1
    fi
    USE_BUILDKIT=$(getValueByJsonPath ".docker.use_buildkit" "${CONFIG}")
    DOCKER_IMAGE_NAME=$(getValueByJsonPath ".docker.image_name" "${CONFIG}")
    DOWNLOAD_FOLDER=$(getValueByJsonPath ".docker.download_folder" "${CONFIG}")
    LOCAL_RP_LKM_USE=$(getValueByJsonPath ".docker.local_rp_lkm_use" "${CONFIG}")
    LOCAL_RP_LKM_PATH=$(getValueByJsonPath ".docker.local_rp_lkm_path" "${CONFIG}")
    LOCAL_RP_LOAD_USE=$(getValueByJsonPath ".docker.local_rp_load_use" "${CONFIG}")
    LOCAL_RP_LOAD_PATH=$(getValueByJsonPath ".docker.local_rp_load_path" "${CONFIG}")
    TARGET_PLATFORM=$(getValueByJsonPath ".platform_version | split(\"-\")[0]" "${BUILD_CONFIG}")
    TARGET_VERSION=$(getValueByJsonPath ".platform_version | split(\"-\")[1]" "${BUILD_CONFIG}")
    DSM_VERSION=$(getValueByJsonPath ".platform_version | split(\"-\")[1][0:3]" "${BUILD_CONFIG}")
    TARGET_REVISION=$(getValueByJsonPath ".platform_version | split(\"-\")[2]" "${BUILD_CONFIG}")
    USER_CONFIG_JSON=$(getValueByJsonPath ".user_config_json" "${BUILD_CONFIG}")
    DOCKER_BASE_IMAGE=$(getValueByJsonPath ".docker_base_image" "${BUILD_CONFIG}")
    COMPILE_WITH=$(getValueByJsonPath ".compile_with" "${BUILD_CONFIG}")
    REDPILL_LKM_MAKE_TARGET=$(getValueByJsonPath ".redpill_lkm_make_target" "${BUILD_CONFIG}")
    KERNEL_DOWNLOAD_URL=$(getValueByJsonPath ".downloads.kernel.url" "${BUILD_CONFIG}")
    KERNEL_DOWNLOAD_SHA256=$(getValueByJsonPath ".downloads.kernel.sha256" "${BUILD_CONFIG}")
    KERNEL_FILENAME=$(getValueByJsonPath ".downloads.kernel.url | split(\"/\")[] | select ( . | endswith(\".txz\"))" "${BUILD_CONFIG}")
    TOOLKIT_DEV_DOWNLOAD_URL=$(getValueByJsonPath ".downloads.toolkit_dev.url" "${BUILD_CONFIG}")
    TOOLKIT_DEV_DOWNLOAD_SHA256=$(getValueByJsonPath ".downloads.toolkit_dev.sha256" "${BUILD_CONFIG}")
    TOOLKIT_DEV_FILENAME=$(getValueByJsonPath ".downloads.toolkit_dev.url | split(\"/\")[] | select ( . | endswith(\".txz\"))" "${BUILD_CONFIG}")
    REDPILL_LKM_REPO=$(getValueByJsonPath ".redpill_lkm.source_url" "${BUILD_CONFIG}")
    REDPILL_LKM_BRANCH=$(getValueByJsonPath ".redpill_lkm.branch" "${BUILD_CONFIG}")
    REDPILL_LOAD_REPO=$(getValueByJsonPath ".redpill_load.source_url" "${BUILD_CONFIG}")
    REDPILL_LOAD_BRANCH=$(getValueByJsonPath ".redpill_load.branch" "${BUILD_CONFIG}")
    EXTRACTED_KSRC='/linux*'
    if [ "${COMPILE_WITH}" == "toolkit_dev" ]; then
        EXTRACTED_KSRC="/usr/local/x86_64-pc-linux-gnu/x86_64-pc-linux-gnu/sys-root/usr/lib/modules/DSM-${DSM_VERSION}/build/"
    fi
else
    if [ "${ACTION}" != "clean" ]; then
        echo "All is not supported for action \"${ACTION}\""
        exit 1
    fi
fi

case "${ACTION}" in
    build)  if [ "${COMPILE_WITH}" == "kernel" ];then
                downloadFromUrlIfNotExists "${KERNEL_DOWNLOAD_URL}" "${DOWNLOAD_FOLDER}/${KERNEL_FILENAME}" "Kernel"
            else
                downloadFromUrlIfNotExists "${TOOLKIT_DEV_DOWNLOAD_URL}" "${DOWNLOAD_FOLDER}/${TOOLKIT_DEV_FILENAME}" "Toolkit Dev"
            fi
            buildImage
            if [ "${AUTO_CLEAN}" == "true" ]; then
                clean
            fi
            ;;
    ext)    shift
            runContainer "ext" "${0}" $@
            ;;
    run)    runContainer "run"
            ;;
    auto)   runContainer "auto"
            ;;
    clean)  clean
            ;;
    *)      if [ ! -z ${ACTION} ];then
                echo "Error: action ${ACTION} does not exist"
                echo ""
            fi
            showHelp
            exit 1
            ;;
esac