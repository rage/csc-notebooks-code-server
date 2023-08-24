FROM archlinux:latest as base

RUN pacman -Syu --noconfirm && \
  pacman -S python-poetry python-pip --noconfirm \
  && rm -rf /var/cache/pacman/pkg/*

# Add a regular user for building packages and for running processes in the final image
RUN useradd user --create-home

# ----------------------------------------------
# Build dependencies in a temporary container. The build artifacts are copied to the final container.
# This is done to reduce the size of the final image.
# ----------------------------------------------
FROM base as builder

RUN pacman -S git base-devel --noconfirm
USER user

# Build the code-server package
RUN cd /home/user \
  && git clone https://aur.archlinux.org/code-server.git \
  && cd code-server \
  # Commit hash verified to be safe. If you update this, verify the files in the commit so that we don't accidentally execute malicious code code.
  && git checkout ee81de7ae8f012ac09316318fd72ddd229ebb6b2 \
  && env PKGEXT='.pkg.tar.zst' makepkg --syncdeps --noconfirm

# Install code-server
USER root
RUN pacman -U /home/user/code-server/code-server-*.pkg.tar.zst --noconfirm
USER user

# Preinstall the TMC extension
RUN mkdir -p /home/user/.code-server/extensions \
  && code-server --install-extension moocfi.test-my-code --extensions-dir /home/user/.code-server/extensions \
  && code-server --install-extension ms-python.python --extensions-dir /home/user/.code-server/extensions \
  && code-server --install-extension ms-toolsai.jupyter --extensions-dir /home/user/.code-server/extensions

USER root
# Convert poetry lock file to requirements.txt
COPY pyproject.toml poetry.lock /home/user/build-venv/
RUN cd /home/user/build-venv \
  && poetry export -f requirements.txt --output requirements.txt

# ----------------------------------------------
# Final image
# ----------------------------------------------
FROM base

# Install code-server
COPY --from=builder /home/user/code-server/code-server-*.pkg.tar.zst /tmp/code-server.pkg.tar.zst
RUN pacman -U /tmp/code-server.pkg.tar.zst --noconfirm \
  && rm -rf /var/cache/pacman/pkg/* \
  && rm /tmp/code-server.pkg.tar.zst

# Use the preinstalled extensions
COPY --from=builder --chown=user /home/user/.code-server/extensions /home/user/.code-server/extensions

USER user

# install python dependencies
COPY --from=builder --chown=user /home/user/build-venv/requirements.txt /home/user/build-venv/requirements.txt
RUN pip install --user --break-system-packages -r /home/user/build-venv/requirements.txt
RUN rm -rf /home/user/build-venv


RUN mkdir -p /home/user/Code

ENTRYPOINT ["/usr/bin/code-server", "--bind-addr", "0.0.0.0:8080", "--auth", "none", "--disable-telemetry", "--disable-update-check", "--extensions-dir", "/home/user/.code-server/extensions", "/home/user/Code"]
EXPOSE 8080
