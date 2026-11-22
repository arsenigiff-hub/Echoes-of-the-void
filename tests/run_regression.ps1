param(
	[string]$Godot = "D:\Godot_v4.7.2-stable_win64.exe",
	[string]$Project = (Split-Path $PSScriptRoot -Parent)
)

# General regression pass. Runs every permanent test headless and fails on the
# first non-zero exit code. The ObjectDB leak warning at shutdown is known and
# does not affect the exit code.
$tests = @(
	"test_upper_deck.gd",
	"test_object_placement.gd",
	"test_full_spatial.gd",
	"test_ship_layout_b.gd",
	"test_eva_oxygen.gd",
	"test_full_regression.gd"
)

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
