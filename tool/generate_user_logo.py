import os, math
from PIL import Image, ImageDraw

def create_user_logo(size=1024):
    scale = 2
    S = size * scale  # 2048x2048 supersampling

    # Base image
    bg_color = (15, 43, 82, 255) # Deep navy blue #0F2B52

    canvas = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)

    # Outer rounded squircle
    pad = int(80 * scale)
    corner_radius = int(380 * scale)

    draw.rounded_rectangle(
        [pad, pad, S - pad, S - pad],
        radius=corner_radius,
        fill=bg_color
    )

    cx, cy = S // 2, S // 2 + int(35 * scale) # Center

    # 1. Top Stopwatch Loop Handle
    loop_w = int(180 * scale)
    loop_h = int(100 * scale)
    loop_top = cy - int(440 * scale) - loop_h
    loop_thickness = int(28 * scale)

    draw.rounded_rectangle(
        [cx - loop_w, loop_top, cx + loop_w, loop_top + loop_h * 2],
        radius=int(60 * scale),
        outline=(255, 255, 255, 255),
        width=loop_thickness
    )

    # Cover bottom half of loop rectangle
    draw.rectangle(
        [cx - loop_w - int(20*scale), cy - int(440 * scale), cx + loop_w + int(20*scale), S],
        fill=bg_color
    )

    # 2. Main Clock Circle
    r = int(410 * scale)
    circle_thickness = int(28 * scale)

    draw.ellipse(
        [cx - r, cy - r, cx + r, cy + r],
        outline=(255, 255, 255, 255),
        width=circle_thickness
    )

    # 3. Four Tick Marks (12, 3, 6, 9)
    tick_len = int(55 * scale)
    tick_w = int(26 * scale)

    # 12 o'clock
    draw.line([cx, cy - r + circle_thickness//2, cx, cy - r + circle_thickness//2 + tick_len], fill=(255, 255, 255, 255), width=tick_w)
    # 6 o'clock
    draw.line([cx, cy + r - circle_thickness//2, cx, cy + r - circle_thickness//2 - tick_len], fill=(255, 255, 255, 255), width=tick_w)
    # 3 o'clock
    draw.line([cx + r - circle_thickness//2, cy, cx + r - circle_thickness//2 - tick_len, cy], fill=(255, 255, 255, 255), width=tick_w)
    # 9 o'clock
    draw.line([cx - r + circle_thickness//2, cy, cx - r + circle_thickness//2 + tick_len, cy], fill=(255, 255, 255, 255), width=tick_w)

    # 4. Checkmark Hands
    hand_w = int(42 * scale)

    # Short hand (white, pointing down-left ~225 deg)
    sh_dx = int(-140 * scale)
    sh_dy = int(-140 * scale)
    draw.line([cx, cy, cx + sh_dx, cy + sh_dy], fill=(255, 255, 255, 255), width=hand_w)

    # Long hand (steel blue #5E7E9E, pointing up-right ~45 deg)
    lh_dx = int(270 * scale)
    lh_dy = int(-270 * scale)
    draw.line([cx, cy, cx + lh_dx, cy + lh_dy], fill=(94, 126, 158, 255), width=hand_w)

    # Rounded line caps
    cap_r = hand_w // 2
    draw.ellipse([cx - cap_r, cy - cap_r, cx + cap_r, cy + cap_r], fill=(255, 255, 255, 255))
    draw.ellipse([cx + sh_dx - cap_r, cy + sh_dy - cap_r, cx + sh_dx + cap_r, cy + sh_dy + cap_r], fill=(255, 255, 255, 255))
    draw.ellipse([cx + lh_dx - cap_r, cy + lh_dy - cap_r, cx + lh_dx + cap_r, cy + lh_dy + cap_r], fill=(94, 126, 158, 255))

    # Downscale with high quality Lanczos filter
    final_img = canvas.resize((size, size), Image.Resampling.LANCZOS)
    return final_img

if __name__ == '__main__':
    logo = create_user_logo(1024)
    os.makedirs('assets/images', exist_ok=True)
    logo.save('assets/images/app_logo.png')
    print('Generated assets/images/app_logo.png')

    mipmaps = {
        'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
        'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': 72,
        'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': 96,
        'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': 144,
        'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
    }
    for path, sz in mipmaps.items():
        os.makedirs(os.path.dirname(path), exist_ok=True)
        resized = logo.resize((sz, sz), Image.Resampling.LANCZOS)
        resized.save(path)
        print(f'Saved {path} ({sz}x{sz})')
