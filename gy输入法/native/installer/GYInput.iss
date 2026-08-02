#ifndef MyAppVersion
  #define MyAppVersion "0.9.13"
#endif
#ifndef MyTsfVersion
#define MyTsfVersion "0.9.13"
#endif
#define MyAppName "GY 输入法"
#define MyAppPublisher "GY Input Method"
#define MyPayloadDir AddBackslash(SourcePath) + "..\release\GYInput-" + MyAppVersion + "\payload"
#define MyLicenseDir AddBackslash(SourcePath) + "..\release\GYInput-" + MyAppVersion + "\LICENSES"
#define MyClassId "{5F689D3D-73E3-4C2B-979A-2DD86E438D6F}"
#define MyVersionRoot "{app}\versions\" + MyAppVersion
#define MyTsfRoot "{app}\tsf-" + MyTsfVersion

[Setup]
AppId={{5F689D3D-73E3-4C2B-979A-2DD86E438D6F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName=GY 输入法 {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\GYInput
DefaultGroupName=GY 输入法
DisableProgramGroupPage=yes
DisableDirPage=yes
DisableWelcomePage=no
DisableReadyPage=no
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#SourcePath}\..\release
OutputBaseFilename=GYInputSetup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
WizardImageFile={#SourcePath}\assets\gy-wizard-large.bmp
WizardSmallImageFile={#SourcePath}\assets\gy-wizard-small.bmp
SetupIconFile={#SourcePath}\assets\gy.ico
CloseApplications=no
RestartIfNeededByRun=no
UninstallDisplayName=GY 输入法
VersionInfoVersion={#MyAppVersion}
VersionInfoProductVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription=GY 输入法安装程序

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
SetupAppTitle=安装程序
SetupWindowTitle=安装 - %1
ButtonBack=< 上一步(&B)
ButtonNext=下一步(&N) >
ButtonInstall=安装(&I)
ButtonOK=确定
ButtonCancel=取消
ButtonYes=是(&Y)
ButtonNo=否(&N)
ButtonFinish=完成(&F)
ExitSetupTitle=退出安装
ExitSetupMessage=安装尚未完成。现在退出不会影响当前正在使用的输入法。%n%n以后可以随时重新运行安装程序。%n%n确定退出吗？
WelcomeLabel1=欢迎使用 [name] 安装程序
WelcomeLabel2=此安装程序会将 [name/ver] 安全安装到你的电脑。%n%n无需关闭微信、Chrome、ChatGPT 或其他正在使用的应用；新版本会与旧版本并存。
WizardInstalling=正在安装
InstallingLabel=正在准备 GY 输入法，请稍候…
FinishedHeadingLabel=GY 输入法安装完成
FinishedLabelNoIcons=GY 输入法已完成安装。
ClickFinish=点击“完成”退出安装程序。
ConfirmUninstall=确定要卸载 %1 吗？%n%n旧窗口可能仍在使用输入法；关闭它们后即可完全清理。
UninstallAppTitle=卸载程序
UninstallStatusLabel=正在从电脑中移除 %1，请稍候…
UninstalledAll=%1 已成功卸载。
UninstalledMost=%1 已完成卸载。%n%n少量正被应用使用的旧文件会在应用关闭后由系统清理。

[Files]
; Every release has a private DLL and Host, so installers never overwrite a
; module currently loaded by ChatGPT, Chrome, WeChat, or another application.
Source: "{#MyPayloadDir}\GyIme-{#MyAppVersion}.dll"; DestDir: "{#MyTsfRoot}"; DestName: "GyIme.dll"; Flags: onlyifdoesntexist
Source: "{#MyPayloadDir}\GyImeHost-{#MyAppVersion}.exe"; DestDir: "{#MyVersionRoot}"; Flags: onlyifdoesntexist
Source: "{#MyPayloadDir}\GyImeHealth-{#MyAppVersion}.exe"; DestDir: "{#MyVersionRoot}"; Flags: onlyifdoesntexist

Source: "{#SourcePath}\assets\gy.ico"; DestDir: "{#MyTsfRoot}"; Flags: onlyifdoesntexist
Source: "{#MyPayloadDir}\rime.dll"; DestDir: "{#MyVersionRoot}"; Flags: onlyifdoesntexist
Source: "{#MyPayloadDir}\rime-data\*"; DestDir: "{#MyVersionRoot}\rime-data"; Flags: onlyifdoesntexist recursesubdirs createallsubdirs
Source: "{#SourcePath}\Set-GYKeyboard.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourcePath}\Validate-GYInput.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourcePath}\Rollback-GYInput.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyLicenseDir}\*"; DestDir: "{app}\LICENSES"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Windows 输入法设置"; Filename: "{sys}\explorer.exe"; Parameters: "ms-settings:regionlanguage"
Name: "{group}\验证 GY 输入法安装"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Validate-GYInput.ps1"""
Name: "{group}\回退到上一版 GY 输入法"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Rollback-GYInput.ps1"""
Name: "{group}\卸载 GY 输入法"; Filename: "{uninstallexe}"

[Code]
var
  KeyboardAdded: Boolean;
  CoreConnectorIsNew: Boolean;
  PreviousDll: String;
  PreviousHost: String;
  PreviousHostVersion: String;
  PreviousHealth: String;
  PreviousStateAvailable: Boolean;

function VersionDirectory(): String;
begin
  Result := ExpandConstant('{#MyVersionRoot}');
end;

function StableDllPath(): String;
begin
  Result := ExpandConstant('{#MyTsfRoot}\GyIme.dll');
end;

function VersionHostPath(): String;
begin
  Result := AddBackslash(VersionDirectory()) + 'GyImeHost-{#MyAppVersion}.exe';
end;

function VersionHealthPath(): String;
begin
  Result := AddBackslash(VersionDirectory()) + 'GyImeHealth-{#MyAppVersion}.exe';
end;

function InstalledVersionDirectory(): String;
begin
  // InitializeSetup runs before {app} exists. Use the fixed all-users path
  // only for the early same-version/repair check.
  Result := ExpandConstant('{autopf}\GYInput\versions\{#MyAppVersion}');
end;

function InstalledStableDllPath(): String;
begin
  // InitializeSetup runs before {app} has been resolved.
  Result := ExpandConstant('{autopf}\GYInput\tsf-{#MyTsfVersion}\GyIme.dll');
end;
function ReleaseIsComplete(): Boolean;
var
  Directory: String;
begin
  Directory := InstalledVersionDirectory();
  Result := FileExists(InstalledStableDllPath()) and
            FileExists(AddBackslash(Directory) + 'GyImeHost-{#MyAppVersion}.exe') and
            FileExists(AddBackslash(Directory) + 'GyImeHealth-{#MyAppVersion}.exe') and
            FileExists(AddBackslash(Directory) + 'rime.dll') and
            DirExists(AddBackslash(Directory) + 'rime-data\shared');
end;

function RegisterGyTextService(): Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec(ExpandConstant('{sys}\regsvr32.exe'), '/s "' + StableDllPath() + '"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  if (not Result) or (ResultCode <> 0) then begin
    MsgBox('GY 输入法无法完成系统注册（错误代码：' + IntToStr(ResultCode) + '）。安装已停止，现有输入法不会受到影响。', mbError, MB_OK);
    Result := False;
  end;
end;

function VerifyNewHost(): Boolean;
var
  ResultCode: Integer;
begin
  // Validate the staged, versioned Host before registry activation. The prior
  // Host registration remains untouched on a failed check, so an update is
  // safely reversible without closing Chrome, WeChat, or any target app.
  Result := Exec(VersionHealthPath(), '', VersionDirectory(), SW_HIDE,
                 ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
  if not Result then begin
    MsgBox('GY 输入法未能通过新版离线引擎自检（错误代码：' + IntToStr(ResultCode) +
           '）。当前正在使用的版本保持不变；请保留此安装包并反馈该错误代码。', mbError, MB_OK);
  end;
end;
procedure RegisterGyHost();
begin
  RegWriteStringValue(HKLM64, 'SOFTWARE\GYInput', 'HostPath', VersionHostPath());
  RegWriteStringValue(HKLM64, 'SOFTWARE\GYInput', 'HostVersion', '{#MyAppVersion}');
end;

function JsonEscape(const Value: String): String;
begin
  Result := Value;
  StringChangeEx(Result, '\', '\\', True);
  StringChangeEx(Result, '"', '\"', True);
end;

function GyStateJson(const DllPath, HostPath, HostVersion, HealthPath: String): String;
begin
  Result := '{"dll":"' + JsonEscape(DllPath) + '","host":"' + JsonEscape(HostPath) +
            '","version":"' + JsonEscape(HostVersion) + '","hostVersion":"' + JsonEscape(HostVersion) +
            '","coreVersion":"{#MyTsfVersion}","health":"' + JsonEscape(HealthPath) + '"}';
end;

procedure CapturePreviousGyState();
var
  ActiveDll: String;
begin
  PreviousStateAvailable := False;
  PreviousDll := '';
  PreviousHost := '';
  PreviousHostVersion := '';
  PreviousHealth := '';
  if not RegQueryStringValue(HKLM64, 'SOFTWARE\Classes\CLSID\{#MyClassId}\InprocServer32', '', ActiveDll) then Exit;
  if not RegQueryStringValue(HKLM64, 'SOFTWARE\GYInput', 'HostPath', PreviousHost) then Exit;
  if not RegQueryStringValue(HKLM64, 'SOFTWARE\GYInput', 'HostVersion', PreviousHostVersion) then Exit;
  PreviousHealth := AddBackslash(ExtractFileDir(PreviousHost)) + 'GyImeHealth-' + PreviousHostVersion + '.exe';
  if (CompareText(ActiveDll, StableDllPath()) = 0) and (CompareText(PreviousHost, VersionHostPath()) = 0) then Exit;
  if FileExists(ActiveDll) and FileExists(PreviousHost) and FileExists(PreviousHealth) then begin
    PreviousDll := ActiveDll;
    PreviousStateAvailable := True;
  end;
end;

procedure SaveCapturedPreviousGyState();
begin
  if not PreviousStateAvailable then Exit;
  SaveStringToFile(ExpandConstant('{app}\install-state.previous.json'),
                   GyStateJson(PreviousDll, PreviousHost, PreviousHostVersion, PreviousHealth), False);
end;

procedure SaveActiveGyState();
begin
  SaveStringToFile(ExpandConstant('{app}\install-state.json'),
                   GyStateJson(StableDllPath(), VersionHostPath(), '{#MyAppVersion}', VersionHealthPath()), False);
end;

function UpdateKeyboardList(Add: Boolean): Boolean;
var
  ResultCode: Integer;
  Args: String;
begin
  if Add then
    Args := '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\Set-GYKeyboard.ps1') + '" -Add'
  else
    Args := '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\Set-GYKeyboard.ps1') + '" -Remove';
  Result := ExecAsOriginalUser(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Args, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := Result and (ResultCode = 0);
end;

function IsThisReleaseActive(): Boolean;
var
  ActiveDll: String;
begin
  Result := RegQueryStringValue(HKLM64, 'SOFTWARE\Classes\CLSID\{#MyClassId}\InprocServer32', '', ActiveDll) and
            (CompareText(ActiveDll, StableDllPath()) = 0);
end;

function IsThisHostReleaseActive(): Boolean;
var
  ActiveHost: String;
begin
  Result := RegQueryStringValue(HKLM64, 'SOFTWARE\GYInput', 'HostPath', ActiveHost) and
            (CompareText(ActiveHost, VersionHostPath()) = 0);
end;

function InitializeSetup(): Boolean;
begin
  CoreConnectorIsNew := not FileExists(InstalledStableDllPath());
  if ReleaseIsComplete() then begin
    if MsgBox('GY 输入法 {#MyAppVersion} 已安装。'#13#10#13#10'选择“是”可重新注册并修复键盘列表；选择“否”将保持当前状态。', mbConfirmation, MB_YESNO) = IDYES then begin
      Result := True;
    end else begin
      Result := False;
    end;
  end else begin
    Result := True;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then begin
    if not VerifyNewHost() then Abort;
    CapturePreviousGyState();
    if not RegisterGyTextService() then Abort;
    RegisterGyHost();
    SaveActiveGyState();
    SaveCapturedPreviousGyState();
    KeyboardAdded := UpdateKeyboardList(True);
    if not KeyboardAdded then begin
      MsgBox('GY 输入法已安装，但未能自动加入当前账户的键盘列表。请在随后打开的 Windows 输入法设置中添加“GY 输入法（拼音）”。', mbInformation, MB_OK);
    end;
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then begin
    if CoreConnectorIsNew then begin
      WizardForm.FinishedLabel.Caption := 'GY 输入法已准备就绪。'#13#10#13#10'现在按 Win + Space，选择“GY 输入法（拼音）”。'#13#10#13#10'这是一次核心兼容更新：无需重启 Windows。已打开的微信、Chrome、Office 等应用会继续安全使用旧 DLL；关闭后重新打开即可使用新版。';
    end else begin
      WizardForm.FinishedLabel.Caption := 'GY 输入法已准备就绪。'#13#10#13#10'这是一次 Host、词库与候选窗更新：无需关闭应用或重启 Windows；下一次输入将自动连接新版 Host。'#13#10#13#10'如需回退，可在开始菜单的“GY 输入法”中选择“回退到上一版”。';
    end;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  if CurUninstallStep = usUninstall then begin
    if IsThisReleaseActive() and IsThisHostReleaseActive() then begin
      Exec(ExpandConstant('{sys}\regsvr32.exe'), '/s /u "' + StableDllPath() + '"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      if not UpdateKeyboardList(False) then begin
        MsgBox('系统文件已移除，但无法自动更新当前账户的键盘列表。请在 Windows 输入法设置中手动移除 GY 输入法。', mbInformation, MB_OK);
      end;
    end;
    if IsThisHostReleaseActive() then begin
      RegDeleteValue(HKLM64, 'SOFTWARE\GYInput', 'HostPath');
      RegDeleteValue(HKLM64, 'SOFTWARE\GYInput', 'HostVersion');
    end;
  end;
end;




