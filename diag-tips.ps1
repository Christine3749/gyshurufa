$tipRoot = "HKLM:\SOFTWARE\Microsoft\CTF\TIP"
$rows = @()
foreach ($tip in Get-ChildItem $tipRoot) {
    $clsid = $tip.PSChildName
    $desc = (Get-ItemProperty -Path ("$tipRoot\$clsid") -Name Description -ErrorAction SilentlyContinue).Description
    $cats = @()
    $catPath = "$tipRoot\$clsid\Category\Category"
    if (Test-Path $catPath) {
        foreach ($c in Get-ChildItem $catPath) { $cats += $c.PSChildName }
    }
    $rows += [PSCustomObject]@{ CLSID = $clsid; Description = $desc; Categories = ($cats -join " ") }
}
$rows | Format-List
Write-Host "===== WinUserLanguageList ====="
Get-WinUserLanguageList | ForEach-Object {
    Write-Host ("Language: " + $_.LanguageTag)
    $_.InputMethodTips | ForEach-Object { Write-Host ("  TIP: " + $_) }
}
