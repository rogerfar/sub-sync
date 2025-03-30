[CmdletBinding()]
param (
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateScript({ Test-Path $_ })]
  [string]$InputFile
)

function ConvertTo-TimeSpan {
  param ([string]$TimeString)
  return [timespan]::ParseExact($TimeString.Replace(',', '.'), 'hh\:mm\:ss\.fff', $null)
}

function ConvertFrom-TimeSpan {
  param ([timespan]$TimeSpan)
  return $TimeSpan.ToString('hh\:mm\:ss\.fff').Replace('.', ',')
}

function Adjust-Timestamps {
  param (
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d{2}:\d{2}:\d{2},\d{3} --> \d{2}:\d{2}:\d{2},\d{3}$')]
    [string]$TimestampLine
  )

  $times = $TimestampLine -split ' --> '
  $startTime = ConvertTo-TimeSpan $times[0]
  $endTime = ConvertTo-TimeSpan $times[1]
    
  $startTime = $startTime.Add([timespan]::FromMilliseconds(-200))
  $endTime = $endTime.Add([timespan]::FromMilliseconds(200))
    
  return '{0} --> {1}' -f (ConvertFrom-TimeSpan $startTime), (ConvertFrom-TimeSpan $endTime)
}

function Fix-Overlaps {
  param ([array]$Subtitles)
    
  $fixedSubs = @()
  $previousEnd = $null
    
  foreach ($sub in $Subtitles) {
    if ($sub -match '(\d{2}:\d{2}:\d{2},\d{3}) --> (\d{2}:\d{2}:\d{2},\d{3})') {
      $currentStart = ConvertTo-TimeSpan $matches[1]
      $currentEnd = ConvertTo-TimeSpan $matches[2]
            
      if ($previousEnd -and $currentStart -lt $previousEnd) {
        # Overlap detected - adjust current start time
        $currentStart = $previousEnd.Add([timespan]::FromMilliseconds(10))
                
        # If the new start time would be after or too close to the end time, adjust both
        if ($currentStart -ge $currentEnd -or ($currentEnd - $currentStart).TotalMilliseconds -lt 100) {
          $currentEnd = $currentStart.Add([timespan]::FromMilliseconds(500))
        }
                
        $sub = "{0} --> {1}" -f (ConvertFrom-TimeSpan $currentStart), (ConvertFrom-TimeSpan $currentEnd)
      }
            
      $previousEnd = $currentEnd
    }
        
    $fixedSubs += $sub
  }
    
  return $fixedSubs
}

function Get-AssStyle {
  param (
    [string]$FontName = "Arial",
    [int]$FontSize = 21,
    [string]$PrimaryColor = "&H00FFFFFF", # White
    [string]$SecondaryColor = "&H00FFFFFF", # White
    [string]$OutlineColor = "&H00000000", # Black
    [string]$BackColor = "&H00000000", # Black
    [int]$Bold = 0,
    [int]$Italic = 0,
    [int]$Underline = 0,
    [int]$StrikeOut = 0,
    [int]$ScaleX = 110,
    [int]$ScaleY = 100,
    [int]$Spacing = 1,
    [int]$Angle = 0,
    [int]$BorderStyle = 3,
    [int]$Outline = 1,
    [int]$Shadow = 0,
    [int]$Alignment = 2,
    [int]$MarginL = 10,
    [int]$MarginR = 10,
    [int]$MarginV = 23,
    [int]$Encoding = 1
  )

  return "Style: Default,{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10},{11},{12},{13},{14},{15},{16},{17},{18},{19},{20},{21}" -f @(
    $FontName,
    $FontSize,
    $PrimaryColor,
    $SecondaryColor,
    $OutlineColor,
    $BackColor,
    $Bold,
    $Italic,
    $Underline,
    $StrikeOut,
    $ScaleX,
    $ScaleY,
    $Spacing,
    $Angle,
    $BorderStyle,
    $Outline,
    $Shadow,
    $Alignment,
    $MarginL,
    $MarginR,
    $MarginV,
    $Encoding
  )
}

function Convert-SrtToAss {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string]$SrtPath
  )

  try {
    $fileInfo = Get-Item $SrtPath
    $directory = $fileInfo.Directory
    $baseName = $fileInfo.BaseName
    $assPath = Join-Path $directory "$baseName.ass"
    $tempSrtPath = Join-Path $directory "$baseName.adj.srt"

    Write-Verbose "Adjusting timestamps and fixing overlaps..."
    $srtContent = Get-Content $SrtPath
    $adjustedContent = $srtContent | ForEach-Object {
      if ($_ -match '\d{2}:\d{2}:\d{2},\d{3} --> \d{2}:\d{2}:\d{2},\d{3}') {
        Adjust-Timestamps $_
      }
      else {
        $_
      }
    }
        
    # Fix any overlapping timestamps
    $adjustedContent = Fix-Overlaps $adjustedContent
        
    $adjustedContent | Out-File $tempSrtPath -Encoding UTF8
        
    Write-Verbose "Converting to ASS format..."
    $ffmpegCommand = "ffmpeg -y -i `"$tempSrtPath`" `"$assPath`""
    Invoke-Expression $ffmpegCommand

    Write-Verbose "Applying custom style..."
    $assContent = Get-Content -Path $assPath
    $newStyle = Get-AssStyle
    $updatedContent = $assContent -replace '(?<=^Style: Default).*', $newStyle.Substring(14)
    $updatedContent | Set-Content -Path $assPath

    Write-Verbose "Cleaning up temporary files..."
    Remove-Item $tempSrtPath -ErrorAction SilentlyContinue

    Write-Output "Conversion completed successfully. Output file: $assPath"

    # Strip any language code pattern (like .en, .nl, etc) from base name
    $videoBaseName = $baseName -replace '\.[a-z]{2,3}$', ''
    
    # Try different video extensions in order of preference
    $videoExtensions = @('.mkv', '.mp4', '.avi')
    $videoPath = $null
    
    foreach ($ext in $videoExtensions) {
      $testPath = Join-Path $directory "$videoBaseName$ext"
      if (Test-Path $testPath) {
        $videoPath = $testPath
        Write-Verbose "Found matching video: $videoPath"
        break
      }
    }

    if ($videoPath) {
      Write-Verbose "Opening video with subtitles in VLC..."
      $vlcPath = "C:\Program Files\VideoLAN\VLC\vlc.exe"
      if (Test-Path $vlcPath) {
        Start-Process $vlcPath -ArgumentList "`"$videoPath`"", "--sub-file=`"$assPath`"", "--no-sub-autodetect-file", "--qt-continue=2"
      }
      else {
        Write-Warning "VLC not found at default location. Please install VLC or update path."
      }
    }
    else {
      Write-Warning "No matching video file found for: $videoBaseName"
    }
  }
  catch {
    Write-Error "An error occurred during conversion: $_"
    throw
  }
}

# Execute the conversion
Convert-SrtToAss -SrtPath $InputFile