# Dotfiles (mitamae)

Inspired by [K0kubun's dotfiles](https://github.com/k0kubun/dotfiles) I
transitioned to using [mitamae](https://github.com/itamae-kitchen/mitamae) to
manage my dotfiles.

## Usage

```
git clone git@github.com:eightbitraptor.com/dotfiles-mitamae ~/.dotfiles
cd ~/.dotfiles 
./install.sh
```

## Debugging 

```
EBR_LOG_LEVEL=debug ./install.sh
```

There's a `Containerfile` in the repo, so if you don't want to test on your
local machine then you can build this using

```
podman build .
```

But bear in mind that systemd stuff won't work in a container.

## Structure

### base.rb

Contains glue code and custom definitions that make most of this structure work
together. Also configures the `prelude` recipes - these are OS specific recipes
that should run on every machine of a particular OS. They should do basic OS
specific config that is guaranteed to be needed on every machine of that type.

As a general rule, try not to add new code to the preludes.

### nodes

* `senjougahara` - Development Desktop, Fedora 37.
* `hitomi` - Development Laptop, Microsoft Surface Pro 7 i7, Fedora 37, kernel
  from the [linux surface](https://github.com/linux-surface/linux-surface)
  project.
* `shopify-mvh` - Work laptop, Macbook Pro M1 Pro, macOS

### recipes

Individual recipes go here, I try and keep them as single purpose as possible,
hence `sway`, `emacs`, `vim` etc.

### files

Associated with recipes, convention is to put files in a subdirectory according
to their recipe, so `files/git/gitconfig` etc.

### templates

Follow the same convention as files

