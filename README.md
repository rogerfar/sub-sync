# Sub Tools

## Convert SRT to ASS

Converts a SRT subtitle file to ASS. This will add a black background to overlay burned in subtitles.

Make sure you have ffmpeg installed:

```
choco install ffmpeg
```

or

```
https://www.gyan.dev/ffmpeg/builds/ffmpeg-git-full.7z
```

To execute:

```
& '.\Convert SRT to ASS.ps1' "Video.en.srt"
```

This will output `Video.en.ass` and attempts to launch VLC with the video file and subtitle.

To adjust the fonts etc, you can manually change the script and adjust the parameters in `Get-AssStyle`.
