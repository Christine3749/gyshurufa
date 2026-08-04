# Add the missing TSF capability categories for the GY text service so it can
# activate in the Windows 11 console / Windows Terminal input stack.
# Mirrors exactly what ITfCategoryMgr::RegisterCategory writes. Needs admin.
$tip = "{5F689D3D-73E3-4C2B-979A-2DD86E438D6F}"
$cats = @(
    "{13A016DF-560B-46CD-947A-4C3AF1E0E35D}",  # TIPCAP_IMMERSIVESUPPORT
    "{25504FB4-7BAB-4BC1-9C69-CF81890F0EF5}",  # TIPCAP_SYSTRAYSUPPORT
    "{49D2F9CE-1F5E-11D7-A6D3-00065B84435C}",  # TIPCAP_UIELEMENTENABLED
    "{364215D9-75BC-11D7-A6EF-00065B84435C}"   # TIPCAP_COMLESS
)
$root = "HKLM:\SOFTWARE\Microsoft\CTF\TIP\$tip\Category"
foreach ($cat in $cats) {
    New-Item -Path "$root\Category\$cat\$tip" -Force | Out-Null
    New-Item -Path "$root\Item\$tip\$cat" -Force | Out-Null
}
Write-Host "Registered categories for GY:"
Get-ChildItem "$root\Category" | ForEach-Object { Write-Host ("  " + $_.PSChildName) }
