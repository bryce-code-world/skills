# AI 方向包

本文件只定义 AI 方向“查什么”。共享来源读取 [sources.md](sources.md)，目标用户画像和注意力权重读取 [audiences.md](audiences.md)。

## 导航

- [范围与边界](#范围与边界)
- [重点主题与事件类型](#重点主题与事件类型)
- [查询配置](#查询配置)
- [实体观察名单](#实体观察名单)
- [企业观察名单](#企业观察名单)
- [默认目标用户群](#默认目标用户群)
- [AI 特有高质量来源](#ai-特有高质量来源)
- [事件影响特征](#事件影响特征)

## 范围与边界

纳入能够改变 AI 能力、使用方式、开发生态、产业结构、规则或公众认知的事件：

- 模型、产品、Agent、平台和关键基础设施变化；
- 开源项目、开发工具、算力、芯片、数据与安全事件；
- 论文、实验室成果、专利布局、独立评测和复现；
- AI 相关政策、监管、标准、诉讼和治理；
- 大企业的投资、采购、组织、财报、合作和商业化；
- 对 AI 采用和公共认知产生实际影响的人物与文化事件。

排除只换标题的旧闻、没有新增事实的传闻、只靠榜单微小波动制造的比较、与 AI 实际影响无关的明星八卦，以及无法回到原始来源的营销摘要。

## 重点主题与事件类型

| 主题 | 重点事件 |
| --- | --- |
| 模型与产品 | 发布、开放、降价、限额、能力变化、故障、下线和入口调整 |
| 开源与开发者 | 开源、换许可、重大 Release、生态迁移、供应链风险和生产采用 |
| 研究与知识产权 | 论文、实验室成果、数据或代码开放、复现、撤回、专利公开和授权 |
| 政策与治理 | 草案、征求意见、通过、生效、执法、诉讼、标准和安全评测 |
| 企业与产业 | 投资、融资、并购、采购、财报、资本开支、合作、组织调整和客户采用 |
| 人物与公众 | 能够改变采用、监管、市场或公共认知的声明、行动和争议 |

## 查询配置

| 维度 | 查询内容 |
| --- | --- |
| 核心概念 | artificial intelligence、AI、大模型、LLM、multimodal、agent、reasoning、inference、training |
| 产品能力 | model、API、benchmark、pricing、context、tool use、coding、voice、video、robotics |
| 研究产权 | arXiv 分类、论文主题、实验室、作者、专利申请人、CPC/IPC 分类 |
| 政策风险 | AI Act、model safety、copyright、privacy、security、standards、evaluation、governance |
| 企业产业 | capex、data center、chip、cloud、partnership、acquisition、earnings、customer adoption |

关键词只负责召回。候选是否属于 AI 方向，最终按主体、核心动作和实际影响判断。

## 实体观察名单

以下是初始观察集合，不是实力排名，也不是封闭名单。每次研究按时间窗、地区和目标用户补充新主体，并核对当前正式名称、官网和存续状态。

| 实体组 | 初始观察对象 |
| --- | --- |
| 国际模型与研究组织 | OpenAI、Anthropic、Google DeepMind、Meta AI、xAI、Mistral AI、Cohere、AI2、Hugging Face |
| 中国模型与研究组织 | DeepSeek、阿里通义千问、智谱 GLM、月之暗面 Kimi、MiniMax、百度文心、腾讯混元、字节豆包、华为盘古、阶跃星辰 |
| 云与企业平台 | Microsoft Azure、AWS、Google Cloud、Oracle、Salesforce、ServiceNow、SAP、Adobe、阿里云、腾讯云、百度智能云 |
| 芯片与基础设施 | NVIDIA、AMD、Intel、TSMC、Broadcom、ASML、Samsung、SK hynix、华为昇腾 |
| 开源项目与组织 | PyTorch、vLLM、llama.cpp、Ollama、LangChain、LlamaIndex、Model Context Protocol 及主要模型官方仓库 |
| 研究与治理机构 | Stanford HAI、MIT CSAIL、BAIR、NIST CAISI、英国 AISI、欧盟 AI Office、OECD.AI、中国 AI 相关主管部门 |

人物不维护永久明星榜。只在当事人的行为或言论可能改变 AI 采用、政策、产业或公众认知时，按事件临时加入观察。

## 企业观察名单

企业观察采用“固定种子 + 任务增量”，不在 Skill 中复制完整 Global 500：

1. 固定观察模型、云、芯片、数据中心、企业软件和关键开源生态主体；
2. 按目标用户所在行业，从 Fortune Global 500、Forbes Global 2000、交易所名单或行业龙头中补充企业；
3. 优先捕捉正式财报、监管披露、资本开支、采购、产品、组织和客户变化；
4. 榜单只提供观察对象，不构成热点事实或影响证据；
5. 企业改名、合并、退市或业务重组后，以当前官方披露更新本轮实体名。

## 默认目标用户群

AI 方向默认支持以下用户画像 ID，具体权重和渠道基线见 [audiences.md](audiences.md)：

- `developer`：开发者；
- `product-founder`：产品经理与创业者；
- `enterprise-leader`：企业管理者；
- `investor-industry`：投资与产业人群；
- `general-tech`：普通科技读者。

用户明确指定更具体读者时，以用户定义覆盖默认画像，不改写方向范围和事实门禁。

## AI 特有高质量来源

这些来源只补充共享信源，不复制共享目录：

| 来源 | 作用 | 质量边界 |
| --- | --- | --- |
| 主要模型组织的官方新闻、文档、模型卡、系统卡和代码仓库 | 模型、产品、研究和平台原始变化 | 官方自评不能代替独立测试 |
| 国内主要模型组织、云厂商和官方开源组织的公告、文档与模型仓库 | 中文市场模型、产品、价格和生态变化 | 区分正式发布、灰度开放、邀测和路线图 |
| [NIST CAISI](https://www.nist.gov/caisi)、[英国 AISI](https://www.aisi.gov.uk/research)、[欧盟 AI Office](https://digital-strategy.ec.europa.eu/en/policies/ai-office) 及各地 AI 专责机构 | 前沿评测、治理、政策和安全研究 | 研究报告、指南和强制法规的法律效力不同 |
| Stanford HAI、MIT CSAIL、BAIR 等 AI 研究机构官方页面 | 研究发现、实验室和作者入口 | 机构发布不能代替论文限制和外部复现 |
| LM Arena、Artificial Analysis、Epoch AI、METR 等专业评测或分析机构 | 独立能力、成本、趋势和风险信号 | 核对方法、样本、版本、赞助关系和可复现性 |
| [AI HOT](https://aihot.virxact.com) 等 AI 聚合服务 | 快速发现中文候选 | 模型摘要和聚合内容不能作为事实来源 |

## 事件影响特征

方向包只提取事件特征，不替目标用户决定权重：

| 事件类型 | 优先提取的影响特征 |
| --- | --- |
| 模型与产品 | 能力差异、真实可用性、价格、速度、限制、入口和替代关系 |
| 开源与开发者 | 许可、部署成本、兼容性、维护者可信度、采用速度和实际问题 |
| 论文、实验室与专利 | 新颖性、实验条件、代码数据、复现、法律状态和产业时间尺度 |
| 政策与治理 | 法律阶段、覆盖范围、生效时间、义务、处罚、合规成本和执行可能性 |
| 企业与产业 | 投入规模、收入或成本影响、客户覆盖、供应链、竞争反应和兑现周期 |
| 人物与大众文化 | 身份真实性、跨圈扩散、行为改变、公共利益和与 AI 的实质关联 |
