# zf9-pixelify.ps1 - install Google apps from Play, make them default, DISABLE (never delete) Lineage twins.
#   powershell -ExecutionPolicy Bypass -File .\zf9-pixelify.ps1            open Play pages for missing apps, then apply
#   powershell -ExecutionPolicy Bypass -File .\zf9-pixelify.ps1 -Apply     only set defaults + disable Lineage twins
#   powershell -ExecutionPolicy Bypass -File .\zf9-pixelify.ps1 -Undo      re-enable every Lineage app this script disabled
# A Lineage app is disabled ONLY if its Google replacement is installed. Nothing is uninstalled.
param([switch]$Apply, [switch]$Undo, [switch]$DisableAudioFX)
$ErrorActionPreference = 'Continue'

# Google package, Lineage twin to disable ('' = none), role to assign ('' = none), label
$Apps = @(
  @('com.google.android.dialer',                   'com.android.dialer',          'android.app.role.DIALER',  'Phone'),
  @('com.google.android.apps.messaging',           'com.android.messaging',       'android.app.role.SMS',     'Messages'),
  @('com.google.android.contacts',                 'com.android.contacts',        '',                         'Contacts'),
  @('com.google.android.calendar',                 'org.lineageos.etar',          '',                         'Calendar'),
  @('com.google.android.deskclock',                'com.android.deskclock',       '',                         'Clock'),
  @('com.google.android.calculator',               'com.android.calculator2',     '',                         'Calculator'),
  @('com.google.android.apps.photos',              'org.lineageos.glimpse',       '',                         'Photos'),
  @('com.android.chrome',                          'org.lineageos.jelly',         'android.app.role.BROWSER', 'Chrome'),
  @('com.google.android.apps.youtube.music',       'org.lineageos.twelve',        '',                         'YouTube Music'),
  @('com.google.android.inputmethod.latin',        'com.android.inputmethod.latin','',                        'Gboard'),
  @('com.google.android.gm',                       '',                            '',                         'Gmail'),
  @('com.google.android.apps.maps',                '',                            '',                         'Maps'),
  @('com.google.android.apps.nbu.files',           '',                            '',                         'Files by Google'),
  @('com.google.android.googlequicksearchbox',     '',                            '',                         'Google app'),
  @('com.google.android.tts',                      '',                            '',                         'Speech Services'),
  @('com.google.android.apps.wellbeing',           '',                            '',                         'Digital Wellbeing'),
  @('com.google.android.apps.docs',                '',                            '',                         'Drive'),
  @('com.google.android.keep',                     '',                            '',                         'Keep'),
  @('com.google.android.apps.wallpaper',           '',                            '',                         'Wallpapers')
)
# Kept on purpose: Aperture camera (GCam is separate), Recorder (Pixel-only replacement),
# Trebuchet launcher (Pixel Launcher breaks recents on Lineage), DocumentsUI and all providers.

function Write-Flag([string]$L, [string]$M) { $c=@{OK='Green';WARN='Yellow';FAIL='Red';INFO='Cyan'}[$L]; Write-Host "[$L] $M" -ForegroundColor $c }
function Invoke-Adb { (& adb @args 2>&1 | Out-String).Trim() }
$state = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'diag\pixelify_disabled.txt'

$devs = (Invoke-Adb devices) -split "`r?`n" | Where-Object { $_ -match "`tdevice$" }
if (@($devs).Count -ne 1) { Write-Flag FAIL "need exactly one device in Android, found $(@($devs).Count)"; exit 1 }
$installed = @{}
foreach ($l in ((Invoke-Adb shell pm list packages) -split "`r?`n")) { if ($l -match '^package:(.+)$') { $installed[$Matches[1].Trim()] = $true } }
$disabled = @{}
foreach ($l in ((Invoke-Adb shell pm list packages -d) -split "`r?`n")) { if ($l -match '^package:(.+)$') { $disabled[$Matches[1].Trim()] = $true } }

