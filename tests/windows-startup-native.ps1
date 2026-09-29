# OS tests use hidden disposable windows, never the real client or account.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Add-Type -Path (Join-Path $root 'startup/windows-native.cs') -ReferencedAssemblies System.Management,System.Core,System.Windows.Forms
$temp=Join-Path ([IO.Path]::GetTempPath()) ('badge-startup-native-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$fixture=Join-Path $temp 'Codex.exe'
$child=$null
function Assert($condition,$message) { if(!$condition) { throw $message } }
function Stop-Fixture {
    [IO.File]::WriteAllText((Join-Path $temp 'stop'),'stop')
    if($child) { Assert ($child.WaitForExit(5000)) 'Fixture did not finish'; $child.Dispose(); $script:child=$null }
}
function Start-Fixture([string]$arguments='') {
    foreach($name in @('stop','ready','query','ended')) { $file=Join-Path $temp $name;if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file} }
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$fixture;$info.Arguments=$arguments;$info.UseShellExecute=$false;$info.WindowStyle='Hidden'
    $script:child=[Diagnostics.Process]::Start($info)
    $deadline=[DateTime]::UtcNow.AddSeconds(5)
    while(!(Test-Path -LiteralPath (Join-Path $temp 'ready')) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 50}
    Assert (Test-Path -LiteralPath (Join-Path $temp 'ready')) 'Fixture not ready'
}
try {
    Add-Type -ReferencedAssemblies System.Windows.Forms -OutputAssembly $fixture -OutputType WindowsApplication -TypeDefinition @'
using System;
using System.IO;
using System.Windows.Forms;
public class StartupFixture : Form {
    static string Root=AppDomain.CurrentDomain.BaseDirectory;
    Timer timer=new Timer();
    public StartupFixture() {
        var handle=Handle;
        File.WriteAllText(Path.Combine(Root,"ready"),"ready");
        timer.Interval=100;timer.Tick+=(s,e)=>{if(File.Exists(Path.Combine(Root,"stop"))) Application.Exit();};timer.Start();
    }
    protected override void SetVisibleCore(bool value) { base.SetVisibleCore(false); }
    protected override void WndProc(ref Message message) {
        if(message.Msg==0x0011) {
            File.WriteAllText(Path.Combine(Root,"query"),"query-session-end");
            message.Result=File.Exists(Path.Combine(Root,"refuse"))?IntPtr.Zero:new IntPtr(1);return;
        }
        if(message.Msg==0x0016 && message.WParam!=IntPtr.Zero) {
            File.WriteAllText(Path.Combine(Root,"ended"),"session-end");Application.Exit();return;
        }
        base.WndProc(ref message);
    }
    [STAThread] public static void Main(){Application.Run(new StartupFixture());}
}
'@
    [CodexUsageBadge.Startup.Native]::Configure($fixture,(Join-Path $temp 'watcher-stop'),$PID)
    $activityType=[CodexUsageBadge.Startup.Native].Assembly.GetType('CodexUsageBadge.Startup.InputActivity')
    $meaningful=$activityType.GetMethod('Meaningful',[Reflection.BindingFlags]'NonPublic,Static')
    foreach($flags in @(0,2,8,32,128,512)) {
        Assert (!$meaningful.Invoke($null,@([uint32]0,[uint16]$flags))) 'Pointer motion and button release must not cancel startup'
    }
    foreach($flags in @(1,4,16,64,256,1024,2048)) {
        Assert ($meaningful.Invoke($null,@([uint32]0,[uint16]$flags))) 'Mouse clicks and wheels must protect active work'
    }
    Assert ($meaningful.Invoke($null,@([uint32]1,[uint16]0))) 'Typing must protect active work'
    Assert (!$meaningful.Invoke($null,@([uint32]1,[uint16]1))) 'Launch key release must not cancel startup'
    Assert (([CodexUsageBadge.Startup.Native]::TakeSnapshot()).inputStamp -ne 'unknown') 'Raw Input monitor must be running'
    Start-Fixture '--remote-debugging-port=39222'
    $snapshot=[CodexUsageBadge.Startup.Native]::TakeSnapshot()
    Assert ($snapshot.apps.Count -eq 1 -and $snapshot.apps[0].debugPort -eq '39222') 'Actual Windows argument inspection'
    Assert (!$snapshot.apps[0].plainLaunch) 'Custom arguments must not be dropped by restart'
    $reply=[CodexUsageBadge.Startup.Native]::Quit($child.Id,'wrong-identity',$snapshot.inputStamp)
    Assert (!$reply.accepted -and !$child.HasExited) 'Invalid identity guard'
    Stop-Fixture
    Start-Fixture
    $snapshot=[CodexUsageBadge.Startup.Native]::TakeSnapshot()
    Assert ($snapshot.apps.Count -eq 1 -and $snapshot.apps[0].plainLaunch) 'Plain native launch detection'
    $identityMethod=[CodexUsageBadge.Startup.Native].GetMethod('ReadApplicationId',[Reflection.BindingFlags]'NonPublic,Static')
    Assert ($null -eq $identityMethod.Invoke($null,@($child))) 'Unpackaged fixture must use the desktop launch path'
    $reply=[CodexUsageBadge.Startup.Native]::Quit($child.Id,$snapshot.apps[0].key,$snapshot.inputStamp)
    Assert (!$reply.accepted -and !$child.HasExited) 'Background/hidden app guard'
    $method=[CodexUsageBadge.Startup.Native].GetMethod('ShutdownProcess',[Reflection.BindingFlags]'NonPublic,Static')
    $reply=$method.Invoke($null,@($child,[Func[bool]]{ $true },[Func[bool]]{ $false }))
    Assert ($reply.accepted -and $child.WaitForExit(5000)) ('Non-forced shutdown failed: '+$reply.reason)
    Assert (Test-Path -LiteralPath (Join-Path $temp 'query')) 'OS query-session-end was not delivered'
    Assert (Test-Path -LiteralPath (Join-Path $temp 'ended')) 'OS session-end was not delivered'
    $child.Dispose();$child=$null
    [IO.File]::WriteAllText((Join-Path $temp 'refuse'),'refuse')
    Start-Fixture
    $reply=$method.Invoke($null,@($child,[Func[bool]]{ $true },[Func[bool]]{ $false }))
    Assert (!$reply.accepted -and !$child.HasExited) 'Refusing app must remain alive'
    Assert (!(Test-Path -LiteralPath (Join-Path $temp 'ended'))) 'Refusal must not become a forced end-session'
    Stop-Fixture
    $snapshot=[CodexUsageBadge.Startup.Native]::TakeSnapshot()
    $reply=[CodexUsageBadge.Startup.Native]::Launch('invalid-input-stamp',$snapshot.frontmostPid)
    Assert (!$reply.launched) 'Changed input must cancel reopen'
    [IO.File]::WriteAllText((Join-Path $temp 'watcher-stop'),'stop')
    $reply=[CodexUsageBadge.Startup.Native]::Launch($snapshot.inputStamp,$snapshot.frontmostPid)
    Assert (!$reply.launched) 'Stop file must cancel reopen'
    Remove-Item -LiteralPath (Join-Path $temp 'watcher-stop')
    Remove-Item -LiteralPath (Join-Path $temp 'stop')
    # An activation failure must surface without falling back to direct execution of a Store binary.
    $idField=[CodexUsageBadge.Startup.Native].GetField('applicationId',[Reflection.BindingFlags]'NonPublic,Static')
    $idField.SetValue($null,('CodexUsageBadgeMissing_'+[guid]::NewGuid().ToString('N')+'!App'))
    $startMethod=[CodexUsageBadge.Startup.Native].GetMethod('StartApplication',[Reflection.BindingFlags]'NonPublic,Static')
    $activationFailed=$false
    try { $startMethod.Invoke($null,@()) | Out-Null } catch { $activationFailed=$true }
    Assert $activationFailed 'Invalid Store identity must fail activation'
    Assert (([CodexUsageBadge.Startup.Native]::TakeSnapshot()).apps.Count -eq 0) 'Store activation failure must not fall back to an executable'
    $idField.SetValue($null,$null)
    # Explicit launch must not depend on input stamps, foreground state or watcher lifetime.
    # A hidden disposable fixture receives the flags even with the watcher stopped.
    [IO.File]::WriteAllText((Join-Path $temp 'watcher-stop'),'stop')
    $explicitPid=[CodexUsageBadge.Startup.Native]::StartExplicit($fixture,$null)
    $child=[Diagnostics.Process]::GetProcessById($explicitPid)
    $snapshot=[CodexUsageBadge.Startup.Native]::TakeSnapshot()
    Assert ($snapshot.apps.Count -eq 1 -and $snapshot.apps[0].pid -eq $explicitPid -and $snapshot.apps[0].debugPort -eq '39222') 'Explicit launch must carry debug flags without input guards'
    Stop-Fixture
    Remove-Item -LiteralPath (Join-Path $temp 'watcher-stop')
    Remove-Item -LiteralPath (Join-Path $temp 'stop')
    $activationFailed=$false
    try { [CodexUsageBadge.Startup.Native]::StartExplicit($fixture,('CodexUsageBadgeMissing_'+[guid]::NewGuid().ToString('N')+'!App')) | Out-Null } catch { $activationFailed=$true }
    Assert $activationFailed 'Explicit Store activation must surface errors'
    Assert (([CodexUsageBadge.Startup.Native]::TakeSnapshot()).apps.Count -eq 0) 'Explicit Store activation must not fall back to desktop execution'
    # This fixture overrides SetVisibleCore, so the native launch cannot display a window.
    $snapshot=[CodexUsageBadge.Startup.Native]::TakeSnapshot()
    $reply=[CodexUsageBadge.Startup.Native]::Launch($snapshot.inputStamp,$snapshot.frontmostPid)
    Assert $reply.launched 'Hidden native reopen failed (do not interact during test)'
    $child=[Diagnostics.Process]::GetProcessById($reply.pid)
    $snapshot=[CodexUsageBadge.Startup.Native]::TakeSnapshot()
    Assert ($snapshot.apps.Count -eq 1 -and $snapshot.apps[0].key -eq $reply.key -and $snapshot.apps[0].debugPort -eq '39222') 'Relaunch must return correct process identity and debugging flags'
    $shown=[CodexUsageBadge.Startup.Native]::Show($reply.pid,$reply.key,'invalid-input-stamp',$snapshot.frontmostPid)
    Assert (!$shown.shown) 'Changed input must prevent showing a replacement'
    Stop-Fixture
    Write-Host 'PASS native process identity/arguments, background guards, normal OS shutdown, refusal, hidden relaunch, input cancellation and stop guard'
} finally {
    Stop-Fixture
    $resolved=[IO.Path]::GetFullPath($temp)
    if(!$resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolved) -notlike 'badge-startup-native-*') { throw 'Unexpected cleanup path' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
