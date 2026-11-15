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
;   • onyx.exe работает БЕЗ прав (#55). Права нужны только туннелю (WinTUN):
;     его поднимает onyx-core.exe из C:\Program Files\Onyx\core через задачу
;     планировщика \Onyx\OnyxCore_<пользователь> (наивысшие права, по запросу,
;     пользователю — только чтение и запуск). Конфиг от приложения onyx-core
;     считает недоверенным и пересобирает по белому списку;
;   • права администратора (UAC) спрашиваются ОДИН раз и только когда нужно:
;     поставить или обновить ядро, убрать следы старых версий (задача
;     OnyxVpnService от SYSTEM, запись в HKLM, старый автозапуск с правами
;     админа), закрыть старый Onyx, запущенный с правами админа. Обычное
;     обновление приложения — без UAC;
;   • автозапуск — HKCU\Run, без прав (#58);
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
#if !FileExists(AddBackslash(SourceDir) + "core\onyx-core.exe")
  #error "В SourceDir\core нет onyx-core.exe — соберите: dart compile exe tools\onyx_core\bin\onyx_core.dart -o <SourceDir>\core\onyx-core.exe"
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
; Тестовая установка — по умолчанию в свою папку Onyx-test: без /DIR она
; иначе встала бы поверх настоящей Onyx (#104). PrepareToInstall это проверяет.
DefaultDirName={localappdata}\Onyx{code:TestDirSuffix}
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

; Onyx закрываем сами (PrepareToInstall): новый — без прав, старый, запущенный
; с правами админа, — повышенным шагом; Restart Manager тут не помощник
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
ru.TaskAutostart=Запускать Onyx при входе в систему
ru.LaunchOnyx=Запустить Onyx
ru.ShortcutComment=Onyx — VPN в одну кнопку
ru.ReadyElevationHeader=Разрешение администратора (Windows спросит один раз):
ru.ReadyElevationNote=Для установки самого Onyx это разрешение не нужно.
ru.ReasonStop=закрыть запущенный Onyx
ru.ReasonLeftovers=остановить оставшиеся процессы Onyx
ru.ReasonLegacy=удалить остатки старых версий Onyx
ru.ReasonCore=установить компонент VPN-туннеля
ru.WaitingForPermission=Ждём разрешения администратора — нажмите «Да» в запросе Windows.
ru.OnyxRunningNoAdmin=Onyx сейчас запущен, а без разрешения администратора установщик не может его закрыть.%n%nЗакройте Onyx (значок лисы у часов → «Выход») и запустите установку снова.
ru.CoreLeft=Компонент VPN-туннеля не установлен: разрешение администратора не получено. Без него Onyx не сможет подключиться — запустите установку ещё раз и нажмите «Да» в запросе Windows.
ru.LegacyLeft=Остатки старой версии Onyx не удалены: для этого нужно разрешение администратора. Запустите установку ещё раз и нажмите «Да» в запросе Windows.
ru.UninstallDeleteData=Удалить также данные Onyx — подписки, серверы и настройки?%n%nЕсли собираетесь установить Onyx снова, нажмите «Нет»: всё сохранится.
ru.UninstallCloseOnyx=Onyx сейчас запущен, а без разрешения администратора его не закрыть.%n%nЗакройте Onyx (значок лисы у часов → «Выход») и запустите удаление снова.

en.GroupShortcuts=Shortcuts:
en.TaskDesktop=Desktop shortcut
en.GroupStartup=Startup:
en.TaskAutostart=Start Onyx when I sign in to Windows
en.LaunchOnyx=Launch Onyx
en.ShortcutComment=Onyx — one-click VPN
en.ReadyElevationHeader=Administrator permission (Windows asks once):
en.ReadyElevationNote=Onyx itself installs into your user folder and doesn't need this permission.
en.ReasonStop=close the running Onyx
en.ReasonLeftovers=stop leftover Onyx processes
en.ReasonLegacy=remove leftovers of old Onyx versions
en.ReasonCore=install the VPN tunnel component
en.WaitingForPermission=Waiting for administrator permission — click Yes in the Windows prompt.
en.OnyxRunningNoAdmin=Onyx is running now, and Setup cannot close it without administrator permission.%n%nClose Onyx (fox icon near the clock → Exit) and run Setup again.
en.CoreLeft=The VPN tunnel component was not installed: administrator permission was not granted. Onyx cannot connect without it — run Setup again and click Yes in the Windows prompt.
en.LegacyLeft=Leftovers of an old Onyx version were not removed: this needs administrator permission. Run Setup again and click Yes in the Windows prompt.
en.UninstallDeleteData=Also delete Onyx data — subscriptions, servers and settings?%n%nIf you plan to install Onyx again, choose No: everything will be kept.
en.UninstallCloseOnyx=Onyx is running now and cannot be closed without administrator permission.%n%nClose Onyx (fox icon near the clock → Exit) and run the uninstaller again.

zh.GroupShortcuts=快捷方式：
zh.TaskDesktop=在桌面创建快捷方式
zh.GroupStartup=启动：
zh.TaskAutostart=登录 Windows 时自动启动 Onyx
zh.LaunchOnyx=启动 Onyx
zh.ShortcutComment=Onyx —— 一键 VPN
zh.ReadyElevationHeader=管理员权限（Windows 只会请求一次）：
zh.ReadyElevationNote=安装 Onyx 本身不需要该权限。
zh.ReasonStop=关闭正在运行的 Onyx
zh.ReasonLeftovers=结束残留的 Onyx 进程
zh.ReasonLegacy=清理旧版本 Onyx 的残留
zh.ReasonCore=安装 VPN 隧道组件
zh.WaitingForPermission=正在等待管理员权限，请在 Windows 弹出的提示中点击“是”。
zh.OnyxRunningNoAdmin=Onyx 正在运行，没有管理员权限安装程序无法关闭它。%n%n请先关闭 Onyx（时钟旁的狐狸图标 → 退出），然后重新运行安装程序。
zh.CoreLeft=VPN 隧道组件未安装：未获得管理员权限。没有它 Onyx 无法连接——请重新运行安装程序，并在 Windows 提示中点击“是”。
zh.LegacyLeft=旧版本 Onyx 的残留未清理：这需要管理员权限。请重新运行安装程序，并在 Windows 提示中点击“是”。
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
; Старый апдейтер (payload.zip) — обновляет теперь сам установщик (#54)
Type: files; Name: "{app}\OnyxUpdater.exe"
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
; onyx.exe работает без прав (#55) — UAC при запуске нет
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchOnyx}"; Flags: postinstall nowait skipifsilent shellexec; Check: not IsTestMode
; Обновление из приложения (#54): тихий режим с /ONYXUPDATE=1 — Onyx закрылся
; сам, после установки запускаем его снова (без галочки, без skipifsilent)
Filename: "{app}\{#AppExe}"; Flags: nowait; Check: IsUpdateRun

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
; Метка тестовой установки (пишется кодом)
Type: files; Name: "{app}\onyxtest.flag"
Type: dirifempty; Name: "{app}"

[Code]
const
  LegacyUninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\Onyx';
  RunKey = 'Software\Microsoft\Windows\CurrentVersion\Run';
  RunValue = 'Onyx';

var
  LegacyLeft: Boolean;
  // Ядро (туннель) не установилось: Windows не дала разрешение
  CoreLeft: Boolean;
  DeleteDataOnUninstall: Boolean;
  // Запущен свой процесс, который держит файлы в папке установки
  // (выставляет OnyxRunning). sing-box из папки данных файлы установки не
  // держит: без UAC он просто останется, установку это не блокирует.
  OnyxBlocks: Boolean;
  // Среди своих процессов есть запущенные с правами админа (старая версия:
  // путь без прав не виден) — закрыть их можно только с UAC
  OnyxElevated: Boolean;
  // Тестовый режим определяется один раз (см. IsTestMode)
  TestModeKnown, TestModeOn: Boolean;
  // Файлы ядра извлечены во {tmp} (для сравнения и установки в Program Files)
  CoreExtracted: Boolean;
  // Галочка автозапуска выставлена по факту (HKCU\Run / старая задача)
  AutostartInitDone: Boolean;
  // До установки был старый автозапуск (задача с правами админа) — его
  // убирает повышенный шаг, а включённость переносим в HKCU\Run
  HadOldAutostart: Boolean;
  // Onyx уже стоял (обновление) — в тихом режиме автозапуск не трогаем
  WasInstalled: Boolean;

// ── Окружение ───────────────────────────────────────────────────────────────

// /ONYXTEST=1 — без UAC, ярлыков, остановки процессов и удаления данных, со
// своей записью в «Программах» (AppId + «.test») и своим ключом HKCU.
// Деинсталлятор тестовой установки узнаёт её и без ключа — по метке
// onyxtest.flag в папке. Решение кэшируется: к концу удаления метки уже нет,
// а ошибиться и снести настоящие данные или ключ нельзя.
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

function TestDirSuffix(Param: String): String;
begin
  if IsTestMode then Result := '-test' else Result := '';
end;

// Тихое обновление из приложения (#54): OnyxSetup.exe /VERYSILENT /ONYXUPDATE=1.
// Из тестовой установки приложение добавляет /ONYXTEST=1 /DIR=<её папка> — и
// обновление, и перезапуск остаются в тестовой папке (#104).
function IsUpdateRun: Boolean;
begin
  Result := ExpandConstant('{param:ONYXUPDATE|0}') = '1';
end;

// Папка основной (не тестовой) установки по её ключу HKCU; '' — не найдена.
function MainInstallDir: String;
var
  S: String;
begin
  S := '';
  if RegQueryStringValue(HKCU, 'Software\Z43 Studios\Onyx', 'InstallDir', S) and (S <> '') then
    Result := RemoveBackslashUnlessRoot(S)
  else
    Result := '';
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

// ── Ядро туннеля (#55) ──────────────────────────────────────────────────────
// onyx.exe работает без прав. Туннелю (WinTUN) нужен администратор — его
// поднимает onyx-core.exe из C:\Program Files\Onyx\core (писать туда может
// только администратор) через задачу планировщика \Onyx\OnyxCore_<имя>:
// наивысшие права, запуск по требованию, пользователю — только чтение и
// запуск (SDDL). Конфиг от приложения onyx-core считает недоверенным.
// Ставится повышенным шагом (UAC) — только если ядро новое или задачи нет.

function CoreRoot: String;
begin
  // {commonpf64} — из реестра, а не из переменных окружения (их пользователь
  // подменяет сам, а здесь путь для повышенного шага).
  Result := ExpandConstant('{commonpf64}\Onyx');
end;

function CoreDir: String;
begin
  Result := CoreRoot + '\core';
end;

function SafeName(const S: String): String;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    if ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z')) or
       ((C >= '0') and (C <= '9')) or (C = '_') or (C = '.') or (C = '-') then
      Result := Result + C
    else
      Result := Result + '_';
  end;
end;

// То же имя строит приложение (SingboxBridgeWindows.coreTaskName).
function CoreTaskName: String;
begin
  Result := 'OnyxCore_' + SafeName(GetUserNameString);
end;

function CoreFile(I: Integer): String;
begin
  case I of
    0: Result := 'sing-box.exe';
    1: Result := 'wintun.dll';
  else
    Result := 'onyx-core.exe';
  end;
end;

procedure ExtractCore;
var
  I: Integer;
begin
  if CoreExtracted then exit;
  for I := 0 to 2 do
    ExtractTemporaryFile(CoreFile(I));
  CoreExtracted := True;
end;

// Задача ядра есть и запускает onyx-core.exe из Program Files с наивысшими
// правами (читается и без прав).
function CoreTaskOk: Boolean;
var
  Svc, Task, Def: Variant;
  RunLevel: Integer;
  ExePath: String;
begin
  Result := False;
  try
    Svc := CreateOleObject('Schedule.Service');
    Svc.Connect();
    Task := Svc.GetFolder('\Onyx').GetTask(CoreTaskName);
    Def := Task.Definition;
    RunLevel := Def.Principal.RunLevel;
    ExePath := Def.Actions.Item(1).Path;
    Result := (RunLevel = 1) and (CompareText(ExePath, CoreDir + '\onyx-core.exe') = 0);
  except
    Result := False;
  end;
end;

// Ядро в Program Files совпадает с этим установщиком и задача на месте —
// повышенный шаг ради ядра не нужен (обычное обновление приложения — без UAC).
function CoreUpToDate: Boolean;
var
  I: Integer;
  Mine, Theirs: String;
begin
  ExtractCore;
  Result := CoreTaskOk;
  for I := 0 to 2 do
  begin
    if not Result then exit;
    Mine := ExpandConstant('{tmp}\') + CoreFile(I);
    Theirs := CoreDir + '\' + CoreFile(I);
    Result := FileExists(Theirs) and (GetSHA256OfFile(Mine) = GetSHA256OfFile(Theirs));
  end;
end;

// ── Процессы ────────────────────────────────────────────────────────────────
// WMI без прав видит путь только у процессов своего уровня: у процессов с
// правами админа (старый Onyx, ядро) он пустой. «Свои» — из папки установки
// и старой папки v0.2.0; onyx.exe с пустым путём — «возможно свой, с правами
// админа» (точно решает повышенный шаг). sing-box из папки данных — только
// дети своих onyx.exe или сироты. Соседнюю сборку с той же папкой данных
// (тестовая OnyxRedesign) и её туннель не трогаем.

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

// Запущен ли «наш» Onyx (onyx.exe / служба / апдейтер из наших папок) или
// sing-box из папки данных, чей родитель — наш onyx.exe либо уже мёртв.
function OnyxRunning: Boolean;
var
  Procs, P, Parent: Variant;
  I, Pid, ParentPid: Integer;
  Name, Path, OursPids: String;
begin
  Result := False;
  OnyxBlocks := False;
  OnyxElevated := False;
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
        if Path = '' then OnyxElevated := True;
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

// Закрыть Onyx без прав (#55: onyx.exe теперь работает как пользователь):
// туннель — флагом остановки ядра и снятием задачи; свои onyx.exe/апдейтер
// и пробы sing-box своего уровня — taskkill. С правами админа (старая версия)
// так не закрыть — их видно по пустому пути, ими займётся повышенный шаг.
procedure StopOnyxQuietly;
var
  Procs, P: Variant;
  I, Code, Pid: Integer;
  Name, Path: String;
begin
  if IsTestMode then
  begin
    // Только тихое обновление тестовой установки: закрываем onyx.exe из её
    // папки (она не совпадает с основной — проверено в PrepareToInstall).
    // Ядро, пробы и основную Onyx не трогаем.
    if IsUpdateRun then
    begin
      try
        Procs := WmiQuery('SELECT ProcessId, ExecutablePath FROM Win32_Process WHERE Name = ''onyx.exe''');
        for I := 0 to Procs.Count - 1 do
        begin
          P := Procs.ItemIndex(I);
          Path := VarStr(P.ExecutablePath);
          if (Path <> '') and UnderDir(Path, AppDir) then
          begin
            Pid := P.ProcessId;
            Log(Format('ONYXTEST: закрываем тестовый onyx.exe PID %d', [Pid]));
            Exec(ExpandConstant('{sys}\taskkill.exe'), Format('/F /PID %d', [Pid]), '', SW_HIDE, ewWaitUntilTerminated, Code);
          end;
        end;
      except
        Log('WMI недоступен: ' + GetExceptionMessage);
      end;
      Sleep(800);
    end
    else
      Log('ONYXTEST: Onyx не закрываем');
    exit;
  end;
  ForceDirectories(DataDir + '\singbox');
  SaveStringToFile(DataDir + '\singbox\core.stop', '1', False);
  Exec(ExpandConstant('{sys}\schtasks.exe'), '/End /TN "\Onyx\' + CoreTaskName + '"', '', SW_HIDE, ewWaitUntilTerminated, Code);
  try
    Procs := WmiQuery('SELECT ProcessId, Name, ExecutablePath FROM Win32_Process ' +
      'WHERE Name = ''onyx.exe'' OR Name = ''OnyxUpdater.exe'' OR Name = ''sing-box.exe''');
    for I := 0 to Procs.Count - 1 do
    begin
      P := Procs.ItemIndex(I);
      Name := LowerCase(VarStr(P.Name));
      Path := VarStr(P.ExecutablePath);
      if (Path <> '') and (UnderDir(Path, AppDir) or UnderDir(Path, LegacyDir) or
         ((Name = 'sing-box.exe') and UnderDir(Path, DataDir))) then
      begin
        Pid := P.ProcessId;
        Log(Format('Закрываем без прав: %s PID %d', [Name, Pid]));
        Exec(ExpandConstant('{sys}\taskkill.exe'), Format('/F /PID %d', [Pid]), '', SW_HIDE, ewWaitUntilTerminated, Code);
      end;
    end;
  except
    Log('WMI недоступен: ' + GetExceptionMessage);
  end;
  Sleep(1200);
end;

// ── Наследие: v0.2.0 и автозапуск-задача ────────────────────────────────────

// v0.2.0 (64-битный Flutter-установщик) писала запись в 64-битное
// представление HKLM. Смотрим оба явно: сам Setup — 32-битный процесс.
function LegacyPresent: Boolean;
begin
  Result := RegKeyExists(HKLM64, LegacyUninstallKey) or
    RegKeyExists(HKLM32, LegacyUninstallKey) or
    FileExists(LegacyDir + '\OnyxService.exe') or
    FileExists(AppDir + '\OnyxService.exe');
end;

// Старый автозапуск (0.3.0-test3 и раньше): задача \Onyx\Onyx Autostart с
// наивысшими правами — запускала onyx.exe из папки пользователя от имени
// администратора. Теперь автозапуск — обычный HKCU\Run (без прав), задачу
// убираем.
function OldAutostartTask: Boolean;
var
  Svc, Task: Variant;
begin
  Result := False;
  try
    Svc := CreateOleObject('Schedule.Service');
    Svc.Connect();
    Task := Svc.GetFolder('\Onyx').GetTask('Onyx Autostart');
    Result := True;
  except
    Result := False;
  end;
end;

function RunValueExists: Boolean;
begin
  Result := RegValueExists(HKCU, RunKey, RunValue);
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

// [StopOnyx] — закрыть свои процессы с правами админа (старый Onyx, ядро,
// брошенный sing-box); [CleanLegacy] — следы v0.2.0 и старая задача
// автозапуска; [InstallCore] — ядро в Program Files + задача ядра;
// [RemoveCore] — удалить задачу ядра этого пользователя (и само ядро, если
// других пользователей нет).
function BuildAdminScript(StopOnyx, CleanLegacy, InstallCore, RemoveCore: Boolean; const Marker: String): String;
var
  S, NL: String;
begin
  NL := #13#10;
  S := '$ErrorActionPreference = ''SilentlyContinue''' + NL +
    '$out = New-Object System.Collections.Generic.List[string]' + NL +
    // Разрядность PowerShell: Setup 32-битный, ShellExec запускает 32-битный
    // PowerShell — реестр HKLM поэтому трогаем только через явные представления.
    '$out.Add(''ps64='' + [Environment]::Is64BitProcess)' + NL +
    '$app = ' + Q(AppDir) + '; $legacy = ' + Q(LegacyDir) + '; $data = ' + Q(DataDir) + NL +
    '$coreRoot = ' + Q(CoreRoot) + '; $coreDir = ' + Q(CoreDir) + '; $runDir = ' + Q(CoreRoot + '\run') + NL +
    '$user = ' + Q(UserAccount) + '; $taskName = ' + Q(CoreTaskName) + NL +
    'function Under($path, $dir) { return [bool]$path -and $path.StartsWith($dir + ''\'', [StringComparison]::OrdinalIgnoreCase) }' + NL +
    'function Get-Ours { Get-CimInstance Win32_Process -Filter "Name=''onyx.exe'' OR Name=''OnyxService.exe'' OR Name=''OnyxUpdater.exe''" | Where-Object { (Under $_.ExecutablePath $app) -or (Under $_.ExecutablePath $legacy) } }' + NL;
  // Свои onyx.exe/службу/апдейтер — только из папки установки и старой папки;
  // sing-box из папки данных — только дети своих onyx.exe или сироты.
  if StopOnyx then
    S := S +
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
      'foreach ($view in ''Registry64'', ''Registry32'') { try { $hk = [Microsoft.Win32.RegistryKey]::OpenBaseKey(''LocalMachine'', $view); $hk.DeleteSubKeyTree($legacyKey, $false); $hk.Close() } catch { $out.Add(''legacy-key-error='' + $view) } }' + NL +
      // Старый автозапуск с наивысшими правами (0.3.0-test3 и раньше)
      'Get-ScheduledTask -TaskPath ''\Onyx\'' -TaskName ''Onyx Autostart'' | Unregister-ScheduledTask -Confirm:$false' + NL +
      'if (Get-ScheduledTask -TaskPath ''\Onyx\'' -TaskName ''Onyx Autostart'') { $out.Add(''oldauto=left'') } else { $out.Add(''oldauto=gone'') }' + NL;
  if InstallCore or RemoveCore then
    S := S +
      // Ядро: остановить все экземпляры из нашей папки Program Files
      'Get-ScheduledTask -TaskPath ''\Onyx\'' | Where-Object { $_.TaskName -like ''OnyxCore_*'' } | Stop-ScheduledTask' + NL +
      'Get-CimInstance Win32_Process -Filter "Name=''onyx-core.exe'' OR Name=''sing-box.exe''" | Where-Object { Under $_.ExecutablePath $coreRoot } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }' + NL +
      'Start-Sleep -Milliseconds 500' + NL;
  if InstallCore then
    S := S +
      'New-Item -ItemType Directory -Force -Path $coreDir, $runDir | Out-Null' + NL +
      'foreach ($f in ''sing-box.exe'', ''wintun.dll'', ''onyx-core.exe'') { Copy-Item -LiteralPath (Join-Path ' + Q(ExpandConstant('{tmp}')) + ' $f) -Destination $coreDir -Force }' + NL +
      // Журнал ядра: пишут только администраторы и SYSTEM, пользователи читают
      '& icacls.exe $runDir /inheritance:r /grant:r ''*S-1-5-32-544:(OI)(CI)F'' ''*S-1-5-18:(OI)(CI)F'' ''*S-1-5-32-545:(OI)(CI)RX'' | Out-Null' + NL +
      // Задача ядра: по требованию, наивысшие права, только onyx-core.exe из
      // Program Files; пользователю — чтение и запуск (менять её он не может)
      '$svc = New-Object -ComObject Schedule.Service; $svc.Connect()' + NL +
      'try { $folder = $svc.GetFolder(''\Onyx'') } catch { $folder = $svc.GetFolder(''\'').CreateFolder(''Onyx'') }' + NL +
      '$def = $svc.NewTask(0)' + NL +
      '$def.RegistrationInfo.Description = ''Onyx VPN: tunnel (WinTUN) with administrator rights. Runs only onyx-core.exe from Program Files.''' + NL +
      '$def.Principal.UserId = $user; $def.Principal.LogonType = 3; $def.Principal.RunLevel = 1' + NL +
      '$def.Settings.MultipleInstances = 2; $def.Settings.DisallowStartIfOnBatteries = $false; $def.Settings.StopIfGoingOnBatteries = $false' + NL +
      '$def.Settings.ExecutionTimeLimit = ''PT0S''; $def.Settings.Priority = 4; $def.Settings.AllowHardTerminate = $true' + NL +
      '$act = $def.Actions.Create(0); $act.Path = (Join-Path $coreDir ''onyx-core.exe''); $act.WorkingDirectory = $coreDir' + NL +
      '$sid = (New-Object System.Security.Principal.NTAccount($user)).Translate([System.Security.Principal.SecurityIdentifier]).Value' + NL +
      '$sddl = ''D:P(A;;FA;;;BA)(A;;FA;;;SY)(A;;GRGX;;;'' + $sid + '')''' + NL +
      '[void]$folder.RegisterTaskDefinition($taskName, $def, 6, $user, $null, 3, $sddl)' + NL +
      '$t = $null; try { $t = $folder.GetTask($taskName) } catch {}' + NL +
      'if ($t -and $t.Definition.Actions.Item(1).Path -eq (Join-Path $coreDir ''onyx-core.exe'') -and (Test-Path -LiteralPath (Join-Path $coreDir ''onyx-core.exe''))) { $out.Add(''core=ok'') } else { $out.Add(''core=fail'') }' + NL;
  if RemoveCore then
    S := S +
      'Get-ScheduledTask -TaskPath ''\Onyx\'' -TaskName $taskName | Unregister-ScheduledTask -Confirm:$false' + NL +
      // Ядро общее: удаляем, только если других пользователей с Onyx нет
      'if (-not (Get-ScheduledTask -TaskPath ''\Onyx\'' | Where-Object { $_.TaskName -like ''OnyxCore_*'' })) { Remove-Item -LiteralPath $coreRoot -Recurse -Force; $out.Add(''core=removed'') } else { $out.Add(''core=kept'') }' + NL +
      'try { $svc = New-Object -ComObject Schedule.Service; $svc.Connect(); $f = $svc.GetFolder(''\Onyx''); if ($f.GetTasks(1).Count -eq 0) { $svc.GetFolder(''\'').DeleteFolder(''Onyx'', 0) } } catch {}' + NL;
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

