#!/bin/sh
set -e

mitamae_version="1.14.1"
mitamae_linux_sha256="dc5fe86e5a6ea46f8d1deedb812670871b9cd06547c7be456ebace73f83cbf7b"
mitamae_darwin_sha256="6a966123aa74c265847c55bc864b60264010ea0737e0c7063d0bad1bcfc3aa5c"
mitamae_darwin_arm_sha256="afe1a1dd766414d610fd3f05a68d7d223e60c293f4d377b7ec469dd61ba28552"

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
