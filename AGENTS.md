# AGENTS.md

这个项目是一个托管在 cloudflare 上的静态网站。提供一个首页和符合pypi simple api的静态访问连接。

## 构建方式

构建方式参考 Instructions.md，不同的wheel暂时存放在wheelhouse里面，需要你调整到合适的路径。

## 首页

首页提供简单的介绍信息，当前网站的使用方式(包含pip的时候extra-index和直接下载whl的方式)以及 `build_cyclonedds_wheels.sh` 的使用方式。

## 域名

默认使用域名为 pypi.cyoahs.dev，但是需要可迁移，其他用户修改某个配置文件之后可以自动适配域名。

## i18n

提供简体中文和英语。
