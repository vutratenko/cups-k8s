FROM docker.io/sbs20/scanservjs:v3.3.0

RUN apt-get update \
 && apt-get install -yq --no-install-recommends libsane-hpaio \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* \
 && grep -qxF hpaio /etc/sane.d/dll.conf || echo hpaio >> /etc/sane.d/dll.conf