// Маркер результата повышенного шага: строки «core=ok», «legacy=ok», «done»…
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
  HadOldAutostart := OldAutostartTask;
  // {app} здесь ещё не известен — без LegacyPresent
  WasInstalled := RegValueExists(HKCU, OnyxRegKey, 'InstallDir') or
    RegKeyExists(HKLM64, LegacyUninstallKey) or FileExists(LegacyDir + '\OnyxService.exe');
  Result := True;
end;

// Галочка автозапуска — по факту, а не по памяти прошлой установки: её
// могли переключить в самом Onyx. При обновлении со старым автозапуском
// (задача с правами админа) — тоже включена: переносим его в HKCU\Run.
procedure InitAutostartCheckbox;
begin
  if AutostartInitDone then exit;
  AutostartInitDone := True;
  if IsTestMode then exit;
  if RunValueExists or HadOldAutostart then
    WizardSelectTasks('autostart')
  else if WasInstalled then
    WizardSelectTasks('!autostart');
end;

// Блок памятки — через пустую строку от предыдущего. Первый блок — без
// отступа сверху: при обновлении страница папки пропущена, MemoDirInfo пуст.
procedure AddMemoBlock(var Memo: String; const Block, NewLine: String);
begin
  if Block = '' then exit;
  if Memo <> '' then Memo := Memo + NewLine + NewLine;
  Memo := Memo + Block;
