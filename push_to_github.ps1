$env:Path = "C:\Users\HP\AppData\Local\Programs\Git\cmd;C:\Users\HP\AppData\Local\Programs\Git\ucrt64\bin;C:\Users\HP\AppData\Local\Programs\Git\usr\bin;$env:Path"
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Pushing SkyPoints11 project to GitHub (branch: main)" -ForegroundColor Cyan
Write-Host "Remote: https://github.com/aswinunnisunil/SkyPoints11.git" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
git push -u origin main
if ($LASTEXITCODE -eq 0) {
    Write-Host "`nSuccessfully pushed to https://github.com/aswinunnisunil/SkyPoints11" -ForegroundColor Green
} else {
    Write-Host "`nIf prompted, please authenticate with your GitHub credentials or Personal Access Token (PAT)." -ForegroundColor Yellow
}
