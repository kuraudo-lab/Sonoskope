# 纯系统层会议音频诊断：观察边界

用户已明确不依赖 Zoom / Teams 接口。以下是产品边界推断，平台资料仅用于解释哪些信息属于应用内部。

- 系统层设备状态、音频流格式及可取得的音频样本，有助于发现设备切换、静音、低电平、削波、明显中断等问题，但不能单凭这些信号证明远端实际听到的声音正常。
- 本地麦克风录音不等于会议应用经降噪、自动增益、回声消除和编码后发送的音频；进程输出捕获也不等于其上行音频。应把“本地采集正常”和“通话发送正常”分开表达。
- 系统网络连通性或主动探测不能替代正在进行的会议媒体流的丢包、抖动和延迟统计。若不读取平台内部指标，诊断应给出关联证据与候选原因，不能把普通 ping 正常当作 Teams 网络正常的证明。
- 主动打开蓝牙耳机麦克风可能改变设备工作状态，测试本身可能影响音频；应把被动观察与用户触发的主动测试区分，记录测试前后状态。这是工程设计建议，需要实机验证。
- 推荐输出“已观察事实 + 可能原因 + 下一步对照测试”，而非无依据的综合音质分数或确定性根因。

## 已查官方资料（不作为产品集成依赖）

- [Teams Call health](https://support.microsoft.com/en-gb/teams/meetings/monitor-call-and-meeting-quality-in-microsoft-teams?trk=article-ssr-frontend-pulse_little-text-block)：应用自身显示 RTT、接收抖动、丢包和编解码器等指标，每 15 秒更新。这说明会议媒体质量存在系统设备属性之外的一层可观察数据。
- [Zoom statistics](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0070504)：应用统计包含音频采样率、延迟、抖动和丢包。
- [Graph callRecords](https://learn.microsoft.com/en-us/graph/api/callrecords-callrecord-get?view=graph-rest-1.0)：记录在通话结束后生成，需应用权限 CallRecords.Read.All，不支持委托权限，不适合作为普通个人桌面工具的即时诊断依赖。

这里只确认了上述平台官方文档；macOS API 能力与进程捕获的具体行为需由主研究核实。
