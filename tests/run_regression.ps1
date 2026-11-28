param(
	[string]$Godot = "D:\Godot_v4.7.2-stable_win64.exe",
	[string]$Project = (Split-Path $PSScriptRoot -Parent)
)

# Permanent headless tests for the slimmed-down game (menu, intro, new shuttle).
# The old ship's tests live in D:\Echoes-of-the-void-main_old_ship\tests.
$tests = @("test_shuttle_blockout.gd", "test_game_flow.gd", "test_shuttle_eva.gd")

$failed = @()
foreach ($test in $tests) {
	$name = [System.IO.Path]::GetFileNameWithoutExtension($test)
	$out = Join-Path $env:TEMP "echoes_$name.out.log"
	$err = Join-Path $env:TEMP "echoes_$name.err.log"
	$process = Start-Process -FilePath $Godot -ArgumentList @(
		"--headless", "--path", $Project, "--script", "res://tests/$test"
	) -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -Wait
	if ($process.ExitCode -eq 0) {
		Write-Host "PASS $test"
	} else {
		Write-Host "FAIL $test (exit $($process.ExitCode))"
		Get-Content $out | Select-Object -Last 8
		$failed += $test
	}
}

if ($failed.Count -gt 0) {
	Write-Host "REGRESSION_FAILED: $($failed -join ', ')"
	exit 1
}
Write-Host "REGRESSION_OK: $($tests.Count) tests"
exit 0
