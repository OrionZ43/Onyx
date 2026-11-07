# Свой сервер для Onyx на AWS (бесплатно, карта UnionPay) · 用银联卡在 AWS 免费搭建 Onyx 服务器

_Onyx VPN · 2026-11 · RU ниже, 中文在后半部分_

> **Коротко.** AWS с февраля 2025 принимает китайские карты **UnionPay**. Новый аккаунт получает **Free plan**: кредиты до $200 на срок до 6 месяцев, и без ручного перехода на платный план деньги не списываются. Сервер ставим в **Токио**, на нём одной командой запускается `onyx-server.sh`, а получившуюся строку вставляем в Onyx.
>
> Что проверено, а что нет:
> - Скрипт и связка «Onyx ↔ сервер» проверены локально: REALITY и Hysteria2 работают, HTTPS и UDP проходят.
> - Регистрацию AWS из Китая и доступность сервера из сети China Unicom мы проверить не можем. Это проверяет друг.

---

## Русский

### 0. Что понадобится
- Карта **China UnionPay** (кредитная) на своё имя.
- Китайское удостоверение личности: AWS просит верификацию личности для аккаунтов с UnionPay.
- Номер телефона +86 и e-mail.
- 30–60 минут.

### 1. Регистрация AWS
1. Откройте <https://aws.amazon.com> → **Create an AWS Account**. Регистрируйтесь **без VPN**, с обычного домашнего интернета: страна IP, адрес и карта должны совпадать.
2. Введите e-mail и имя аккаунта, подтвердите почту, задайте пароль.
3. Contact information: **Personal**, страна **China**. Адрес пишите латиницей или пиньинем, как в выписке по карте.
4. Billing information: выберите **China UnionPay**, введите данные карты и пройдите **верификацию личности**. Проверка может занять до одного рабочего дня.
5. Подтвердите телефон (SMS или звонок).
6. Support plan: **Basic (бесплатный)**.
7. Если предложат выбор плана, выберите **Free plan**, не Paid. Free plan сам закрывается по окончании кредитов или срока и **не списывает деньги**.
8. Сразу после входа: **Billing → Budgets → Create budget → Zero spend budget**. AWS пришлёт письмо, если что-то начнёт стоить денег.

### 2. Сервер: вариант А — Lightsail (проще, рекомендую)
1. Консоль AWS → в поиске **Lightsail** → **Create instance**.
2. Region: **Tokyo (ap-northeast-1)**. Если в Токио не дают, подойдёт **Seoul** или **Singapore**.
3. Platform: **Linux/Unix** → **OS Only** → **Ubuntu 24.04 LTS**.
4. Plan: самый дешёвый тариф с IPv4 (~$5). Если рядом написано «free for 3 months», это то, что нужно. Если Lightsail недоступен на Free plan, переходите к варианту Б.
5. **Create instance** и подождите 1–2 минуты.
6. Вкладка **Networking**:
   - **Attach static IP**: создать и привязать. Пока IP привязан, он бесплатный.
   - **IPv4 Firewall → Add rule**, добавить три правила:
     - Custom · **TCP** · порт **443**
     - Custom · **UDP** · порт **443**
     - Custom · **UDP** · порты **20000–50000**
7. Вкладка **Connect** → **Connect using SSH**: откроется терминал в браузере.

### 2. Сервер: вариант Б — EC2
1. Консоль → **EC2**, справа вверху регион **Asia Pacific (Tokyo)** → **Launch instance**.
2. Name: `onyx`. AMI: **Ubuntu Server 24.04 LTS**. Instance type: **t3.micro** (или t4g.small для ARM; оба помечены «Free tier eligible»).
3. Key pair: **Proceed without a key pair**, подключаться будем из браузера.
4. Network settings → **Edit** → Security group, Inbound rules:
   - SSH · TCP 22 · Source **My IP**
   - Custom TCP · **443** · 0.0.0.0/0
   - Custom UDP · **443** · 0.0.0.0/0
   - Custom UDP · **20000-50000** · 0.0.0.0/0
5. **Launch instance**. Дождитесь статуса Running → **Connect → EC2 Instance Connect → Connect**.

