# release.ps1: build Hare & Hex and publish it as a GitHub release the launcher picks up.
#
#   powershell -File tools\release.ps1 -Version 0.1.4 -Notes "Faster shop, fixed the bench"
#   powershell -File tools\release.ps1 -Version 0.1.4 -DryRun     (build and zip only, upload nothing)
#
# What it does:
#   1. sets the version in export_presets.cfg (exe metadata, export paths, Android version name)
#   2. exports the Windows build to build\windows\ and the launcher to build\HareHex-Launcher.exe
#   3. zips the build as build\HareHex-windows.zip (the asset name the launcher looks for)
#   4. creates release v<Version> as a draft on the current commit, uploads both files, then publishes it
#      (publishing is what testers' launchers see, and what posts to Discord via release-discord.yml)
#
# Needs a GitHub token with "Contents: Read and write" on the repo, in $env:GITHUB_TOKEN or in
# release_token.txt at the project root (git-ignored). Make one at
# https://github.com/settings/personal-access-tokens/new (fine-grained, only this repository).
# Releases are pre-releases unless -Full is given; the launcher installs either.
# -NotesFile reads the notes from a file; -Yes answers yes to every question (the launcher's
# release panel uses both, after showing its own warnings).

param(
	[Parameter(Mandatory = $true)][string]$Version,
	[string]$Notes = "",
	[string]$NotesFile = "",
	[switch]$Yes,
	[switch]$Full,
	[switch]$DryRun,
	[switch]$SkipLauncher,
	[string]$Godot = "E:\Godot\Godot_v4.7.2-stable_win64_console.exe",
	[string]$Repo = "Pentastic23/Hare-Hex"
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Root = Split-Path -Parent $PSScriptRoot
$Build = Join-Path $Root "build"
$Asset = "HareHex-windows.zip"
$Tag = "v$Version"

function Step($text) { Write-Host "`n== $text" -ForegroundColor Yellow }
function Ask($question) {
	if ($Yes) { Write-Host "$question yes (-Yes)"; return }
	$a = Read-Host "$question (y/n)"
	if ($a -ne "y") { Write-Host "Stopped."; exit 1 }
}

if ($Version -notmatch '^\d+(\.\d+){1,3}$') { throw "Version should look like 0.1.4 (got '$Version')." }
if ($NotesFile) { $Notes = [IO.File]::ReadAllText($NotesFile).Trim() }
if (-not (Test-Path $Godot)) { throw "Godot not found at $Godot (pass -Godot <path>)." }
if (-not (Test-Path (Join-Path $Root "bug_report_webhook.txt"))) {
	Write-Warning "bug_report_webhook.txt is missing: bug reports won't work in this build."
	Ask "Build anyway?"
}

# --- Token and git checks (skipped for a dry run) ------------------------------------------------

$Token = $env:GITHUB_TOKEN
$TokenFile = Join-Path $Root "release_token.txt"
if (-not $Token -and (Test-Path $TokenFile)) { $Token = (Get-Content $TokenFile -Raw).Trim() }
$Headers = @{ Authorization = "Bearer $Token"; Accept = "application/vnd.github+json"; "X-GitHub-Api-Version" = "2022-11-28"; "User-Agent" = "HareHex-Release" }

Push-Location $Root
try {
	if (-not $DryRun) {
		if (-not $Token) { throw "No GitHub token: set GITHUB_TOKEN or put one in release_token.txt (see the top of this script)." }
		$existing = $null
		try { $existing = Invoke-RestMethod -Headers $Headers "https://api.github.com/repos/$Repo/releases/tags/$Tag" } catch { }
		if ($existing) { throw "Release $Tag already exists: $($existing.html_url)" }

		if (git status --porcelain) {
			Write-Warning "You have uncommitted changes. They go into the build, but the release's tag points at the last commit."
			Ask "Release anyway?"
		}
		git fetch origin --quiet
		$branch = (git rev-parse --abbrev-ref HEAD).Trim()
		$ahead = (git rev-list --count "origin/$branch..HEAD" 2>$null)
		if ($LASTEXITCODE -ne 0 -or [int]$ahead -gt 0) {
			Write-Warning "This commit isn't on GitHub yet ($branch is $ahead commit(s) ahead of origin)."
			Ask "Push $branch now?"
			git push origin $branch
			if ($LASTEXITCODE -ne 0) { throw "git push failed." }
		}
		$Commit = (git rev-parse HEAD).Trim()
	}

	# --- Version ---------------------------------------------------------------------------------

	Step "Setting version $Version"
	$presets = Join-Path $Root "export_presets.cfg"
	$cfg = [IO.File]::ReadAllText($presets)
	$cfg = $cfg -replace 'application/file_version="[^"]*"', "application/file_version=`"$Version`""
	$cfg = $cfg -replace 'application/product_version="[^"]*"', "application/product_version=`"$Version`""
	$cfg = $cfg -replace 'export_path="\./Hare&Hex v[^"]*\.exe"', "export_path=`"./Hare&Hex v$Version.exe`""
	$cfg = $cfg -replace 'export_path="\./H&H mobile v[^"]*\.apk"', "export_path=`"./H&H mobile v$Version.apk`""
	$cfg = $cfg -replace 'version/name="Hare&Hex Mobile [^"]*"', "version/name=`"Hare&Hex Mobile $Version`""
	$cfg = $cfg -replace 'package/name="Hare&Hex Mobile [^"]*"', "package/name=`"Hare&Hex Mobile $Version`""
	[IO.File]::WriteAllText($presets, $cfg)

	# --- Build -----------------------------------------------------------------------------------

	Step "Exporting the game"
	$gameDir = Join-Path $Build "windows"
	if (Test-Path $gameDir) { Remove-Item $gameDir -Recurse -Force }
	New-Item -ItemType Directory -Force $gameDir | Out-Null
	$gameExe = Join-Path $gameDir "Hare&Hex.exe"
	& $Godot --headless --path $Root --export-release "Windows Desktop" $gameExe
	if (-not (Test-Path $gameExe)) { throw "The game export failed (no $gameExe)." }

	$launcherExe = Join-Path $Build "HareHex-Launcher.exe"
	if (-not $SkipLauncher) {
		Step "Exporting the launcher"
		& $Godot --headless --path (Join-Path $Root "launcher") --export-release "Windows Desktop" $launcherExe
		if (-not (Test-Path $launcherExe)) { throw "The launcher export failed (no $launcherExe)." }
	}

	Step "Zipping"
	$zip = Join-Path $Build $Asset
	if (Test-Path $zip) { Remove-Item $zip -Force }
	Add-Type -AssemblyName System.IO.Compression.FileSystem
	[IO.Compression.ZipFile]::CreateFromDirectory($gameDir, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)
	$mb = "{0:N1}" -f ((Get-Item $zip).Length / 1MB)
	Write-Host "$zip ($mb MB)"

	if ($DryRun) {
		Step "Dry run: nothing uploaded"
		Write-Host "Game:     $gameExe`nZip:      $zip"
		if (-not $SkipLauncher) { Write-Host "Launcher: $launcherExe" }
		exit 0
	}

	# --- Release ---------------------------------------------------------------------------------

	Step "Creating draft release $Tag"
	$body = @{
		tag_name = $Tag
		target_commitish = $Commit
		name = "Hare&Hex $Tag"
		body = $Notes
		draft = $true
		prerelease = -not $Full
		generate_release_notes = ($Notes -eq "")
	} | ConvertTo-Json
	$release = Invoke-RestMethod -Method Post -Headers $Headers -ContentType "application/json" `
		-Body ([Text.Encoding]::UTF8.GetBytes($body)) "https://api.github.com/repos/$Repo/releases"

	try {
		$uploads = @(@{ Path = $zip; Name = $Asset; Type = "application/zip" })
		if (-not $SkipLauncher) { $uploads += @{ Path = $launcherExe; Name = "HareHex-Launcher.exe"; Type = "application/octet-stream" } }
		foreach ($u in $uploads) {
			Step "Uploading $($u.Name)"
			Invoke-RestMethod -Method Post -Headers $Headers -ContentType $u.Type -InFile $u.Path -TimeoutSec 3600 `
				"https://uploads.github.com/repos/$Repo/releases/$($release.id)/assets?name=$($u.Name)" | Out-Null
		}
		Step "Publishing"
		$published = Invoke-RestMethod -Method Patch -Headers $Headers -ContentType "application/json" `
			-Body (@{ draft = $false } | ConvertTo-Json) "https://api.github.com/repos/$Repo/releases/$($release.id)"
	} catch {
		Write-Warning "Upload failed; the draft is left on GitHub so you can finish or delete it: $($release.html_url)"
		throw
	}
	git fetch origin --tags --quiet
	Write-Host "`nReleased $Tag`n$($published.html_url)" -ForegroundColor Green
	Write-Host "Testers' launchers will install it the next time they start."
}
finally {
	Pop-Location
}
