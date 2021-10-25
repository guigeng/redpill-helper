#!/usr/bin/env bash
set -eu

case "${1}" in

    auto)
        git -C "${REDPILL_LKM_SRC}" fetch
        git -C "${REDPILL_LOAD_SRC}" fetch

        if [ "${LOCAL_RP_LKM_USE}" == "false" ]; then
            REDPILL_LKM_BRANCH=$(git -C "${REDPILL_LKM_SRC}" name-rev --name-only HEAD)
            echo "Checking if redpill-lkm sources require pull."
            if [ $(git -C "${REDPILL_LKM_SRC}" rev-list HEAD...origin/${REDPILL_LKM_BRANCH} --count ) -eq 0 ];then
                echo "  Nothing to do."
            else
                git -C ${REDPILL_LKM_SRC} pull
                echo "Pulled latest commits."
            fi
        else
            echo "Redpill-lkm sources are mapped into the build container, skipping pull of latest sources."
        fi


        if [ "${LOCAL_RP_LOAD_USE}" == "false" ]; then
            REDPILL_LOAD_BRANCH=$(git -C ${REDPILL_LOAD_SRC} name-rev --name-only HEAD)
            echo "Check if redpill-load sources require pull."
            if [ $(git -C ${REDPILL_LOAD_SRC} rev-list HEAD...origin/${REDPILL_LOAD_BRANCH} --count ) -eq 0 ];then
                echo "  Nothing to do."
            else
                git -C ${REDPILL_LOAD_SRC} pull
                echo "Pulled latest commits."
            fi
        else
            echo "Redpill-load sources are mapped into the build container, skipping pull of latest sources."
        fi

        echo "Lay back and enjoy the show: Magic is about to happen!"
        make build_all
        rc=$?
        if [ ${rc} -eq 0 ];then
            echo "The redpill bootloader is created, the container will be ended now."
        else
            echo "An error occoured, please check the log output."
        fi
        exit $rc
        ;;

    ext)
        SCRIPTNAME="${2}"
        PLATFORM_VERSION="${3}"
        shift 3
        cd "${REDPILL_LOAD_SRC}"
        export MRP_SRC_NAME="${SCRIPTNAME} ext ${PLATFORM_VERSION}"
        ./ext-manager.sh $@
        exit $?
        ;;
    run )
        exec /bin/bash
        ;;
    *)
        shift 2
        exec "$@"
        ;;

esac