### 3. Установка Onyx-сервера (одна команда)
В терминале сервера вставьте:

```bash
curl -fsSL https://raw.githubusercontent.com/OrionZ43/Onyx/main/tools/server/onyx-server.sh | sudo bash
```

> Пока ветка `feat/china` не влита в `main`, этой ссылки ещё нет. Тогда скопируйте файл `tools/server/onyx-server.sh` на сервер любым способом и запустите `sudo bash onyx-server.sh`.

Через 1–2 минуты скрипт напечатает **строку подписки**: длинную строку из букв и цифр. Её же можно показать снова:

```bash
sudo cat /etc/onyx/subscription.txt
```

Скрипт делает следующее:
- ставит sing-box 1.14.4 и сверяет SHA-256;
- создаёт ключи;
- поднимает **VLESS REALITY** (TCP 443) и **Hysteria2** (UDP 443 + port hopping 20000–50000);
- открывает порты в iptables;
- включает BBR;
- регистрирует автозапуск (systemd).

Повторный запуск безопасен: ключи сохраняются. Новые ключи — `--regen`, удаление — `--uninstall`.

### 4. Подключить в Onyx
1. Скопируйте строку подписки, например через «Избранное» WeChat.
2. Onyx → **«Подписки и серверы»** → **«Добавить серверы или источник»** → вставьте строку целиком (это не URL, Onyx понимает и так) → **Сохранить**.
3. Появятся два сервера: **Onyx REALITY** и **Onyx Hysteria2**. Подключайтесь к любому: Onyx сам объединит их в группу и переключится на живой транспорт.

### 5. Если не работает
- **Не подключается ни один сервер.** Проверьте правила Firewall/Security group (п. 2). Проверьте на сервере: `sudo systemctl status onyx-singbox`.
- **REALITY работает, Hysteria2 нет.** Провайдер душит UDP. Работайте через REALITY: голос Discord всё равно пойдёт, внутри TCP.
- **Вчера работало, сегодня нет.** IP мог попасть под блокировку. Lightsail: отвяжите static IP и создайте новый. EC2: Stop → Start даёт новый IP. Затем снова `sudo bash onyx-server.sh` (ключи те же) и обновите подписку в Onyx: изменился только IP.
- **Через 6 месяцев** Free plan закончится и сервер удалится. Можно зарегистрировать новый аккаунт или перейти на платный план (Lightsail ~$5/мес).

---

## 中文（简体）

> **简要说明**：自 2025 年 2 月起，AWS 支持使用中国**银联**信用卡注册。新账户可选择 **Free plan（免费计划）**：最多 $200 抵扣额度，最长 6 个月；不手动升级就**不会扣费**。我们在**东京**创建服务器，运行一条命令安装 `onyx-server.sh`，再把输出的字符串粘贴到 Onyx 即可。
> 已在本地测试脚本与 Onyx 的连接（REALITY 和 Hysteria2 均可，HTTPS 与 UDP 正常）；从中国联通网络的实际效果需要你亲自测试。

### 0. 准备
- 本人名下的**银联信用卡**；
- 中国身份证（银联注册需要身份验证）；
- +86 手机号和邮箱；
- 大约 30–60 分钟。

### 1. 注册 AWS
1. 打开 <https://aws.amazon.com> → **Create an AWS Account**。请**关闭 VPN**，用家里的正常网络注册：IP 所在国家、地址和银行卡要一致。
2. 填写邮箱和账户名，验证邮箱，设置密码。
3. Contact information：选择 **Personal（个人）**，国家选 **China**。地址用拼音或英文填写，与信用卡账单地址一致。
4. Billing information：选择 **China UnionPay（银联）**，填写卡信息并完成**身份验证**（审核最多需要 1 个工作日）。
5. 手机验证（短信或语音电话）。
6. Support plan：选 **Basic（免费）**。
7. 如果出现计划选择，请选 **Free plan**，不要选 Paid。Free plan 到期或额度用完会自动关闭，**不会扣钱**。
8. 登录后立刻设置：**Billing → Budgets → Create budget → Zero spend budget**，一旦产生费用会发邮件提醒。

