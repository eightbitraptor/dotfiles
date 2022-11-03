FROM fedora

RUN dnf install -y curl coreutils flatpak

# Fake the output of hostname for testing
RUN mkdir -p /usr/local/bin
RUN echo "echo senjougahara" > /usr/local/bin/hostname
RUN chmod +x /usr/local/bin/hostname

ADD . /dotfiles
WORKDIR /dotfiles
RUN bash bin/setup.sh
run ./install.sh
