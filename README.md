# CycloneDDS Prebuilt Binaries

Static website and PEP 503 compatible Python simple index for prebuilt
CycloneDDS wheels on Linux aarch64 Unitree images.

The upstream Python binding is
[eclipse-cyclonedds/cyclonedds-python](https://github.com/eclipse-cyclonedds/cyclonedds-python).
Its official prebuilt binaries cover relatively few aarch64 robot environments,
so installation often falls back to building CycloneDDS from source. This
repository hosts a small static wheel index for those cases.

## Install

Use this repository as an extra index:

```bash
pip install --extra-index-url https://pypi.cyoahs.dev/simple cyclonedds
```

Or install only from this index:

```bash
pip install --index-url https://pypi.cyoahs.dev/simple cyclonedds
```

Direct wheel downloads are available under:

```text
https://pypi.cyoahs.dev/packages/
```

### Unitree SDK2 Python compatibility note

When using Python newer than 3.10, `unitree_sdk2_python` with
`cyclonedds==0.10.2` may hit a runtime buffer overflow around
`ChannelFactoryInitialize`; see
[unitreerobotics/unitree_sdk2_python#90](https://github.com/unitreerobotics/unitree_sdk2_python/issues/90).
For Python 3.11 or 3.12 environments, install `unitree_sdk2_python` first, then
override CycloneDDS with a newer wheel from this index:

```bash
pip install --upgrade --extra-index-url https://pypi.cyoahs.dev/simple cyclonedds==0.10.5
```

## Build Environments

The current wheels were built on Unitree factory images:

| Device / image | Python version | CycloneDDS versions |
| --- | --- | --- |
| Thor, JetPack 7.0, L4T 38.2.1 | CPython 3.12 (`cp312`) | 0.10.2, 0.10.5, 11.0.1 |
| Orin NX, JetPack 5.1.1, L4T 35.3.1 | CPython 3.8 (`cp38`) | 0.10.2, 0.10.5 |

If this index does not have a wheel for your Python, CycloneDDS, or device
image combination, build it on the target environment:

```bash
./build_cyclonedds_wheels.sh 0.10.2
```

The deployed site also exposes the script:

```text
https://pypi.cyoahs.dev/build_cyclonedds_wheels.sh
```

## Static Layout

Everything served by Cloudflare lives in `public/`:

```text
public/
├── index.html
├── en/
├── simple/
├── packages/
├── build_cyclonedds_wheels.sh
├── site-config.js
├── site.js
└── styles.css
```

The PyPI simple index uses relative package links, so it remains portable when
the domain changes. To change the displayed install domain, edit
`public/site-config.js`.

## Deploy

This repository is configured for Cloudflare Workers Static Assets with
`wrangler.jsonc`:

```jsonc
{
  "name": "cyclonedds",
  "compatibility_date": "2026-05-20",
  "assets": {
    "directory": "./public",
    "not_found_handling": "404-page"
  }
}
```

Use these Cloudflare Workers Builds commands:

```text
Build command: true
Deploy command: npx wrangler deploy
```

## Updating Wheels

1. Build the missing wheel on the target device/image.
2. Copy the wheel into `public/packages/`.
3. Add the wheel link to the matching `public/simple/<package>/index.html`.
4. If needed, update `public/packages/index.html` and the home page download list.

No generated site step is required; the repository is already a static deploy
tree.

## License

MIT License. See `LICENSE`.
