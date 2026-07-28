FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PRINTER_NAME=HP_DeskJet_3050_J610 \
    PRINTER_USB_VIDPID=03f0:9311

RUN apt-get update && apt-get install -y --no-install-recommends \
    avahi-daemon \
    ca-certificates \
    cups \
    cups-bsd \
    cups-client \
    cups-filters \
    dbus \
    hplip \
    ipp-usb \
    libusb-1.0-0 \
    printer-driver-hpcups \
    usbutils \
    wget \
    && rm -rf /var/lib/apt/lists/*

RUN usermod -aG lp root || true

COPY cupsd.conf avahi-daemon.conf /opt/cups-k8s/
COPY avahi-services/ /opt/cups-k8s/avahi-services/
COPY entrypoint.sh /opt/cups-k8s/entrypoint.sh
RUN chmod +x /opt/cups-k8s/entrypoint.sh

EXPOSE 631

HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
  CMD lpstat -r >/dev/null 2>&1

ENTRYPOINT ["/opt/cups-k8s/entrypoint.sh"]
