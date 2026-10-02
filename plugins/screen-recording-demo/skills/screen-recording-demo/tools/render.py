#!/usr/bin/env python3
"""Turns a raw take into a finished tutorial video.

Usage: python3 tools/render.py <name>|all [--speed 1.3] [--frames] [--gif]

Reads work/raw-<name>.mkv and work/<name>.log (both written by tools/take.zsh) and writes
output/<name>.mp4. "all" renders both and also joins them into output/tutorial.mp4. The log's "step N" marks decide when each numbered caption shows, and its
"cut-start"/"cut-end" marks bracket frames to remove (the file dialogs resizing themselves).
The title card and captions for each take come from tools/videos.json.
With --frames, stills from the finished video are written to work/frames-<name>/ for review.
With --gif, an animated GIF (for places that cannot play video, such as a GitHub README) is
written beside each MP4.
"""

import argparse
import json
import pathlib
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

PROJECT = pathlib.Path(__file__).resolve().parent.parent
WORK = PROJECT / "work"
OUTPUT = PROJECT / "output"

BAND_HEIGHT = 152          # caption band below the screen capture, in capture pixels
OUTPUT_WIDTH = 1032        # the capture is 1376 wide; the embed column is 460 CSS px
TITLE_SECONDS = 1.5
FADE_SECONDS = 0.35
CUT_LEAD = 0.15            # keep this much after a click so the click itself is visible
TAIL_HOLD = 0.5            # freeze on the last frame this long
GIF_WIDTH = 688            # the capture region's width in points
GIF_FPS = 10

BACKDROP = (59, 74, 107)   # matches BACKDROP_COLOR in common.zsh
BAND = (28, 36, 58)
ACCENT = (56, 99, 230)
DONE = (34, 160, 90)
WHITE = (255, 255, 255)
MUTED = (196, 205, 224)

FONT_PATH = "/System/Library/Fonts/SFNS.ttf"

# Title card text and one caption per "step N" mark, for each take.
VIDEOS = json.loads((pathlib.Path(__file__).resolve().parent / "videos.json").read_text())


def font(size, weight="Semibold"):
    f = ImageFont.truetype(FONT_PATH, size)
    try:
        f.set_variation_by_name(weight)
    except (OSError, ValueError):
        pass
    return f


def fit_font(draw, text, max_width, size, weight="Semibold"):
    while size > 20:
        f = font(size, weight)
        if draw.textlength(text, font=f) <= max_width:
            return f
        size -= 2
    return font(size, weight)


def caption_image(path, width, number, text, is_last):
    """Draws one caption band: a numbered badge (a check mark on the final step) and the text."""
    img = Image.new("RGB", (width, BAND_HEIGHT), BAND)
    d = ImageDraw.Draw(img)
    r = 44
    cx, cy = 40 + r, BAND_HEIGHT // 2
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=DONE if is_last else ACCENT)
    if is_last:
        d.line((cx - 20, cy + 2, cx - 6, cy + 16, cx + 22, cy - 16), fill=WHITE, width=9, joint="curve")
    else:
        d.text((cx, cy), str(number), font=font(54, "Bold"), fill=WHITE, anchor="mm")
    left = cx + r + 30
    f = fit_font(d, text, width - left - 40, 52)
    d.text((left, cy), text, font=f, fill=WHITE, anchor="lm")
    img.save(path)


