---
name: buzz-media-attachments
description: "Use when attaching a local media file to the active Buzz conversation. Do not use for general media editing or non-Buzz delivery."
version: 1.0.0
metadata:
  hermes:
    tags: [buzz, attachments, media, mp4, gif, nostr]
---

# Buzz Media Attachments

Use this workflow when a user asks to post a local media file into the current Buzz conversation and normal `MEDIA:/path` delivery fails.

## Workflow

1. **Verify the source file** exists and is readable. Use `ffprobe` for video metadata when relevant.

2. **Find the current Buzz channel UUID** from the live gateway log rather than guessing:

   ```bash
   # Search ~/.hermes/logs/gateway.log for the user's latest inbound Buzz message.
   # The line contains: platform=buzz ... chat=<CHANNEL_UUID>
   ```

3. **Use Buzz's native attachment mechanism**:

   ```bash
   buzz messages send \
     --channel <CHANNEL_UUID> \
     --content - \
     --file /absolute/path/to/file
   ```

   `--file` may be repeated to attach several files to one message.

4. **Load Buzz credentials without shell-sourcing `.env`.** `BUZZ_AUTH_TAG` can contain JSON that shell `source` mangles. Parse the file with `python-dotenv` and pass values through a subprocess environment:

   ```python
   import os, subprocess
   from dotenv import dotenv_values

   env = os.environ.copy()
   env.update({
       k: v for k, v in dotenv_values(os.path.expanduser("~/.hermes/.env")).items()
       if v is not None
   })
   result = subprocess.run(
       ["buzz", "messages", "send",
        "--channel", channel_id,
        "--content", "-",
        "--file", file_path],
       input=caption,
       text=True,
       env=env,
       capture_output=True,
       timeout=180,
   )
   ```

5. **If Buzz rejects an MP4**, diagnose the returned relay error:

   - `moov atom not at front of file (not fast-start)`: first try remuxing:

     ```bash
     ffmpeg -y -v error -i input.mp4 -c copy -movflags +faststart output.mp4
     ```

   - `media contains metadata or a non-canonical metadata channel`: use Buzz Desktop's canonical sanitizer settings. A simple stream-copy remux is insufficient because FFmpeg may retain or add forbidden MP4 metadata structures. Fully re-encode exactly as follows:

     ```bash
     ffmpeg -y -nostdin -loglevel error -protocol_whitelist file,pipe \
       -i input.mp4 \
       -map 0:v:0 -map '0:a:0?' \
       -map_metadata -1 -map_chapters -1 -sn -dn \
       -fflags +bitexact -flags:v +bitexact -flags:a +bitexact \
       -c:v libx264 -preset fast -crf 23 -pix_fmt yuv420p \
       -vf 'pad=ceil(iw/2)*2:ceil(ih/2)*2' \
       -c:a aac -b:a 128k \
       -movflags +faststart -metadata encoder= \
       output.mp4
     ```

     This matches `block/buzz` Desktop's `transcode_to_mp4()` implementation and produces the canonical H.264/AAC, metadata-free, fast-start MP4 expected by the relay.

   - If canonical MP4 encoding is undesirable, fails, or the user specifically asks for **Attach Image**, convert a short clip to an animated GIF:

     ```bash
     ffmpeg -y -v error -i input.mp4 \
       -vf "fps=12,scale=512:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer" \
       -loop 0 -map_metadata -1 output.gif
     ```

   Upload the resulting MP4 or GIF through `buzz messages send --file`.

6. **Verify success from real output.** Only report success when Buzz returns JSON containing:

   ```json
   {"accepted": true, "event_id": "..."}
   ```

## Pitfalls

- Plain `MEDIA:/absolute/path.mp4` can route through Hermes' generic `send_video` fallback; Buzz may not implement native video delivery there.
- Do not claim an attachment worked merely because the gateway accepted the assistant response. Check the Buzz CLI's `accepted` value and retain the `event_id` as verification.
- Never print `BUZZ_PRIVATE_KEY` or other `.env` values.
- Keep converted GIFs in `/tmp` unless the user requests durable copies; do not modify the source MP4.
- GIF conversion can increase file size. For long or high-resolution clips, lower `fps`, scale width, or color count before uploading.