end;

// Страница «Всё готово к установке»: честно предупреждаем о запросе UAC
// до нажатия «Установить» — заголовок и причины отдельными короткими строками
// (памятка не переносит длинные строки).
function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo,
  MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
var
  Reasons: String;
  Dummy: Boolean;
begin
  Result := '';
  AddMemoBlock(Result, MemoDirInfo, NewLine);
  AddMemoBlock(Result, MemoTasksInfo, NewLine);
  Reasons := '';
  Dummy := OnyxRunning;
  if OnyxElevated then Reasons := Reasons + NewLine + Space + CustomMessage('ReasonStop');
  if LegacyPresent or HadOldAutostart then Reasons := Reasons + NewLine + Space + CustomMessage('ReasonLegacy');
  if not CoreUpToDate then Reasons := Reasons + NewLine + Space + CustomMessage('ReasonCore');
  if Reasons <> '' then
  begin
    AddMemoBlock(Result, CustomMessage('ReadyElevationHeader') + Reasons, NewLine);
    AddMemoBlock(Result, CustomMessage('ReadyElevationNote'), NewLine);
  end;
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
  Running, Blocks, Legacy, NeedCore, Ok: Boolean;
begin
  Result := '';
  // Тестовая установка не ставится в папку основной Onyx (#104): иначе
  // /ONYXTEST=1 без /DIR перезаписал бы рабочую установку.
  if IsTestMode and ((CompareText(AppDir, LegacyDir) = 0) or
     ((MainInstallDir <> '') and (CompareText(AppDir, MainInstallDir) = 0))) then
  begin
    Result := 'ONYXTEST: тестовая установка не ставится в папку основной Onyx (' + AppDir + '). Укажите другую: /DIR=…';
    Log(Result);
    exit;
  end;
  // Сначала без прав: новый Onyx (asInvoker), ядро и пробы закрываются так.
  StopOnyxQuietly;
  Running := OnyxRunning;
  Blocks := OnyxBlocks;
  Legacy := LegacyPresent or HadOldAutostart;
  NeedCore := not CoreUpToDate;
  Log(Format('Подготовка: onyx запущен=%s (держит файлы=%s, с правами админа=%s), наследие=%s, ядро нужно ставить=%s', [BoolStr(Running), BoolStr(Blocks), BoolStr(OnyxElevated), BoolStr(Legacy), BoolStr(NeedCore)]));

  // Брошенный sing-box сам по себе UAC не стоит: файлы установки он не держит.
  if not (Blocks or Legacy or NeedCore) then exit;

  ShowWaiting(True);
  Ok := RunElevated(BuildAdminScript(Running, Legacy, NeedCore, False, MarkerPath));
  ShowWaiting(False);
  if not Ok then
    Log('Повышенный шаг не выполнен');

  if NeedCore and not (IsTestMode or MarkerHas('core=ok')) then
    CoreLeft := True;
  if Legacy and not (IsTestMode or MarkerHas('legacy=ok')) then
    LegacyLeft := True;

  // Если наш Onyx так и не закрылся — его файлы заняты, честно останавливаемся.
  // Решает маркер повышенного шага (он видит процессы точно), а не повторная
  // проверка без прав.
  if Blocks and not (IsTestMode or MarkerHas('stopped=ok')) then
    Result := CustomMessage('OnyxRunningNoAdmin');
