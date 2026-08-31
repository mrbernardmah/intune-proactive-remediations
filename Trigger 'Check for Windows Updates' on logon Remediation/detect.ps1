try {
    $UpdateSession = New-Object -ComObject Microsoft.Update.Session
    $UpdateSearcher = $UpdateSession.CreateUpdateSearcher()
    $SearchResult = $UpdateSearcher.Search("IsInstalled=0 and Type='Software'")

    if ($SearchResult.Updates.Count -gt 0) {
        $UpdateNames = ($SearchResult.Updates | ForEach-Object { $_.Title }) -join ", "
        Write-Output "Pending updates found ($($SearchResult.Updates.Count)): $UpdateNames"
        exit 1
    }
    else {
        Write-Output "No pending Windows updates."
        exit 0
    }
}
catch {
    Write-Error "Failed to check for Windows updates: $_"
    exit 1
}