def title_image(path, width, height, title, subtitle):
    img = Image.new("RGB", (width, height), BACKDROP)
    d = ImageDraw.Draw(img)
    f = fit_font(d, title, width - 160, 104, "Bold")
    d.text((width // 2, height // 2 - 40), title, font=f, fill=WHITE, anchor="mm")
    d.text((width // 2, height // 2 + 70), subtitle, font=fit_font(d, subtitle, width - 200, 50, "Regular"), fill=MUTED, anchor="mm")
    img.save(path)


def read_marks(log_path):
    marks = []
    for line in log_path.read_text().splitlines():
        stamp, _, action = line.partition("\t")
        if action.startswith("mark "):
            marks.append((float(stamp), action[5:]))
    return marks


def probe(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=start_time:stream=width,height", "-of", "json", str(path)],
        check=True, capture_output=True, text=True,
    ).stdout
    info = json.loads(out)
    return float(info["format"]["start_time"]), info["streams"][0]["width"], info["streams"][0]["height"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("name", choices=[*VIDEOS, "all"])
    ap.add_argument("--speed", type=float, default=1.3, help="playback speed of the screen capture")
    ap.add_argument("--frames", action="store_true", help="also write review stills")
    ap.add_argument("--gif", action="store_true", help="also write an animated GIF of each video")
    args = ap.parse_args()

    if args.name != "all":
        render(args.name, args.speed, args.frames, args.gif)
        return
    parts = [render(name, args.speed, args.frames, args.gif) for name in VIDEOS]
    listing = WORK / "concat.txt"
    listing.write_text("".join(f"file '{part}'\n" for part in parts))
    joined = OUTPUT / "tutorial.mp4"
    subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0", "-i", str(listing),
         "-c", "copy", "-movflags", "+faststart", str(joined)],
        check=True,
    )
    print(f"{joined.relative_to(PROJECT)}: {joined.stat().st_size / 1e6:.2f} MB")


def render(name, speed, want_frames, want_gif):
    spec = VIDEOS[name]
    raw = WORK / f"raw-{name}.mkv"
    start_time, width, height = probe(raw)
    marks = [(t - start_time, label) for t, label in read_marks(WORK / f"{name}.log")]

    steps = [t for t, label in marks if label.startswith("step ")]
    end = next(t for t, label in marks if label == "end")
    if len(steps) != len(spec["captions"]):
        sys.exit(f"log has {len(steps)} steps but {len(spec['captions'])} captions are defined")

    # Segments of the raw capture to keep, in raw time.
    cut_starts = [t + CUT_LEAD for t, label in marks if label == "cut-start"]
    cut_ends = [t for t, label in marks if label == "cut-end"]
    keep, cursor = [], steps[0]
    for a, b in zip(cut_starts, cut_ends):
        keep.append((cursor, a))
        cursor = b
    keep.append((cursor, end))

    def to_output(t):
        """Maps a raw-capture time to a time in the edited, sped-up body."""
        total = 0.0
        for a, b in keep:
            if t >= b:
                total += b - a
            elif t > a:
                total += t - a
        return total / speed

    body_seconds = to_output(end) + TAIL_HOLD
    full_height = height + BAND_HEIGHT
    assets = WORK / f"assets-{name}"
    assets.mkdir(exist_ok=True)
    OUTPUT.mkdir(exist_ok=True)

    title_png = assets / "title.png"
    title_image(title_png, width, full_height, spec["title"], spec["subtitle"])
    inputs = ["-i", str(raw), "-loop", "1", "-t", str(TITLE_SECONDS), "-i", str(title_png)]

    n = len(keep)
    graph = [f"[0:v]fps=30,split={n}" + "".join(f"[s{i}]" for i in range(n))]
    for i, (a, b) in enumerate(keep):
        graph.append(f"[s{i}]trim=start={a:.3f}:end={b:.3f},setpts=PTS-STARTPTS[k{i}]")
    graph.append(
        "".join(f"[k{i}]" for i in range(n))
        + f"concat=n={n}:v=1:a=0,setpts=PTS/{speed},fps=30,"
        + f"pad={width}:{full_height}:0:0:color=0x{BAND[0]:02x}{BAND[1]:02x}{BAND[2]:02x}[p0]"
    )
    bounds = [to_output(t) for t in steps] + [body_seconds + 1]
    for i, text in enumerate(spec["captions"]):
        png = assets / f"caption-{i + 1}.png"
        caption_image(png, width, i + 1, text, is_last=(i == len(spec["captions"]) - 1))
        inputs += ["-i", str(png)]
        graph.append(
            f"[p{i}][{i + 2}:v]overlay=0:{height}:enable='between(t,{bounds[i]:.3f},{bounds[i + 1] - 0.001:.3f})'[p{i + 1}]"
        )
    last = f"p{len(spec['captions'])}"
    out_height = round(full_height * OUTPUT_WIDTH / width / 2) * 2
    graph.append(f"[{last}]tpad=stop_mode=clone:stop_duration={TAIL_HOLD},format=yuv420p,settb=AVTB[body]")
    graph.append("[1:v]fps=30,format=yuv420p,settb=AVTB[title]")
    graph.append(
        f"[title][body]xfade=transition=fade:duration={FADE_SECONDS}:offset={TITLE_SECONDS - FADE_SECONDS},"
        f"scale={OUTPUT_WIDTH}:{out_height}:flags=lanczos,format=yuv420p[out]"
    )

    out = OUTPUT / f"{name}.mp4"
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *inputs,
           "-filter_complex", ";".join(graph), "-map", "[out]", "-an",
           "-c:v", "libx264", "-preset", "slow", "-crf", "22", "-r", "30",
           "-movflags", "+faststart", str(out)]
    subprocess.run(cmd, check=True)

    total = TITLE_SECONDS - FADE_SECONDS + body_seconds
    print(f"{out.relative_to(PROJECT)}: {total:.1f} s, {out.stat().st_size / 1e6:.2f} MB")
    offset = TITLE_SECONDS - FADE_SECONDS
    for i, b in enumerate(bounds[:-1]):
        print(f"  step {i + 1} at {b + offset:5.2f} s  {spec['captions'][i]}")

    if want_frames:
        frames = WORK / f"frames-{name}"
        frames.mkdir(exist_ok=True)
        for old in frames.glob("*.jpg"):
            old.unlink()
        subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(out),
             "-vf", "fps=2,scale=516:-2", "-q:v", "4", str(frames / "f-%03d.jpg")],
            check=True,
        )
        print(f"  review stills in {frames.relative_to(PROJECT)}")

    if want_gif:
        gif = out.with_suffix(".gif")
        # A palette built from the video itself keeps flat UI colors clean. Dithering is off
        # because it adds noise that GIF compresses badly.
        subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(out), "-filter_complex",
             f"fps={GIF_FPS},scale={GIF_WIDTH}:-2:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];"
             "[b][p]paletteuse=dither=none:diff_mode=rectangle", str(gif)],
            check=True,
        )
        print(f"  {gif.relative_to(PROJECT)}: {gif.stat().st_size / 1e6:.2f} MB")
    return out


if __name__ == "__main__":
    main()