if ($Undo) {
  if (-not (Test-Path $state)) { Write-Flag WARN "no record at $state; nothing to undo"; exit 0 }
  foreach ($p in (Get-Content $state | Where-Object { $_ })) {
    $r = Invoke-Adb shell pm enable --user 0 $p
    if ($r -match 'enabled') { Write-Flag OK "re-enabled $p" } else { Write-Flag WARN "$p : $r" }
  }
  Remove-Item $state; exit 0
}

if (-not $Apply) {
  $missing = @($Apps | Where-Object { -not $installed[$_[0]] })
  Write-Flag INFO "$($missing.Count) Google apps not installed yet"
  foreach ($a in $missing) {
    Invoke-Adb shell am start -a android.intent.action.VIEW -d "market://details?id=$($a[0])" | Out-Null
    Read-Host "Play Store opened for $($a[3]). Tap Install on the phone, then press Enter here (or Enter to skip)" | Out-Null
  }
  $installed = @{}
  foreach ($l in ((Invoke-Adb shell pm list packages) -split "`r?`n")) { if ($l -match '^package:(.+)$') { $installed[$Matches[1].Trim()] = $true } }
}

New-Item -ItemType Directory -Force (Split-Path $state) | Out-Null
foreach ($a in $Apps) {
  $g, $twin, $role, $label = $a
  if (-not $installed[$g]) { Write-Flag WARN "$label not installed: $twin left enabled"; continue }
  if ($role) {
    $r = Invoke-Adb shell cmd role add-role-holder --user 0 $role $g
    $holders = Invoke-Adb shell cmd role get-role-holders --user 0 $role
    if ($holders -match [regex]::Escape($g)) { Write-Flag OK "$label is default ($role)" } else { Write-Flag FAIL "$label could not take $role : $r $holders"; continue }
  }
  if ($g -eq 'com.google.android.inputmethod.latin') {
    $ime = ((Invoke-Adb shell ime list -a -s) -split "`r?`n" | Where-Object { $_ -like "$g/*" } | Select-Object -First 1)
    if ($ime) { Invoke-Adb shell ime enable $ime | Out-Null; Invoke-Adb shell ime set $ime | Out-Null
      if ((Invoke-Adb shell settings get secure default_input_method) -eq $ime) { Write-Flag OK "Gboard is the active keyboard" } else { Write-Flag FAIL "Gboard not active; $twin left enabled"; continue } }
    else { Write-Flag FAIL "Gboard IME not found; open Gboard once, then rerun -Apply"; continue }
  }
  if ($twin -and $installed[$twin] -and -not $disabled[$twin]) {
    $r = Invoke-Adb shell pm disable-user --user 0 $twin
    if ($r -match 'disabled') { Add-Content $state $twin; Write-Flag OK "disabled $twin (replaced by $label)" } else { Write-Flag WARN "$twin : $r" }
  } elseif ($twin -and $disabled[$twin]) { Write-Flag OK "$twin already disabled" }
  else { Write-Flag OK "$label installed" }
}
# Optional (-DisableAudioFX): AudioFX can conflict with ViPER4Android
foreach ($p in @($(if ($DisableAudioFX) { 'org.lineageos.audiofx', 'org.rinko.audiofx' }))) {
  if (-not $installed[$p]) { Write-Flag INFO "$p not present"; continue }
  if ($disabled[$p]) { Write-Flag OK "$p already disabled"; continue }
  $r = Invoke-Adb shell pm disable-user --user 0 $p
  if ($r -match 'disabled') { Add-Content $state $p; Write-Flag OK "disabled $p (conflicts with V4A)" } else { Write-Flag WARN "$p : $r" }
}
Write-Host "`nUndo anytime: powershell -ExecutionPolicy Bypass -File .\zf9-pixelify.ps1 -Undo" -ForegroundColor Cyan
