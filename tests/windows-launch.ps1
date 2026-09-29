# All launch and package APIs are mocked. Never open or close the real client.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$version=(Get-Content -LiteralPath (Join-Path $root 'package.json') -Raw | ConvertFrom-Json).windowsVersion
. (Join-Path $root ('dist/CodexUsageBadge-Windows-'+$version+'/manage-windows.ps1')) -Action Functions
function Assert($condition,$message) { if(!$condition) { throw $message } }
function Throws([scriptblock]$body) {
    $failed=$false
    try { & $body } catch { $failed=$true }
    Assert $failed 'Expected launch refusal'
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('badge-launch-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
try {
    $store=Join-Path $temp 'WindowsApps/OpenAI.Codex_version'
    $exe=Join-Path $store 'app/ChatGPT.exe'
    $script:packages=@([pscustomobject]@{Name='OpenAI.Codex';InstallLocation=$store;PackageFullName='current-package';PackageFamilyName='OpenAI.Codex_fixture'})
    $script:manifest=[xml]'<Package><Applications><Application Id="Helper" Executable="app/helper.exe"/><Application Id="Main" Executable="app/ChatGPT.exe"/></Applications></Package>'
    function Get-AppxPackage { [CmdletBinding()]param() $script:packages }
    function Get-AppxPackageManifest { [CmdletBinding()]param($Package) Assert ($Package -eq 'current-package') 'Must read matching registered package'; $script:manifest }
    Assert ((Get-AppActivationId $exe) -eq 'OpenAI.Codex_fixture!Main') 'Exact executable must resolve its Store identity'
    Assert ($null -eq (Get-AppActivationId (Join-Path $temp 'Desktop/ChatGPT.exe'))) 'Unpackaged desktop must not use Store activation'
    Throws { Get-AppActivationId (Join-Path $store 'missing.exe') }
    Throws { Get-AppActivationId (Join-Path $temp 'WindowsApps/OpenAI.Codex_version-other/app/ChatGPT.exe') }
    $script:packages=@()
    Throws { Get-AppActivationId $exe }
    Write-Host 'PASS Store identity: exact executable, package boundary, missing registration and ordinary desktop'

    $script:InstallRoot=$temp
    $script:ConfigPath=Join-Path $temp 'config.json'
    [IO.File]::WriteAllText($script:ConfigPath,'{}')
    $script:calls=New-Object 'Collections.Generic.List[string]'
    $script:pages=@();$script:processes=@();$script:worker=$true
    function Assert-OwnedDirectory($Path) {}
    function Resolve-Configuration($Saved,$Overrides) { [pscustomobject]@{AppExe=$exe} }
    function Get-DebugPages { $script:pages }
    function Test-Worker { $script:worker }
    function Stop-Worker { $script:calls.Add('stop-worker') }
    function Start-Worker { $script:calls.Add('start-worker') }
    function Write-Json($Path,$Value) { $script:calls.Add('write-config') }
    function Get-Process { [CmdletBinding()]param($Name) $script:processes }
    function Test-DesktopExecutable($Path) { $true }
    function Start-ExplicitClient($Config) { $script:calls.Add('explicit-launch');$script:pages=@('connected') }
    Launch-Badge
    Assert (($script:calls -join ',') -eq 'stop-worker,write-config,start-worker,explicit-launch') 'Cold start must launch once with no input-sensitive takeover'
    $script:calls.Clear()
    Launch-Badge
    Assert ($script:calls.Count -eq 0) 'Already connected client must not restart client or healthy worker'
    $script:worker=$false
    Launch-Badge
    Assert (($script:calls -join ',') -eq 'start-worker') 'Connected client may recover a stopped worker'
    $script:calls.Clear();$script:pages=@();$script:processes=@([pscustomobject]@{Path=$exe})
    Throws { Launch-Badge }
    Assert ($script:calls.Count -eq 0) 'Unconnected running client must be left untouched'
    Write-Host 'PASS explicit launch: cold start, already connected, worker recovery and active-client refusal'
} finally {
    $resolved=[IO.Path]::GetFullPath($temp)
    Assert ($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -like 'badge-launch-*') 'Unexpected cleanup path'
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
