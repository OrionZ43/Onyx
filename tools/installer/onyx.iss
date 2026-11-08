; ─────────────────────────────────────────────────────────────────────────────
; Onyx VPN — установщик и деинсталлятор для Windows (Inno Setup 6.7+).
;
; Сборка (см. tools/installer/build-installer.ps1):
;   ISCC.exe /DAppVersion=0.3.0 /DSourceDir=<папка с onyx.exe, data\, core\>
;            /DOutputDir=<куда> /DOutputName=<имя без .exe> tools\installer\onyx.iss
;
; Принципы:
;   • per-user, без прав администратора: файлы в %LOCALAPPDATA%\Onyx (там же
;     жила v0.2.0 — новая версия ставится поверх и заменяет её);
;   • права администратора (UAC) спрашиваются ОДИН раз и только когда нужно:
;     закрыть запущенный Onyx (он работает с правами админа), убрать следы
;     v0.2.0 (задача OnyxVpnService от SYSTEM и запись в HKLM), настроить
;     автозапуск (задача планировщика с наивысшими правами — иначе Windows
;     не запустит при входе программу, которой нужен админ);
;   • ядро sing-box и WinTUN — внутри установщика (для Китая: ничего не качаем);
;   • постоянный AppId: новые версии ставятся поверх, без дублей, данные
;     (%APPDATA%\z43.studios\onyx) не трогаются.
;
; Тестовый режим /ONYXTEST=1: повышенные шаги не выполняются (команда только
; пишется в лог), ярлыки не создаются, данные при удалении не стираются.
; ─────────────────────────────────────────────────────────────────────────────

#ifndef AppVersion
  #define AppVersion "0.3.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\dist"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\build\installer"
#endif
#ifndef OutputName
  #define OutputName "OnyxSetup_v" + AppVersion
#endif

#define AppName      "Onyx VPN"
#define AppExe       "onyx.exe"
#define Publisher    "Z43 Studios"
#define RepoUrl      "https://github.com/OrionZ43/Onyx"
; ВНИМАНИЕ: AppId НИКОГДА не менять — по нему Windows и Inno узнают, что это
; та же программа (обновление поверх, одна запись в «Программах и компонентах»).
#define AppId        "{{0E682CBC-A702-4780-AFEB-87FA0B615378}"
#define BrandDir     "..\..\docs\brand\installer"

#if VER < EncodeVer(6, 7, 0)
  #error "Нужен Inno Setup 6.7 или новее (тёмный мастер WizardStyle=modern dark, WizardBackColor)"
#endif

#if !FileExists(AddBackslash(SourceDir) + "onyx.exe")
  #error "В SourceDir нет onyx.exe — сначала соберите приложение (flutter build windows)"
#endif
#if !FileExists(AddBackslash(SourceDir) + "core\sing-box.exe") || !FileExists(AddBackslash(SourceDir) + "core\wintun.dll")
  #error "В SourceDir\core нет sing-box.exe / wintun.dll — запустите tools\core\fetch-core.ps1 -Out <SourceDir>\core"
#endif

