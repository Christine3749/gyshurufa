# GY 输入法公开 Beta 签名流程

公开 Beta 必须使用受信任 CA 颁发、带私钥的 Windows Authenticode 代码签名证书；不能用自签名证书代替。

1. 先完成并保存 `release\approvals\x.y.z.json` 人工验收单；它必须记录源码／自动测试、回退、真实应用、隐私边界四项均已通过。
2. 执行 `package.ps1 -Version x.y.z -ApprovalPath <approval-json>`。
3. 在当前用户证书存储导入硬件令牌或证书服务提供的证书。
4. 运行：

```powershell
.\installer\Sign-GYRelease.ps1 -Version x.y.z -CertificateThumbprint <thumbprint> -TimestampServer <https RFC3161 endpoint> -ApprovalPath <approval-json>
```

脚本会签名 GY 的 TSF DLL、Host、Health Check，重建哈希清单与 ZIP，使用已签名 payload 重建 EXE，再签 EXE，最后以 `Verify-GYRelease.ps1 -RequireSignature` 强制验签。

没有完成该流程的二进制只能标为内测包，不得显示“已验证签名”或标注公开 Beta。没有验收单的草稿甚至不能生成发布 payload。
