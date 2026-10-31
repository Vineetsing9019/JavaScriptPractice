# Daily push: copies not-yet-pushed JavaScript practice files into JavaScriptPractice, one commit each.
# Run by the Windows scheduled task "JavaScriptPractice daily push". -Count sets how many files (default 4),
# -DryRun shows the picks without writing anything, -Force pushes again on a day that already has a push.
# Source: Desktop\JavaScript (one folder per topic, e.g. basics). New topic folders are picked up by themselves.
# A .js file goes if it has code; an .html page goes if its <script> has code. Empty files wait until written.
param([int]$Count = 4, [switch]$DryRun, [switch]$Force)

$ErrorActionPreference = 'Stop'
$Repo    = 'D:\JavaScriptPractice'
$Log     = Join-Path $Repo 'tools\daily-push.log'
$Pushed  = Join-Path $Repo 'daily\pushed.txt'
$Desk    = 'C:\Users\Vineet\OneDrive\Desktop'
# Vineet renamed the folder to my_JavaScript on 31 Oct. Either name works, and files pushed under the old
# name still count as pushed (paths compare with my_JavaScript read as JavaScript).
$Sources = @('my_JavaScript', 'JavaScript') | ForEach-Object { Join-Path $Desk $_ } | Where-Object { Test-Path $_ } | Select-Object -First 1
function Same-Name($p) { return ($p -replace '\\Desktop\\my_JavaScript\\', '\Desktop\JavaScript\') }
$SkipRe  = '\\(node_modules|dist|vendor)\\|\.min\.js$|\\bootstrap[^\\]*\.js$|\\jquery[^\\]*\.js$'
$BS      = [string][char]92

# A file is pushed only if it has real JavaScript: 20+ characters of code once comments and spaces are
# removed (in a page, the code inside its <script> tags, or a <script src> it loads).
function Has-Code($path) {
    $t = Get-Content $path -Raw -ErrorAction SilentlyContinue
    if (-not $t) { return $false }
    if ($path -match '\.html?$') {
        if ($t -match '(?i)<script[^>]+src\s*=') { return $true }
        $t = (([regex]::Matches($t, '(?is)<script[^>]*>(.*?)</script>')) | ForEach-Object { $_.Groups[1].Value }) -join "`n"
    }
    $t = [regex]::Replace($t, '(?s)/\*.*?\*/|<!--.*?-->', '')
    $t = [regex]::Replace($t, '//[^\r\n]*', '')
    return (($t -replace '\s', '').Length -ge 20)
}

function Log($msg) {
    $line = "{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $msg
    Add-Content -Path $Log -Value $line -Encoding utf8
    Write-Host $line
}

# The topic folder (first folder under JavaScript\), plus what the file name says it practises.
function Get-Topic($rel, $name) {
    $parts = $rel.Split($BS)
    $folder = if ($parts.Count -gt 2) { $parts[1] } else { 'basics' }
    $topic = "JavaScript $($folder.ToLower())"
    $page = [IO.Path]::GetFileNameWithoutExtension($name).ToLower()
    $hints = [ordered]@{
        'variable|datatype|typeof'      = 'variables and data types'
        'operator'                      = 'operators'
        'condition|ifelse|if-else|switch' = 'conditions'
        'loop|for|while'                = 'loops'
        'function|arrow|callback'       = 'functions'
        'array'                         = 'arrays'
        'object|json'                   = 'objects'
        'string'                        = 'strings'
        'dom|element|query'             = 'the DOM'
        'event|click|listener'          = 'events'
        'form|valid'                    = 'forms and validation'
        'promise|async|await|fetch'     = 'async code'
        'class|oop|inherit'             = 'classes'
        'myscript|external'             = 'external scripts'
        'first|hello|intro'             = 'my first scripts'
    }
    foreach ($k in $hints.Keys) { if ($page -match $k) { return "$topic ($($hints[$k]))" } }
    return $topic
}

try {
    Set-Location $Repo
    if (-not $DryRun -and (git ls-remote --heads origin main)) { git pull --rebase --quiet origin main }
    $today = Get-Date -Format 'yyyy-MM-dd'
    if (-not (Test-Path $Pushed)) { New-Item -ItemType File -Path $Pushed -Force | Out-Null }
    $done = @(Get-Content $Pushed -ErrorAction SilentlyContinue)

    if (($done | Where-Object { $_ -like "$today|*" }) -and -not $DryRun -and -not $Force) {
        Log "Already pushed today; nothing to do."
        exit 0
    }

    $candidates = @(foreach ($s in $Sources) {
        if (-not (Test-Path $s)) { continue }
        Get-ChildItem -Path $s -Recurse -File | Where-Object {
            $_.Extension -match '^\.(js|html|htm)$' -and $_.FullName -notmatch $SkipRe -and (Has-Code $_.FullName)
        }
    })
    $candidates = @($candidates | Where-Object { $f = Same-Name $_.FullName; -not ($done | Where-Object { (Same-Name $_.Split('|')[1]) -eq $f }) })
    if (-not $candidates) { Log "No unpushed JavaScript files left."; exit 0 }

    # Oldest first, so the repo follows the order the lessons were written in.
    foreach ($pick in ($candidates | Sort-Object LastWriteTime | Select-Object -First $Count)) {
        $rel   = $pick.FullName.Substring($Desk.Length).TrimStart($BS) -replace '^my_JavaScript', 'JavaScript'
        $topic = Get-Topic $rel $pick.Name
        $dest  = Join-Path $Repo ("daily" + $BS + $today + $BS + $rel)
        if ($DryRun) { Log "Dry run would push $($pick.FullName)  [$topic]"; continue }
        New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null

        $content = Get-Content $pick.FullName -Raw
        $note    = "Learning $topic - practice file from $($rel.Split($BS)[0]), pushed $today"
        $header  = if ($pick.Extension -eq '.js') { "// $note`r`n" } else { "<!-- $note -->`r`n" }
        Set-Content -Path $dest -Value ($header + $content) -Encoding utf8
        Log "Picked $($pick.FullName) -> $dest  [$topic]"

        $relDest = ("daily/$today/" + $rel.Replace($BS, '/')).Replace(' ', '%20')
        Add-Content -Path (Join-Path $Repo 'README.md') -Value ("| $today | [{0}]({1}) | Learning {2} |" -f $pick.Name, $relDest, $topic) -Encoding utf8
        Add-Content -Path $Pushed -Value "$today|$($pick.FullName)" -Encoding utf8

        git add -A
        git commit --quiet -m "Learning $topic`: $($pick.Name)" -m "Practice file from $rel."
        git push --quiet -u origin main
        Log "Pushed $($pick.Name)"
    }
}
catch {
    Log "FAILED: $($_.Exception.Message)"
    exit 1
}
