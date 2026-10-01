$ErrorActionPreference = 'Stop'
$reportPath = 'D:\godot\GodotGame-main\Отчет о проделанной работе ECHOES OF THE VOID.docx'
$pdfPath = 'D:\godot\GodotGame-main\.codex_qa\work_report\report_word.pdf'
$reportWord = New-Object -ComObject Word.Application
$reportWord.Visible = $false
$reportWord.DisplayAlerts = 0
try {
    $reportDoc = $reportWord.Documents.Open($reportPath, $false, $true)
    $reportDoc.Repaginate()
    $reportDoc.ExportAsFixedFormat($pdfPath, 17)
    Write-Output ('Pages: ' + $reportDoc.ComputeStatistics(2))
    $reportDoc.Close(0)
} finally {
    $reportWord.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($reportWord) | Out-Null
}
