Param(
  [Parameter()][switch]$Local
)
# concatenates files

$targets = @{
	"editor.js" = @(
		"dwachss/historystack/history.js",
		"dwachss/keymap/keymap.js",
		"dwachss/status/status.js",
		"dwachss/toolbar/toolbar.js",
		"bililiteRange.js",
		"bililiteRange.undo.js",
		"bililiteRange.lines.js",
		"bililiteRange.find.js",
		"bililiteRange.ex.js",
		"bililiteRange.evim.js"
	);
	"bililiteRange.js" = @(
		"bililiteRange.js",
		"bililiteRange.find.js"
	)
}

$shaSize = 7

function Get-Repo {
  param([Parameter(Mandatory=$true)][string]$Source)
  (Split-Path $source) -replace '\\', '/'
}

function Get-Sha {
	param($repo)
	if ($repo) {
    $url = "https://api.github.com/repos/$repo/commits/master"
    $headers = @{Accept = 'application/vnd.github.sha'}
    $req = (Invoke-WebRequest $url -Headers $headers)
    $content = $req.Content[0..$shaSize]
		[char[]]($content) -join ''
	}else{
		git rev-parse --short=$shaSize HEAD
	}
}

function Get-Source-Content {
	param(
    [Parameter(Mandatory=$true)][string]$File,
    [Parameter(Mandatory=$false)][string[]]$Repo
  )
  $existsLocally = [System.IO.File]::Exists($File)
  $remote = "https://raw.githubusercontent.com/$repo/master/$file"

  $result = $null
  if ($Repo) {
    if ($Local.IsPresent -and $existsLocally) {
      $result = Get-Content $file
      if ([string]::IsNullOrWhiteSpace($result)) {
        Write-Warning "Failed to get content from local file $File, using remote $repo`n $remote"
        $req = Invoke-WebRequest $remote
        if ($req) {
          $result = $req.Content
          if (!$result) {
            Write-Error "No Content returned from remote $repo`n $remote"
          }
        }
      }
    } else {
      $req = Invoke-WebRequest $remote
      if ($req) {
        $result = $req.Content
      }
      if ([string]::IsNullOrWhiteSpace($result)) {
        Write-Warning "Failed to get content from $repo`n $remote`n, using local file $File"
        $result = Get-Content $file
        if (!$result) {
          Write-Error "Failed to get content from local file $File,`n and the remote!"
        }
      }
    }
  } else {
    $result = Get-Content $file
    if (!$result) {
      Write-Error "Failed to get content from local file $File, using remote $repo to fallback to was specified"
    }
  }
  ($result | % { [string]$_ }) -as [string[]]
}

$pkgJson = Get-Source-Content "package.json" | ConvertFrom-Json


function Wrap-Content {
	param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][Array]$Content,
    [Parameter(Mandatory=$false)][hashtable]$Info
  )
  if (!$Info) { $Info = @{} }
  $hash = [ordered]@{ }
  $hash.source = if ([string]::IsNullOrWhiteSpace($Info.source)) { $Source } else { $Info.source }
  $hash.file = if ([string]::IsNullOrWhiteSpace($Info.file)) { Split-Path $Source -leaf } else { $Info.file }
  $hash.repo = if ([string]::IsNullOrWhiteSpace($Info.repo)) { Get-Repo $Source } else { $Info.repo }
  $hash.commit = if ([string]::IsNullOrWhiteSpace($Info.commit)) { Get-Sha $hash.repo } else { $Info.commit }
  $hash.version = if ([string]::IsNullOrWhiteSpace($Info.version)) { $pkgJson.version } else { $Info.version }
  $hash.date = if ([string]::IsNullOrWhiteSpace($Info.date)) { Get-Date -Format 'yyyy-MM-dd' } else { $Info.date }
  $Info.GetEnumerator() | % {
    if (!$hash.Contains($_.Key)) {
      $hash[$_.Key] = $_.Value
    }
  }

  $sha = Get-Sha $repo
  $file = Split-Path $Source -leaf
  $hashlines = $hash.GetEnumerator() | % {
    $k = $_.Key
    $v = $_.Value
    $name = $k.PadLeft(10)
    " * $($name): $v"
  }
  $lines = @(
    "",
    "",
    "/$('*'*49)",
    $hashlines,
    " $('*'*48)/",
    "",
    $Content,
    ""
  ) | % { $_ }
  $lines
}



foreach ($target in $targets.Keys){
  $path = "dist/$target"
  $targetLines = [System.Collections.Generic.List[string]]::new()
	foreach ($source in $targets[$target]){
    $pref = $ErrorActionPreference
    try {
      $ErrorActionPreference = 'Break'
      $file = Split-Path $Source -leaf
      $repo =  Get-Repo $source
      $content = Get-Source-Content $file $repo
      $lines = Wrap-Content -Source $source -Content $content -Info @{ source = $source; file = $file; repo = $repo }
      foreach($ln in $lines){
        $targetLines.Add($ln)
      }
    } catch {
      $targetLines = $null
      $ErrorActionPreference = $pref
      Write-Error $_
    } finally {
      $ErrorActionPreference = $pref
    }
	}
  if ($targetLines -and $targetLines.Count -gt 0) {
    if ([System.IO.File]::Exists($path)) {
      Remove-Item $path
    }
    $content = ($targetLines -join "`n").Trim();
    $content >> $path
  }
}