end;

// Автозапуск — HKCU\Run, без прав (#55, #58). В интерактивной установке — по
// галочке; в тихой (обновление из приложения) — как было, но старую задачу
// автозапуска переносим в HKCU\Run.
procedure ApplyAutostart;
var
  Want: Boolean;
begin
  if IsTestMode then
  begin
    Log('ONYXTEST: автозапуск (HKCU\Run) не трогаем');
    exit;
  end;
  // Тихое обновление (из приложения): как было — его могли переключить в
  // самом Onyx; старый автозапуск переносим. Первая установка — по /TASKS.
  if WizardSilent and not AutostartInitDone and WasInstalled then
    Want := RunValueExists or HadOldAutostart
  else
    Want := WizardIsTaskSelected('autostart');
  if Want then
    RegWriteStringValue(HKCU, RunKey, RunValue, '"' + AppDir + '\onyx.exe" --autostart')
  else
    RegDeleteValue(HKCU, RunKey, RunValue);
  if Want then
    RegWriteDWordValue(HKCU, OnyxRegKey, 'Autostart', 1)
  else
    RegWriteDWordValue(HKCU, OnyxRegKey, 'Autostart', 0);
  Log('Автозапуск (HKCU\Run): ' + BoolStr(Want));
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    ApplyAutostart;
    if IsTestMode then
      SaveStringToFile(AppDir + '\onyxtest.flag', 'ONYXTEST', False);
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
var
  Note: String;
