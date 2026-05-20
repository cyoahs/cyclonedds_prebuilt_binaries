# CycloneDDS Prebuilt Binaries

Static website and PEP 503 compatible Python simple index for prebuilt
CycloneDDS wheels.

The upstream Python binding lives at
[eclipse-cyclonedds/cyclonedds-python](https://github.com/eclipse-cyclonedds/cyclonedds-python).
Official prebuilt binaries for `cyclonedds-python` are limited on some Linux
aarch64 targets, so installing on Unitree robots often requires building from
the CycloneDDS source tree first. This repository hosts a small static index of
prebuilt wheels for those environments.

## Build Environments

The current wheels were built on Unitree factory images:

| Device / image | Python version | CycloneDDS versions |
| --- | --- | --- |
| Thor, JetPack 7.0, L4T 38.2.1 | CPython 3.12 (`cp312`) | 0.10.2, 0.10.5, 11.0.1 |
| Orin NX, JetPack 5.1.1, L4T 35.3.1 | CPython 3.8 (`cp38`) | 0.10.2 |

If this index does not have a wheel for your Python, CycloneDDS, or device
image combination, run [`build_cyclonedds_wheels.sh`](build_cyclonedds_wheels.sh)
on the target environment and add the resulting wheel to the static index.

## Static Site Layout

This project is already laid out as static files for Cloudflare Pages. The
deployable directory is `public/`; it contains the home page, English page,
PEP 503 simple index, and wheel files.

To migrate the domain, edit `public/site-config.js`. The simple index uses
relative wheel links, so package installation keeps working when the domain
changes.

## Install

```bash
pip install --extra-index-url https://pypi.cyoahs.dev/simple cyclonedds
```

To install only from this index:

```bash
pip install --index-url https://pypi.cyoahs.dev/simple cyclonedds
```

## Build Wheels

```bash
./build_cyclonedds_wheels.sh 0.10.2 0.10.5 11.0.1
```

The deployed site also exposes the script at
`https://pypi.cyoahs.dev/build_cyclonedds_wheels.sh`.

Cloudflare Workers Builds can use:

```text
Build command: true
Deploy command: npx wrangler deploy
```

The `wrangler.jsonc` file points Workers Static Assets at `./public`.

After adding or replacing wheels, put them in `public/packages/` and update the
matching static pages under `public/simple/`.

## License

MIT License. See `LICENSE`.
