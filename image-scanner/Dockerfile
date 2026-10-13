FROM docker.io/sbs20/scanservjs:v3.3.0

RUN apt-get update \
 && apt-get install -yq --no-install-recommends dbus libsane-hpaio \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* \
 && grep -qxF hpaio /etc/sane.d/dll.conf || echo hpaio >> /etc/sane.d/dll.conf \
 && mkdir -p /opt/scanner-k8s \
 && mv /entrypoint.sh /opt/scanner-k8s/scanservjs-entrypoint.sh

COPY entrypoint.sh /opt/scanner-k8s/entrypoint.sh
RUN chmod +x /opt/scanner-k8s/entrypoint.sh

ENTRYPOINT ["/opt/scanner-k8s/entrypoint.sh"]
