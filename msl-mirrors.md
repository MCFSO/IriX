---
icon: cloud
title: MSL 服务端镜像源
createTime: 2025/10/12 21:39:20
permalink: /docs/msl/msl-mirrors/
---
<CardGrid>
<LinkCard title="在线下载" href="https://dl.mslmc.cn" icon="cloud" description="前往MSL服务端镜像独立站下载资源。" />
<LinkCard title="在线下载(用户中心)" href="https://user.mslmc.net/mc-tools/download-server-core" icon="cloud" description="前往MSL用户中心的服务端镜像下载页面下载资源。" />
<LinkCard title="API文档" href="https://apidoc-v4.mslmc.cn/api-429587266" icon="book" description="基于Apifox的MSL-API-V4的服务端镜像下载API。" />

<Card title="QWQ?" icon="heart"> 

![](./assets/ef8c86003ce5397d98ecce574ffeed9e_5817017236091018001.png)

 </Card>

</CardGrid>



## 简介

MSL服务端镜像源为 ==MSLTeam== 自主研发的MC服务端镜像源同步系统，支持诸多常用的MC服务端，且会定期从各服务端官方API拉取更新。  

目前大部分服务端均在MSL服务器做了镜像，下载速度 ==非常快==~

部分服务端来自第三方源（如Forge端返回的是来自BMCL的下载地址）。

::: important 开发须知

MSL 服务端镜像源大部分采用了 ==自建加速镜像源=={.important}，搭配了全球加速CDN，存在流量成本。因此，如果您需要使用我们的服务，请遵守以下规则，若发现违反的行为，我们有可能会在不通知的情况下在后端对相关请求进行屏蔽操作。

- 如果您需要在您的软件/应用中集成我们的下载服务，请务必在 ==使用本API的软件页面=={.important} 注明 `本服务由MSL开服器提供`，并带上我们的 ==Logo以及官网地址=={.important} 。
- 对于使用量大的情况，请务必向 `support@mslmc.net` 发送邮件进行相应申请，并带上您应用所使用的UA。

:::

## MSL服务端镜像源API文档（概述版）

::: tip API信息
API端点地址：

```
https://api.mslmc.cn/v4
```
MSL-API-V4 通用返回格式:
```json
{
  "code": 200,
  "message": "",
  "data": ""
}
```

单IP QPS限制：中国大陆地区  ==20 QPS== | 海外(含港澳台) ==100 QPS==

请求API时请带上含有相应APP名字的 ==User-Agent==

:::

### 1.查询镜像源支持的服务端

<Badge type="tip" text="方法: GET"  />

```
/mirrors
```

返回服务端列表（分类显示），示例:

```json
{
  "code": 200,
  "message": "",
  "data": {
    "pluginsCore": [
      "paper",
      "purpur",
      "leaf",
      "spigot",
      "bukkit",
      "folia",
      "leaves",
      "pufferfish",
      "pufferfish_purpur",
      "spongevanilla"
    ],
    "pluginsAndModsCore_Forge": [
      "arclight-forge",
      "arclight-neoforge",
      "youer",
      "mohist",
      "catserver",
      "spongeforge"
    ],
    "pluginsAndModsCore_Fabric": [
      "arclight-fabric",
      "banner"
    ],
    "modsCore_Forge": [
      "neoforge",
      "forge"
    ],
    "modsCore_Fabric": [
      "fabric",
      "quilt"
    ],
    "vanillaCore": [
      "vanilla",
      "vanilla-snapshot"
    ],
    "bedrockCore": [
      "bedrock-server",
      "nukkitx"
    ],
    "proxyCore": [
      "velocity",
      "bungeecord",
      "lightfall",
      "travertine"
    ]
  }
}
```

<Badge type="tip" text="方法: GET"  />

```
/mirrors?view=list
```

返回服务端列表（无分类），示例:

```json
{
  "code": 200,
  "message": "",
  "data": [
    "paper",
    "purpur",
    "leaf",
    "leaves",
    "spigot",
    "arclight-forge",
    "arclight-fabric",
    "arclight-neoforge",
    "spongevanilla",
    "youer",
    "mohist",
    "catserver",
    "banner",
    "spongeforge",
    "neoforge",
    "forge",
    "fabric",
    "bukkit",
    "vanilla",
    "vanilla-snapshot",
    "folia",
    "lightfall",
    "pufferfish",
    "pufferfish_purpur",
    "travertine",
    "bungeecord",
    "velocity",
    "bedrock-server",
    "nukkitx",
    "quilt"
  ]
}
```

### 2.查询服务端支持的MC版本

<Badge type="tip" text="方法: GET"  />
:::: field-group

::: field name="server" type="String" required 
服务端名字（从上一步获取到的）
:::

::::

```
/mirrors/{server}
```

返回支持的MC版本列表（数组），示例:

```json
{
  "code": 200,
  "message": "",
  "data": {
    "description": "[原版端推荐]Paper是基于Spigot的高性能Fork,仅支持插件",
    "versions": [
      "26.1.1",
      "1.21.11",
      "1.21.10",
      "1.21.9"
    ]
  }
}
```

### 3.查询特定MC版本的服务端下载地址
::: important 防滥用限制
本接口具有特殊的请求限制  
1小时:  ==30次=={.important}  1天:  ==60次=={.important} 
:::

<Badge type="tip" text="方法: GET"  />

:::: field-group

::: field name="server" type="String" required 
服务端名字
:::

::: field name="version" type="String" required 
MC版本号
:::

::::



```
/download/server/{server}/{version}
```

返回下载地址链接和校验值（如果有），示例:

```json
{
  "code": 200,
  "message": "",
  "data": {
    "url": "https://file.mslmc.cn/servers/xxx/xxx.jar",
    "sha256": "933514c5ff8df47ab8fdb106ad435945bf6512702f9299cc66c4d173a1b7062x"
  }
}
```

::: warning 注意

并非所有服务端下载都会返回 ==sha256=={.warning} 这个key！

也有可能是这样的:

```json
{
  "code": 200,
  "message": "",
  "data": {
    "url": "https://file.mslmc.cn/mirrors/vanilla/xxx/server.jar"
  }
}
```

:::

### 其他API

我们还支持获取各服务端的简介，服务端分类，部分服务端支持下载不同的构建版本的api接口，这些请参考Apifox文档啦~

<LinkCard title="API文档" href="https://apidoc-v4.mslmc.cn/api-429587266" icon="book" description="基于Apifox的MSL-API-V4的服务端镜像下载API。" />