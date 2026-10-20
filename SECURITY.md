# Security

zr is a compiler: it writes binaries that other people run. A defect
that makes a binary do something its program does not say is a
security problem, and so is a defect in the runtime that a program's
input can reach.

## Report a problem

Do not open a public issue. Use GitHub's private vulnerability
reporting for this repository (Security, then "Report a
vulnerability"), or write to ryan@ryanseys.com.

Include the output of `zr doctor` (the zr and ruby versions, the host
and what it builds), the target, the smallest program that shows the
problem, and what the binary does.

You will get a reply within a week. A fix goes into the next release,
and the CHANGELOG names the problem once the release is out.

## Trust model

- **The cache.** zr loads code from the files of its cache (the
  directory that `zr cache path` prints) and runs the binaries that it
  keeps there. So the cache must be yours alone. zr makes it with mode
  0700, and stops with status 2 when another user owns it, when other
  users can write to it, or when every user can write to a directory
  above it that has no sticky bit. Do not point `ZR_CACHE` at a
  directory that other users share. A CI cache that the job's own user
  restores is safe.
- **Runtime bundles.** `zr cache import` and `zr cache fetch` put a
  runtime that another machine built into the cache, so the same rule
  applies: import only a bundle that you trust as you trust zr. `fetch`
  downloads over HTTPS from this version's GitHub Release (or from
  `ZR_PREBUILT_URL`) and checks the bundle against the release's
  `SHA256SUMS`; `--sha256` pins a digest that you give. Each release
  attests its bundles (`gh attestation verify FILE -R ryanseys/zr`). An
  import checks every file against the bundle's manifest, takes only
  paths of the cache's own layout, and writes the cache's roots last.
- **`--native-ext`.** A build with `--native-ext` runs the gem's
  `extconf.rb` and `make`, as `gem install` does. Use it only with gems
  that you trust as much as you would to install them.
- **A compiled program** reads the `ZR_*` debug variables
  (`ZR_GC_STRESS`, `ZR_THREADS` and others) and `ZR_HOME`, which acts as
  `RUBYLIB` does for ruby. Whoever sets the environment of a program
  can change what it loads, as with ruby.

## Supported versions

Only the latest release gets fixes.
