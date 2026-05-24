#!/usr/bin/env python3

import argparse
import json
import math
import statistics
from pathlib import Path

from PIL import Image, ImageChops, ImageStat


def parse_args():
    parser = argparse.ArgumentParser(
        description="Verify ChatView edge fade/blur screenshots without OpenCV."
    )
    parser.add_argument("before", type=Path, help="Screenshot before scrolling")
    parser.add_argument("after", type=Path, help="Screenshot after scrolling")
    parser.add_argument(
        "--output",
        type=Path,
        help="Optional JSON output path",
    )
    return parser.parse_args()


def crop_band(image, top, height, x_margin_ratio=0.08):
    width, image_height = image.size
    margin = int(width * x_margin_ratio)
    y0 = max(0, int(top))
    y1 = min(image_height, int(top + height))
    return image.crop((margin, y0, width - margin, y1))


def grayscale(image):
    return image.convert("L")


def mean_abs_diff(first, second):
    diff = ImageChops.difference(first, second)
    return sum(ImageStat.Stat(diff).mean) / len(diff.getbands())


def channel_stddev(image):
    stats = ImageStat.Stat(image)
    return sum(stats.stddev) / len(stats.stddev)


def luminance_mean(image):
    return ImageStat.Stat(grayscale(image)).mean[0]


def sobel_energy(image):
    gray = grayscale(image)
    pixels = gray.load()
    width, height = gray.size
    if width < 3 or height < 3:
        return 0.0

    total = 0.0
    count = 0
    for y in range(1, height - 1):
        for x in range(1, width - 1):
            gx = (
                -pixels[x - 1, y - 1]
                - 2 * pixels[x - 1, y]
                - pixels[x - 1, y + 1]
                + pixels[x + 1, y - 1]
                + 2 * pixels[x + 1, y]
                + pixels[x + 1, y + 1]
            )
            gy = (
                -pixels[x - 1, y - 1]
                - 2 * pixels[x, y - 1]
                - pixels[x + 1, y - 1]
                + pixels[x - 1, y + 1]
                + 2 * pixels[x, y + 1]
                + pixels[x + 1, y + 1]
            )
            total += math.sqrt(gx * gx + gy * gy)
            count += 1
    return total / count


def row_luminance_profile(image):
    gray = grayscale(image)
    width, height = gray.size
    pixels = gray.load()
    return [
        sum(pixels[x, y] for x in range(width)) / width
        for y in range(height)
    ]


def monotonic_trend_score(values, expected_direction):
    if len(values) < 2:
        return 0.0
    pairs = zip(values, values[1:])
    if expected_direction == "down":
        good = sum(1 for a, b in pairs if b <= a + 0.25)
    else:
        good = sum(1 for a, b in pairs if b + 0.25 >= a)
    return good / (len(values) - 1)


def summarize_band(name, before, after, center_energy):
    energy_before = sobel_energy(before)
    energy_after = sobel_energy(after)
    edge_ratio = edge_to_inner_energy_ratio(before, name)
    return {
        "mean_abs_scroll_delta": round(mean_abs_diff(before, after), 3),
        "channel_stddev": round(channel_stddev(before), 3),
        "sobel_energy_before": round(energy_before, 3),
        "sobel_energy_after": round(energy_after, 3),
        "energy_ratio_to_center": round(energy_before / center_energy, 3) if center_energy else None,
        "outer_to_inner_energy_ratio": round(edge_ratio, 3),
        "luminance_mean": round(luminance_mean(before), 3),
    }


def edge_to_inner_energy_ratio(image, name):
    width, height = image.size
    slice_height = max(6, height // 3)
    if name == "top":
        outer = image.crop((0, 0, width, slice_height))
        inner = image.crop((0, height - slice_height, width, height))
    else:
        outer = image.crop((0, height - slice_height, width, height))
        inner = image.crop((0, 0, width, slice_height))

    inner_energy = sobel_energy(inner)
    if inner_energy == 0:
        return 0.0
    return sobel_energy(outer) / inner_energy


def verify(before_path, after_path):
    before = Image.open(before_path).convert("RGB")
    after = Image.open(after_path).convert("RGB")
    if before.size != after.size:
        raise ValueError(f"Screenshot sizes differ: {before.size} vs {after.size}")

    width, height = before.size
    top_band = crop_band(before, top=104, height=112)
    top_band_after = crop_band(after, top=104, height=112)
    bottom_band = crop_band(before, top=height - 190, height=118)
    bottom_band_after = crop_band(after, top=height - 190, height=118)
    center_band = crop_band(before, top=height * 0.40, height=height * 0.18)

    center_energy = sobel_energy(center_band)
    top = summarize_band("top", top_band, top_band_after, center_energy)
    bottom = summarize_band("bottom", bottom_band, bottom_band_after, center_energy)

    thresholds = {
        "mean_abs_scroll_delta_min": 2.0,
        "channel_stddev_min": 8.0,
        "energy_ratio_to_center_max": 0.95,
        "outer_to_inner_energy_ratio_max": 0.86,
    }

    def band_passes(band):
        return (
            band["mean_abs_scroll_delta"] >= thresholds["mean_abs_scroll_delta_min"]
            and band["channel_stddev"] >= thresholds["channel_stddev_min"]
            and band["energy_ratio_to_center"] is not None
            and band["energy_ratio_to_center"] <= thresholds["energy_ratio_to_center_max"]
            and band["outer_to_inner_energy_ratio"] <= thresholds["outer_to_inner_energy_ratio_max"]
        )

    result = {
        "before": str(before_path),
        "after": str(after_path),
        "image_size": {"width": width, "height": height},
        "bands": {
            "top": top,
            "bottom": bottom,
            "center": {
                "sobel_energy": round(center_energy, 3),
                "channel_stddev": round(channel_stddev(center_band), 3),
                "luminance_mean": round(luminance_mean(center_band), 3),
            },
        },
        "thresholds": thresholds,
        "passed": {
            "top": band_passes(top),
            "bottom": band_passes(bottom),
        },
    }
    result["passed"]["all"] = all(result["passed"].values())

    samples = [top["mean_abs_scroll_delta"], bottom["mean_abs_scroll_delta"]]
    result["summary"] = {
        "mean_edge_scroll_delta": round(statistics.mean(samples), 3),
        "interpretation": (
            "Edge bands respond to scrolled message content and retain texture while reducing high-frequency detail."
            if result["passed"]["all"]
            else "One or more edge bands did not meet the expected fade/blur evidence thresholds."
        ),
    }
    return result


def main():
    args = parse_args()
    result = verify(args.before, args.after)
    payload = json.dumps(result, indent=2, sort_keys=True)
    print(payload)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload + "\n", encoding="utf-8")
    raise SystemExit(0 if result["passed"]["all"] else 1)


if __name__ == "__main__":
    main()
