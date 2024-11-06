#!/bin/sh
set -e

mitamae_version="1.14.2"
mitamae_linux_sha256="9087071eab88d4243639eb73b50c19277d00d614d46edacbd9febd6250515755"
mitamae_darwin_sha256="c443c2fb85f54c29f44cbec2ad1b9932efaf07b3fa48e8799cfe6e16507effa5"
mitamae_darwin_arm_sha256="4fcd11d73c119b89b85d510861da5184552b8f23dc85dd49afc2ca0d6366e2e0"

mitamae_cache="mitamae-${mitamae_version}"
if ! [ -f "bin/${mitamae_cache}" ]; then
  case "$(uname)" in
    "Linux")
      mitamae_bin="mitamae-x86_64-linux"
      mitamae_sha256="$mitamae_linux_sha256"
      ;;
    "Darwin")
      if [ $(uname -p) == "arm" ]; then
        mitamae_bin="mitamae-aarch64-darwin"
        mitamae_sha256="$mitamae_darwin_arm_sha256"
      else
        mitamae_bin="mitamae-x86_64-darwin"
        mitamae_sha256="$mitamae_darwin_sha256"
      fi
      ;;
    *)
      echo "unexpected uname: $(uname)"
      exit 1
      ;;
  esac

  curl -o "bin/${mitamae_bin}.tar.gz" -fL "https://github.com/itamae-kitchen/mitamae/releases/download/v${mitamae_version}/${mitamae_bin}.tar.gz"
  sha256="$(sha256sum "bin/${mitamae_bin}.tar.gz" | cut -d' ' -f 1 )"
  if [ "$mitamae_sha256" != "$sha256" ]; then
    echo "checksum verification failed!\nexpected: ${mitamae_sha256}\n  actual: ${sha256}"
    exit 1
  fi
  tar xvzf "bin/${mitamae_bin}.tar.gz"

  rm "bin/${mitamae_bin}.tar.gz"
  mv "${mitamae_bin}" "bin/${mitamae_cache}"
  chmod +x "bin/${mitamae_cache}"
fi
ln -sf "${mitamae_cache}" bin/mitamae