begin
  if CurPageID = wpSelectTasks then
    InitAutostartCheckbox;
  if CurPageID = wpFinished then
  begin
    Note := '';
    if CoreLeft then Note := Note + #13#10#13#10 + CustomMessage('CoreLeft');
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
  Running, Blocks, Legacy, HasCore: Boolean;
begin
  if CurUninstallStep = usUninstall then
  begin
    StopOnyxQuietly;
    Running := OnyxRunning;
    Blocks := OnyxBlocks;
    Legacy := LegacyPresent or OldAutostartTask;
    HasCore := CoreTaskOk or DirExists(CoreRoot);
    Log(Format('Удаление: onyx запущен=%s (держит файлы=%s), наследие=%s, ядро=%s', [BoolStr(Running), BoolStr(Blocks), BoolStr(Legacy), BoolStr(HasCore)]));
    if Blocks or Legacy or HasCore then
    begin
      if not RunElevated(BuildAdminScript(Running, Legacy, False, HasCore, MarkerPath)) then
        Log('Повышенный шаг удаления не выполнен: задача ядра могла остаться');
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
    end
    else if IsTestMode then
      Log('ONYXTEST: копия ядра в данных оставлена')
    else
    begin
      // Копия ядра, которую Onyx раскладывает в данные, — бинарники, а не
      // настройки: убираем всегда. Решение здесь, а не в [UninstallDelete]:
      // там условие вычислялось бы при установке, и тестовое удаление
      // настоящей установки всё равно стёрло бы её.
      DeleteFile(DataDir + '\singbox\sing-box.exe');
      DeleteFile(DataDir + '\singbox\wintun.dll');
    end;
    if not IsTestMode then
      RegDeleteValue(HKCU, RunKey, RunValue);
    RegDeleteKeyIncludingSubkeys(HKCU, OnyxRegKey);
    RegDeleteKeyIfEmpty(HKCU, 'Software\Z43 Studios');
  end;
end;
