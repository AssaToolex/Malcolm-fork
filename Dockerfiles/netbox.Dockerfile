FROM netboxcommunity/netbox:latest

# Copyright (c) 2023 Battelle Energy Alliance, LLC.  All rights reserved.
LABEL maintainer="malcolm@inl.gov"
LABEL org.opencontainers.image.authors='malcolm@inl.gov'
LABEL org.opencontainers.image.url='https://github.com/cisagov/Malcolm'
LABEL org.opencontainers.image.documentation='https://github.com/cisagov/Malcolm/blob/main/README.md'
LABEL org.opencontainers.image.source='https://github.com/cisagov/Malcolm'
LABEL org.opencontainers.image.vendor='Cybersecurity and Infrastructure Security Agency'
LABEL org.opencontainers.image.title='malcolmnetsec/netbox'
LABEL org.opencontainers.image.description='Malcolm container providing the NetBox asset management system'

ENV DEBIAN_FRONTEND noninteractive
ENV TERM xterm
ENV LANG C.UTF-8

ARG DEFAULT_UID=1000
ARG DEFAULT_GID=1000
ENV DEFAULT_UID $DEFAULT_UID
ENV DEFAULT_GID $DEFAULT_GID
ENV PUSER "boxer"
ENV PGROUP "boxer"
ENV PUSER_PRIV_DROP true

ENV SUPERCRONIC_VERSION "0.2.2"
ENV SUPERCRONIC_URL "https://github.com/aptible/supercronic/releases/download/v$SUPERCRONIC_VERSION/supercronic-linux-amd64"
ENV SUPERCRONIC "supercronic-linux-amd64"
ENV SUPERCRONIC_SHA1SUM "2319da694833c7a147976b8e5f337cd83397d6be"
ENV SUPERCRONIC_CRONTAB "/etc/crontab"

ENV NETBOX_DEVICETYPE_LIBRARY_URL "https://codeload.github.com/netbox-community/devicetype-library/tar.gz/master"

ARG NETBOX_DEVICETYPE_LIBRARY_PATH="/opt/netbox-devicetype-library"
ARG NETBOX_DEFAULT_SITE=Malcolm
ARG NETBOX_CRON=false

ENV BASE_PATH netbox
ENV NETBOX_DEVICETYPE_LIBRARY_PATH $NETBOX_DEVICETYPE_LIBRARY_PATH
ENV NETBOX_DEFAULT_SITE $NETBOX_DEFAULT_SITE
ENV NETBOX_CRON $NETBOX_CRON

RUN apt-get -q update && \
    apt-get -y -q --no-install-recommends upgrade && \
    apt-get install -q -y --no-install-recommends \
      jq \
      procps \
      psmisc \
      supervisor \
      tini && \
    /opt/netbox/venv/bin/python -m pip install psycopg2 pynetbox python-slugify randomcolor && \
    curl -fsSLO "$SUPERCRONIC_URL" && \
      echo "${SUPERCRONIC_SHA1SUM}  ${SUPERCRONIC}" | sha1sum -c - && \
      chmod +x "$SUPERCRONIC" && \
      mv "$SUPERCRONIC" "/usr/local/bin/${SUPERCRONIC}" && \
      ln -s "/usr/local/bin/${SUPERCRONIC}" /usr/local/bin/supercronic && \
      touch "${SUPERCRONIC_CRONTAB}" && \
    apt-get -q -y autoremove && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    groupadd --gid ${DEFAULT_GID} ${PUSER} && \
      useradd -m --uid ${DEFAULT_UID} --gid ${DEFAULT_GID} ${PUSER} && \
      usermod -a -G tty ${PUSER} && \
    mkdir -p /opt/unit "${NETBOX_DEVICETYPE_LIBRARY_PATH}" && \
    chown -R $PUSER:$PGROUP /etc/netbox /opt/unit /opt/netbox && \
    # trying to see if things still work if these are owned by root (to avoid a costly chown on container startup)
    chown --silent -R root:root /opt/netbox/venv/* && \
    cd "$(dirname "${NETBOX_DEVICETYPE_LIBRARY_PATH}")" && \
        curl -sSL "$NETBOX_DEVICETYPE_LIBRARY_URL" | tar xzvf - -C ./"$(basename "${NETBOX_DEVICETYPE_LIBRARY_PATH}")" --strip-components 1 && \
    mkdir -p /opt/netbox/netbox/$BASE_PATH && \
      mv /opt/netbox/netbox/static /opt/netbox/netbox/$BASE_PATH/static && \
      jq '. += { "settings": { "http": { "discard_unsafe_fields": false } } }' /etc/unit/nginx-unit.json | jq 'del(.listeners."[::]:8080")' | jq ".routes[0].match.uri = \"/${BASE_PATH}/static/*\"" > /etc/unit/nginx-unit-new.json && \
      mv /etc/unit/nginx-unit-new.json /etc/unit/nginx-unit.json && \
      chmod 644 /etc/unit/nginx-unit.json && \
    tr -cd '\11\12\15\40-\176' < /opt/netbox/netbox/netbox/configuration.py > /opt/netbox/netbox/netbox/configuration_ascii.py && \
      mv /opt/netbox/netbox/netbox/configuration_ascii.py /opt/netbox/netbox/netbox/configuration.py

COPY --chmod=755 shared/bin/docker-uid-gid-setup.sh /usr/local/bin/
COPY --chmod=755 shared/bin/service_check_passthrough.sh /usr/local/bin/
COPY --chmod=755 netbox/scripts/* /usr/local/bin/
COPY --chmod=644 netbox/supervisord.conf /etc/supervisord.conf
COPY --chmod=644 netbox/*-defaults.json /etc/
COPY --from=pierrezemb/gostatic --chmod=755 /goStatic /usr/bin/goStatic

EXPOSE 9001

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-uid-gid-setup.sh", "/usr/local/bin/service_check_passthrough.sh"]

CMD ["/opt/netbox/docker-entrypoint.sh", "/usr/bin/supervisord", "-c", "/etc/supervisord.conf", "-n"]

# to be populated at build-time:
ARG BUILD_DATE
ARG MALCOLM_VERSION
ARG VCS_REVISION

ENV BUILD_DATE $BUILD_DATE
ENV MALCOLM_VERSION $MALCOLM_VERSION
ENV VCS_REVISION $VCS_REVISION

LABEL org.opencontainers.image.created=$BUILD_DATE
LABEL org.opencontainers.image.version=$MALCOLM_VERSION
LABEL org.opencontainers.image.revision=$VCS_REVISION
