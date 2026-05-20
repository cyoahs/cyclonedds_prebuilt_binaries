# CycloneDDS Prebuilt Binaries

Static website and PEP 503 compatible Python simple index for prebuilt
CycloneDDS wheels.

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

Cloudflare Pages can use:

```text
Build command: leave empty
Build output directory: public
```

After adding or replacing wheels, put them in `public/packages/` and update the
matching static pages under `public/simple/`.

## License

MIT License. See `LICENSE`.
