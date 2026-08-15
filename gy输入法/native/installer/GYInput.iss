#ifndef MyAppVersion
  #error "MyAppVersion must be supplied by build-installer.ps1"
#endif
#ifndef MyTsfVersion
#error "MyTsfVersion must be supplied by build-installer.ps1"
#endif
#define MyAppName "GY 输入法"
#define MyAppPublisher "GY Input Method"
#define MyAppId "GYInput"
#define MyPayloadDir AddBackslash(SourcePath) + "..\release\GYInput-" + MyAppVersion + "\payload"
#define MyLicenseDir AddBackslash(SourcePath) + "..\release\GYInput-" + MyAppVersion + "\LICENSES"
#define MyClassId "{5F689D3D-73E3-4C2B-979A-2DD86E438D6F}"
#define MyVersionRoot "{app}\versions\" + MyAppVersion
#define MyTsfRoot "{app}\tsf-" + MyTsfVersion

[Setup]
; Product identity must remain stable across upgrades.  The previous
; version-qualified AppId made every update appear as a separate installed app.
AppId={#MyAppId}
UninstallFilesDir={app}\uninstall
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
Source: "{#SourcePath}\assets\gy.ico"; DestDir: "{#MyVersionRoot}"; Flags: onlyifdoesntexist
; Keep the TSF profile icon at a stable path so Windows' language-bar cache
; never points at a removed version directory after an upgrade.
Source: "{#SourcePath}\assets\gy.ico"; DestDir: "{app}"; DestName: "gy.ico"; Flags: ignoreversion uninsneveruninstall onlyifdoesntexist; Check: ShouldInstallSharedHelpers
Source: "{#MyPayloadDir}\release-notes.txt"; DestDir: "{#MyVersionRoot}"; DestName: "RELEASE-NOTES.txt"; Flags: onlyifdoesntexist
Source: "{#MyPayloadDir}\rime.dll"; DestDir: "{#MyVersionRoot}"; Flags: onlyifdoesntexist
Source: "{#MyPayloadDir}\rime-data\*"; DestDir: "{#MyVersionRoot}\rime-data"; Flags: onlyifdoesntexist recursesubdirs createallsubdirs
Source: "{#MyPayloadDir}\english-lexicon\*"; DestDir: "{#MyVersionRoot}\english-lexicon"; Flags: onlyifdoesntexist recursesubdirs createallsubdirs
Source: "{#SourcePath}\Set-GYKeyboard.ps1"; DestDir: "{app}"; Flags: ignoreversion uninsneveruninstall; Check: ShouldInstallSharedHelpers
Source: "{#SourcePath}\Migrate-GYLegacyInstallEntries.ps1"; DestDir: "{app}"; Flags: ignoreversion uninsneveruninstall; Check: ShouldInstallSharedHelpers
Source: "{#SourcePath}\Validate-GYInput.ps1"; DestDir: "{app}"; Flags: ignoreversion uninsneveruninstall; Check: ShouldInstallSharedHelpers
Source: "{#SourcePath}\Get-GYLoadedClientState.ps1"; DestDir: "{app}"; Flags: ignoreversion uninsneveruninstall; Check: ShouldInstallSharedHelpers
Source: "{#SourcePath}\Get-GYKeepHealth.ps1"; DestDir: "{app}"; Flags: ignoreversion uninsneveruninstall; Check: ShouldInstallSharedHelpers
Source: "{#SourcePath}\Rollback-GYInput.ps1"; DestDir: "{app}"; Flags: ignoreversion uninsneveruninstall; Check: ShouldInstallSharedHelpers
Source: "{#SourcePath}\Repair-GYInput.ps1"; DestDir: "{app}"; Flags: ignoreversion uninsneveruninstall; Check: ShouldInstallSharedHelpers
Source: "{#SourcePath}\AutoUpdate-GYInput.ps1"; DestDir: "{app}"; Flags: ignoreversion uninsneveruninstall; Check: ShouldInstallSharedHelpers
Source: "{#SourcePath}\Sync-GYEnglishLexicon.ps1"; DestDir: "{app}"; Flags: ignoreversion uninsneveruninstall; Check: ShouldInstallSharedHelpers
Source: "{#SourcePath}\Prune-GYOldVersions.ps1"; DestDir: "{app}"; Flags: ignoreversion uninsneveruninstall; Check: ShouldInstallSharedHelpers
Source: "{#SourcePath}\GYInputTransaction.ps1"; DestDir: "{app}"; Flags: ignoreversion uninsneveruninstall; Check: ShouldInstallSharedHelpers
Source: "{#SourcePath}\Finalize-GYClientReload.ps1"; DestDir: "{commonappdata}\GYInput"; Flags: ignoreversion uninsneveruninstall; Check: ShouldInstallSharedHelpers
Source: "{#SourcePath}\Prune-GYOldVersions.ps1"; DestDir: "{commonappdata}\GYInput"; Flags: ignoreversion uninsneveruninstall; Check: ShouldInstallSharedHelpers
Source: "{#SourcePath}\GYInputTransaction.ps1"; DestDir: "{commonappdata}\GYInput"; Flags: ignoreversion uninsneveruninstall; Check: ShouldInstallSharedHelpers
Source: "{#SourcePath}\Register-GYInputActivationTasks.ps1"; DestDir: "{app}"; Flags: ignoreversion uninsneveruninstall; Check: ShouldInstallSharedHelpers
Source: "{#SourcePath}\Register-GYInputActivationTasks.ps1"; DestDir: "{commonappdata}\GYInput"; Flags: ignoreversion uninsneveruninstall; Check: ShouldInstallSharedHelpers
Source: "{#MyLicenseDir}\*"; DestDir: "{app}\LICENSES"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Windows 输入法设置"; Filename: "{sys}\explorer.exe"; Parameters: "ms-settings:regionlanguage"
Name: "{group}\GY 输入法"; Filename: "{app}\versions\{#MyAppVersion}\GyImeHost-{#MyAppVersion}.exe"; WorkingDir: "{app}"; IconFilename: "{app}\gy.ico"; AppUserModelID: "GYInput.Desktop"
Name: "{group}\验证 GY 输入法安装"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Validate-GYInput.ps1"""
Name: "{group}\整备 GY 输入法"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Repair-GYInput.ps1"""
Name: "{group}\回退到上一版 GY 输入法"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Rollback-GYInput.ps1"""
Name: "{group}\卸载 GY 输入法"; Filename: "{uninstallexe}"

[Code]
function GYCreateMutex(lpMutexAttributes: Integer; bInitialOwner: Boolean; lpName: String): Integer;
  external 'CreateMutexW@kernel32.dll stdcall';
function GYGetLastError(): Integer;
  external 'GetLastError@kernel32.dll stdcall';
function GYCloseHandle(hObject: Integer): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';
var
  ActivationPending: Boolean;
  PreviousDll: String;
  PreviousHost: String;
  PreviousHostVersion: String;
  PreviousHealth: String;
  ActivationMutexHandle: Integer;
  PreviousStateAvailable: Boolean;

function AcquireActivationMutex(): Boolean;
begin
  ActivationMutexHandle := GYCreateMutex(0, True, 'Global\GYInputFinalizePending');
  if ActivationMutexHandle = 0 then begin
    Result := False;
    Exit;
  end;
  if GYGetLastError() = 183 then begin
    GYCloseHandle(ActivationMutexHandle);
    ActivationMutexHandle := 0;
    Result := False;
    Exit;
  end;
  Result := True;
end;
procedure ReleaseActivationMutex();
begin
  if ActivationMutexHandle <> 0 then begin
    GYCloseHandle(ActivationMutexHandle);
    ActivationMutexHandle := 0;
  end;
end;
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

function PendingActivationPath(): String;
begin
  Result := ExpandConstant('{autopf}\GYInput\pending-activation.json');
end;

function CommonFinalizerPath(): String;
begin
  Result := ExpandConstant('{commonappdata}\GYInput\Finalize-GYClientReload.ps1');
end;

function PendingTaskName(): String;
begin
  Result := 'GYInput\ActivatePending';
end;

function LegacyPendingTaskNameLogon(): String;
begin
  Result := 'GYInput\ActivatePendingLogon';
end;

function GYSchtasksPath(): String;
begin
  // Setup is a 32-bit process even on x64 Windows. Use the native task
  // scheduler binary so the SYSTEM task is registered in the same scheduler
  // namespace used by the 64-bit PowerShell Finalizer.
  Result := ExpandConstant('{sysnative}\schtasks.exe');
end;

function GYWindowsPowerShellPath(): String;
begin
  Result := ExpandConstant('{sysnative}\WindowsPowerShell\v1.0\powershell.exe');
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
            FileExists(AddBackslash(Directory) + 'gy.ico') and
            FileExists(AddBackslash(Directory) + 'rime.dll') and
            DirExists(AddBackslash(Directory) + 'rime-data\shared');
end;

function GyVersionPart(const Value: String; Part: Integer; var Valid: Boolean): Integer;
var
  Work: String;
  Token: String;
  Dot: Integer;
  Index: Integer;
begin
  Work := Value;
  Token := '';
  Valid := True;
  for Index := 1 to Part do begin
    if Work = '' then begin
      Token := '0';
    end else begin
      Dot := Pos('.', Work);
      if Dot > 0 then begin
        Token := Copy(Work, 1, Dot - 1);
        Delete(Work, 1, Dot);
      end else begin
        Token := Work;
        Work := '';
      end;
    end;
    if Token = '' then begin
      Valid := False;
      Result := 0;
      Exit;
    end;
  end;
  Result := StrToIntDef(Token, -1);
  if Result < 0 then Valid := False;
end;

function CompareGyVersions(const Left, Right: String; var Valid: Boolean): Integer;
var
  LeftValid: Boolean;
  RightValid: Boolean;
  Index: Integer;
  LeftPart: Integer;
  RightPart: Integer;
begin
  Valid := True;
  for Index := 1 to 4 do begin
    LeftPart := GyVersionPart(Left, Index, LeftValid);
    RightPart := GyVersionPart(Right, Index, RightValid);
    if (not LeftValid) or (not RightValid) then begin
      Valid := False;
      Result := 0;
      Exit;
    end;
    if LeftPart < RightPart then begin
      Result := -1;
      Exit;
    end;
    if LeftPart > RightPart then begin
      Result := 1;
      Exit;
    end;
  end;
  Result := 0;
end;

function SharedActivationHelpersExist(): Boolean;
begin
  Result := FileExists(CommonFinalizerPath()) and
            FileExists(ExpandConstant('{commonappdata}\GYInput\Prune-GYOldVersions.ps1')) and
            FileExists(ExpandConstant('{commonappdata}\GYInput\GYInputTransaction.ps1')) and
            FileExists(ExpandConstant('{commonappdata}\GYInput\Register-GYInputActivationTasks.ps1'));
end;

function ShouldInstallSharedHelpers(): Boolean;
var
  ActiveVersion: String;
  Valid: Boolean;
  Comparison: Integer;
begin
  // Finalizer helpers are deliberately self-cleaning after a successful
  // activation. A later install must recreate a missing transient set before
  // it can schedule another core reload, even when this package is older.
  if not SharedActivationHelpersExist() then begin
    Result := True;
    Exit;
  end;
  // An older EXE must never overwrite the shared transaction/finalizer
  // scripts that a newer active release still needs. If the registry value
  // is malformed, fail closed and preserve the existing helpers.
  if not RegQueryStringValue(HKLM64, 'SOFTWARE\GYInput', 'HostVersion', ActiveVersion) then begin
    Result := True;
    Exit;
  end;
  if ActiveVersion = '' then begin
    Result := True;
    Exit;
  end;
  Comparison := CompareGyVersions(ActiveVersion, '{#MyAppVersion}', Valid);
  if not Valid then begin
    Result := False;
    Exit;
  end;
  Result := Comparison <= 0;
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

function JsonEscape(const Value: String): String;
begin
  Result := Value;
  StringChangeEx(Result, '\', '\\', True);
  StringChangeEx(Result, '"', '\"', True);
end;

function SavePendingActivation(): Boolean;
var
  Json: String;
  BootId: Cardinal;
begin
  Result := RegQueryDWordValue(HKLM64,
    'SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters',
    'BootId', BootId);
  if not Result then Exit;
  Json := '{"schemaVersion":2,"activationState":"pending","version":"{#MyAppVersion}","dll":"' +
          JsonEscape(StableDllPath()) + '","host":"' + JsonEscape(VersionHostPath()) +
          '","health":"' + JsonEscape(VersionHealthPath()) +
          '","previousDll":"' + JsonEscape(PreviousDll) +
          '","previousHost":"' + JsonEscape(PreviousHost) +
          '","previousHealth":"' + JsonEscape(PreviousHealth) +
          '","previousVersion":"' + JsonEscape(PreviousHostVersion) + '","firstInstall":';
  if PreviousStateAvailable then Json := Json + 'false' else Json := Json + 'true';
  Json := Json + ',"stagedBootId":' + IntToStr(BootId) + '}';
  Result := SaveStringToFile(PendingActivationPath(), Json, False);
end;

function PendingTaskExists(const TaskName: String): Boolean;
var
  Attempt: Integer;
  ResultCode: Integer;
begin
  Result := False;
  for Attempt := 1 to 10 do begin
    Exec(GYSchtasksPath(),
         '/Query /TN "' + TaskName + '"', '', SW_HIDE,
         ewWaitUntilTerminated, ResultCode);
    if ResultCode = 0 then begin
      Result := True;
      Exit;
    end;
    Sleep(200);
  end;
end;

function SchedulePendingActivation(): Boolean;
var
  ResultCode: Integer;
  Args: String;
  PrimaryCreated: Boolean;
begin
  Args := '-NoProfile -ExecutionPolicy Bypass -File "' +
          ExpandConstant('{app}\Register-GYInputActivationTasks.ps1') +
          '" -LockAlreadyHeld';
  PrimaryCreated := Exec(GYWindowsPowerShellPath(), Args, '', SW_HIDE,
                         ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
  Result := PrimaryCreated and
            PendingTaskExists(PendingTaskName());
end;

procedure CancelPendingActivation();
var
  ResultCode: Integer;
begin
  Exec(GYSchtasksPath(),
       '/Delete /TN "' + PendingTaskName() + '" /F', '', SW_HIDE,
       ewWaitUntilTerminated, ResultCode);
  Exec(GYSchtasksPath(),
       '/Delete /TN "' + LegacyPendingTaskNameLogon() + '" /F', '', SW_HIDE,
       ewWaitUntilTerminated, ResultCode);
  DeleteFile(PendingActivationPath());
end;

function PendingActivationTargetsThisRelease(): Boolean;
var
  PendingJson: AnsiString;
begin
  Result := False;
  if not FileExists(PendingActivationPath()) then Exit;
  if not LoadStringFromFile(PendingActivationPath(), PendingJson) then Exit;
  Result := Pos('"version":"{#MyAppVersion}"', PendingJson) > 0;
end;
function GyStateJson(const DllPath, HostPath, HostVersion, CoreVersion, HealthPath, ActivationState: String): String;
begin
  Result := '{"schemaVersion":2,"dll":"' + JsonEscape(DllPath) + '","host":"' + JsonEscape(HostPath) +
            '","version":"' + JsonEscape(HostVersion) + '","hostVersion":"' + JsonEscape(HostVersion) +
            '","coreVersion":"' + JsonEscape(CoreVersion) + '","health":"' + JsonEscape(HealthPath) +
            '","activationState":"' + JsonEscape(ActivationState) +
            '","registryVerified":';
  if (ActivationState = 'staged') or (ActivationState = 'pending') then
    Result := Result + 'false'
  else
    Result := Result + 'true';
  Result := Result + ',"requiresClientReload":';
  if (ActivationState = 'registered-pending-client-reload') or (ActivationState = 'staged') or (ActivationState = 'pending') then
    Result := Result + 'true'
  else
    Result := Result + 'false';
  Result := Result + '}';
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
  // This was the verified version active before the transaction. A rollback
  // is permitted to target only an active, registry-verified snapshot.
  SaveStringToFile(ExpandConstant('{app}\install-state.previous.json'),
                    GyStateJson(PreviousDll, PreviousHost, PreviousHostVersion, PreviousHostVersion, PreviousHealth, 'active'), False);
end;

function VerifyCapturedPreviousGyState(): Boolean;
var
  ResultCode: Integer;
  ActiveDll: String;
  ActiveHost: String;
  ActiveVersion: String;
begin
  Result := False;
  if not PreviousStateAvailable then Exit;
  if not RegQueryStringValue(HKLM64, 'SOFTWARE\Classes\CLSID\{#MyClassId}\InprocServer32', '', ActiveDll) then Exit;
  if not RegQueryStringValue(HKLM64, 'SOFTWARE\GYInput', 'HostPath', ActiveHost) then Exit;
  if not RegQueryStringValue(HKLM64, 'SOFTWARE\GYInput', 'HostVersion', ActiveVersion) then Exit;
  if (CompareText(ActiveDll, PreviousDll) <> 0) or
     (CompareText(ActiveHost, PreviousHost) <> 0) or
     (CompareText(ActiveVersion, PreviousHostVersion) <> 0) then Exit;
  Result := Exec(PreviousHealth, '', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and
            (ResultCode = 0);
end;

function HasExistingGyRegistration(): Boolean;
var
  ActiveDll: String;
  ActiveHost: String;
begin
  Result := RegQueryStringValue(HKLM64, 'SOFTWARE\Classes\CLSID\{#MyClassId}\InprocServer32', '', ActiveDll) or
            RegQueryStringValue(HKLM64, 'SOFTWARE\GYInput', 'HostPath', ActiveHost);
end;

procedure SaveTransactionGyState(const ActivationState: String);
begin
  SaveStringToFile(ExpandConstant('{app}\install-state.json'),
                   GyStateJson(StableDllPath(), VersionHostPath(), '{#MyAppVersion}', '{#MyTsfVersion}', VersionHealthPath(), ActivationState), False);
end;

function RemoveKeyboardListForUninstall(): Boolean;
var
  ResultCode: Integer;
  Args: String;
begin
  Args := '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\Set-GYKeyboard.ps1') + '" -Remove';
  Result := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Args, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
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

function OtherReleaseIsActive(): Boolean;
var
  ActiveDll: String;
  ActiveHost: String;
begin
  Result := False;
  if RegQueryStringValue(HKLM64, 'SOFTWARE\Classes\CLSID\{#MyClassId}\InprocServer32', '', ActiveDll) then begin
    if (ActiveDll <> '') and (CompareText(ActiveDll, StableDllPath()) <> 0) then begin
      Result := True;
      Exit;
    end;
  end;
  if RegQueryStringValue(HKLM64, 'SOFTWARE\GYInput', 'HostPath', ActiveHost) then begin
    if (ActiveHost <> '') and (CompareText(ActiveHost, VersionHostPath()) <> 0) then begin
      Result := True;
      Exit;
    end;
  end;
end;
procedure RestoreCapturedPreviousStateFile();
begin
  if PreviousStateAvailable then begin
    SaveStringToFile(ExpandConstant('{app}\install-state.json'),
                      GyStateJson(PreviousDll, PreviousHost, PreviousHostVersion, PreviousHostVersion, PreviousHealth, 'active'), False);
  end else begin
    DeleteFile(ExpandConstant('{app}\install-state.json'));
  end;
end;
function RequirePendingActivationComplete(): Boolean;
begin
  Result := True;
  if not FileExists(PendingActivationPath()) then Exit;
  MsgBox('检测到已有待激活版本。为保护正在运行的办公软件，本次安装不会在当前会话中切换 DLL。请先正常重启 Windows；重启完成后再运行安装程序。', mbInformation, MB_OK);
  Result := False;
end;

function InitializeSetup(): Boolean;
begin
  if not AcquireActivationMutex() then begin
    MsgBox('GY 输入法已有另一个安装/激活事务正在运行，请稍后重试。', mbError, MB_OK);
    Result := False;
    Exit;
  end;
  try
    if not RequirePendingActivationComplete() then begin
      Result := False;
      Exit;
    end;
  finally
    ReleaseActivationMutex();
  end;
  if ReleaseIsComplete() then begin
    if WizardSilent then begin
      Result := True;
    end else if MsgBox('GY 输入法 {#MyAppVersion} 的文件已存在。'#13#10#13#10'选择“是”可重新核验并安排重启激活；选择“否”将保持当前状态。', mbConfirmation, MB_YESNO) = IDYES then begin
      Result := True;
    end else begin
      Result := False;
    end;
  end else begin
    Result := True;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ThinkPadSettingsDirectory: String;
  ThinkPadSettingsPath: String;
begin
  if CurStep = ssPostInstall then begin
    if not AcquireActivationMutex() then begin
      MsgBox('GY 输入法已有另一个安装/激活事务正在运行，请稍后重试。', mbError, MB_OK);
      Abort;
    end;
    try
    if not VerifyNewHost() then Abort;
    CapturePreviousGyState();
    if PreviousStateAvailable and (not VerifyCapturedPreviousGyState()) then begin
      MsgBox('当前 GY 输入法版本未通过离线自检，已拒绝覆盖它。请先使用“整备 GY 输入法”恢复当前版本。', mbError, MB_OK);
      Abort;
    end;
    if (not PreviousStateAvailable) and HasExistingGyRegistration() then begin
      MsgBox('检测到已有 GY 注册状态，但无法建立完整回退快照。为避免丢失可恢复版本，本次安装未作任何切换。', mbError, MB_OK);
      Abort;
    end;
#ifdef MyThinkPadCandidate
    // Calibrate only after both the new payload and rollback state pass their
    // checks, but before creating any pending activation state.  Auto follows
    // the physical monitor: the notebook panel resolves to 95%, while an
    // external desktop display can retain the 100% composition.
    ThinkPadSettingsDirectory := ExpandConstant('{localappdata}\GYInput');
    ThinkPadSettingsPath := AddBackslash(ThinkPadSettingsDirectory) + 'settings.ini';
    if not ForceDirectories(ThinkPadSettingsDirectory) or
       not SetIniString('Appearance', 'CandidateScale', '0', ThinkPadSettingsPath) then begin
      MsgBox('ThinkPad 屏幕自动比例未能写入。安装已安全停止，当前输入法保持不变。', mbError, MB_OK);
      Abort;
    end;
#endif
    // Every install is stage-only, including a first install. Neither the
    // installer nor a logon event may switch the TSF DLL in a live session.
    // The boot task verifies BootId changed before registering this release.
    ActivationPending := True;
    SaveCapturedPreviousGyState();
    SaveTransactionGyState('staged');
    if (not SavePendingActivation()) or (not SchedulePendingActivation()) then begin
      CancelPendingActivation();
      RestoreCapturedPreviousStateFile();
      MsgBox('GY 输入法文件已暂存，但无法安排重启后的自动激活。当前输入法保持不变；请重新运行安装程序。', mbError, MB_OK);
      Abort;
    end;
    SaveTransactionGyState('pending');
    { Persist until Set-GYKeyboard reads back the GY TIP successfully. }
    RegWriteStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run',
      'GYInputCompleteKeyboard',
      '"' + ExpandConstant('{win}\System32\WindowsPowerShell\v1.0\powershell.exe') + '" -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' +
      ExpandConstant('{app}\Set-GYKeyboard.ps1') + '" -Add -RequireActiveVersion "{#MyAppVersion}" -RetryAtNextLogon -WaitForActivationSeconds 60');
    MsgBox('GY 输入法测试版已暂存。请正常重启 Windows；新版只会在重启时激活，不会关闭任何正在运行的办公软件。', mbInformation, MB_OK);
    Exit;
    finally
      ReleaseActivationMutex();
    end;
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then begin
    if ActivationPending then begin
      WizardForm.FinishedLabel.Caption := 'GY 输入法新版核心已暂存。'#13#10#13#10'请现在重启 Windows，重启时会自动完成新版 DLL 激活并清理旧版本。'#13#10#13#10'在重启前继续使用当前版本，避免新旧 DLL 混合运行。';
    end;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
  PendingUpgrade: Boolean;
  OtherReleaseActive: Boolean;
begin
  if CurUninstallStep = usUninstall then begin
    if not AcquireActivationMutex() then begin
      MsgBox('GY 输入法已有另一个安装/激活事务正在运行，请稍后重试。', mbError, MB_OK);
      Exit;
    end;
    try
      PendingUpgrade := FileExists(PendingActivationPath());
      OtherReleaseActive := OtherReleaseIsActive();
      if (not OtherReleaseActive) or PendingActivationTargetsThisRelease() then
        CancelPendingActivation();
      if OtherReleaseActive then Exit;
    if IsThisReleaseActive() and IsThisHostReleaseActive() then begin
      Exec(ExpandConstant('{sys}\regsvr32.exe'), '/s /u "' + StableDllPath() + '"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      if not RemoveKeyboardListForUninstall() then begin
        MsgBox('系统文件已移除，但无法自动更新当前账户的键盘列表。请在 Windows 输入法设置中手动移除 GY 输入法。', mbInformation, MB_OK);
      end;
    end;
    if IsThisHostReleaseActive() then begin
      RegDeleteValue(HKLM64, 'SOFTWARE\GYInput', 'HostPath');
      RegDeleteValue(HKLM64, 'SOFTWARE\GYInput', 'HostVersion');
    end;
    // Full uninstall means no version may stay behind: sweep every versioned
    // directory (including ones installed by older/newer setups), both state
    // manifests, and queue locked files for the rename-then-delete fallback.
    if PendingUpgrade then Exit;
    // A normal uninstall can sweep all version directories after unregistering the active release.
    Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
         '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\Prune-GYOldVersions.ps1') +
         '" -InstallRoot "' + ExpandConstant('{app}') + '" -All', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    finally
      ReleaseActivationMutex();
    end;
end;
  end;