### 2. 服务器：方案 A — Lightsail（更简单，推荐）
1. 控制台搜索 **Lightsail** → **Create instance**。
2. Region：**Tokyo (ap-northeast-1)**（不行就选 **Seoul** 或 **Singapore**）。
3. Platform：**Linux/Unix** → **OS Only** → **Ubuntu 24.04 LTS**。
4. Plan：选最便宜、带 IPv4 的套餐（约 $5）。如果旁边写着 “free for 3 months” 就选它。如果 Free plan 下不能用 Lightsail，请使用方案 B。
5. 点 **Create instance**，等待 1–2 分钟。
6. 打开 **Networking** 选项卡：
   - **Attach static IP**：创建并绑定静态 IP（绑定期间免费）；
   - **IPv4 Firewall → Add rule**，添加三条规则：
     - Custom · **TCP** · 端口 **443**
     - Custom · **UDP** · 端口 **443**
     - Custom · **UDP** · 端口 **20000–50000**
7. 打开 **Connect** 选项卡 → **Connect using SSH**（浏览器里会打开终端）。

### 2. 服务器：方案 B — EC2
1. 控制台 → **EC2**，右上角区域选 **Asia Pacific (Tokyo)** → **Launch instance**。
2. 名称 `onyx`；系统镜像 **Ubuntu Server 24.04 LTS**；实例类型 **t3.micro**（或 ARM 的 t4g.small，都标有 “Free tier eligible”）。
3. Key pair：**Proceed without a key pair**（用浏览器连接）。
4. Network settings → **Edit** → 安全组入站规则：
   - SSH · TCP 22 · 来源 **My IP**
   - Custom TCP · **443** · 0.0.0.0/0
   - Custom UDP · **443** · 0.0.0.0/0
   - Custom UDP · **20000-50000** · 0.0.0.0/0
5. **Launch instance**，状态变为 Running 后 → **Connect → EC2 Instance Connect → Connect**。

### 3. 安装 Onyx 服务端（一条命令）
在服务器终端粘贴：

```bash
curl -fsSL https://raw.githubusercontent.com/OrionZ43/Onyx/main/tools/server/onyx-server.sh | sudo bash
```

> 如果 `feat/china` 分支尚未合并到 `main`，上面的链接还不存在。请先把 `tools/server/onyx-server.sh` 文件传到服务器上，再运行 `sudo bash onyx-server.sh`。

1–2 分钟后脚本会输出一行很长的**订阅字符串**。之后也可以用下面的命令再次查看：

```bash
sudo cat /etc/onyx/subscription.txt
```

脚本会：
- 安装 sing-box 1.14.4（校验 SHA-256）；
- 生成密钥；
- 启动 **VLESS REALITY**（TCP 443）和 **Hysteria2**（UDP 443，端口跳跃 20000–50000）；
- 在 iptables 中放行端口；
- 开启 BBR；
- 设置开机自启（systemd）。

可以重复运行：密钥会保留。`--regen` 重新生成密钥，`--uninstall` 卸载。

### 4. 在 Onyx 中添加
1. 复制订阅字符串（例如通过微信「文件传输助手」）。
2. Onyx → **«Подписки и серверы»** → **«Добавить серверы или источник»** → 粘贴整行（不是网址也没关系，Onyx 能识别）→ 保存。
3. 会出现两个服务器：**Onyx REALITY** 和 **Onyx Hysteria2**。连接任意一个即可，Onyx 会自动把它们组成一组并在故障时切换。

### 5. 常见问题
- **两个都连不上**：检查上面第 2 步的防火墙 / 安全组规则；在服务器上执行 `sudo systemctl status onyx-singbox`。
- **REALITY 能用，Hysteria2 不能用**：运营商在限制 UDP。用 REALITY 也可以，Discord 语音会通过 TCP 隧道传输。
- **昨天能用，今天不能用**：IP 可能被封。Lightsail：解绑静态 IP 再新建一个；EC2：先 Stop 再 Start 会换新 IP。然后再次运行 `sudo bash onyx-server.sh`（密钥不变），并在 Onyx 中更新订阅（只是 IP 变了）。
- **6 个月后** Free plan 结束，服务器会被删除。可以重新注册新账户，或升级为付费（Lightsail 约 $5/月）。
