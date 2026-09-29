$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$version = (Get-Content -LiteralPath (Join-Path $root 'package.json') -Raw | ConvertFrom-Json).windowsVersion
$package = Join-Path $root ('dist/CodexUsageBadge-Windows-' + $version)
$manager = Join-Path $package 'manage-windows.ps1'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($manager, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
if ($tokens | Where-Object { $_.Kind.ToString() -in @('QuestionQuestion','QuestionQuestionEquals','AndAnd','OrOr') }) { throw 'Unsupported PowerShell 7 syntax' }
. $manager -Action Functions
function Assert($Condition, [string]$Message) { if (!$Condition) { throw "ASSERT: $Message" } }
function Throws([scriptblock]$Body, [string]$Pattern) {
    $failure = $null
    try { & $Body } catch { $failure = $_.Exception.Message }
    Assert ($failure -and $failure -match $Pattern) "expected $Pattern, got $failure"
}
Assert ((ConvertTo-NativeArgument '') -ceq '""') 'empty argument'
Assert ((ConvertTo-NativeArgument '中文 name') -ceq '"中文 name"') 'unicode and spaces'
Assert ((ConvertTo-NativeArgument 'a"b') -ceq '"a\"b"') 'embedded quote'
Assert ((ConvertTo-NativeArgument 'C:\with space\') -ceq '"C:\with space\\"') 'trailing slash doubled'
Assert ((ConvertTo-NativeArgument 'a\"b') -ceq '"a\\\"b"') 'slash before embedded quote'
Assert ((Join-NativeArguments @('-File','C:\中文 目录\manage-windows.ps1','-Action','Run')) -ceq '"-File" "C:\中文 目录\manage-windows.ps1" "-Action" "Run"') 'argument array'
$run = $ast.Find({param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Run-Worker'}, $true).Extent.Text
Assert ($run -notmatch 'Launch-Badge|\$config.AppExe\s+-ArgumentList|\.focus\(|AppActivate') 'worker never launches GUI'
Assert ($run -match 'WindowStyle Hidden' -and $run -match 'CODEX_BADGE_STOP_FILE') 'hidden child and graceful stop'
Write-Host 'PASS PowerShell parsing, argument quoting, no background activation'

$temp = Join-Path ([IO.Path]::GetTempPath()) ('badge-windows-中文 空格-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$oldLocal = $env:LOCALAPPDATA; $oldHome = $env:USERPROFILE; $oldCodexHome = $env:CODEX_HOME
try {
    $env:LOCALAPPDATA = Join-Path $temp 'Local AppData'; $env:USERPROFILE = $temp; $env:CODEX_HOME = ''
    [void][IO.Directory]::CreateDirectory($env:LOCALAPPDATA)
    $gui = Join-Path $temp 'Apps/ChatGPT.exe'
    [void][IO.Directory]::CreateDirectory((Join-Path (Split-Path $gui) 'resources'))
    Write-Utf8 $gui 'fixture'
    Write-Utf8 (Join-Path (Split-Path $gui) 'resources/app.asar') 'fixture'
    $cli = Join-Path $env:LOCALAPPDATA 'OpenAI/Codex/bin/new-hash/codex.exe'
    [void][IO.Directory]::CreateDirectory((Split-Path $cli)); Write-Utf8 $cli 'fixture'
    $node = Join-Path $env:LOCALAPPDATA 'OpenAI/Codex/runtimes/cua_node/new-hash/bin/node.exe'
    [void][IO.Directory]::CreateDirectory((Split-Path $node)); Write-Utf8 $node 'fixture'
    $legacy = Join-Path $env:LOCALAPPDATA 'OpenAI/Codex/bin/codex.exe'; Write-Utf8 $legacy 'bad executable'
    function Invoke-Hidden([string]$Exe, [string[]]$Arguments, [int]$TimeoutMs = 12000) {
        if ($Exe -eq $legacy) { throw 'stale / blocked runtime' }
        if ($Arguments[0] -eq '-e') { return 'badge-runtime-ok' }
        if ($Arguments[0] -eq '--version') { return 'codex-cli 0.999.0' }
        return ''
    }
    function Get-AppCandidates($Saved) { $cli; $gui; Get-Setting $Saved 'AppExe' }
    Assert (!(Test-DesktopExecutable $cli)) 'CLI must not be mistaken for desktop app'
    Assert (Test-DesktopExecutable $gui) 'desktop resources check'
    [xml]$manifest = '<Package><Applications><Application Executable="app\Codex.exe"/><Application Executable="app\helper.exe"/></Applications></Package>'
    $manifestPaths = @(Get-ManifestExecutables $manifest $temp)
    Assert ($manifestPaths.Count -eq 1 -and $manifestPaths[0] -match 'app[/\\]Codex.exe$') 'Store manifest executable'
    $config = Resolve-Configuration ([pscustomobject]@{AppExe='stale';NodeExe='stale';CodexBin='stale'}) $null
    Assert ($config.AppExe -eq $gui -and $config.NodeExe -eq $node -and $config.CodexBin -eq $cli) 'Store runtime discovery and invalid runtime fallback'
    $explicitHome = Join-Path $temp '自定义 Codex 数据'
    $custom = Resolve-Configuration $config ([pscustomobject]@{CodexHome=$explicitHome;NodeExe=$node})
    Assert ($custom.CodexHome -eq $explicitHome -and $custom.Overrides.NodeExe -eq $node) 'custom paths persisted'
    Throws { Resolve-Configuration $config ([pscustomobject]@{NodeExe=(Join-Path $temp 'missing.exe')}) } 'Node.js'
    Throws { Resolve-Configuration $config ([pscustomobject]@{CodexHome='relative-folder'}) } '绝对路径'
    Write-Host 'PASS desktop vs CLI detection, Store manifest, managed runtimes, stale paths, explicit overrides'

    $script:InstallRoot = Join-Path $temp 'installed'
    $script:ManagerPath = Join-Path $script:InstallRoot 'manage-windows.ps1'
    $script:ConfigPath = Join-Path $script:InstallRoot 'config.json'
    $script:StatePath = Join-Path $script:InstallRoot 'worker.json'
    $script:StopPath = Join-Path $script:InstallRoot 'stop.request'
    $script:PowerShell = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    $script:DesktopLink = Join-Path $temp 'Codex 用量条.lnk'
    $script:StartupLink = Join-Path $temp 'background.lnk'
    $script:running = $false; $script:failLink = $false; $script:failStart = $false
    function Test-Worker { $script:running }
    function Stop-Worker { $script:running = $false }
    function Start-Worker {
        if ($script:failStart) { $script:failStart = $false; throw 'injected startup failure' }
        $script:running = $true
    }
    function Test-OwnedShortcut([string]$Path, [string]$Mode) {
        (Test-Path -LiteralPath $Path -PathType Leaf) -and (Get-Content -LiteralPath $Path -Raw -Encoding UTF8) -ceq (Get-ManagerArguments $Mode)
    }
    function Write-Shortcut([string]$Path, [string]$Mode, [string]$Icon) {
        Assert-ShortcutAvailable $Path $Mode
        if ($script:failLink -and $Mode -eq 'Run') { throw 'injected shortcut failure' }
        Write-Utf8 $Path (Get-ManagerArguments $Mode)
    }
    [void][IO.Directory]::CreateDirectory($script:InstallRoot)
    Write-Utf8 (Join-Path $script:InstallRoot 'unrelated.txt') 'keep'
    Throws { Install-Badge $null } '不属于本插件'
    Assert ((Get-Content -LiteralPath (Join-Path $script:InstallRoot 'unrelated.txt')) -eq 'keep') 'unowned directory preserved'
    Remove-Item -LiteralPath $script:InstallRoot -Recurse
    Write-Utf8 $script:DesktopLink 'unrelated link'
    Install-Badge $null
    Assert ((Get-Content -LiteralPath $script:DesktopLink) -eq 'unrelated link') 'unrelated shortcut preserved at install'
    Uninstall-Badge
    Assert ((Get-Content -LiteralPath $script:DesktopLink) -eq 'unrelated link') 'unrelated shortcut preserved at uninstall'
    Remove-Item -LiteralPath $script:DesktopLink
    [void][IO.Directory]::CreateDirectory($script:DesktopLink)
    Install-Badge $null
    Uninstall-Badge
    Assert (Test-Path -LiteralPath $script:DesktopLink -PathType Container) 'unrelated folder with shortcut name preserved'
    Remove-Item -LiteralPath $script:DesktopLink
    $script:failLink = $true
    Throws { Install-Badge $null } 'injected shortcut failure'
    Assert (!(Test-Path -LiteralPath $script:InstallRoot)) 'failed first install rolled back directory'
    Assert (!(Test-Path -LiteralPath $script:DesktopLink)) 'failed first install rolled back shortcut'
    $script:failLink = $false
    Install-Badge $null
    Assert ($script:running -and (Test-Path -LiteralPath $script:ConfigPath)) 'install succeeded'
    Assert (Test-OwnedShortcut $script:DesktopLink 'Launch') 'reliable desktop launcher created'
    Write-Utf8 $script:DesktopLink (Get-ManagerArguments 'Launch')
    Write-Json (Join-Path $script:InstallRoot 'startup/state.json') @{lastAttemptAt=123;event='attempt'}
    $firstConfig = Get-Content -LiteralPath $script:ConfigPath -Raw
    Write-Utf8 (Join-Path $script:InstallRoot 'old-version.txt') 'old fixture'
    $script:failStart = $true
    Throws { Install-Badge $null } 'injected startup failure'
    Assert ($script:running -and (Test-Path -LiteralPath (Join-Path $script:InstallRoot 'old-version.txt'))) 'failed upgrade restores previous install and worker'
    Assert ((Get-Content -LiteralPath $script:ConfigPath -Raw) -ceq $firstConfig) 'old config restored exactly'
    Assert (Test-OwnedShortcut $script:DesktopLink 'Launch') 'failed upgrade restores legacy shortcut'
    Install-Badge $null
    Assert (!(Test-Path -LiteralPath (Join-Path $script:InstallRoot 'old-version.txt'))) 'successful upgrade uses new package'
    Assert (Test-OwnedShortcut $script:DesktopLink 'Launch') 'owned desktop launcher retained on upgrade'
    Assert ((Read-Json (Join-Path $script:InstallRoot 'startup/state.json')).lastAttemptAt -eq 123) 'cooldown receipt retained during upgrade'
    Write-Utf8 (Join-Path $temp 'unrelated-data.txt') 'keep'
    Uninstall-Badge
    Assert (!$script:running -and !(Test-Path -LiteralPath $script:InstallRoot)) 'uninstall stopped worker and archived install'
    Assert (!(Test-Path -LiteralPath $script:DesktopLink) -and !(Test-Path -LiteralPath $script:StartupLink)) 'owned shortcuts removed'
    Assert ((Get-Content -LiteralPath (Join-Path $temp 'unrelated-data.txt')) -eq 'keep') 'uninstall preserves unrelated files'
    Uninstall-Badge
    Write-Host 'PASS first-install rollback, retry, upgrade rollback, backup, ownership conflicts, uninstall and repeat uninstall (Windows OS calls mocked)'
} finally {
    $env:LOCALAPPDATA = $oldLocal; $env:USERPROFILE = $oldHome; $env:CODEX_HOME = $oldCodexHome
    $resolved=[IO.Path]::GetFullPath($temp)
    Assert ($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -like 'badge-windows-*') 'cleanup must stay inside fixture root'
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
