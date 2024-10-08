# 一键安装 NaiveProxy + Hysteria + Xray

这个项目提供了一个一键安装脚本，用于快速部署 NaiveProxy、Hysteria 和 Xray 的联合使用。通过这个脚本，你可以轻松地搭建一个高性能的代理服务。

## 优化Linux

运行以下命令来优化Linux：

```
bash <(curl -fsSL "https://raw.githubusercontent.com/niu0506/naiveproxy-hysteria-Xray-install/main/bbr.sh" | tr -d '\r')

```

## 安装

运行以下命令来安装 NaiveProxy、Hysteria 和 Xray：

```
wget -P /root -N --no-check-certificate "https://raw.githubusercontent.com/niu0506/naiveproxy-hysteria-Xray-install/main/install.sh" && chmod 700 /root/install.sh && bash install.sh

```

## 配置文件

安装完成后，配置文件位于root目录下。

## 特别感谢

特别感谢以下项目的作者和贡献者：

- [Xray Install](https://github.com/xtls/Xray-core)
- [NaiveProxy](https://github.com/klzgrad/naiveproxy)
- [Hysteria](https://github.com/HyNetwork/hysteria)







