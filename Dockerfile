# Notchless, for everyone who is not the author.
#
# The real app needs macOS 14, Apple silicon, AppKit, a menu bar and a physical
# notch. This image ships none of those, which is precisely why it will run on
# your machine as well as it runs on his.

FROM swift:6.4.0-jammy-slim

WORKDIR /notchless
COPY Sources ./Sources
COPY --chmod=755 docker/notchless.sh /usr/local/bin/notchless

ENTRYPOINT ["notchless"]