[Setup]
; Тестовый режим (/ONYXTEST=1) — своя запись в «Программах» и свой ключ HKCU:
; иначе тестовое удаление снесло бы регистрацию настоящей установки.
AppId={#AppId}{code:TestIdSuffix}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#Publisher}
AppPublisherURL={#RepoUrl}
AppSupportURL=https://t.me/Orion_Z43
AppUpdatesURL={#RepoUrl}/releases
AppCopyright=© 2026 {#Publisher}
AppContact=https://t.me/Orion_Z43
VersionInfoVersion={#AppVersion}.0
VersionInfoCompany={#Publisher}
VersionInfoDescription={#AppName} Setup
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#AppVersion}

; per-user, без UAC на весь установщик
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Onyx
UsePreviousAppDir=yes
; AppId с константой (тестовый режим) требует явного UsePreviousLanguage=no:
; язык и так берётся из языка Windows (ShowLanguageDialog=auto)
UsePreviousLanguage=no
AppendDefaultDirName=yes
DirExistsWarning=no
DisableProgramGroupPage=yes
DisableWelcomePage=no
DisableReadyPage=no
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

; Языки: русский по умолчанию, английский и китайский — по языку Windows
; (диалог выбора — только если язык Windows не из этих трёх)
ShowLanguageDialog=auto
LanguageDetectionMethod=uilanguage

; Внешний вид: тёмный мастер в цветах Onyx (docs/brand/installer/README.md)
WizardStyle=modern dark hidebevels includetitlebar
WizardBackColor=#0C0C0E
WizardBackColorDynamicDark=#0C0C0E
WizardImageFile={#BrandDir}\wizard-202x386.png,{#BrandDir}\wizard-336x643.png,{#BrandDir}\wizard-430x824.png
WizardImageBackColor=#0C0C0E
WizardSmallImageFile={#BrandDir}\small-58.png,{#BrandDir}\small-97.png,{#BrandDir}\small-124.png,{#BrandDir}\small-159.png
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}{code:TestNameSuffix}

; Onyx запущен с правами админа — Restart Manager без прав его не закроет,
; поэтому закрываем сами (повышенный шаг в PrepareToInstall)
CloseApplications=no
RestartApplications=no
SetupMutex=OnyxSetup_{#AppId}
SetupLogging=yes

Compression=lzma2/ultra64
SolidCompression=yes
LZMANumBlockThreads=2
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"; InfoBeforeFile: "text\info-ru.txt"
Name: "en"; MessagesFile: "compiler:Default.isl"; InfoBeforeFile: "text\info-en.txt"
Name: "zh"; MessagesFile: "lang\ChineseSimplified.isl"; InfoBeforeFile: "text\info-zh.txt"

[Messages]
ru.WelcomeLabel1=Установка Onyx
ru.WelcomeLabel2=Мастер установит [name/ver] на компьютер.%n%nOnyx — защищённое подключение в одну кнопку: сам обновит список серверов, проверит их и подключится к лучшему.%n%nЕсли Onyx сейчас запущен, установщик закроет его сам.
ru.FinishedHeadingLabel=Onyx установлен
ru.FinishedLabelNoIcons=Onyx готов к работе. Нажмите большую кнопку подключения — остальное он сделает сам.
ru.FinishedLabel=Onyx готов к работе. Нажмите большую кнопку подключения — остальное он сделает сам.
en.WelcomeLabel1=Install Onyx
en.WelcomeLabel2=Setup will install [name/ver] on this computer.%n%nOnyx is a one-click secure connection: it refreshes the server list, tests the servers and connects to the best one on its own.%n%nIf Onyx is running now, Setup will close it for you.
en.FinishedHeadingLabel=Onyx is installed
en.FinishedLabelNoIcons=Onyx is ready. Click the big connect button — Onyx will do the rest.
en.FinishedLabel=Onyx is ready. Click the big connect button — Onyx will do the rest.
zh.WelcomeLabel1=安装 Onyx
zh.WelcomeLabel2=安装向导将在这台电脑上安装 [name/ver]。%n%nOnyx 是一键安全连接：它会自动更新服务器列表、检测服务器，并连接到最佳服务器。%n%n如果 Onyx 正在运行，安装程序会自动关闭它。
zh.FinishedHeadingLabel=Onyx 已安装
zh.FinishedLabelNoIcons=Onyx 已准备就绪。点一下大的连接按钮，其余的交给 Onyx。
zh.FinishedLabel=Onyx 已准备就绪。点一下大的连接按钮，其余的交给 Onyx。

ru.UninstallAppTitle=Деинсталляция — Onyx VPN
en.UninstallAppTitle=Onyx VPN Uninstall
zh.UninstallAppTitle=Onyx VPN 卸载

[CustomMessages]
ru.GroupShortcuts=Ярлыки:
ru.TaskDesktop=Ярлык на рабочем столе
ru.GroupStartup=Запуск:
ru.TaskAutostart=Запускать Onyx при входе в Windows (разрешение спросят один раз)
ru.LaunchOnyx=Запустить Onyx
ru.ShortcutComment=Onyx — VPN в одну кнопку
ru.ReadyElevationHeader=Разрешение администратора (Windows спросит один раз):
ru.ReadyElevationNote=Для установки самого Onyx это разрешение не нужно.
ru.ReasonStop=закрыть запущенный Onyx
ru.ReasonLeftovers=остановить оставшиеся процессы Onyx
ru.ReasonLegacy=убрать старую версию Onyx 0.2.0
ru.ReasonAutostartOn=настроить автозапуск
ru.ReasonAutostartOff=выключить автозапуск
ru.WaitingForPermission=Ждём разрешения администратора — подтвердите запрос Windows («Да»).
ru.OnyxRunningNoAdmin=Onyx сейчас запущен, а без разрешения администратора установщик не может его закрыть.%n%nЗакройте Onyx (значок лисы у часов → «Выход») и запустите установку снова.
ru.AutostartSkipped=Автозапуск не настроен: Windows не дала разрешение. Чтобы включить его, запустите установку ещё раз.
ru.LegacyLeft=Старая версия Onyx 0.2.0 осталась в списке программ: для её удаления нужно разрешение администратора. Запустите установку ещё раз и разрешите изменения.
ru.UninstallDeleteData=Удалить также данные Onyx — подписки, серверы и настройки?%n%nЕсли собираетесь установить Onyx снова, нажмите «Нет»: всё сохранится.
ru.UninstallCloseOnyx=Onyx сейчас запущен, а без разрешения администратора его не закрыть.%n%nЗакройте Onyx (значок лисы у часов → «Выход») и запустите удаление снова.

en.GroupShortcuts=Shortcuts:
en.TaskDesktop=Desktop shortcut
en.GroupStartup=Startup:
en.TaskAutostart=Start Onyx when I sign in to Windows (asks for permission once)
en.LaunchOnyx=Launch Onyx
en.ShortcutComment=Onyx — one-click VPN
en.ReadyElevationHeader=Administrator permission (Windows asks once):
en.ReadyElevationNote=Onyx itself installs into your user folder and doesn't need this permission.
en.ReasonStop=close the running Onyx
en.ReasonLeftovers=stop leftover Onyx processes
en.ReasonLegacy=remove the old Onyx 0.2.0
en.ReasonAutostartOn=set up start with Windows
en.ReasonAutostartOff=turn off start with Windows
en.WaitingForPermission=Waiting for administrator permission — confirm the Windows prompt (Yes).
en.OnyxRunningNoAdmin=Onyx is running now, and Setup cannot close it without administrator permission.%n%nClose Onyx (fox icon near the clock → Exit) and run Setup again.
en.AutostartSkipped=Start with Windows was not set up: Windows did not grant permission. Run Setup again to turn it on.
en.LegacyLeft=The old Onyx 0.2.0 is still listed in installed apps: removing it needs administrator permission. Run Setup again and allow the changes.
en.UninstallDeleteData=Also delete Onyx data — subscriptions, servers and settings?%n%nIf you plan to install Onyx again, choose No: everything will be kept.
en.UninstallCloseOnyx=Onyx is running now and cannot be closed without administrator permission.%n%nClose Onyx (fox icon near the clock → Exit) and run the uninstaller again.

zh.GroupShortcuts=快捷方式：
zh.TaskDesktop=在桌面创建快捷方式
zh.GroupStartup=启动：
zh.TaskAutostart=登录 Windows 时自动启动 Onyx（会请求一次权限）
zh.LaunchOnyx=启动 Onyx
zh.ShortcutComment=Onyx —— 一键 VPN
zh.ReadyElevationHeader=管理员权限（Windows 只会请求一次）：
zh.ReadyElevationNote=安装 Onyx 本身不需要该权限。
zh.ReasonStop=关闭正在运行的 Onyx
zh.ReasonLeftovers=结束残留的 Onyx 进程
zh.ReasonLegacy=移除旧版本 Onyx 0.2.0
zh.ReasonAutostartOn=设置开机自动启动
zh.ReasonAutostartOff=关闭开机自动启动
zh.WaitingForPermission=正在等待管理员权限，请在 Windows 弹出的提示中点击“是”。
zh.OnyxRunningNoAdmin=Onyx 正在运行，没有管理员权限安装程序无法关闭它。%n%n请先关闭 Onyx（时钟旁的狐狸图标 → 退出），然后重新运行安装程序。
zh.AutostartSkipped=未设置开机自动启动：Windows 没有授予权限。如需开启，请重新运行安装程序。
zh.LegacyLeft=旧版本 Onyx 0.2.0 仍在已安装程序列表中：移除它需要管理员权限。请重新运行安装程序并允许更改。
zh.UninstallDeleteData=同时删除 Onyx 的数据（订阅、服务器和设置）吗？%n%n如果您还打算重新安装 Onyx，请选择“否”，所有数据都会保留。
zh.UninstallCloseOnyx=Onyx 正在运行，没有管理员权限无法关闭它。%n%n请先关闭 Onyx（时钟旁的狐狸图标 → 退出），然后重新运行卸载程序。

[Tasks]
Name: "desktopicon"; Description: "{cm:TaskDesktop}"; GroupDescription: "{cm:GroupShortcuts}"
Name: "autostart"; Description: "{cm:TaskAutostart}"; GroupDescription: "{cm:GroupStartup}"; Flags: unchecked

[InstallDelete]
; Сборочные ресурсы прошлой версии (flutter_assets и т. п.) — ставим начисто
Type: filesandordirs; Name: "{app}\data"
; Наследие v0.2.0: неиспользуемая служба, резервные копии старого апдейтера
Type: files; Name: "{app}\OnyxService.exe"
Type: filesandordirs; Name: "{app}\.bak"
Type: files; Name: "{%PUBLIC}\onyx_install_log.txt"; Check: not IsTestMode
; Ярлык на рабочем столе от v0.2.0 создавался всегда; если галочку сняли — убираем
Type: files; Name: "{userdesktop}\Onyx.lnk"; Tasks: not desktopicon; Check: not IsTestMode

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Excludes: "OnyxService.exe"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Имя «Onyx» и AppUserModelID «Onyx» совпадают с тем, что ищет local_notifier
; (WinToast) — уведомления Windows работают, дублей ярлыков нет. Тот же путь,
; что у ярлыка v0.2.0, — он просто заменяется.
Name: "{userprograms}\Onyx"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Comment: "{cm:ShortcutComment}"; AppUserModelID: "Onyx"; Check: not IsTestMode
Name: "{userdesktop}\Onyx"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Comment: "{cm:ShortcutComment}"; Tasks: desktopicon; Check: not IsTestMode

[Registry]
Root: HKCU; Subkey: "{code:RegKeyPath}"; ValueType: string; ValueName: "InstallDir"; ValueData: "{app}"; Flags: uninsdeletekey
Root: HKCU; Subkey: "{code:RegKeyPath}"; ValueType: string; ValueName: "Version"; ValueData: "{#AppVersion}"

[Run]
; onyx.exe требует прав администратора — shellexec, чтобы Windows показала UAC
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchOnyx}"; Flags: postinstall nowait skipifsilent shellexec; Check: not IsTestMode

[UninstallDelete]
; Файлы, которые мог дописать встроенный апдейтер (их нет в журнале установки)
Type: filesandordirs; Name: "{app}\data"
Type: filesandordirs; Name: "{app}\core"
Type: filesandordirs; Name: "{app}\logs"
Type: filesandordirs; Name: "{app}\.bak"
Type: files; Name: "{app}\*.dll"
Type: files; Name: "{app}\{#AppExe}"
Type: files; Name: "{app}\OnyxUpdater.exe"
Type: files; Name: "{app}\OnyxService.exe"
; Копия ядра, которую Onyx раскладывает в данные — это бинарники, не настройки
Type: files; Name: "{userappdata}\z43.studios\onyx\singbox\sing-box.exe"; Check: not IsTestMode
Type: files; Name: "{userappdata}\z43.studios\onyx\singbox\wintun.dll"; Check: not IsTestMode
; Метка тестовой установки (пишется кодом)
Type: files; Name: "{app}\onyxtest.flag"
Type: dirifempty; Name: "{app}"

[Code]
const
  LegacyUninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\Onyx';

var
  AutostartSkipped: Boolean;
  LegacyLeft: Boolean;
  DeleteDataOnUninstall: Boolean;
  // Новое состояние автозапуска для HKCU: -1 — не менялось, 0/1 — записать
  AutostartState: Integer;
  // Запущен свой процесс, который держит файлы в папке установки
  // (выставляет OnyxRunning). sing-box из папки данных файлы установки не
  // держит: без UAC он просто останется, установку это не блокирует.
  OnyxBlocks: Boolean;
  // Тестовый режим определяется один раз (см. IsTestMode)
  TestModeKnown, TestModeOn: Boolean;

// ── Окружение ───────────────────────────────────────────────────────────────

// /ONYXTEST=1 — без UAC, ярлыков и удаления данных, со своей записью в
// «Программах» (AppId + «.test») и своим ключом HKCU. Деинсталлятор тестовой
// установки узнаёт её и без ключа — по метке onyxtest.flag в папке. Решение
// кэшируется: к концу удаления метки уже нет, а ошибиться и снести настоящие
// данные или ключ нельзя.
function IsTestMode: Boolean;
begin
  if not TestModeKnown then
  begin
    TestModeOn := ExpandConstant('{param:ONYXTEST|0}') = '1';
    if (not TestModeOn) and IsUninstaller then
      TestModeOn := FileExists(ExpandConstant('{app}\onyxtest.flag'));
    TestModeKnown := True;
  end;
  Result := TestModeOn;
end;

function OnyxRegKey: String;
begin
  if IsTestMode then
    Result := 'Software\Z43 Studios\Onyx (test)'
  else
    Result := 'Software\Z43 Studios\Onyx';
end;

function RegKeyPath(Param: String): String;
begin
  Result := OnyxRegKey;
end;

function TestIdSuffix(Param: String): String;
begin
  if IsTestMode then Result := '.test' else Result := '';
end;

function TestNameSuffix(Param: String): String;
begin
  if IsTestMode then Result := ' (test)' else Result := '';
end;

function AppDir: String;
begin
  Result := RemoveBackslashUnlessRoot(ExpandConstant('{app}'));
end;

function LegacyDir: String;
begin
  Result := ExpandConstant('{localappdata}\Onyx');
end;

function DataDir: String;
begin
  Result := ExpandConstant('{userappdata}\z43.studios\onyx');
end;

function UserAccount: String;
var
  Domain: String;
begin
  Domain := GetEnv('USERDOMAIN');
  if Domain = '' then
    Domain := GetComputerNameString;
  Result := Domain + '\' + GetUserNameString;
end;

function BoolStr(B: Boolean): String;
begin
  if B then Result := 'yes' else Result := 'no';
end;

// ── Процессы ────────────────────────────────────────────────────────────────
// WMI без прав видит путь и у процессов с правами админа того же пользователя
// (у процессов SYSTEM — пусто). «Свои» — только из папки установки и старой
// папки v0.2.0; sing-box из папки данных — только дети своих onyx.exe или
// сироты (например, брошенные пробы серверов). Соседнюю сборку с той же
// папкой данных (тестовая OnyxRedesign) и её туннель не трогаем.

function UnderDir(const Path, Dir: String): Boolean;
var
  Prefix: String;
begin
  Prefix := AddBackslash(Dir);
  Result := (Length(Path) > Length(Prefix)) and
    (CompareText(Copy(Path, 1, Length(Prefix)), Prefix) = 0);
end;

function WmiQuery(const Query: String): Variant;
var
  Locator, Service: Variant;
begin
  Locator := CreateOleObject('WbemScripting.SWbemLocator');
  Service := Locator.ConnectServer('.', 'root\CIMV2');
  Result := Service.ExecQuery(Query);
end;

function VarStr(const V: Variant): String;
begin
  if VarIsNull(V) or VarIsEmpty(V) then
    Result := ''
  else
    Result := V;
end;

// Запущен ли «наш» Onyx: onyx.exe / служба / апдейтер из наших папок или
// sing-box из папки данных, чей родитель — наш onyx.exe либо уже мёртв.
function OnyxRunning: Boolean;
var
  Procs, P, Parent: Variant;
  I, Pid, ParentPid: Integer;
  Name, Path, OursPids: String;
begin
  Result := False;
  OnyxBlocks := False;
  try
    Procs := WmiQuery('SELECT ProcessId, ParentProcessId, Name, ExecutablePath FROM Win32_Process ' +
      'WHERE Name = ''onyx.exe'' OR Name = ''OnyxService.exe'' OR Name = ''OnyxUpdater.exe'' OR Name = ''sing-box.exe''');
    OursPids := ',';
    for I := 0 to Procs.Count - 1 do
    begin
      P := Procs.ItemIndex(I);
      Name := LowerCase(VarStr(P.Name));
      Path := VarStr(P.ExecutablePath);
      Pid := P.ProcessId;
      if (Name <> 'sing-box.exe') and ((Path = '') or UnderDir(Path, AppDir) or UnderDir(Path, LegacyDir)) then
      begin
        Log(Format('Наш процесс: %s PID %d (%s)', [Name, Pid, Path]));
        OursPids := OursPids + IntToStr(Pid) + ',';
        OnyxBlocks := True;
        Result := True;
      end;
    end;
    for I := 0 to Procs.Count - 1 do
    begin
      P := Procs.ItemIndex(I);
      if LowerCase(VarStr(P.Name)) = 'sing-box.exe' then
      begin
        Path := VarStr(P.ExecutablePath);
        Pid := P.ProcessId;
        ParentPid := P.ParentProcessId;
        if UnderDir(Path, AppDir) or UnderDir(Path, LegacyDir) then
        begin
          Log(Format('Наш sing-box: PID %d (%s)', [Pid, Path]));
          OnyxBlocks := True;
          Result := True;
        end
        else if UnderDir(Path, DataDir) then
        begin
          Parent := WmiQuery(Format('SELECT ProcessId FROM Win32_Process WHERE ProcessId = %d', [ParentPid]));
          if (Pos(',' + IntToStr(ParentPid) + ',', OursPids) > 0) or (Parent.Count = 0) then
          begin
            Log(Format('Наш sing-box (дочерний или сирота): PID %d, родитель %d', [Pid, ParentPid]));
            Result := True;
          end;
        end;
      end;
    end;
  except
    Log('WMI недоступен: ' + GetExceptionMessage);
  end;
end;

// ── Наследие v0.2.0 и автозапуск ────────────────────────────────────────────

// v0.2.0 (64-битный Flutter-установщик) писала запись в 64-битное
// представление HKLM. Смотрим оба явно: сам Setup — 32-битный процесс.
function LegacyPresent: Boolean;
begin
  Result := RegKeyExists(HKLM64, LegacyUninstallKey) or
    RegKeyExists(HKLM32, LegacyUninstallKey) or
    FileExists(LegacyDir + '\OnyxService.exe') or
    FileExists(AppDir + '\OnyxService.exe');
end;

// Задача автозапуска \Onyx\Onyx Autostart (читается и без прав админа).
// -1 — планировщик недоступен, 0 — задачи нет, 1 — есть и уже запускает
// onyx.exe из этой папки с наивысшими правами (повторная регистрация и UAC
// ради неё не нужны), 2 — есть, но другая.
function AutostartTaskState: Integer;
var
  Svc, Task, Def, Act: Variant;
  Enabled: Boolean;
  RunLevel, Count: Integer;
begin
  // -1 — планировщик недоступен (не знаем)
  Result := -1;
  try
    Svc := CreateOleObject('Schedule.Service');
    Svc.Connect();
  except
    Log('Планировщик недоступен: ' + GetExceptionMessage);
    exit;
  end;
  Result := 0;
  try
    Task := Svc.GetFolder('\Onyx').GetTask('Onyx Autostart');
  except
    exit;
  end;
  Result := 2;
  try
    Def := Task.Definition;
    // Variant → типизированные переменные: Pascal Script не сравнивает их в «and»
    Enabled := Task.Enabled;
    RunLevel := Def.Principal.RunLevel;
    Count := Def.Actions.Count;
    if Enabled and (RunLevel = 1) and (Count >= 1) then
    begin
      Act := Def.Actions.Item(1);
      if (CompareText(VarStr(Act.Path), AppDir + '\onyx.exe') = 0) and
        (VarStr(Act.Arguments) = '--autostart') then
        Result := 1;
    end;
  except
    Log('Задача автозапуска не прочитана: ' + GetExceptionMessage);
  end;
end;

function PrevAutostart: Boolean;
var
  V: Cardinal;
begin
  Result := RegQueryDWordValue(HKCU, OnyxRegKey, 'Autostart', V) and (V = 1);
end;

// ── Повышенный шаг: PowerShell через UAC, команда в -EncodedCommand ─────────
// (без временного .ps1: его нельзя подменить между записью и запуском)

function Utf16LeBase64(const S: String): String;
var
  Bytes: array of Byte;
  Tbl: String;
  I, N, B0, B1, B2: Integer;
begin
  Tbl := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  N := Length(S) * 2;
  SetArrayLength(Bytes, N);
  for I := 1 to Length(S) do
  begin
    Bytes[(I - 1) * 2] := Ord(S[I]) and $FF;
    Bytes[(I - 1) * 2 + 1] := (Ord(S[I]) shr 8) and $FF;
  end;
  Result := '';
  I := 0;
  while I < N do
  begin
    B0 := Bytes[I];
    if I + 1 < N then B1 := Bytes[I + 1] else B1 := 0;
    if I + 2 < N then B2 := Bytes[I + 2] else B2 := 0;
    Result := Result + Tbl[(B0 shr 2) + 1];
    Result := Result + Tbl[(((B0 and 3) shl 4) or (B1 shr 4)) + 1];
    if I + 1 < N then
      Result := Result + Tbl[(((B1 and 15) shl 2) or (B2 shr 6)) + 1]
    else
      Result := Result + '=';
    if I + 2 < N then
      Result := Result + Tbl[(B2 and 63) + 1]
    else
      Result := Result + '=';
    I := I + 3;
  end;
end;

// Строковый литерал PowerShell в одинарных кавычках
function Q(const S: String): String;
var
  T: String;
begin
  T := S;
  StringChangeEx(T, '''', '''''', True);
  Result := '''' + T + '''';
end;

function BuildAdminScript(StopOnyx, CleanLegacy, AddAutostart, RemoveAutostart: Boolean; const Marker: String): String;
var
  S, NL: String;
begin
  NL := #13#10;
  S := '$ErrorActionPreference = ''SilentlyContinue''' + NL +
    '$out = New-Object System.Collections.Generic.List[string]' + NL +
    // Разрядность PowerShell: Setup 32-битный, ShellExec запускает 32-битный
    // PowerShell — реестр HKLM поэтому трогаем только через явные представления.
    '$out.Add(''ps64='' + [Environment]::Is64BitProcess)' + NL;
  // Свои onyx.exe/службу/апдейтер — только из папки установки и старой папки;
  // sing-box из папки данных — только дети своих onyx.exe или сироты.
  if StopOnyx then
    S := S +
      '$app = ' + Q(AppDir) + '; $legacy = ' + Q(LegacyDir) + '; $data = ' + Q(DataDir) + NL +
      'function Under($path, $dir) { return [bool]$path -and $path.StartsWith($dir + ''\'', [StringComparison]::OrdinalIgnoreCase) }' + NL +
      'function Get-Ours { Get-CimInstance Win32_Process -Filter "Name=''onyx.exe'' OR Name=''OnyxService.exe'' OR Name=''OnyxUpdater.exe''" | Where-Object { (Under $_.ExecutablePath $app) -or (Under $_.ExecutablePath $legacy) } }' + NL +
      '$ours = @(Get-Ours)' + NL +
      '$oursPids = @($ours | ForEach-Object { $_.ProcessId })' + NL +
      'foreach ($p in $ours) { if ($p.Name -eq ''onyx.exe'') { $gp = Get-Process -Id $p.ProcessId; if ($gp) { [void]$gp.CloseMainWindow() } } }' + NL +
      'if ($ours.Count -gt 0) { Start-Sleep -Milliseconds 1500 }' + NL +
      'foreach ($p in $ours) { Stop-Process -Id $p.ProcessId -Force }' + NL +
      '$alive = @(Get-Process | ForEach-Object { $_.Id })' + NL +
      'foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name=''sing-box.exe''")) {' + NL +
      '  $path = $p.ExecutablePath' + NL +
      '  $mine = (Under $path $app) -or (Under $path $legacy) -or ((Under $path $data) -and (($oursPids -contains $p.ParentProcessId) -or -not ($alive -contains $p.ParentProcessId)))' + NL +
      '  if ($mine) { Stop-Process -Id $p.ProcessId -Force; $out.Add(''killed-singbox='' + $p.ProcessId) }' + NL +
      '}' + NL +
      'Start-Sleep -Milliseconds 700' + NL;
  if CleanLegacy then
    S := S +
      '$legacyTask = @(Get-ScheduledTask -TaskName ''OnyxVpnService'')' + NL +
      '$legacyTask | Unregister-ScheduledTask -Confirm:$false' + NL +
      'if ($legacyTask.Count -eq 0) { $out.Add(''legacy-task=none'') } elseif (Get-ScheduledTask -TaskName ''OnyxVpnService'') { $out.Add(''legacy-task=left'') } else { $out.Add(''legacy-task=removed'') }' + NL +
      '$legacyKey = ' + Q(LegacyUninstallKey) + NL +
      'foreach ($view in ''Registry64'', ''Registry32'') { try { $hk = [Microsoft.Win32.RegistryKey]::OpenBaseKey(''LocalMachine'', $view); $hk.DeleteSubKeyTree($legacyKey, $false); $hk.Close() } catch { $out.Add(''legacy-key-error='' + $view) } }' + NL;
  if AddAutostart then
    S := S +
      '$user = ' + Q(UserAccount) + NL +
      '$a = New-ScheduledTaskAction -Execute ' + Q(AppDir + '\onyx.exe') + ' -Argument ''--autostart'' -WorkingDirectory ' + Q(AppDir) + NL +
      '$t = New-ScheduledTaskTrigger -AtLogOn -User $user' + NL +
      '$p = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest' + NL +
      '$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew' + NL +
      'Register-ScheduledTask -TaskPath ''\Onyx\'' -TaskName ''Onyx Autostart'' -Action $a -Trigger $t -Principal $p -Settings $s -Force | Out-Null' + NL +
      'if (Get-ScheduledTask -TaskPath ''\Onyx\'' -TaskName ''Onyx Autostart'') { $out.Add(''autostart=ok'') } else { $out.Add(''autostart=fail'') }' + NL;
  if RemoveAutostart then
    S := S +
      'Unregister-ScheduledTask -TaskPath ''\Onyx\'' -TaskName ''Onyx Autostart'' -Confirm:$false' + NL +
      'try { $svc = New-Object -ComObject Schedule.Service; $svc.Connect(); $svc.GetFolder(''\'').DeleteFolder(''Onyx'', 0) } catch {}' + NL +
      'if (-not (Get-ScheduledTask -TaskPath ''\Onyx\'' -TaskName ''Onyx Autostart'')) { $out.Add(''autostart=off'') }' + NL;
  if CleanLegacy then
    S := S +
      '$legacyLeft = $false' + NL +
      'foreach ($view in ''Registry64'', ''Registry32'') { $hk = [Microsoft.Win32.RegistryKey]::OpenBaseKey(''LocalMachine'', $view); $k = $hk.OpenSubKey($legacyKey); if ($k) { $legacyLeft = $true; $k.Close() }; $hk.Close() }' + NL +
      'if (-not $legacyLeft) { $out.Add(''legacy=ok'') }' + NL;
  if StopOnyx then
    S := S +
      '$busy = @(Get-Ours | Where-Object { $_.Name -ne ''OnyxUpdater.exe'' }) + @(Get-CimInstance Win32_Process -Filter "Name=''sing-box.exe''" | Where-Object { (Under $_.ExecutablePath $app) -or (Under $_.ExecutablePath $legacy) })' + NL +
      'if ($busy.Count -eq 0) { $out.Add(''stopped=ok'') }' + NL;
  S := S + '$out.Add(''done'')' + NL +
    'Set-Content -LiteralPath ' + Q(Marker) + ' -Value $out -Encoding ASCII' + NL +
    'exit 0';
  Result := S;
end;

// Маркер результата повышенного шага: строки «autostart=ok», «legacy=ok», «done»…
// (код выхода ShellExec документацией не гарантирован — читаем файл).
function MarkerPath: String;
begin
  Result := ExpandConstant('{tmp}\onyx-elevated-result.txt');
end;

function MarkerHas(const Line: String): Boolean;
var
  Content: AnsiString;
begin
  Result := False;
  if LoadStringFromFile(MarkerPath, Content) then
    Result := Pos(#10 + Line + #13, #10 + String(Content)) > 0;
end;

// True — пользователь разрешил, повышенный шаг дошёл до конца (маркер «done»)
function RunElevated(const Script: String): Boolean;
var
  Params: String;
  Code: Integer;
  Content: AnsiString;
begin
  Log('Повышенный шаг:' + #13#10 + Script);
  if IsTestMode then
  begin
    Log('ONYXTEST: повышенный шаг не выполняется');
    Result := True;
    exit;
  end;
  DeleteFile(MarkerPath);
  Params := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand ' + Utf16LeBase64(Script);
  if not ShellExec('runas', ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    Params, '', SW_HIDE, ewWaitUntilTerminated, Code) then
  begin
    Log(Format('Повышенный шаг не запущен (UAC отклонён?): %d %s', [Code, SysErrorMessage(Code)]));
    Result := False;
    exit;
  end;
  // Весь маркер — в журнал: по нему видно, что именно сделал повышенный шаг.
  if LoadStringFromFile(MarkerPath, Content) then
    Log('Маркер повышенного шага:' + #13#10 + String(Content))
  else
    Log('Маркер повышенного шага не найден');
  Result := MarkerHas('done');
  Log('Повышенный шаг: маркер done=' + BoolStr(Result));
end;

// ── Установка ───────────────────────────────────────────────────────────────

function InitializeSetup: Boolean;
begin
  AutostartState := -1;
  Result := True;
end;

// Страница «Всё готово к установке»: честно предупреждаем о запросе UAC
// до нажатия «Установить» — заголовок и причины отдельными короткими строками
// (памятка не переносит длинные строки).
// Что делать с автозапуском — одно решение для «Всё готово» и установки.
// NeedAuto — зарегистрировать задачу (её нет или она другая), DropAuto — снять
// (галочка снята, а задача есть), AutoReady — уже настроена как надо: при
// обновлении с включённым автозапуском UAC ради него не нужен.
procedure PlanAutostart(var NeedAuto, DropAuto, AutoReady: Boolean);
var
  WantAuto: Boolean;
  St: Integer;
begin
  WantAuto := WizardIsTaskSelected('autostart');
  St := AutostartTaskState;
  AutoReady := WantAuto and (St = 1);
  NeedAuto := WantAuto and (St <> 1);
  // Планировщик недоступен (St = -1) — верим флагу прошлой установки
  DropAuto := (not WantAuto) and ((St > 0) or ((St < 0) and PrevAutostart));
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo,
  MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
var
  NeedAuto, DropAuto, AutoReady: Boolean;
  Reasons: String;
begin
  Result := MemoDirInfo;
  if MemoTasksInfo <> '' then
    Result := Result + NewLine + NewLine + MemoTasksInfo;
  PlanAutostart(NeedAuto, DropAuto, AutoReady);
  Reasons := '';
  if OnyxRunning then
  begin
    if OnyxBlocks then
      Reasons := Reasons + NewLine + Space + CustomMessage('ReasonStop')
    else
      Reasons := Reasons + NewLine + Space + CustomMessage('ReasonLeftovers');
  end;
  if LegacyPresent then Reasons := Reasons + NewLine + Space + CustomMessage('ReasonLegacy');
  if NeedAuto then Reasons := Reasons + NewLine + Space + CustomMessage('ReasonAutostartOn');
  if DropAuto then Reasons := Reasons + NewLine + Space + CustomMessage('ReasonAutostartOff');
  if Reasons <> '' then
    Result := Result + NewLine + NewLine + CustomMessage('ReadyElevationHeader') + Reasons +
      NewLine + NewLine + CustomMessage('ReadyElevationNote');
end;

// Пока Windows спрашивает разрешение, страница «Подготовка к установке» иначе
// пустая — подсказываем, чего ждём.
procedure ShowWaiting(Show: Boolean);
begin
  if WizardSilent then exit;
  if Show then
    WizardForm.PreparingLabel.Caption := CustomMessage('WaitingForPermission')
  else
    WizardForm.PreparingLabel.Caption := '';
  WizardForm.PreparingLabel.Visible := Show;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Running, Blocks, Legacy, NeedAuto, DropAuto, AutoReady, Ok: Boolean;
begin
  Result := '';
  Running := OnyxRunning;
  Blocks := OnyxBlocks;
  Legacy := LegacyPresent;
  PlanAutostart(NeedAuto, DropAuto, AutoReady);
  Log(Format('Подготовка: onyx запущен=%s (держит файлы=%s), наследие 0.2.0=%s, включить автозапуск=%s, уже настроен=%s, выключить автозапуск=%s', [BoolStr(Running), BoolStr(Blocks), BoolStr(Legacy), BoolStr(NeedAuto), BoolStr(AutoReady), BoolStr(DropAuto)]));

  if not (Running or Legacy or NeedAuto or DropAuto) then
  begin
    if AutoReady then AutostartState := 1 else AutostartState := 0;
    exit;
  end;

  ShowWaiting(True);
  Ok := RunElevated(BuildAdminScript(Running or Legacy, Legacy, NeedAuto, DropAuto, MarkerPath));
  ShowWaiting(False);

  if NeedAuto then
  begin
    if IsTestMode or MarkerHas('autostart=ok') then
      AutostartState := 1
    else
      AutostartSkipped := True;
  end
  else if DropAuto then
  begin
    if IsTestMode or MarkerHas('autostart=off') then AutostartState := 0;
  end
  else if AutoReady then
    AutostartState := 1
  else
    AutostartState := 0;

  if Legacy and not (IsTestMode or MarkerHas('legacy=ok')) then
    LegacyLeft := True;
  if not Ok then
    Log('Повышенный шаг не выполнен: автозапуск/очистка 0.2.0 пропущены');

  // Если наш Onyx так и не закрылся — его файлы заняты, честно останавливаемся.
  // Решает маркер повышенного шага (он видит процессы точно), а не повторная
  // проверка без прав.
  if Blocks and not (IsTestMode or MarkerHas('stopped=ok')) then
    Result := CustomMessage('OnyxRunningNoAdmin');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if (CurStep = ssPostInstall) and (AutostartState >= 0) then
    RegWriteDWordValue(HKCU, OnyxRegKey, 'Autostart', AutostartState);
  if (CurStep = ssPostInstall) and IsTestMode then
    SaveStringToFile(AppDir + '\onyxtest.flag', 'ONYXTEST', False);
end;

procedure CurPageChanged(CurPageID: Integer);
var
  Note: String;
begin
  if CurPageID = wpFinished then
  begin
    Note := '';
    if AutostartSkipped then Note := Note + #13#10#13#10 + CustomMessage('AutostartSkipped');
    if LegacyLeft then Note := Note + #13#10#13#10 + CustomMessage('LegacyLeft');
    if Note <> '' then
      WizardForm.FinishedLabel.Caption := WizardForm.FinishedLabel.Caption + Note;
  end;
end;

// ── Удаление ────────────────────────────────────────────────────────────────

// Решение о тестовом режиме — в самом начале, пока метка onyxtest.flag на месте
function InitializeUninstall: Boolean;
begin
  Log('Тестовый режим: ' + BoolStr(IsTestMode));
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Running, Blocks, Legacy, HadAuto: Boolean;
  St: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    Running := OnyxRunning;
    Blocks := OnyxBlocks;
    Legacy := LegacyPresent;
    St := AutostartTaskState;
    HadAuto := (St > 0) or ((St < 0) and PrevAutostart);
    Log(Format('Удаление: onyx запущен=%s (держит файлы=%s), наследие=%s, автозапуск=%s', [BoolStr(Running), BoolStr(Blocks), BoolStr(Legacy), BoolStr(HadAuto)]));
    if Running or Legacy or HadAuto then
    begin
      if not RunElevated(BuildAdminScript(True, Legacy, False, True, MarkerPath)) then
        Log('Повышенный шаг удаления не выполнен: задача автозапуска могла остаться');
      // Onyx не закрылся — его файлы заняты: не удаляем наполовину.
      if Blocks and not (IsTestMode or MarkerHas('stopped=ok')) then
      begin
        SuppressibleMsgBox(CustomMessage('UninstallCloseOnyx'), mbError, MB_OK, IDOK);
        Abort;
      end;
    end;

    // По умолчанию данные ОСТАВЛЯЕМ (в тихом режиме — тоже).
    DeleteDataOnUninstall := SuppressibleMsgBox(CustomMessage('UninstallDeleteData'),
      mbConfirmation, MB_YESNO or MB_DEFBUTTON2, IDNO) = IDYES;
  end;

  if CurUninstallStep = usPostUninstall then
  begin
    if DeleteDataOnUninstall then
    begin
      if IsTestMode then
        Log('ONYXTEST: удаление данных пропущено: ' + DataDir)
      else
      begin
        Log('Удаляем данные: ' + DataDir);
        DelTree(DataDir, True, True, True);
        DelTree(ExpandConstant('{localappdata}\z43.studios\onyx'), True, True, True);
      end;
    end;
    RegDeleteKeyIncludingSubkeys(HKCU, OnyxRegKey);
    RegDeleteKeyIfEmpty(HKCU, 'Software\Z43 Studios');
  end;
end;
