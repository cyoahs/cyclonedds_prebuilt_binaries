最简单：**Cloudflare Pages 托管一个静态 PEP 503 simple index**。本质就是几个 HTML 文件 + whl 文件。pip 的 `--index-url/--extra-index-url` 需要指向符合 PEP 503 的 simple repository；Cloudflare Pages 可以直接部署静态 HTML 目录。([Python Enhancement Proposals (PEPs)][1])

## 1. 目录结构

建一个仓库，比如 `unitree-pypi-simple`：

```text
unitree-pypi-simple/
├── simple/
│   ├── index.html
│   ├── cyclonedds/
│   │   └── index.html
│   └── unitree-sdk2-python/
│       └── index.html
└── packages/
    ├── cyclonedds-0.10.2-cp312-cp312-linux_aarch64.whl
    └── unitree_sdk2_python-1.0.0-py3-none-any.whl
```

注意包名目录要用 **normalized name**：小写，并把 `_`、`.`、连续 `-` 归一成 `-`。所以：

```text
unitree_sdk2_python -> unitree-sdk2-python
cyclonedds          -> cyclonedds
```

---

## 2. 写 HTML index

`simple/index.html`：

```html
<!DOCTYPE html>
<html>
  <body>
    <a href="cyclonedds/">cyclonedds</a><br>
    <a href="unitree-sdk2-python/">unitree-sdk2-python</a><br>
  </body>
</html>
```

`simple/cyclonedds/index.html`：

```html
<!DOCTYPE html>
<html>
  <body>
    <a href="../../packages/cyclonedds-0.10.2-cp312-cp312-linux_aarch64.whl">
      cyclonedds-0.10.2-cp312-cp312-linux_aarch64.whl
    </a><br>
  </body>
</html>
```

`simple/unitree-sdk2-python/index.html`：

```html
<!DOCTYPE html>
<html>
  <body>
    <a href="../../packages/unitree_sdk2_python-1.0.0-py3-none-any.whl">
      unitree_sdk2_python-1.0.0-py3-none-any.whl
    </a><br>
  </body>
</html>
```

这就是最小可用 simple API。

---

## 3. 部署到 Cloudflare Pages

Cloudflare Dashboard 里：

```text
Workers & Pages
→ Create application
→ Pages
→ Import existing Git repository
→ 选择这个 GitHub 仓库
```

构建设置：

```text
Framework preset: None
Build command: 留空
Build output directory: /
```

如果 Cloudflare 不接受 `/`，就把所有内容放进 `public/`：

```text
public/
├── simple/
└── packages/
```

然后设置：

```text
Build output directory: public
```

Cloudflare Pages 官方流程就是从 Workers & Pages 创建 Pages 应用并导入 Git 仓库。([Cloudflare Docs][2])

---

## 4. 用户安装方式

假设你的 Pages 域名是：

```text
https://unitree-pypi.pages.dev
```

用户安装：

```bash
pip install \
  --extra-index-url https://unitree-pypi.pages.dev/simple \
  unitree_sdk2_python
```

如果只想从你的源安装，不走 PyPI：

```bash
pip install \
  --index-url https://unitree-pypi.pages.dev/simple \
  unitree_sdk2_python
```

如果你的 `unitree_sdk2_python` metadata 里写了：

```toml
dependencies = [
  "cyclonedds==0.10.2",
]
```

pip 会自动访问：

```text
https://unitree-pypi.pages.dev/simple/unitree-sdk2-python/
https://unitree-pypi.pages.dev/simple/cyclonedds/
```

然后下载对应 whl。

---

## 5. 一键生成 simple index 的脚本

在 `packages/` 放好 whl 后，运行这个脚本自动生成 `simple/`：

```python
#!/usr/bin/env python3
import html
import re
from pathlib import Path
from packaging.utils import parse_wheel_filename, canonicalize_name

ROOT = Path(__file__).resolve().parent
PKG_DIR = ROOT / "packages"
SIMPLE_DIR = ROOT / "simple"

SIMPLE_DIR.mkdir(exist_ok=True)

projects = {}

for whl in sorted(PKG_DIR.glob("*.whl")):
    name, version, build, tags = parse_wheel_filename(whl.name)
    project = canonicalize_name(name)
    projects.setdefault(project, []).append(whl.name)

# top-level /simple/
with (SIMPLE_DIR / "index.html").open("w", encoding="utf-8") as f:
    f.write("<!DOCTYPE html>\n<html><body>\n")
    for project in sorted(projects):
        f.write(f'<a href="{project}/">{project}</a><br>\n')
    f.write("</body></html>\n")

# per-project /simple/<name>/
for project, files in projects.items():
    project_dir = SIMPLE_DIR / project
    project_dir.mkdir(exist_ok=True)

    with (project_dir / "index.html").open("w", encoding="utf-8") as f:
        f.write("<!DOCTYPE html>\n<html><body>\n")
        for filename in sorted(files):
            escaped = html.escape(filename)
            href = f"../../packages/{escaped}"
            f.write(f'<a href="{href}">{escaped}</a><br>\n')
        f.write("</body></html>\n")

print("Generated simple index:")
for project in sorted(projects):
    print(f"  /simple/{project}/")
```

安装依赖：

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install packaging
python generate_simple_index.py
```

然后提交：

```bash
git add packages simple generate_simple_index.py
git commit -m "add python simple index"
git push
```

Cloudflare Pages 会自动重新部署。

---

## 6. 更适合你的实际命令

你现在可以这样组织：

```bash
mkdir -p unitree-pypi-simple/packages

cp cyclonedds_wheel_build/wheelhouse/0.10.2/cyclonedds-0.10.2-*.whl \
  unitree-pypi-simple/packages/

cp dist/unitree_sdk2_python-*.whl \
  unitree-pypi-simple/packages/
```

生成 index 后，用户一条命令：

```bash
pip install \
  --extra-index-url https://unitree-pypi.pages.dev/simple \
  unitree_sdk2_python
```

---

## 小提醒：`--extra-index-url` 有依赖混淆风险

如果你发布的是内部包，且包名可能和 PyPI 上的包重名，用：

```bash
pip install \
  --index-url https://unitree-pypi.pages.dev/simple \
  unitree_sdk2_python
```

比 `--extra-index-url` 更安全。

但如果你还想让 `numpy`、`opencv-python` 这些依赖继续从 PyPI 装，就用：

```bash
pip install \
  --extra-index-url https://unitree-pypi.pages.dev/simple \
  unitree_sdk2_python
```

前提是你的私有包名不要和 PyPI 上的恶意/同名包冲突。

[1]: https://peps.python.org/pep-0503/?utm_source=chatgpt.com "PEP 503 – Simple Repository API | peps.python.org"
[2]: https://developers.cloudflare.com/pages/framework-guides/deploy-anything/?utm_source=chatgpt.com "Static HTML · Cloudflare Pages docs"
